import SwiftUI

/// The reader's collected highlights and margin notes for one book —
/// marginalia that matters (SCOPE §5.3): these flow into seminars as
/// `userAnnotations` once live mode lands.
struct MarginaliaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let bookID: String

    var body: some View {
        NavigationStack {
            Group {
                let highlights = app.highlightStore.highlights(bookID: bookID)
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "No marginalia yet",
                        systemImage: "highlighter",
                        description: Text("Long-press a paragraph in the reader to highlight it and leave a note."))
                } else {
                    List {
                        ForEach(highlights) { highlight in
                            MarginaliaRow(bookID: bookID, highlight: highlight)
                                .listRowBackground(Theme.card)
                        }
                        .onDelete { indexSet in
                            let items = app.highlightStore.highlights(bookID: bookID)
                            for index in indexSet {
                                app.highlightStore.remove(items[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.paper)
            .navigationTitle("Marginalia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MarginaliaRow: View {
    @Environment(AppModel.self) private var app
    let bookID: String
    let highlight: Highlight

    @State private var excerpt: String?
    @State private var chapterTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chapterTitle ?? "Section \(highlight.ch + 1)").overline(Theme.accent)

            Text("\u{201C}\(excerpt ?? "…")\u{201D}")
                .font(.callout)
                .fontDesign(.serif)
                .italic()
                .lineLimit(4)
                .foregroundStyle(Theme.ink)

            if let note = highlight.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 2)
                    Text(note)
                        .font(.footnote)
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Text("chars \(highlight.charStart)–\(highlight.charEnd)")
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.inkSecondary.opacity(0.7))
        }
        .padding(.vertical, 4)
        .task {
            guard excerpt == nil else { return }
            if let chapter = await app.chapter(bookID: bookID, ch: highlight.ch) {
                chapterTitle = chapter.title
                excerpt = Self.slice(chapter.text,
                                     from: highlight.charStart,
                                     to: highlight.charEnd)
            }
        }
    }

    /// Slice the canonical chapter text by stored char offsets.
    static func slice(_ text: String, from start: Int, to end: Int) -> String {
        guard start >= 0, end > start, start < text.count else { return "" }
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: min(end, text.count))
        return String(text[lower..<upper])
    }
}
