import SwiftUI

/// One authored node of a thought experiment, rendered as a card with
/// tappable choice buttons (§12.7 / DECISIONS A10). The first node carries
/// the spec's setup text; branching is deterministic — no streaming, no
/// model. Node prose is authored course content, not a citation, so it is
/// never quote-styled (§9).
struct ExperimentNodeCard: View {
    let spec: ThoughtExperimentSpec
    let node: ThoughtExperimentSpec.Node
    let tint: Color
    let isBusy: Bool
    let onChoice: (ThoughtExperimentSpec.Option) -> Void

    private var isFirstNode: Bool { node.id == spec.startNode?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spec.title).overline(tint)

            if isFirstNode {
                Text(spec.setup)
                    .font(.body)
                    .fontDesign(.serif)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.rule).frame(height: 1)
            }

            Text(node.text)
                .font(.body.weight(isFirstNode ? .semibold : .regular))
                .fontDesign(.serif)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let options = node.options, !options.isEmpty {
                VStack(spacing: 8) {
                    ForEach(options, id: \.label) { option in
                        Button {
                            onChoice(option)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption)
                                Text(option.label)
                                    .font(.subheadline.weight(.medium))
                                    .fontDesign(.serif)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tint.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(tint.opacity(0.35), lineWidth: 1))
                            .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
                .padding(.top, 2)
            } else {
                Text("The case is closed. Your professor takes it from here.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }
}

/// "The dial turns" — an authored intuition-pump variation, visually
/// distinct from both professor prose and node cards (§12.7). Rendered when
/// the professor's `applyPump` stateOp fires.
struct PumpCard: View {
    let pump: ThoughtExperimentSpec.Pump
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "dial.high")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Text("The dial turns").overline(tint)
            }
            Text(pump.variation)
                .font(.callout)
                .fontDesign(.serif)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(tint.opacity(0.25)).frame(height: 1)
            Text("Testing: \(pump.testsPrinciple)")
                .font(.caption)
                .fontDesign(.default)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.highlightWash))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
    }
}
