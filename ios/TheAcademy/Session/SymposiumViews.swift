import SwiftUI

/// Phase indicator for the monthly Symposium (§16.2/§16.5): The Question →
/// The Exchange → Your Ruling → Cross-Examination → Debrief, rendered from
/// the client's SymposiumClientState mirror above the chat — the
/// clinic/steelman/news strip pattern.
struct SymposiumPhaseStrip: View {
    let phase: SymposiumPhase
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SymposiumPhase.allCases.enumerated()), id: \.element) { index, step in
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
        .accessibilityLabel("Symposium phase: \(phase.displayName)")
    }

    /// The strip is tight for five long names; the dots wear short labels.
    private func label(_ step: SymposiumPhase) -> String {
        switch step {
        case .questionPresented: return "Question"
        case .exchange: return "Exchange"
        case .adjudication: return "Ruling"
        case .crossExamination: return "Cross-Exam"
        case .jointDebrief: return "Debrief"
        }
    }

    private func phaseDot(_ step: SymposiumPhase) -> some View {
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

    private func reached(_ step: SymposiumPhase) -> Bool {
        let order = SymposiumPhase.allCases
        guard let current = order.firstIndex(of: phase),
              let target = order.firstIndex(of: step) else { return false }
        return target <= current
    }
}

// MARK: - Multi-voice bubble (§16.2: the envelope's speakers[] contract)

