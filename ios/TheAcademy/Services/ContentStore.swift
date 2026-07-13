import Foundation

/// Catalog/content access. `FixtureContentStore` reads the bundled fixtures;
/// a future `SupabaseContentStore` will fetch the same shapes from the
/// `courses` / `personas` / `chapters` tables (CONTRACTS §9) behind this
/// same protocol.
protocol ContentStore {
    func loadCourses() async throws -> [Course]
    func loadPersonas() async throws -> [Persona]
    func loadBooks() async throws -> [BookMeta]
    func loadChapter(bookID: String, ch: Int) async throws -> Chapter
    func availableChapters(bookID: String) async -> [Int]
    /// The daily bank (§13.2); fixture-bundled, later the `daily_questions`
    /// table.
    func loadDailyQuestions() async throws -> [DailyQuestion]
    /// The weekly drop bank (§14.3); fixture-bundled, later the `drops`
    /// table.
    func loadDrops() async throws -> [Drop]
    /// This week's news brief (§15.2); a fixture mock in mock mode, later
    /// the `news_briefs` cache (the server generates it on first start).
    func loadNewsBrief() async throws -> NewsBrief
    /// The practice exercise bank (§15.3); fixture-bundled, later the
    /// `practice_exercises` catalog table.
    func loadPracticeExercises() async throws -> PracticeBank
}

enum ContentStoreError: LocalizedError {
    case fixturesMissing
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .fixturesMissing: return "Bundled fixtures folder is missing."
        case .notFound(let what): return "\(what) is not bundled."
        }
    }
}

/// Loads the placeholder content bundled under `Fixtures/` (a folder
/// reference, so subpaths are preserved in the app bundle).
final class FixtureContentStore: ContentStore {

    private let decoder = JSONDecoder()

    private var fixturesRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Fixtures", isDirectory: true)
    }

    func loadCourses() async throws -> [Course] {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let coursesDir = root.appendingPathComponent("courses", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: coursesDir, includingPropertiesForKeys: nil)) ?? []
        var courses: [Course] = []
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            courses.append(try decoder.decode(Course.self, from: data))
        }
        return courses.sorted { $0.title < $1.title }
    }

    func loadPersonas() async throws -> [Persona] {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("personas.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode([Persona].self, from: data)
    }

    func loadBooks() async throws -> [BookMeta] {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let booksDir = root.appendingPathComponent("books", isDirectory: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: booksDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var books: [BookMeta] = []
        for dir in dirs {
            let meta = dir.appendingPathComponent("book.json")
            guard FileManager.default.fileExists(atPath: meta.path) else { continue }
            let data = try Data(contentsOf: meta)
            books.append(try decoder.decode(BookMeta.self, from: data))
        }
        return books.sorted { $0.title < $1.title }
    }

    func loadChapter(bookID: String, ch: Int) async throws -> Chapter {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("books/\(bookID)/chapters/\(ch).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ContentStoreError.notFound("Chapter \(ch) of \(bookID)")
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Chapter.self, from: data)
    }

    func loadDailyQuestions() async throws -> [DailyQuestion] {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("daily-questions.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(DailyQuestionBank.self, from: data).questions
    }

    func loadDrops() async throws -> [Drop] {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("drops.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(DropBank.self, from: data).drops
    }

    func loadNewsBrief() async throws -> NewsBrief {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("news-brief.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(NewsBrief.self, from: data)
    }

    func loadPracticeExercises() async throws -> PracticeBank {
        guard let root = fixturesRoot else { throw ContentStoreError.fixturesMissing }
        let url = root.appendingPathComponent("practice-exercises.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(PracticeBank.self, from: data)
    }

    func availableChapters(bookID: String) async -> [Int] {
        guard let root = fixturesRoot else { return [] }
        let dir = root.appendingPathComponent("books/\(bookID)/chapters", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { Int($0.deletingPathExtension().lastPathComponent) }
            .sorted()
    }
}
