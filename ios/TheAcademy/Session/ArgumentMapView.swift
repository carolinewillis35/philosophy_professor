import SwiftUI

/// Deterministic argument-map renderer (§12.7 / DECISIONS A11): pure SwiftUI
/// geometry from the authored `ArgumentSpec`, no LLM anywhere in the render
/// path. Premises sit in layers above the conclusion; connector lines
/// converge on what each premise supports. In hunt mode the unstated premise
/// renders as a dashed empty slot until `reveal`; in collapse mode the
/// removed premise is greyed out.
struct ArgumentMapView: View {
    let spec: ArgumentSpec
    let phase: ArgumentLabPhase
    let tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 34) {
                ForEach(layers.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(layers[index]) { premise in
                            premiseNode(premise)
                        }
                    }
                }
                conclusionNode
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .backgroundPreferenceValue(NodeAnchorsKey.self) { anchors in
                GeometryReader { proxy in
                    connectors(anchors: anchors, in: proxy)
                }
            }
        }
    }

    // MARK: layered layout (premise depth = hops to the conclusion)

    /// Rows of premises, deepest first, so support chains read downward into
    /// the conclusion.
    private var layers: [[ArgumentSpec.Premise]] {
        var depths: [String: Int] = [spec.conclusion.id: 0]
        // Statements form a small tree; a few passes settle every depth.
        for _ in 0..<spec.premises.count {
            for premise in spec.premises where depths[premise.id] == nil {
                if let target = depths[premise.supports] {
                    depths[premise.id] = target + 1
                }
            }
        }
        let grouped = Dictionary(grouping: spec.premises) { depths[$0.id] ?? 1 }
        return grouped.keys.sorted(by: >).map { depth in
            grouped[depth] ?? []
        }
    }

    // MARK: node states

    private func isHiddenSlot(_ premise: ArgumentSpec.Premise) -> Bool {
        spec.mode == .hunt
            && premise.id == spec.hiddenPremiseId
            && phase != .reveal && phase != .rebuild
    }

    private func isRemoved(_ premise: ArgumentSpec.Premise) -> Bool {
        spec.mode == .collapse && premise.id == spec.removedPremiseId
            && phase != .mapPresented
    }

    private func isRevealed(_ premise: ArgumentSpec.Premise) -> Bool {
        spec.mode == .hunt && premise.id == spec.hiddenPremiseId
            && (phase == .reveal || phase == .rebuild)
    }

    // MARK: nodes

    @ViewBuilder
    private func premiseNode(_ premise: ArgumentSpec.Premise) -> some View {
        Group {
            if isHiddenSlot(premise) {
                // The unstated premise: an empty slot to be hunted (§12.1).
                VStack(spacing: 6) {
                    Image(systemName: "questionmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                    Text("Unstated premise")
                        .font(.caption2.weight(.semibold))
                        .fontDesign(.default)
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: nodeWidth)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(premise.id.uppercased())
                            .font(.caption2.weight(.bold))
                            .fontDesign(.default)
                            .foregroundStyle(labelColor(premise))
                        if isRemoved(premise) {
                            Text("removed").overline(Theme.inkSecondary)
                        } else if isRevealed(premise) {
                            Text("found").overline(tint)
                        } else if !premise.stated {
                            Text("unstated").overline(tint)
                        }
                    }
                    Text(premise.text)
                        .font(.caption)
                        .fontDesign(.serif)
                        .lineSpacing(2)
                        .foregroundStyle(isRemoved(premise) ? Theme.inkSecondary.opacity(0.6) : Theme.ink)
                        .strikethrough(isRemoved(premise), color: Theme.inkSecondary.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(width: nodeWidth, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isRemoved(premise) ? Theme.rule.opacity(0.35)
                          : isRevealed(premise) ? tint.opacity(0.12)
                          : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isRevealed(premise) ? tint : Theme.rule,
                                  lineWidth: isRevealed(premise) ? 1.5 : 1))
                .opacity(isRemoved(premise) ? 0.55 : 1)
            }
        }
        .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { [premise.id: $0] }
    }

    private var conclusionNode: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conclusion").overline(tint)
            Text(spec.conclusion.text)
                .font(.footnote.weight(.medium))
                .fontDesign(.serif)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: nodeWidth * 1.6, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.6), lineWidth: 1.5))
        .anchorPreference(key: NodeAnchorsKey.self, value: .bounds) { [spec.conclusion.id: $0] }
    }

    private func labelColor(_ premise: ArgumentSpec.Premise) -> Color {
        isRemoved(premise) ? Theme.inkSecondary : tint
    }

    private var nodeWidth: CGFloat { 150 }

    // MARK: connectors (inference edges)

    @ViewBuilder
    private func connectors(anchors: [String: Anchor<CGRect>], in proxy: GeometryProxy) -> some View {
        let solid = edgePath(anchors: anchors, proxy: proxy) { !edgeIsDashed($0) }
        let dashed = edgePath(anchors: anchors, proxy: proxy) { edgeIsDashed($0) }
        solid.stroke(Theme.rule, lineWidth: 1.2)
        dashed.stroke(tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
    }

    /// An edge draws dashed while its premise is the hunted empty slot.
    private func edgeIsDashed(_ premise: ArgumentSpec.Premise) -> Bool {
        isHiddenSlot(premise) || isRemoved(premise)
    }

    private func edgePath(anchors: [String: Anchor<CGRect>],
                          proxy: GeometryProxy,
                          include: (ArgumentSpec.Premise) -> Bool) -> Path {
        Path { path in
            for premise in spec.premises where include(premise) {
                guard let fromAnchor = anchors[premise.id],
                      let toAnchor = anchors[premise.supports] else { continue }
                let from = proxy[fromAnchor]
                let to = proxy[toAnchor]
                let start = CGPoint(x: from.midX, y: from.maxY)
                let end = CGPoint(x: to.midX, y: to.minY)
                path.move(to: start)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x, y: start.y + (end.y - start.y) * 0.55),
                    control2: CGPoint(x: end.x, y: end.y - (end.y - start.y) * 0.55))
            }
        }
    }
}

private struct NodeAnchorsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Pinned panel

/// The map pinned above the session transcript, collapsible so the chat can
/// breathe on small screens.
struct ArgumentMapPanel: View {
    let spec: ArgumentSpec
    let phase: ArgumentLabPhase
    let tint: Color

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.footnote)
                        .foregroundStyle(tint)
                    Text(spec.title)
                        .font(.footnote.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(spec.mode == .hunt ? "Hunt" : "Collapse").overline(tint)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse argument map" : "Expand argument map")

            if expanded {
                ArgumentMapView(spec: spec, phase: phase, tint: tint)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }

            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .background(Theme.card)
    }
}
