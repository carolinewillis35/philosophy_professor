import SwiftUI

/// Professor bio card: monogram portrait placeholder (DECISIONS #6) with the
/// professor's tint, name, chair title, and blurb.
struct ProfessorCard: View {
    let persona: Persona

    private var tint: Color { Theme.tint(for: persona.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MonogramPortrait(persona: persona, size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Faculty").overline(tint)
                    Text(persona.name)
                        .font(.headline)
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                    Text(persona.title)
                        .font(.footnote)
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Text(persona.blurb)
                .font(.subheadline)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .bulletinCard(tint: tint)
    }
}
