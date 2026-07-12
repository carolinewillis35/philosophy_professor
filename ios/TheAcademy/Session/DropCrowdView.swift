import SwiftUI

/// The CROWD screen (§14.3/§14.5): where everyone's first choice landed
/// against yours, reachable ONLY from a completed run — mirroring the
/// `drop_aggregate` RPC's hard gate. §14.6 is copy law here: the numbers are
/// a description of where people landed, never what one should think; small
/// crowds (total < 10) are suppressed.
struct DropCrowdView: View {
    @Environment(AppModel.self) private var app
    let drop: Drop

    private var store: DropStore { app.drops }
    private var tint: Color { Theme.tint(for: drop.personaId) }
    private var persona: Persona? { app.persona(drop.personaId) }

    /// The user's own recorded first choice — the gate (§14.6): no answer,
    /// no aggregate.
    private var yourChoice: String? {
        store.isCompleted(drop) ? store.completion?.firstChoice : nil
    }

    private var aggregate: DropAggregate? { store.aggregate(for: drop.id) }

    /// The start node's options, so the distribution renders in the authored
    /// order and shows zero-count choices too.
    private var choiceLabels: [String] {
        drop.experiment.startNode?.options?.map(\.label) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if yourChoice == nil {
                    // Should be unreachable — the screen is only linked from
                    // a completed run — but the gate holds regardless.
                    answerFirstCard
                } else if let aggregate, let byFirstChoice = aggregate.byFirstChoice {
                    distribution(byFirstChoice, total: aggregate.total)
                } else {
                    smallCrowdCard(total: aggregate?.total ?? 0)
                }

                guardrailNote
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("The Crowd")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("This week's divide").overline(tint)
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

    // MARK: the distribution — description, never pressure (§14.6)

    private func distribution(_ byFirstChoice: [String: Int], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headline(byFirstChoice, total: total))
                .font(.subheadline)
                .fontDesign(.serif)
                .lineSpacing(3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.rule).frame(height: 1)

            ForEach(orderedLabels(byFirstChoice), id: \.self) { label in
                choiceRow(label,
                          count: byFirstChoice[label] ?? 0,
                          total: total,
                          isYours: label == yourChoice)
            }
        }
        .bulletinCard(tint: tint)
    }

    /// Ordered as authored, with any off-spec keys appended for safety.
    private func orderedLabels(_ byFirstChoice: [String: Int]) -> [String] {
        let authored = choiceLabels
        let extras = byFirstChoice.keys.filter { !authored.contains($0) }.sorted()
        return authored + extras
    }

    /// "68% plugged in; you didn't; here's the divide" — the where-people-
    /// landed sentence, phrased as a description of the crowd, never a
    /// verdict on the reader.
    private func headline(_ byFirstChoice: [String: Int], total: Int) -> String {
        guard total > 0, let yourChoice else {
            return "\(total) thinkers have run this drop."
        }
        let yours = byFirstChoice[yourChoice] ?? 0
        let pct = Int((Double(yours) / Double(total) * 100).rounded())
        return "\(total) thinkers have run this drop. \(pct)% opened it the way you did — here's the divide."
    }

    private func choiceRow(_ label: String, count: Int, total: Int,
                           isYours: Bool) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        let pct = Int((fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if isYours {
                    Text("You")
                        .font(.caption2.weight(.bold))
                        .fontDesign(.default)
                        .textCase(.uppercase)
                        .kerning(0.7)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(tint)
                }
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.rule.opacity(0.6))
                        Capsule()
                            .fill(isYours ? tint : tint.opacity(0.4))
                            .frame(width: max(geo.size.width * fraction,
                                              count > 0 ? 4 : 0))
                    }
                }
                .frame(height: 6)
                Text("\(pct)%")
                    .font(.caption2.weight(.semibold))
                    .fontDesign(.default)
                    .monospacedDigit()
                    .foregroundStyle(isYours ? tint : Theme.inkSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(pct) percent\(isYours ? ", your choice" : "")")
    }

    // MARK: suppressed / gated states

    /// Small-crowd suppression (§14.3): under 10 responses the RPC returns
    /// byFirstChoice null and this is all anyone sees.
    private func smallCrowdCard(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Too few thinkers yet").overline(tint)
            Text("Too few thinkers yet — check back. The divide only shows once enough people have walked the case for the numbers to mean something.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    private var answerFirstCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After your answer").overline(tint)
            Text("The crowd exists only after you've walked the case yourself. Run this week's drop first.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    private var guardrailNote: some View {
        Text("Where people landed — a description, never a verdict. The reasons are the part worth arguing about.")
            .font(.caption)
            .fontDesign(.serif)
            .italic()
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
