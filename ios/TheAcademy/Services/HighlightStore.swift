import Foundation
import Observation

/// Local shape of the `highlights` table (CONTRACTS §3):
/// `(book_id, ch, char_start, char_end, note)` — offsets into the chapter's
/// canonical `text` string.
struct Highlight: Codable, Identifiable, Hashable {
    let id: UUID
    let bookID: String
    let ch: Int
    let charStart: Int
    let charEnd: Int
    var note: String?
    let createdAt: Date

    init(bookID: String, ch: Int, charStart: Int, charEnd: Int, note: String?) {
        self.id = UUID()
        self.bookID = bookID
        self.ch = ch
        self.charStart = charStart
        self.charEnd = charEnd
        self.note = note
        self.createdAt = Date()
    }
}

/// Persists highlights to a JSON file in Documents. Later replaced by (or
/// synced with) the Supabase `highlights` table.
@Observable
final class HighlightStore {

    private(set) var highlights: [Highlight] = []

    private let fileURL: URL

    init(filename: String = "highlights.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent(filename)
        load()
    }

    func highlights(bookID: String) -> [Highlight] {
        highlights
            .filter { $0.bookID == bookID }
            .sorted { ($0.ch, $0.charStart) < ($1.ch, $1.charStart) }
    }

    func highlights(bookID: String, ch: Int) -> [Highlight] {
        highlights(bookID: bookID).filter { $0.ch == ch }
    }

    func add(_ highlight: Highlight) {
        highlights.append(highlight)
        save()
    }

    func remove(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        save()
    }

    /// Account deletion / local erase.
    func eraseAll() {
        highlights = []
        save()
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        highlights = (try? decoder.decode([Highlight].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(highlights) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
