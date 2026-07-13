import SwiftUI

/// The monthly Symposium card on the home surface (§16.2/§16.5): "This
/// month's Symposium: <question>", the two professors and their one-liners.
/// Tapping opens the BEFORE-TAP sheet — position A / position B / undecided,
/// one tap — and only then does the debate session start: the before is
/// captured before any argument is heard, and is never shown to the session
/// UI after (§16.6). A completed month shows the calm done state and the
/// only home-surface door to the MOVEMENT screen.
struct SymposiumCard: View {
    @Environment(AppModel.self) private var app

    @State private var showBeforeTap = false
    @State private var chosenStance: SymposiumStance?
    @State private var startedRoute: SessionRoute?

    private var store: SymposiumStore { app.symposia }
    private var symposium: SymposiumSpec? { store.thisMonthSymposium }
    private var tint: Color { Theme.tint(for: symposium?.personaA) }

    var body: some View {
        if let symposium {
            VStack(alignment: .leading, spacing: 12) {
                header(symposium)

                Text("This month's Symposium: \(symposium.question)")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                positionLine(personaId: symposium.personaA,
                             position: symposium.positionA)
                positionLine(personaId: symposium.personaB,
                             position: symposium.positionB)

                Rectangle().fill(Theme.rule).frame(height: 1)

                if store.response(for: symposium)?.completed == true {
                    completedBody(symposium)
                } else {
                    Button {
                        // The before-tap already happened this month (an
                        // abandoned run): straight back into the room —
                        // never a second before-tap (§16.6).
                        if let record = store.response(for: symposium) {
                            startedRoute = SessionRoute(symposium: symposium,
                                                        before: record.before)
                        } else {
                            showBeforeTap = true
                        }
                    } label: {
                        Label("Take your seat",
                              systemImage: SessionKind.symposium.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                }
            }
            .bulletinCard(tint: tint)
            .sheet(isPresented: $showBeforeTap, onDismiss: {
                guard let stance = chosenStance else { return }
                chosenStance = nil
                store.recordBefore(symposium: symposium, stance: stance)
                startedRoute = SessionRoute(symposium: symposium, before: stance)
            }) {
                BeforeTapSheet(symposium: symposium, tint: tint) { stance in
                    chosenStance = stance
                    showBeforeTap = false
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(item: $startedRoute) { SessionView(route: $0) }
        }
    }

    private func header(_ symposium: SymposiumSpec) -> some View {
        HStack(spacing: 8) {
            Text("The Symposium").overline(tint)
            Spacer()
            HStack(spacing: -6) {
                MonogramPortrait(persona: app.persona(symposium.personaA), size: 26)
                MonogramPortrait(persona: app.persona(symposium.personaB), size: 26)
            }
        }
    }

    /// One professor's name + one-liner — both sides at full strength.
    private func positionLine(personaId: String,
                              position: SymposiumPosition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app.persona(personaId)?.name ?? personaId.capitalized)
                .overline(Theme.tint(for: personaId))
            Text(position.label)
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Calm done state — this month's session is complete; the movement is
    /// now (and only now) on offer (§16.6).
    @ViewBuilder
    private func completedBody(_ symposium: SymposiumSpec) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(tint)
            Text("You sat this month's symposium.")
                .font(.footnote.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }

        NavigationLink {
            SymposiumMovementView(symposium: symposium)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .font(.footnote)
                Text("See where the house moved")
                    .font(.footnote.weight(.medium))
                    .fontDesign(.serif)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The before-tap (§16.2/§16.6)

/// Where do you arrive? One tap — a side's one-liner, or undecided — and the
/// session begins. This MUST precede the arguments: the ordering is the
/// data's honesty. Undecided is a position, not a hedge (§16.6).
private struct BeforeTapSheet: View {
    @Environment(AppModel.self) private var app
    let symposium: SymposiumSpec
    let tint: Color
    let onChoose: (SymposiumStance) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you hear a word").overline(tint)

                Text(symposium.question)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Where do you arrive? One tap, kept private — the debate starts the moment you answer.")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                stanceButton(.a, title: app.persona(symposium.personaA)?.name
                                ?? symposium.personaA.capitalized,
                             line: symposium.positionA.label,
                             buttonTint: Theme.tint(for: symposium.personaA))
                stanceButton(.b, title: app.persona(symposium.personaB)?.name
                                ?? symposium.personaB.capitalized,
                             line: symposium.positionB.label,
                             buttonTint: Theme.tint(for: symposium.personaB))
                stanceButton(.undecided, title: "Undecided",
                             line: "You'd rather hear the arguments first — a position in its own right.",
                             buttonTint: Theme.inkSecondary)
            }
            .padding(20)
        }
        .background(Theme.paper)
    }

    private func stanceButton(_ stance: SymposiumStance, title: String,
                              line: String, buttonTint: Color) -> some View {
        Button {
            onChoose(stance)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).overline(buttonTint)
                Text(line)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(buttonTint.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
