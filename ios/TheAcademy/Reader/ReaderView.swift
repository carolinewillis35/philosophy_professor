import SwiftUI

// MARK: - Reader home (bookshelf)

struct ReaderHomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Assigned Texts").overline(Theme.accent)

                if app.books.isEmpty {
                    ContentUnavailableView("No texts yet",
                                           systemImage: "books.vertical",
                                           description: Text("Enroll in a course to receive your reading list."))
                } else {
                    ForEach(app.books) { book in
                        NavigationLink(value: ReaderRoute(bookID: book.bookID, ch: nil)) {
                            BookRow(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Reader")
        .academyDestinations()
    }
}

private struct BookRow: View {
    @Environment(AppModel.self) private var app
    let book: BookMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .font(.subheadline)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
            HStack(spacing: 12) {
                Label("\(book.chapterCount) sections", systemImage: "list.bullet")
                if let progress = app.userStore.progress(for: book.bookID) {
                    Label("Resume at section \(progress.ch + 1)", systemImage: "bookmark")
                }
            }
            .font(.caption)
            .fontDesign(.default)
            .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard()
    }
}

// MARK: - Reader

/// Chapter-JSON reader (CONTRACTS §8): serif type, generous leading,
/// adjustable size, long-press-to-highlight with char offsets into the
/// chapter's canonical text string.
struct ReaderView: View {
    @Environment(AppModel.self) private var app
    let route: ReaderRoute

    @AppStorage("readerTextScale") private var textScale: Double = 1.0

    @State private var chapter: Chapter?
    @State private var availableChapters: [Int] = []
    @State private var loadFailed = false
    @State private var composing: ChapterParagraph?
    @State private var showMarginalia = false
    @State private var furthestChar = 0

    var body: some View {
        Group {
            if let chapter {
                chapterScroll(chapter)
            } else if loadFailed {
                ContentUnavailableView(
                    "Not bundled",
                    systemImage: "book.closed",
                    description: Text("This section isn't in the offline fixtures. Live mode will fetch it from the chapters table."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.paper)
        .navigationTitle(app.shortBookTitle(route.bookID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $composing) { paragraph in
            HighlightComposer(bookID: route.bookID, ch: chapter?.ch ?? 0, paragraph: paragraph)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showMarginalia) {
            MarginaliaView(bookID: route.bookID)
        }
        .task { await initialLoad() }
    }

    // MARK: content

    private func chapterScroll(_ chapter: Chapter) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18 * textScale) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.shortBookTitle(route.bookID)).overline(Theme.accent)
                    Text(chapter.title)
                        .font(.system(size: 30 * textScale, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 8)
                }
                .padding(.bottom, 6)

                ForEach(chapter.paragraphs) { paragraph in
                    ParagraphView(
                        paragraph: paragraph,
                        textScale: textScale,
                        isHighlighted: isHighlighted(paragraph, in: chapter),
                        onLongPress: { composing = paragraph })
                    .onAppear {
                        furthestChar = max(furthestChar, paragraph.charStart)
                        app.userStore.setProgress(bookID: route.bookID,
                                                  ch: chapter.ch,
                                                  charOffset: paragraph.charStart)
                    }
                }

                progressFooter(chapter)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    private func isHighlighted(_ paragraph: ChapterParagraph, in chapter: Chapter) -> Bool {
        app.highlightStore.highlights(bookID: route.bookID, ch: chapter.ch).contains {
            $0.charStart < paragraph.charEnd && $0.charEnd > paragraph.charStart
        }
    }

    private func progressFooter(_ chapter: Chapter) -> some View {
        let fraction = chapter.text.isEmpty ? 0 : min(1, Double(furthestChar) / Double(chapter.text.count))
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            HStack {
                Text("\(Int(fraction * 100))% through \(chapter.title)")
                Spacer()
                Text("Long-press a paragraph to highlight")
            }
            .font(.caption)
            .fontDesign(.default)
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 12)
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                ForEach(availableChapters, id: \.self) { ch in
                    Button {
                        Task { await load(ch: ch) }
                    } label: {
                        if ch == chapter?.ch {
                            Label("Section \(ch + 1)", systemImage: "checkmark")
                        } else {
                            Text("Section \(ch + 1)")
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
            }

            Menu {
                Button { textScale = min(1.6, textScale + 0.1) } label: {
                    Label("Larger", systemImage: "textformat.size.larger")
                }
                Button { textScale = max(0.8, textScale - 0.1) } label: {
                    Label("Smaller", systemImage: "textformat.size.smaller")
                }
                Button { textScale = 1.0 } label: {
                    Label("Reset size", systemImage: "textformat")
                }
            } label: {
                Image(systemName: "textformat.size")
            }

            Button { showMarginalia = true } label: {
                Image(systemName: "highlighter")
            }
        }
    }

    // MARK: loading

    private func initialLoad() async {
        guard chapter == nil else { return }
        availableChapters = await app.content.availableChapters(bookID: route.bookID)
        let target = route.ch
            ?? app.userStore.progress(for: route.bookID)?.ch
            ?? availableChapters.first
            ?? 0
        await load(ch: target)
    }

    private func load(ch: Int) async {
        loadFailed = false
        furthestChar = 0
        if let loaded = await app.chapter(bookID: route.bookID, ch: ch) {
            chapter = loaded
        } else {
            chapter = nil
            loadFailed = true
        }
    }
}

// MARK: - Paragraph

private struct ParagraphView: View {
    let paragraph: ChapterParagraph
    let textScale: Double
    let isHighlighted: Bool
    let onLongPress: () -> Void

    var body: some View {
        Text(paragraph.text)
            .font(.system(size: 17.5 * textScale, design: .serif))
            .lineSpacing(8.5 * textScale)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isHighlighted ? 8 : 0)
            .padding(.vertical, isHighlighted ? 6 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Theme.highlightWash : Color.clear)
            )
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35) {
                onLongPress()
            }
    }
}

// MARK: - Highlight composer

private struct HighlightComposer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let bookID: String
    let ch: Int
    let paragraph: ChapterParagraph

    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Highlight").overline(Theme.accent)

                Text(paragraph.text)
                    .font(.callout)
                    .fontDesign(.serif)
                    .italic()
                    .lineLimit(5)
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.highlightWash))

                Text("chars \(paragraph.charStart)–\(paragraph.charEnd)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.inkSecondary)

                TextField("Margin note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.body)
                    .fontDesign(.serif)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule, lineWidth: 1))

                Spacer()
            }
            .padding()
            .background(Theme.paper)
            .navigationTitle("New highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        app.highlightStore.add(Highlight(
                            bookID: bookID, ch: ch,
                            charStart: paragraph.charStart,
                            charEnd: paragraph.charEnd,
                            note: trimmed.isEmpty ? nil : trimmed))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
