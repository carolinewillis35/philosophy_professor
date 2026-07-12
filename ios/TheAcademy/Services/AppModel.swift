import Foundation
import Observation

/// Root app state: catalog content, user data, and the session-client
/// factory (mock vs. live, per Config).
@Observable
@MainActor
final class AppModel {

    // Catalog
    private(set) var courses: [Course] = []
    private(set) var personasByID: [String: Persona] = [:]
    private(set) var books: [BookMeta] = []
    private(set) var loadError: String?
    private(set) var isLoaded = false

    // Course JSON (§7) carries no `is_free`; that lives in the `courses`
    // table. Mirror DECISIONS #7 locally until live mode supplies it.
    let freeCourseIDs: Set<String> = ["what-is-justice"]

    let content: ContentStore
    let userStore: UserStore
    let highlightStore: HighlightStore
    let config: Config
    /// Supabase Auth session (CONTRACTS §4.1); inert in mock mode.
    let auth: AuthClient
    /// The Commitment Map behind the Worldview page (§12.7); fixture-backed
    /// in mock mode.
    let worldview: WorldviewStore
    /// The Daily Question ritual (§13.2): bank, rotation, answered state.
    let daily: DailyQuestionStore
    /// The weekly drop (§14.3): bank, rotation, completion, crowd aggregate.
    let drops: DropStore

    // Voice mode (DECISIONS #11): one mic, one synthesizer, app-wide.
    let speechTranscriber: SpeechTranscriber
    let professorVoice: ProfessorVoice

    private var chapterCache: [String: Chapter] = [:]

    init(content: ContentStore = FixtureContentStore(),
         userStore: UserStore = UserStore(),
         highlightStore: HighlightStore = HighlightStore(),
         config: Config = .shared) {
        self.content = content
        self.userStore = userStore
        self.highlightStore = highlightStore
        self.config = config
        self.auth = AuthClient(config: config)
        self.worldview = WorldviewStore()
        self.daily = DailyQuestionStore()
        self.drops = DropStore()

        // Recording and speaking never overlap: the mic silences the
        // professor, and the professor won't start while the mic is open.
        let voice = SystemProfessorVoice()
        let transcriber = SpeechTranscriber()
        voice.isBlocked = { [weak transcriber] in
            MainActor.assumeIsolated { transcriber?.isRecording ?? false }
        }
        transcriber.willStartRecording = { [weak voice] in voice?.stopSpeaking() }
        self.professorVoice = voice
        self.speechTranscriber = transcriber
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        do {
            courses = try await content.loadCourses()
            let personas = try await content.loadPersonas()
            personasByID = Dictionary(uniqueKeysWithValues: personas.map { ($0.id, $0) })
            books = try await content.loadBooks()
            // The home surface survives a missing daily bank — the card
            // simply doesn't render.
            daily.load(bank: (try? await content.loadDailyQuestions()) ?? [])
            // Same posture for the weekly drop bank (§14.3).
            drops.load(bank: (try? await content.loadDrops()) ?? [])
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: lookups

    func persona(_ id: String) -> Persona? { personasByID[id] }

    /// The full faculty, for the catalog's Faculty section.
    var personas: [Persona] { personasByID.values.sorted { $0.name < $1.name } }

    func course(_ id: String) -> Course? { courses.first { $0.id == id } }

    func book(_ bookID: String) -> BookMeta? { books.first { $0.bookID == bookID } }

    func bookTitle(_ bookID: String) -> String { book(bookID)?.title ?? bookID }

    /// Short display title, e.g. "The Republic" without subtitle clutter.
    func shortBookTitle(_ bookID: String) -> String {
        let title = bookTitle(bookID)
        return title.components(separatedBy: CharacterSet(charactersIn: ";:")).first ?? title
    }

    func chapter(bookID: String, ch: Int) async -> Chapter? {
        let key = "\(bookID):\(ch)"
        if let cached = chapterCache[key] { return cached }
        guard let chapter = try? await content.loadChapter(bookID: bookID, ch: ch) else { return nil }
        chapterCache[key] = chapter
        return chapter
    }

    // MARK: session clients

    /// Mock when Secrets.plist is absent; live SSE client otherwise. The
    /// mock takes the course unit so its scripted professor can lean on the
    /// authored §12.5 specs the way the engine's kind registry does; a drop
    /// session passes its spec the same way (§14.3).
    func makeSessionClient(course: Course? = nil, unit: Int? = nil,
                           assignmentId: String? = nil,
                           dropSpec: ThoughtExperimentSpec? = nil) -> SessionClient {
        if let endpoint = config.sessionEndpoint, let key = config.supabaseAnonKey {
            let auth = self.auth
            return LiveSessionClient(
                endpoint: endpoint, anonKey: key,
                accessTokenProvider: { try await auth.validAccessToken() })
        }
        let courseUnit = course.flatMap { course in
            unit.flatMap { u in course.units.first { $0.number == u + 1 } }
        }
        return MockSessionClient(assignmentId: assignmentId ?? "wij-u1-response",
                                 unit: courseUnit, dropSpec: dropSpec)
    }

    // MARK: account

    /// Sign-in gates only live enrollment/session actions — browsing the
    /// catalog and reader stays open signed-out (free-taste funnel), and
    /// mock mode never shows sign-in at all.
    var requiresSignIn: Bool {
        !config.isMockMode && !auth.signedIn
    }

    /// Wipe everything stored on-device: enrollments, reading progress,
    /// highlights, and essay drafts.
    func eraseLocalData() {
        userStore.eraseAll()
        highlightStore.eraseAll()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("essays", isDirectory: true))
    }

    /// §4.2: server-side deletion (live) then local wipe. In mock mode this
    /// is a local-only erase.
    func deleteAccount() async throws {
        if !config.isMockMode {
            try await auth.deleteAccount()
        }
        eraseLocalData()
    }
}