/// A professor turn with two voices in it: one labeled block per speakers[]
/// entry, each in its professor's name and tint. While the turn is still
/// streaming (speakers[] arrives only with the envelope), the say text's
/// "NAME: …" labeling is parsed live so the voices separate as they speak.
struct SymposiumBubble: View {
    @Environment(AppModel.self) private var app
    let message: TurnMessage
    /// The two persona ids sharing the room, for the fallback parser.
    let voiceIds: [String]
    /// The room's fallback tint for unattributed prose.
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 6) {
                    if let personaId = segment.personaId {
                        HStack(spacing: 6) {
                            Text(app.persona(personaId)?.name ?? personaId.capitalized)
                                .overline(Theme.tint(for: personaId))
                            if message.isStreaming && index == segments.count - 1 {
                                streamingDots(Theme.tint(for: personaId))
                            }
                        }
                    } else if index == 0 {
                        HStack(spacing: 6) {
                            Text("The Symposium").overline(tint)
                            if message.isStreaming && segments.count == 1 {
                                streamingDots(tint)
                            }
                        }
                    }
                    Text(attributed(segment.text))
                        .font(.body)
                        .fontDesign(.serif)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .overlay(alignment: .leading) {
                    if let personaId = segment.personaId {
                        Rectangle()
                            .fill(Theme.tint(for: personaId).opacity(0.35))
                            .frame(width: 2)
                            .padding(.leading, -10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    private struct Segment {
        let personaId: String?
        let text: String
    }

    /// speakers[] when the envelope has landed; the "NAME: …" convention
    /// parsed from the streamed text otherwise. Citations stay empty for
    /// this kind (§16.2), so the voices carry only prose.
    private var segments: [Segment] {
        if !message.speakers.isEmpty {
            return message.speakers.map { Segment(personaId: $0.personaId, text: $0.say) }
        }
        return Self.parse(message.text, voiceIds: voiceIds)
    }

    /// Split labeled dialogue — "WHITMORE: …\n\nLINDQVIST: …" — into voice
    /// segments; prose before any label stays unattributed.
    private static func parse(_ text: String, voiceIds: [String]) -> [Segment] {
        var segments: [Segment] = []
        var currentId: String?
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty || currentId != nil {
                segments.append(Segment(personaId: currentId, text: trimmed))
            }
            current = ""
        }

        for line in text.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if let colon = trimmedLine.firstIndex(of: ":") {
                let label = String(trimmedLine[..<colon])
                    .trimmingCharacters(in: .whitespaces)
                if let match = voiceIds.first(where: {
                    $0.caseInsensitiveCompare(label) == .orderedSame
                }) {
                    flush()
                    currentId = match
                    current = String(trimmedLine[trimmedLine.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    continue
                }
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        flush()
        return segments
    }

    private func streamingDots(_ color: Color) -> some View {
        Image(systemName: "ellipsis")
            .font(.caption2)
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative, options: .repeating)
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

// MARK: - The MOVEMENT screen (§16.3/§16.5)

/// "This argument moved N% of you" — where the house arrived vs. where it
/// ruled, reachable ONLY after the caller's own completed run (§16.6),
/// mirroring the `symposium_movement` RPC's hard gate. Copy law: movement is
/// described, never prescribed; distributions never identify anyone;
/// undecided is a position. Your own path shows privately at the top.
struct SymposiumMovementView: View {
    @Environment(AppModel.self) private var app
    let symposium: SymposiumSpec

    private var store: SymposiumStore { app.symposia }
    private var tint: Color { Theme.tint(for: symposium.personaA) }

    /// The gate (§16.6): no completed response, no movement.
    private var response: SymposiumStore.ResponseRecord? {
        let record = store.response(for: symposium)
        return record?.completed == true ? record : nil
    }

    private var movement: SymposiumMovement? { store.movement(for: symposium.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let response {
                    yourPathCard(response)

                    if let movement, let moved = movement.moved,
                       let byBefore = movement.byBefore, let byAfter = movement.byAfter {
                        movementCard(moved: moved, total: movement.total,
                                     byBefore: byBefore, byAfter: byAfter)
                    } else {
                        smallHouseCard(total: movement?.total ?? 0)
                    }
                } else {
                    // Should be unreachable — the screen is only linked from
                    // a completed run — but the gate holds regardless.
                    completeFirstCard
                }

                guardrailNote
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("The Movement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This month's symposium").overline(tint)
            Text(symposium.question)
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    /// Your own path, before → after — private, yours alone, above any
    /// number (§16.6: your own debrief precedes the aggregate).
    private func yourPathCard(_ response: SymposiumStore.ResponseRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your path — yours alone").overline(tint)
            HStack(spacing: 10) {
                Text(stanceName(response.before))
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(response.after.map(stanceName)
                     ?? "You left it open — that's a position.")
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    // MARK: the movement — description, never pressure (§16.6)

    private func movementCard(moved: Int, total: Int,
                              byBefore: [String: Int],
                              byAfter: [String: Int]) -> some View {
        let pct = total > 0 ? Int((Double(moved) / Double(total) * 100).rounded()) : 0
        let ruled = (byAfter["a"] ?? 0) + (byAfter["b"] ?? 0)
        let leftOpen = max(0, total - ruled)
        return VStack(alignment: .leading, spacing: 14) {
            Text("This argument moved \(pct)% of you.")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text("\(total) symposiasts heard the whole exchange; \(moved) ruled somewhere other than where they arrived.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.rule).frame(height: 1)

            Text("Where the house arrived").overline()
            ForEach(["a", "b", "undecided"], id: \.self) { key in
                stanceRow(key, count: byBefore[key] ?? 0, total: total)
            }

            Rectangle().fill(Theme.rule).frame(height: 1)

            Text("Where the house ruled").overline()
            ForEach(["a", "b"], id: \.self) { key in
                stanceRow(key, count: byAfter[key] ?? 0, total: total)
            }
            if leftOpen > 0 {
                Text("\(leftOpen) left it open — that's a position.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    private func stanceRow(_ key: String, count: Int, total: Int) -> some View {
        let stance = SymposiumStance(rawValue: key) ?? .undecided
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        let pct = Int((fraction * 100).rounded())
        let rowTint = symposium.personaId(for: stance).map { Theme.tint(for: $0) }
            ?? Theme.inkSecondary
        return VStack(alignment: .leading, spacing: 5) {
            Text(stanceName(stance))
                .font(.footnote)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.rule.opacity(0.6))
                        Capsule()
                            .fill(rowTint.opacity(0.7))
                            .frame(width: max(geo.size.width * fraction,
                                              count > 0 ? 4 : 0))
                    }
                }
                .frame(height: 6)
                Text("\(pct)%")
                    .font(.caption2.weight(.semibold))
                    .fontDesign(.default)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stanceName(stance)): \(pct) percent")
    }

    /// A side's display name: the professor holding it; undecided stands on
    /// its own.
    private func stanceName(_ stance: SymposiumStance) -> String {
        if let personaId = symposium.personaId(for: stance) {
            return "With \(app.persona(personaId)?.name ?? personaId.capitalized)"
        }
        return "Undecided"
    }

    // MARK: suppressed / gated states

    /// Small-house suppression (§16.3): under 10 completed responses the RPC
    /// returns nulls and the count is all anyone sees.
    private func smallHouseCard(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Too few symposiasts yet").overline(tint)
            Text("Too few symposiasts yet — check back. The movement only shows once enough people have heard the whole exchange for the numbers to mean something.")
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

    private var completeFirstCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After your own debrief").overline(tint)
            Text("The movement exists only after you've heard the whole exchange and sat the debrief yourself. Attend this month's symposium first.")
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
        Text("Where the house moved — a description, never a verdict. No side won; the argument is the part worth keeping.")
            .font(.caption)
            .fontDesign(.serif)
            .italic()
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
