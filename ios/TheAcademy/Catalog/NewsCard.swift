import SwiftUI

/// The weekly news card on the home surface, below the drop card (§15.2 /
/// §15.5): "This week, read philosophically: <headline>" + the live question
/// + the professor. Tapping runs the standalone newsRead session — one story,
/// two authored lenses, the split, and (optionally) a position. ABSOLUTELY no
/// aggregates or poll framing here or anywhere on news (§15.2).
struct NewsCard: View {
    @Environment(AppModel.self) private var app

    /// The news professor: whitmore unless the student picked otherwise —
    /// the server's default for newsRead starts.
    private let personaId = "whitmore"

    private var tint: Color { Theme.tint(for: personaId) }
    private var persona: Persona? { app.persona(personaId) }

    var body: some View {
        if let brief = app.newsBrief {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text("This week, read philosophically: \(brief.headline)")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(brief.question)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Theme.rule).frame(height: 1)

                NavigationLink(value: SessionRoute(news: brief, personaId: personaId)) {
                    Label("Read it through two lenses",
                          systemImage: SessionKind.newsRead.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.serif)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

                // One story, two frameworks, no crowd: the question is
                // shared; the numbers never are.
                Text("\(brief.lensPair.a.name) · \(brief.lensPair.b.name)")
                    .font(.caption)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .bulletinCard(tint: tint)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("The News, Read Philosophically").overline(tint)
            Spacer()
            if let persona {
                Text(persona.name)
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                MonogramPortrait(persona: persona, size: 26)
            }
        }
    }
}
