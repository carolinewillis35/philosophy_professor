import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security

// MARK: - Auth (CONTRACTS §4.1)
// Sign in with Apple → Supabase Auth id_token grant, hand-rolled over
// URLSession like the SSE client — no third-party SDKs. Tokens live in the
// iOS Keychain; access tokens auto-refresh near expiry. Mock mode needs none
// of this.

enum AuthError: LocalizedError {
    case notConfigured
    case notSignedIn
    case appleCredentialMissing
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No Supabase backend configured."
        case .notSignedIn: return "Sign in to continue."
        case .appleCredentialMissing: return "Apple didn't return a usable credential. Please try again."
        case .server(let message): return message
        }
    }
}

/// Minimal Keychain wrapper (kSecClassGenericPassword) for token storage.
struct KeychainStore {
    let service: String

    func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Supabase Auth session state + Sign in with Apple flow.
@Observable
@MainActor
final class AuthClient {

    private(set) var signedIn = false
    private(set) var userId: String?
    private(set) var lastError: String?
    private(set) var isWorking = false

    private struct StoredSession: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userId: String
    }

    private var session: StoredSession? {
        didSet {
            signedIn = session != nil
            userId = session?.userId
            persist()
        }
    }

    @ObservationIgnored private var currentNonce: String?
    @ObservationIgnored private let keychain = KeychainStore(service: "com.theseminar.app.auth")
    @ObservationIgnored private let keychainAccount = "supabase-session"
    private let config: Config

    /// False in mock mode — no backend, no sign-in surface at all.
    var isConfigured: Bool { !config.isMockMode }

    init(config: Config = .shared) {
        self.config = config
        restore()
    }

    // MARK: Sign in with Apple

    /// Configure the ASAuthorization request: SHA256-hashed nonce (the raw
    /// nonce goes to Supabase with the identity token). No scopes requested —
    /// the app needs only the stable user ID.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = Self.sha256Hex(nonce)
    }

    func handle(_ result: Result<ASAuthorization, Error>) async {
        lastError = nil
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            lastError = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                lastError = AuthError.appleCredentialMissing.errorDescription
                return
            }
            await exchange(idToken: idToken, nonce: nonce)
        }
    }

    /// `POST /auth/v1/token?grant_type=id_token` (§4.1).
    private func exchange(idToken: String, nonce: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await tokenGrant(
                query: "grant_type=id_token",
                body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
            apply(response)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: token lifecycle

    /// Access token for API calls, refreshed when within ~60s of expiry.
    func validAccessToken() async throws -> String {
        guard isConfigured else { throw AuthError.notConfigured }
        guard let session else { throw AuthError.notSignedIn }
        if session.expiresAt.timeIntervalSinceNow > 60 {
            return session.accessToken
        }
        try await refresh()
        guard let refreshed = self.session else { throw AuthError.notSignedIn }
        return refreshed.accessToken
    }

    /// `POST /auth/v1/token?grant_type=refresh_token` (§4.1).
    private func refresh() async throws {
        guard let session else { throw AuthError.notSignedIn }
        do {
            let response = try await tokenGrant(
                query: "grant_type=refresh_token",
                body: ["refresh_token": session.refreshToken])
            apply(response)
        } catch {
            // A rejected refresh token means the session is gone for good.
            clearLocalSession()
            throw error
        }
    }

    func signOut() async {
        if let base = config.supabaseURL, let anonKey = config.supabaseAnonKey,
           let session {
            var request = URLRequest(url: base.appendingPathComponent("auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            _ = try? await URLSession.shared.data(for: request) // best effort
        }
        clearLocalSession()
    }

    /// `POST /functions/v1/delete-account` (§4.2) — erases everything the
    /// user owns server-side, then the auth user itself.
    func deleteAccount() async throws {
        guard let base = config.supabaseURL, let anonKey = config.supabaseAnonKey else {
            throw AuthError.notConfigured
        }
        let token = try await validAccessToken()
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.server(Self.serverMessage(from: data)
                ?? "Account deletion failed. Please try again.")
        }
        clearLocalSession()
    }

    func clearLocalSession() {
        session = nil
        currentNonce = nil
    }

    // MARK: Supabase Auth REST

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: AuthUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    private struct AuthUser: Decodable {
        let id: String
    }

    private func tokenGrant(query: String, body: [String: String]) async throws -> TokenResponse {
        guard let base = config.supabaseURL, let anonKey = config.supabaseAnonKey,
              let url = URL(string: base.absoluteString + "/auth/v1/token?" + query) else {
            throw AuthError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.server(Self.serverMessage(from: data) ?? "Sign-in failed. Please try again.")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func serverMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let message: String?
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case message
                case errorDescription = "error_description"
            }
        }
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return body?.message ?? body?.errorDescription
    }

    private func apply(_ response: TokenResponse) {
        session = StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            userId: response.user.id)
    }

    // MARK: keychain persistence

    private func persist() {
        if let session, let data = try? JSONEncoder().encode(session) {
            keychain.save(data, account: keychainAccount)
        } else {
            keychain.delete(account: keychainAccount)
        }
    }

    private func restore() {
        guard isConfigured,
              let data = keychain.load(account: keychainAccount),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else { return }
        session = stored
    }

    // MARK: nonce

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
