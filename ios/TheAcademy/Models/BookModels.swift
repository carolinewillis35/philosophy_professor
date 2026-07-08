import Foundation

// MARK: - Pipeline output (CONTRACTS §8)

/// `pipeline/output/<bookID>/book.json`
struct BookMeta: Codable, Identifiable, Hashable {
    var id: String { bookID }
    let bookID: String
    let title: String
    let author: String
    let translator: String?
    let source: String
    let sourceUrl: String
    let license: String
    let licenseNote: String?
    let chapterCount: Int
}

/// `pipeline/output/<bookID>/chapters/<ch>.json`
/// `text` is plain text with paragraphs separated by `\n\n`; this exact string
/// is the offset space for every `charStart`/`charEnd` in the system.
struct Chapter: Codable, Hashable {
    let bookID: String
    let ch: Int
    let title: String
    let text: String

    /// Paragraphs with char offsets into `text` (the canonical offset space).
    var paragraphs: [ChapterParagraph] {
        var result: [ChapterParagraph] = []
        var offset = 0
        for (index, part) in text.components(separatedBy: "\n\n").enumerated() {
            let start = offset
            let end = offset + part.count
            result.append(ChapterParagraph(index: index, text: part, charStart: start, charEnd: end))
            offset = end + 2 // the "\n\n" separator
        }
        return result
    }
}

struct ChapterParagraph: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let text: String
    let charStart: Int
    let charEnd: Int
}
