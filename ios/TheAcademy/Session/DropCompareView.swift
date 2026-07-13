import SwiftUI

/// The re-encounter side-by-side (§15.4/§15.5): both runs of the same drop —
/// dates, first choices, full paths — shown after a repeat cycle completes.
/// Copy law: difference is growth, sameness is consistency, and NEITHER is
/// graded (§14.6 spirit).
struct DropCompareView: View {
    @Environment(AppModel.self) private var app
    let drop: Drop
    let prior: DropStore.CompletionRecord
    let current: DropStore.CompletionRecord

    private var tint: Color { Theme.tint(for: drop.personaId) }
    private var persona: Persona? { app.persona(drop.personaId) }

    private var sameFirstChoice: Bool {
        prior.firstChoice == current.firstChoice
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Text(framing)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    runColumn(title: "Then", record: prior)
                    runColumn(title: "Now", record: current)
                }

                Text("Two readings of the same case, side by side — neither is graded. The case didn't change; the reader gets to.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Then & Now")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("A re-encounter").overline(tint)
                Spacer()
                if let persona {
                    MonogramPortrait(persona: persona, size: 26)
                }
            }
            Text(drop.experiment.title)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    /// Difference framed as growth, sameness as consistency — never a score.
    private var framing: String {
        sameFirstChoice
            ? "You opened the case the same way twice, a cycle apart. That's consistency — a position that held while you weren't looking at it."
            : "You opened the case differently this time. That's growth — the same door, read by someone who has thought more since."
    }

    private func runColumn(title: String,
                           record: DropStore.CompletionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).overline(tint)
            Text(Self.displayDate(record.localDate))
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)

            Rectangle().fill(Theme.rule).frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("First choice").overline()
                Text(record.firstChoice.isEmpty ? "—" : record.firstChoice)
                    .font(.footnote.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.path.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The path").overline()
                    ForEach(Array(record.path.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).")
                                .font(.caption2.weight(.semibold))
                                .fontDesign(.default)
                                .monospacedDigit()
                                .foregroundStyle(tint)
                            Text(step.choice)
                                .font(.caption)
                                .fontDesign(.serif)
                                .lineSpacing(2)
                                .foregroundStyle(Theme.ink.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bulletinCard(tint: tint)
    }

    /// "2026-05-30" → "May 30, 2026"; falls back to the raw string.
    static func displayDate(_ localDate: String) -> String {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return localDate }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return localDate }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
