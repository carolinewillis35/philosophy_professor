import SwiftUI

/// Phase indicator for the elenchus (§12.7): thesis → definition →
/// counterexample → revision → reflection, rendered from session state above
/// the chat. The counterexample⇄revision loop re-lights as it cycles.
struct ElenchusPhaseStrip: View {
    let state: ElenchusState
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(ElenchusPhase.allCases.enumerated()), id: \.element) { index, phase in
                    if index > 0 {
                        Rectangle()
                            .fill(reached(phase) ? tint.opacity(0.5) : Theme.rule)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                    phaseDot(phase)
                }
            }
            if state.revisions > 0, state.phase != .reflection {
                Text("Revision \(state.revisions) — the definition is still on the table.")
                    .font(.caption2)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.rule, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elenchus phase: \(state.phase.displayName)")
    }

    private func phaseDot(_ phase: ElenchusPhase) -> some View {
        let isCurrent = phase == state.phase
        return VStack(spacing: 4) {
            Circle()
                .fill(reached(phase) ? tint : Theme.rule)
                .frame(width: isCurrent ? 9 : 6, height: isCurrent ? 9 : 6)
                .overlay {
                    if isCurrent {
                        Circle().strokeBorder(tint.opacity(0.35), lineWidth: 3)
                            .frame(width: 17, height: 17)
                    }
                }
            Text(phase.displayName)
                .font(.system(size: 9, weight: isCurrent ? .bold : .medium))
                .fontDesign(.default)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(isCurrent ? tint : Theme.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func reached(_ phase: ElenchusPhase) -> Bool {
        let order = ElenchusPhase.allCases
        guard let current = order.firstIndex(of: state.phase),
              let target = order.firstIndex(of: phase) else { return false }
        return target <= current
    }
}

/// The aporia beat (§12.7 / §12.8): a designed success state, not an error.
/// Calm, full-width, in the bulletin's voice — "you now know what you don't
/// know."
struct AporiaCard: View {
    let tint: Color
    var reflectionPrompt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aporia").overline(tint)
            Text("You now know what you don't know.")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Rectangle().fill(tint.opacity(0.35)).frame(height: 1)
            Text("Every definition on the table tonight has been examined and found wanting — including yours. Socrates counted this the beginning of wisdom, not the end of the conversation. The reflection below is where the dismantling becomes yours to keep.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }
}

/// The robust outcome, for symmetry: the definition survived the gauntlet.
struct RobustOutcomeCard: View {
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Withstood examination").overline(tint)
            Text("Your definition survived the counterexamples.")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text("Survival is not proof — it is an invitation to harder counterexamples. Bring it back next session.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }
}
