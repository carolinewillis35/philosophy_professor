import Foundation

/// A source of professor turns. `LiveSessionClient` speaks the SSE protocol
/// of CONTRACTS §4; `MockSessionClient` replays a scripted seminar offline.
protocol SessionClient {
    func send(_ request: SessionRequest) -> AsyncStream<SessionEvent>
}

/// Hand-rolled SSE over `URLSession.bytes(for:)` — no third-party deps.
/// POSTs the §4 request body to `{SUPABASE_URL}/functions/v1/session` and
/// parses `event:` / `data:` frames into `SessionEvent`s.
final class LiveSessionClient: SessionClient {

    private let endpoint: URL
    private let anonKey: String
    private let session: URLSession
    /// The signed-in user's Supabase access token (CONTRACTS §4.1); auto-
    /// refreshed by AuthClient.
    private let accessTokenProvider: () async throws -> String

    init(endpoint: URL, anonKey: String,
         accessTokenProvider: @escaping () async throws -> String,
         session: URLSession = .shared) {
        self.endpoint = endpoint
        self.anonKey = anonKey
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    func send(_ request: SessionRequest) -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    // User JWT as bearer, anon key as apikey (§4.1).
                    let accessToken: String
                    do {
                        accessToken = try await accessTokenProvider()
                    } catch {
                        continuation.yield(.error(
                            code: nil,
                            message: (error as? AuthError)?.errorDescription
                                ?? "Sign in to talk with your professor."))
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        // Pre-stream failures arrive as plain JSON. 429 is the
                        // daily budget hard limit (§4.3).
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        continuation.yield(Self.httpError(status: http.statusCode, body: body))
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    var parser = SSEParser()
                    for try await byte in bytes {
                        for frame in parser.consume(byte) {
                            if let event = Self.decode(frame) {
                                continuation.yield(event)
                                if case .done = event {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    if let frame = parser.flush(), let event = Self.decode(frame) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.error(code: nil, message: error.localizedDescription))
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: frame -> SessionEvent

    private static func decode(_ frame: SSEFrame) -> SessionEvent? {
        let decoder = JSONDecoder()
        let data = Data(frame.data.utf8)
        switch frame.event {
        case "session":
            struct SessionStart: Decodable { let sessionId: String; let kind: SessionKind; let unit: Int }
            guard let s = try? decoder.decode(SessionStart.self, from: data) else { return nil }
            return .session(sessionId: s.sessionId, kind: s.kind, unit: s.unit)
        case "say":
            struct Say: Decodable { let delta: String }
            guard let s = try? decoder.decode(Say.self, from: data) else { return nil }
            return .sayDelta(s.delta)
        case "envelope":
            guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
                return .error(code: nil, message: "Malformed envelope from server.")
            }
            return .envelope(envelope)
        case "error":
            let body = try? decoder.decode(ErrorBody.self, from: data)
            return .error(code: body?.code,
                          message: body?.message ?? "Unknown server error")
        case "done":
            return .done
        default:
            return nil // ignore comments/unknown event names
        }
    }

    private struct ErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    /// Map a pre-stream HTTP failure to a SessionEvent (429 = budget, §4.3).
    private static func httpError(status: Int, body: Data) -> SessionEvent {
        let parsed = try? JSONDecoder().decode(ErrorBody.self, from: body)
        if status == 429 {
            return .error(
                code: parsed?.code ?? SessionErrorCode.budgetExceeded,
                message: parsed?.message
                    ?? "You've reached today's discussion budget. The seminar resumes tomorrow — the reading will keep.")
        }
        return .error(code: parsed?.code,
                      message: parsed?.message ?? "Server returned HTTP \(status)")
    }
}

// MARK: - SSE wire parsing

struct SSEFrame {
    var event: String
    var data: String
}

/// Minimal SSE parser: accumulates bytes into lines, lines into frames.
/// A blank line dispatches the pending frame; multiple `data:` lines are
/// joined with newlines per the SSE spec.
struct SSEParser {
    private var lineBuffer: [UInt8] = []
    private var eventName = "message"
    private var dataLines: [String] = []

    /// Feed one byte; returns any frames completed by it.
    mutating func consume(_ byte: UInt8) -> [SSEFrame] {
        if byte == UInt8(ascii: "\n") {
            var line = lineBuffer
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            lineBuffer.removeAll(keepingCapacity: true)
            return consumeLine(String(decoding: line, as: UTF8.self))
        }
        lineBuffer.append(byte)
        return []
    }

    private mutating func consumeLine(_ line: String) -> [SSEFrame] {
        if line.isEmpty {
            guard !dataLines.isEmpty else {
                eventName = "message"
                return []
            }
            let frame = SSEFrame(event: eventName, data: dataLines.joined(separator: "\n"))
            eventName = "message"
            dataLines = []
            return [frame]
        }
        if line.hasPrefix(":") { return [] } // comment / keep-alive
        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }
        switch field {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break // id/retry unused
        }
        return []
    }

    /// Dispatch a trailing frame if the stream ended without a blank line.
    mutating func flush() -> SSEFrame? {
        guard !dataLines.isEmpty else { return nil }
        let frame = SSEFrame(event: eventName, data: dataLines.joined(separator: "\n"))
        dataLines = []
        return frame
    }
}
