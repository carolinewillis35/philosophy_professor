import SwiftUI

/// Phase indicator for the Argument Clinic (§13.3): intake → excavation →
/// map → crux → handback, rendered from the client's ClinicMapState above
/// the chat — mirroring the elenchus strip.
struct ClinicPhaseStrip: View {
    let phase: ClinicPhase
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ClinicPhase.allCases.enumerated()), id: \.element) { index, step in
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
        .accessibilityLabel("Clinic phase: \(phase.displayName)")
    }

    private func phaseDot(_ step: ClinicPhase) -> some View {
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

    private func reached(_ step: ClinicPhase) -> Bool {
        let order = ClinicPhase.allCases
        guard let current = order.firstIndex(of: phase),
              let target = order.firstIndex(of: step) else { return false }
        return target <= current
    }
}

// MARK: - Pinned live map

/// The user's argument pinned above the clinic chat (§13.3): the same
/// deterministic renderer as the argument lab, fed by the map the professor
/// is building via stateOps. Collapsible so the chat can breathe.
struct ClinicMapPanel: View {
    let spec: ArgumentSpec
    let cruxes: [String: ClinicCruxKind]
    let tint: Color

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: SessionKind.argumentClinic.symbolName)
                        .font(.footnote)
                        .foregroundStyle(tint)
                    Text("Your argument, mapped")
                        .font(.footnote.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("Live").overline(tint)
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
                ArgumentMapView(spec: spec, phase: .mapPresented, tint: tint,
                                cruxes: cruxes, dashUnstated: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }

            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .background(Theme.card)
    }
}

// MARK: - Home entry ("Bring me an argument", §13.5)

/// Clinic entry card for the home surface: pick a professor, bring a live
/// argument. Default whitmore (§13.3).
struct ClinicEntryCard: View {
    @Environment(AppModel.self) private var app

    @State private var selectedPersonaId = "whitmore"

    private var tint: Color { Theme.tint(for: selectedPersonaId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The Argument Clinic").overline(tint)
            Text("Bring me an argument")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text("A disagreement you're in, a take you're being pushed on, a decision with sides. A professor maps its structure — the judgment stays yours.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.rule).frame(height: 1)

            HStack(spacing: 10) {
                ForEach(app.personas) { persona in
                    personaChip(persona)
                }
            }

            NavigationLink(value: SessionRoute(standalone: .argumentClinic,
                                               personaId: selectedPersonaId)) {
                Label("Open the clinic", systemImage: SessionKind.argumentClinic.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.serif)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .bulletinCard(tint: tint)
    }

    private func personaChip(_ persona: Persona) -> some View {
        let isSelected = persona.id == selectedPersonaId
        let chipTint = Theme.tint(for: persona.id)
        return Button {
            selectedPersonaId = persona.id
        } label: {
            VStack(spacing: 5) {
                MonogramPortrait(persona: persona, size: 40)
                Text(persona.name.split(separator: " ").last.map(String.init) ?? persona.name)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .fontDesign(.default)
                    .foregroundStyle(isSelected ? chipTint : Theme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? chipTint.opacity(0.10) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? chipTint.opacity(0.6) : Theme.rule,
                              lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(persona.name), \(persona.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
