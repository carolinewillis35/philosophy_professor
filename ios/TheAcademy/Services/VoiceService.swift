import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Voice mode (DECISIONS #11)
// On-device Apple frameworks only: SFSpeechRecognizer for student speech→text,
// AVSpeechSynthesizer for the professor's voice. Everything sits behind the
// ProfessorVoice protocol so premium TTS can slot in later. The professor
// speaks ONLY `say` prose — never citations, never JSON, never quote panels.

// MARK: - Student speech → text

enum SpeechStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case denied
    case unavailable
    case error(String)

    /// User-facing note for non-working states; nil when there is nothing to say.
    var userMessage: String? {
        switch self {
        case .denied:
            return "Microphone or speech recognition is off for The Academy — enable both in Settings to speak to your professor."
        case .unavailable:
            return "Speech recognition isn't available on this device right now."
        case .error(let message):
            return message
        case .idle, .requestingPermission, .listening:
            return nil
        }
    }
}

/// Live microphone transcription over SFSpeechRecognizer + AVAudioEngine.
/// Partial results stream into `transcript`; the session input field mirrors
/// it while recording. Starting the mic always silences the professor first.
@Observable
@MainActor
final class SpeechTranscriber {

    private(set) var transcript = ""
    private(set) var status: SpeechStatus = .idle

    var isRecording: Bool { status == .listening }

    /// Set by AppModel: silences the professor before the mic opens.
    @ObservationIgnored var willStartRecording: () -> Void = {}

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        status = .requestingPermission

        // Recording and speaking never overlap: mic wins.
        willStartRecording()

        // Permissions: speech recognition + microphone.
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechAuth == .authorized else {
            status = .denied
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            status = .denied
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }

        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            status = .listening
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        if self.isRecording { self.stop() }
                    }
                }
            }
        } catch {
            teardownAudio()
            status = .error("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    /// Stops listening. The transcript stays put so the student can edit
    /// before sending.
    func stop() {
        guard status == .listening || status == .requestingPermission else { return }
        teardownAudio()
        status = .idle
    }

    private func teardownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Professor speech

/// Speaks professor turns. `SystemProfessorVoice` is the on-device
/// implementation; a premium/server TTS can replace it behind this protocol.
protocol ProfessorVoice: AnyObject {
    /// The professor currently speaking; controls voice/rate/pitch.
    var persona: Persona? { get set }
    var isSpeaking: Bool { get }
    /// Speak a complete text immediately (interrupts anything queued).
    func speak(_ text: String, persona: Persona?)
    /// Feed a streamed `say` delta; complete sentences are spoken as they form.
    func enqueue(delta: String)
    /// Speak whatever remains in the buffer (call on envelope arrival).
    func flush()
    func stopSpeaking()
}

/// AVSpeechSynthesizer-backed voice. Streamed deltas are buffered and split
/// on sentence boundaries so the professor starts talking before the turn
/// finishes; each sentence is one queued AVSpeechUtterance.
final class SystemProfessorVoice: ProfessorVoice {

    var persona: Persona?

    /// Set by AppModel: speech is blocked while the student's mic is open.
    var isBlocked: () -> Bool = { false }

    private let synthesizer = AVSpeechSynthesizer()
    private var buffer = ""

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String, persona: Persona?) {
        self.persona = persona
        stopSpeaking()
        speakChunk(text)
    }

    func enqueue(delta: String) {
        buffer += delta
        drainCompleteSentences()
    }

    func flush() {
        drainCompleteSentences()
        let tail = buffer
        buffer = ""
        speakChunk(tail)
    }

    func stopSpeaking() {
        buffer = ""
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: sentence chunking

    private func drainCompleteSentences() {
        while let end = Self.sentenceBreak(in: buffer) {
            let sentence = String(buffer[..<end])
            buffer.removeSubrange(buffer.startIndex..<end)
            speakChunk(sentence)
        }
    }

    /// Index just past the first `. ` / `! ` / `? ` boundary, or nil if the
    /// buffer holds no complete sentence yet (the tail waits for flush()).
    static func sentenceBreak(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if ".!?".contains(text[index]) {
                let next = text.index(after: index)
                if next < text.endIndex, text[next].isWhitespace {
                    return text.index(after: next)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func speakChunk(_ raw: String) {
        guard !isBlocked() else { return } // never talk over the student's mic
        let text = Self.strippingMarkdown(raw)
        guard !text.isEmpty else { return }

        configurePlaybackSession()

        let profile = Self.profile(for: persona?.id)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = profile.resolvedVoice()
        utterance.rate = profile.rate
        utterance.pitchMultiplier = profile.pitch
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    /// `say` carries light markdown; the voice should not read asterisks.
    static func strippingMarkdown(_ text: String) -> String {
        var result = text
        for token in ["**", "*", "__", "_", "`", "#"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
    }

    // MARK: per-persona voices (DECISIONS #11)

    struct SpeechProfile {
        /// Tried in order; premium/enhanced first, compact as the floor.
        let identifiers: [String]
        let language: String
        let rate: Float   // AVSpeechUtteranceDefaultSpeechRate == 0.5
        let pitch: Float

        func resolvedVoice() -> AVSpeechSynthesisVoice? {
            for id in identifiers {
                if let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
            }
            return AVSpeechSynthesisVoice(language: language)
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    static func profile(for personaID: String?) -> SpeechProfile {
        switch personaID {
        case "vlachos":
            // The gadfly: unhurried, deeper — every question sounds patient.
            return SpeechProfile(
                identifiers: ["com.apple.voice.enhanced.en-US.Tom",
                              "com.apple.voice.compact.en-US.Fred"],
                language: "en-US", rate: 0.44, pitch: 0.85)
        case "whitmore":
            // The analytic: British, measured, precise — clarity is kindness.
            return SpeechProfile(
                identifiers: ["com.apple.voice.premium.en-GB.Serena",
                              "com.apple.voice.enhanced.en-GB.Kate",
                              "com.apple.voice.compact.en-GB.Daniel"],
                language: "en-GB", rate: 0.49, pitch: 1.0)
        case "lindqvist":
            // The continental: warm, expansive, a touch brighter.
            return SpeechProfile(
                identifiers: ["com.apple.voice.enhanced.en-US.Ava",
                              "com.apple.voice.compact.en-US.Samantha"],
                language: "en-US", rate: 0.47, pitch: 1.04)
        default:
            return SpeechProfile(identifiers: [], language: "en-US", rate: 0.5, pitch: 1.0)
        }
    }
}
