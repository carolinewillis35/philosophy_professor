import SwiftUI

/// Phase indicator for the steelman (§14.4/§14.5): brief → attempt → probe →
/// verdict → debrief, rendered from the client's SteelmanState above the
/// chat — mirroring the clinic strip.
struct SteelmanPhaseStrip: View {
    let phase: SteelmanPhase
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SteelmanPhase.allCases.enumerated()), id: \.element) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(reached(step) ? tint.opacity(0.5) : Theme.rule)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
                phaseDot(step)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.rule, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Steelman phase: \(phase.displayName)")
    }

    private func phaseDot(_ step: SteelmanPhase) -> some View {
        let isCurrent = step == phase
        return VStack(spacing: 4) {
            Circle()
                .fill(reached(step) ? tint : Theme.rule)
                .frame(width: isCurrent ? 9 : 6, height: isCurrent ? 9 : 6)
                .overlay {
                    if isCurrent {
                        Circle().strokeBorder(tint.opacity(0.35), lineWidth: 3)
                            .frame(width: 17, height: 17)
                    }
                }
            Text(step.displayName)
                .font(.system(size: 9, weight: isCurrent ? .bold : .medium))
                .fontDesign(.default)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(isCurrent ? tint : Theme.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func reached(_ step: SteelmanPhase) -> Bool {
        let order = SteelmanPhase.allCases
        guard let current = order.firstIndex(of: phase),
              let target = order.firstIndex(of: step) else { return false }
        return target <= current
    }
}

// MARK: - The verdict beat

/// The level as a designed beat (§14.5), rendered once recordSteelmanScore
/// lands — the four named ranks on their ladder, the earned rung lit. Level
/// names, never "failure" (§14.6): the grade is on the argument produced,
/// not the person.
struct SteelmanVerdictCard: View {
    let level: Int
    let justification: String?
    let tint: Color

    private var earned: SteelmanLevel { SteelmanLevel(rawValue: level) ?? .strawman }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Verdict").overline(tint)
            Text("Level \(earned.rawValue) — \(earned.displayName)")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Rectangle().fill(tint.opacity(0.35)).frame(height: 1)

            // The ladder itself, top rung first — every rank named, the
            // earned one lit. A rung is a place on a climb, not a mark.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SteelmanLevel.allCases.reversed()) { rank in
                    rungRow(rank)
                }
            }

            if let justification, !justification.isEmpty {
                Rectangle().fill(Theme.rule).frame(height: 1)
                Text(justification)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Graded against the argument you produced — never against you.")
                .font(.caption2)
                .fontDesign(.default)
                .foregroundStyle(Theme.inkSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func rungRow(_ rank: SteelmanLevel) -> some View {
        let isEarned = rank == earned
        let isReached = rank.rawValue <= earned.rawValue
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isEarned ? "largecircle.fill.circle" : "circle")
                .font(.caption2)
                .foregroundStyle(isReached ? tint : Theme.inkSecondary.opacity(0.5))
            Text("\(rank.rawValue) · \(rank.displayName)")
                .font(.caption.weight(isEarned ? .bold : .medium))
                .fontDesign(.default)
                .foregroundStyle(isEarned ? tint : (isReached ? Theme.ink : Theme.inkSecondary))
            Text(rank.descriptor)
                .font(.caption2)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
