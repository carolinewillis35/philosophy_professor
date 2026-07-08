import SwiftUI

/// A sourced quotation, set like a well-printed epigraph. Per CONTRACTS §9
/// this is the ONLY element that may carry quote styling: verbatim text from
/// `citations`, with a "Book · Chapter" caption and an open-in-reader
/// affordance. Professor paraphrase stays plain prose.
struct QuotePanel: View {
    @Environment(AppModel.self) private var app
    let citation: Citation
    let tint: Color

    @State private var chapterTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\u{201C}\(citation.quote)\u{201D}")
                .font(.callout)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption).overline(tint)
                    Text(citation.why)
                        .font(.caption)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let bookID = citation.bookID {
                    NavigationLink(value: ReaderRoute(bookID: bookID, ch: citation.chapterIndex)) {
                        Label("Open", systemImage: "book")
                            .font(.caption.weight(.semibold))
                            .fontDesign(.default)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(tint)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.06)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 6)
        }
        .task {
            guard let bookID = citation.bookID, let ch = citation.chapterIndex else { return }
            chapterTitle = (await app.chapter(bookID: bookID, ch: ch))?.title
        }
    }

    private var caption: String {
        guard let bookID = citation.bookID, let ch = citation.chapterIndex else {
            return citation.passageId
        }
        let book = app.shortBookTitle(bookID)
        return "\(book) · \(chapterTitle ?? "Chapter \(ch)")"
    }
}
