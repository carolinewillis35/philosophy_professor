import SwiftUI

/// Phase indicator for the news read (§15.2/§15.5): Brief → Lens A → Lens B
/// → The Split → Your Position, rendered from the client's NewsPhase mirror
/// above the chat — the clinic/steelman strip pattern. The lens phases use
/// the pair's actual lens names where they fit the dot labels; the current
/// phase's full lens name rides underneath either way.
struct NewsPhaseStrip: View {
    let phase: NewsPhase
    let pair: LensPair?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(NewsPhase.allCases.enumerated()), id: \.element) { index, step in
                    if index > 0 {
                        Rectangle()
                            .fill(reached(step) ? tint.opacity(0.5) : Theme.rule)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                    phaseDot(step)
                }
            }
            if let subtitle = currentLensLine {
                Text(subtitle)
                    .font(.caption2)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.rule, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("News phase: \(fullName(phase))")
    }

    /// The dot label: the pair's actual lens name when it fits the strip,
    /// else the generic "Lens A"/"Lens B" (§15.5 "where feasible").
    private func label(_ step: NewsPhase) -> String {
        switch step {
        case .lensA:
            if let name = pair?.a.name, name.count <= 12 { return name }
        case .lensB:
            if let name = pair?.b.name, name.count <= 12 { return name }
        default:
            break
        }
        return step.displayName
    }

    /// The full name for accessibility and the subtitle line.
    private func fullName(_ step: NewsPhase) -> String {
        switch step {
        case .lensA: return pair.map { "Lens A — \($0.a.name)" } ?? step.displayName
        case .lensB: return pair.map { "Lens B — \($0.b.name)" } ?? step.displayName
        default: return step.displayName
        }
    }

    /// The current lens, spelled out under the strip while a lens phase is
    /// live — the actual names get their room even when the dots can't.
    private var currentLensLine: String? {
        switch phase {
        case .lensA, .lensB: return fullName(phase)
        default: return nil
        }
    }

    private func phaseDot(_ step: NewsPhase) -> some View {
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
            Text(label(step))
                .font(.system(size: 9, weight: isCurrent ? .bold : .medium))
                .fontDesign(.default)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(isCurrent ? tint : Theme.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func reached(_ step: NewsPhase) -> Bool {
        let order = NewsPhase.allCases
        guard let current = order.firstIndex(of: phase),
              let target = order.firstIndex(of: step) else { return false }
        return target <= current
    }
}

// MARK: - Sources footer (§15.2/§15.5)

/// The brief's source URLs as tappable links — rendered client-side from the
/// brief (the session itself never searches; citations stay empty). Small,
/// quiet, at the foot of the session.
struct NewsSourcesFooter: View {
    let brief: NewsBrief
    let tint: Color

    var body: some View {
        if !brief.sourceUrls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sources").overline()
                ForEach(brief.sourceUrls, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                Text(displayText(urlString))
                                    .font(.caption)
                                    .fontDesign(.default)
                                    .underline()
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(tint)
                        }
                    }
                }
                Text("The story's sources — the professor read only the brief.")
                    .font(.caption2)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1))
        }
    }

    /// Host + path, without the scheme's noise.
    private func displayText(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host() else {
            return urlString
        }
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }
}
