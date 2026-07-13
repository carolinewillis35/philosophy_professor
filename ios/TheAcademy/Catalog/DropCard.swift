import SwiftUI

/// The weekly drop card on the home surface (§14.3/§14.5): "This week:
/// <title>" + the authored teaser + the professor + a text-only share
/// affordance. Tapping runs the drop as a standalone thoughtExperiment
/// session; a completed week shows the calm done state and the only other
/// door to the CROWD screen.
struct DropCard: View {
    @Environment(AppModel.self) private var app

    private var store: DropStore { app.drops }
    private var drop: Drop? { store.thisWeekDrop }
    private var tint: Color { Theme.tint(for: drop?.personaId) }
    private var persona: Persona? { drop.flatMap { app.persona($0.personaId) } }

    var body: some View {
        if let drop {
            VStack(alignment: .leading, spacing: 12) {
                header(drop)

                Text("This week: \(drop.experiment.title)")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(drop.teaser)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // §15.4 re-encounter badge: this week's drop has a
                // PRIOR-cycle response — the case remembers you.
                if let prior = store.priorResponse(for: drop) {
                    reencounterBadge(prior)
                }

                Rectangle().fill(Theme.rule).frame(height: 1)

                if store.isCompleted(drop) {
                    completedBody(drop)
                } else {
                    NavigationLink(value: SessionRoute(drop: drop)) {
                        Label("Run the experiment",
                              systemImage: SessionKind.thoughtExperiment.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                }

                // Text-only share affordance (§14.5): the teaser travels;
                // the case waits here.
                ShareLink(item: shareText(drop)) {
                    Label("Share this week's case", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityLabel("Share this week's thought experiment")
            }
            .bulletinCard(tint: tint)
        }
    }

    private func header(_ drop: Drop) -> some View {
        HStack(spacing: 8) {
            Text("The Weekly Drop").overline(tint)
            Spacer()
            if let persona {
                Text(persona.name)
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                MonogramPortrait(persona: persona, size: 26)
            }
        }
    }

    /// Calm done state — the run is complete for this cycle; the crowd is
    /// now (and only now) on offer.
    @ViewBuilder
    private func completedBody(_ drop: Drop) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(tint)
            Text("You ran this week's case.")
                .font(.footnote.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }

        NavigationLink {
            DropCrowdView(drop: drop)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.footnote)
                Text("See where the crowd landed")
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

        // §15.4: a completed re-encounter earns the side-by-side — both
        // runs, neither graded.
        if let prior = store.priorResponse(for: drop),
           let current = store.completion, current.dropId == drop.id {
            NavigationLink {
                DropCompareView(drop: drop, prior: prior, current: current)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote)
                    Text("Then & now — compare your two runs")
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

    /// "You've been here before" — a fact about the calendar, not a nudge.
    private func reencounterBadge(_ prior: DropStore.CompletionRecord) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
            Text("You've been here before — \(DropCompareView.displayDate(prior.localDate))")
                .font(.caption.weight(.medium))
                .fontDesign(.serif)
                .italic()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("You answered this drop before, on \(DropCompareView.displayDate(prior.localDate))")
    }

    private func shareText(_ drop: Drop) -> String {
        "This week's thought experiment from The Academy — \(drop.experiment.title): \(drop.teaser)"
    }
}
