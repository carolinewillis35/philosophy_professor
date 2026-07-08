import Foundation
import Observation

/// Everything user-owned that will eventually live in Supabase
/// (`enrollments`, `reading_progress`, profile prefs), persisted locally to a
/// JSON file in Documents for now.
@Observable
final class UserStore {

    private struct UserData: Codable {
        var enrollments: [Enrollment] = []
        var readingProgress: [String: ReadingProgress] = [:] // keyed by bookID
        var pace: Pace = .standard
        var intensity: Intensity = .standard
        var voiceReplies: Bool? = nil // optional: files on disk may predate voice mode
    }

    private(set) var enrollments: [Enrollment] = []
    private(set) var readingProgress: [String: ReadingProgress] = [:]
    var pace: Pace = .standard { didSet { save() } }
    var intensity: Intensity = .standard { didSet { save() } }
    /// Voice mode: professor turns are spoken aloud while they stream.
    var voiceReplies: Bool = false { didSet { save() } }

    private let fileURL: URL

    init(filename: String = "userdata.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent(filename)
        load()
    }

    // MARK: enrollments

    func isEnrolled(in courseId: String) -> Bool {
        enrollments.contains { $0.courseId == courseId }
    }

    func enrollment(for courseId: String) -> Enrollment? {
        enrollments.first { $0.courseId == courseId }
    }

    func enroll(in courseId: String) {
        guard !isEnrolled(in: courseId) else { return }
        enrollments.append(Enrollment(courseId: courseId, pace: pace))
        save()
    }

    func unenroll(from courseId: String) {
        enrollments.removeAll { $0.courseId == courseId }
        save()
    }

    func setCurrentUnit(_ unit: Int, for courseId: String) {
        guard let index = enrollments.firstIndex(where: { $0.courseId == courseId }) else { return }
        enrollments[index].currentUnit = unit
        save()
    }

    /// Account deletion / local erase: drop all user data, keep prefs.
    func eraseAll() {
        enrollments = []
        readingProgress = [:]
        save()
    }

    // MARK: reading progress (CONTRACTS §3 reading_progress shape)

    func progress(for bookID: String) -> ReadingProgress? {
        readingProgress[bookID]
    }

    func setProgress(bookID: String, ch: Int, charOffset: Int) {
        let existing = readingProgress[bookID]
        // Only move forward within the same chapter; chapter changes always stick.
        if let existing, existing.ch == ch, existing.charOffset >= charOffset { return }
        readingProgress[bookID] = ReadingProgress(ch: ch, charOffset: charOffset, updatedAt: Date())
        save()
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(UserData.self, from: data) else { return }
        enrollments = stored.enrollments
        readingProgress = stored.readingProgress
        pace = stored.pace
        intensity = stored.intensity
        voiceReplies = stored.voiceReplies ?? false
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = UserData(enrollments: enrollments, readingProgress: readingProgress,
                            pace: pace, intensity: intensity, voiceReplies: voiceReplies)
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
