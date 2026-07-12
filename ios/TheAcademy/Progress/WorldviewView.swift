import SwiftUI

/// The Academy's identity surface (§12.7 / DECISIONS A14): the student's
/// Commitment Map — positions by domain, open tensions drawn as connected
/// pairs, a timeline of strength changes, contest affordances mirroring the
/// §12.3 RLS grants, markdown export, and the full-transparency note. The
/// reader-profile radar survives as a secondary section; commitments are the
/// product, attention dimensions are supporting cast.
struct WorldviewView: View {
    @Environment(AppModel.self) private var app

    @State private var confirmingDelete: Commitment?

    private var store: WorldviewStore { app.worldview }

    /// Office-hours deep link target for "discuss this" (contest flow).
    private var officeHoursRoute: SessionRoute? {
        let course = app.userStore.enrollments.first.flatMap { app.course($0.courseId) }
            ?? app.courses.first
        guard let course else { return nil }
        let unit = app.userStore.enrollment(for: course.id)?.currentUnit ?? 0
        return SessionRoute(course: course,
                            unit: min(unit, max(course.units.count - 1, 0)),
                            kind: .officeHours)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if store.commitments.isEmpty {
                    emptyState
                    territorySection
                } else {
                    statsHeader
                    territorySection
                    positionsByDomain
                    tensionsSection
                    resolvedTensionsSection
                    changelogSection
                }

                ladderLink
                readerProfileSection
                transparencySection
                settingsLink
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Worldview")
        .toolbar {
            if !store.commitments.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: store.exportMarkdown(),
                              preview: SharePreview("My Worldview")) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export worldview as markdown")
                }
            }
        }
        .academyDestinations()
        .task {
            // Fixture Commitment Map in mock mode (§12.7); live mode will
            // fetch the same shapes from the §12.3 tables.
            if app.config.isMockMode { store.loadIfNeeded() }
        }
        .confirmationDialog(
            "Delete this position? It disappears from your record entirely — use Abandon if you want the arc kept.",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete position", role: .destructive) {
                if let commitment = confirmingDelete { store.delete(commitment) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your positions, in your words").overline(Theme.accent)
            Text("What you have asserted across sessions — held, revised, and sometimes honorably abandoned. Abandoning a position is progress here, and is recorded as such.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing on record yet", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Take a position in a seminar or an elenchus and it will appear here — in your words, never graded.")
        }
    }

    // MARK: stats header (§14.5a) — the proudest stat on the page

    /// "You've changed your mind N times this year — each under pressure of
    /// argument." Changed minds are the point of the practice (§14.6): the
    /// count is worn as a medal, never a warning.
    @ViewBuilder
    private var statsHeader: some View {
        let n = store.changedMindCountThisYear
        if n > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("The Record").overline(Theme.accent)
                Text(n == 1
                     ? "You've changed your mind once this year — under pressure of argument."
                     : "You've changed your mind \(n) times this year — each under pressure of argument.")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("That is the practice working, not failing.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            }
            .bulletinCard(tint: Theme.accent)
        }
    }

    // MARK: territory (§14.5b) — the six domains, examined vs. untouched

    private var territorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Territory")
            Text("Six domains. Where your positions stand — and where nothing of yours yet does.")
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(ClaimDomain.allCases) { domain in
                    TerritoryTile(domain: domain,
                                  liveCount: store.liveCommitments(in: domain).count)
                }
            }
        }
        .bulletinCard()
    }

    // MARK: positions by domain

    private var positionsByDomain: some View {
        ForEach(ClaimDomain.allCases) { domain in
            let positions = store.commitments(in: domain)
            if !positions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: domain.symbolName)
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                        Text(domain.displayName).overline()
                        Spacer()
                    }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    ForEach(positions) { commitment in
                        PositionRow(commitment: commitment,
                                    officeHoursRoute: officeHoursRoute,
                                    steelmanRoute: SessionRoute(
                                        steelman: SteelmanTarget(
                                            claim: commitment.claim,
                                            ontologyId: commitment.ontologyId)),
                                    onAbandon: { store.abandon(commitment) },
                                    onDelete: { confirmingDelete = commitment })
                    }
                }
                .bulletinCard()
            }
        }
    }

    // MARK: tensions

    @ViewBuilder
    private var tensionsSection: some View {
        let open = store.openTensions
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "Open Tensions")
                Text("Two things you hold that pull against each other. Not a verdict — a question worth a session.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(open) { tension in
                    if let a = store.commitment(tension.commitmentA),
                       let b = store.commitment(tension.commitmentB) {
                        TensionPair(a: a, b: b, via: tension.via,
                                    officeHoursRoute: officeHoursRoute)
                    }
                }
            }
            .bulletinCard(tint: Theme.accent)
        }
    }

    // MARK: resolved tensions (§14.2 / §14.5d) — celebrated, not archived

    @ViewBuilder
    private var resolvedTensionsSection: some View {
        let resolved = store.resolvedTensions
        if !resolved.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "Resolved Tensions")
                Text("Two positions that pulled against each other — until you did the work of reconciling them. Earned, not granted.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(resolved) { tension in
                    if let a = store.commitment(tension.commitmentA),
                       let b = store.commitment(tension.commitmentB) {
                        ResolvedTensionRow(tension: tension, a: a, b: b)
                    }
                }
            }
            .bulletinCard(tint: Theme.accent)
        }
    }

    // MARK: the changelog (§14.5c) — the changelog of your mind

    @ViewBuilder
    private var changelogSection: some View {
        if !store.changelog.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "The Changelog")
                Text("Every movement of your mind, with the argument that moved it. Changed minds are the point of the practice.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(store.changelog) { entry in
                    ChangelogRow(entry: entry)
                }
            }
            .bulletinCard()
        } else if !store.timeline.isEmpty {
            // Pre-ledger snapshots (no events yet) keep the old timeline.
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "How It Has Moved")
                ForEach(store.timeline) { event in
                    TimelineRow(event: event)
                }
            }
            .bulletinCard()
        }
    }

    // MARK: ladder link (§14.5) — the steelman ladder lives off this page

    private var ladderLink: some View {
        NavigationLink {
            SteelmanLadderView()
        } label: {
            HStack {
                Label("The Steelman Ladder", systemImage: SessionKind.steelman.symbolName)
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !store.ladder.isEmpty {
                    Text(store.steelmanScores.count == 1
                         ? "1 climb"
                         : "\(store.steelmanScores.count) climbs")
                        .font(.caption)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .bulletinCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: reader profile (secondary, per A14)

    @ViewBuilder
    private var readerProfileSection: some View {
        if let profile = store.readerProfile {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(text: "How You Read")
                Text("The attention profile your professors teach against. It tunes their moves; it never grades you.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)

                AttentionRadar(attention: profile.attention, tint: Theme.accent)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)

                if !profile.strengths.isEmpty {
                    profileList(title: "Strengths", items: profile.strengths, symbol: "checkmark.circle")
                }
                if !profile.growthEdges.isEmpty {
                    profileList(title: "Growth edges", items: profile.growthEdges, symbol: "arrow.up.right.circle")
                }
                if !profile.narrativeSummary.isEmpty {
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    Text(profile.narrativeSummary)
                        .font(.footnote)
                        .fontDesign(.serif)
                        .italic()
                        .lineSpacing(3)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .bulletinCard()
        }
    }

    private func profileList(title: String, items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).overline(Theme.accent)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                    Text(item)
                        .font(.footnote)
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: transparency + settings

    private var transparencySection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Everything the professors see")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Text("This page is the complete record — every position, tension, and reading observation your professors are given about you. Nothing is held back, and any of it can be contested: abandon it, delete it, or argue it in office hours.")
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .bulletinCard()
    }

    private var settingsLink: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack {
                Label("Pace, intensity & account", systemImage: "gearshape")
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .bulletinCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Position row

private struct PositionRow: View {
    let commitment: Commitment
    let officeHoursRoute: SessionRoute?
    /// §14.4/§14.5: live positions invite the best case against themselves.
    let steelmanRoute: SessionRoute?
    let onAbandon: () -> Void
    let onDelete: () -> Void

    private var isAbandoned: Bool { commitment.strength == .abandoned }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(commitment.claim)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .lineSpacing(2)
                    .foregroundStyle(isAbandoned ? Theme.inkSecondary : Theme.ink)
                    .strikethrough(isAbandoned, color: Theme.inkSecondary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                contestMenu
            }
            HStack(spacing: 8) {
                StrengthBadge(strength: commitment.strength)
                Text(commitment.affirmCount == 1
                     ? "affirmed once"
                     : "affirmed \(commitment.affirmCount)×")
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if let steelmanRoute, !isAbandoned {
                NavigationLink(value: steelmanRoute) {
                    Label("Steelman the other side",
                          systemImage: SessionKind.steelman.symbolName)
                        .font(.caption.weight(.semibold))
                        .fontDesign(.default)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Theme.accent)
                .padding(.top, 2)
                .accessibilityLabel("Steelman the other side of this position")
            }
        }
        .padding(.vertical, 4)
    }

    /// Contest affordance (§12.7): exactly the owner-permitted writes of
    /// §12.3 RLS — abandon (update strength), delete — plus the office-hours
    /// argument, which is the honorable route.
    private var contestMenu: some View {
        Menu {
            if let route = officeHoursRoute {
                NavigationLink(value: route) {
                    Label("Discuss in office hours", systemImage: "door.left.hand.open")
                }
            }
            if !isAbandoned {
                Button(action: onAbandon) {
                    Label("Abandon — I no longer hold this", systemImage: "arrow.uturn.down")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete — I never held this", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 1)
        }
        .accessibilityLabel("Contest this position")
    }
}

private struct StrengthBadge: View {
    let strength: CommitmentStrength

    var body: some View {
        Text(strength.displayName)
            .font(.caption2.weight(.bold))
            .fontDesign(.default)
            .textCase(.uppercase)
            .kerning(0.7)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch strength {
        case .asserted: return Theme.accent
        case .leaned: return Theme.ink.opacity(0.75)
        case .explored, .abandoned: return Theme.inkSecondary
        }
    }
}

// MARK: - Tension pair ("pulls against")

private struct TensionPair: View {
    let a: Commitment
    let b: Commitment
    let via: String
    let officeHoursRoute: SessionRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tensionCard(a)

            // The connector: the two positions pull against each other.
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Theme.accent.opacity(0.45))
                    .frame(width: 2, height: 26)
                    .padding(.leading, 22)
                Label("pulls against", systemImage: "arrow.up.and.down")
                    .font(.caption2.weight(.bold))
                    .fontDesign(.default)
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(Theme.accent)
                Spacer()
            }

            tensionCard(b)

            Text(via)
                .font(.caption2)
                .fontDesign(.default)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            if let route = officeHoursRoute {
                NavigationLink(value: route) {
                    Label("Examine this in office hours", systemImage: "door.left.hand.open")
                        .font(.caption.weight(.semibold))
                        .fontDesign(.default)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Theme.accent)
                .padding(.top, 8)
            }
        }
    }

    private func tensionCard(_ commitment: Commitment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(commitment.claim)
                .font(.footnote)
                .fontDesign(.serif)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            StrengthBadge(strength: commitment.strength)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Territory tile (§14.5b)

/// One domain of the six-domain grid: examined (live commitments stand
/// there) or untouched — untouched tiles carry their authored provocation.
private struct TerritoryTile: View {
    let domain: ClaimDomain
    let liveCount: Int

    private var examined: Bool { liveCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: domain.symbolName)
                    .font(.footnote)
                    .foregroundStyle(examined ? Theme.accent : Theme.inkSecondary.opacity(0.6))
                Text(domain.displayName)
                    .font(.caption.weight(.semibold))
                    .fontDesign(.default)
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(examined ? Theme.accent : Theme.inkSecondary)
                Spacer(minLength: 0)
            }
            if examined {
                Text(liveCount == 1 ? "1 live position" : "\(liveCount) live positions")
                    .font(.caption)
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
            } else {
                Text(domain.provocation)
                    .font(.caption2)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(examined ? Theme.accent.opacity(0.06) : Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(examined ? Theme.accent.opacity(0.35) : Theme.rule,
                          style: StrokeStyle(lineWidth: 1,
                                             dash: examined ? [] : [5, 3])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(examined
                            ? "\(domain.displayName): \(liveCount) live positions"
                            : "\(domain.displayName), untouched: \(domain.provocation)")
    }
}

// MARK: - Changelog row (§14.5c)

/// One ledger beat. Abandonments render as achievements — celebrated, with
/// the evidence line ("the argument that moved you") underneath (§14.6).
private struct ChangelogRow: View {
    let entry: WorldviewStore.ChangelogEntry

    private var event: CommitmentEvent { entry.event }

    var body: some View {
        if event.event == .abandoned {
            abandonmentAchievement
        } else {
            movementRow
        }
    }

    /// The celebrated beat: a changed mind, framed as the point of the
    /// practice — never a loss.
    private var abandonmentAchievement: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "medal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Changed your mind").overline(Theme.accent)
                Spacer()
                Text(event.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
            Text(entry.claim)
                .font(.footnote)
                .fontDesign(.serif)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !event.evidence.isEmpty {
                Text(event.evidence)
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    /// An ordinary movement: dot-and-rule timeline voice.
    private var movementRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Rectangle().fill(Theme.rule).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(movement)
                    .font(.caption.weight(.semibold))
                    .fontDesign(.default)
                    .foregroundStyle(Theme.ink)
                Text(entry.claim)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.evidence.isEmpty {
                    Text(event.evidence)
                        .font(.caption2)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(event.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
            .padding(.bottom, 10)
            Spacer(minLength: 0)
        }
    }

    private var movement: String {
        if let prior = event.priorStrength {
            return "You moved from \(prior.displayName.lowercased()) to \(event.event.displayName.lowercased())"
        }
        return "New position — \(event.event.displayName.lowercased())"
    }
}

// MARK: - Resolved tension (§14.2 / §14.5d)

/// A worked-through tension: the two positions, the reconciliation that
/// dissolved the pull, and the date it was earned.
private struct ResolvedTensionRow: View {
    let tension: CommitmentTension
    let a: Commitment
    let b: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Reconciled").overline(Theme.accent)
                Spacer()
                if let resolvedAt = tension.resolvedAt {
                    Text(resolvedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                }
            }
            Text("“\(a.claim)” held against “\(b.claim)”")
                .font(.footnote)
                .fontDesign(.serif)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let resolution = tension.resolution, !resolution.isEmpty {
                Rectangle().fill(Theme.accent.opacity(0.25)).frame(height: 1)
                Text(resolution)
                    .font(.caption)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Timeline

private struct TimelineRow: View {
    let event: WorldviewEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(event.toStrength == .abandoned ? Theme.inkSecondary : Theme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Rectangle().fill(Theme.rule).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(movement)
                    .font(.caption.weight(.semibold))
                    .fontDesign(.default)
                    .foregroundStyle(Theme.ink)
                Text(event.claim)
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = event.note {
                    Text(note)
                        .font(.caption2)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
            .padding(.bottom, 10)
            Spacer(minLength: 0)
        }
    }

    private var movement: String {
        if let from = event.fromStrength {
            return "You moved from \(from.displayName.lowercased()) to \(event.toStrength.displayName.lowercased())"
        }
        return "New position — \(event.toStrength.displayName.lowercased())"
    }
}

// MARK: - Attention radar (custom shape, §11.5 folded in per A14)

/// Six-axis radar over the reader-profile attention dimensions.
struct AttentionRadar: View {
    let attention: [String: Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 26

            ZStack {
                // Grid rings + spokes
                ForEach([0.33, 0.66, 1.0], id: \.self) { scale in
                    RadarPolygon(values: Array(repeating: scale, count: axes.count))
                        .stroke(Theme.rule, lineWidth: 1)
                }
                RadarSpokes(count: axes.count)
                    .stroke(Theme.rule, lineWidth: 0.5)

                // The profile itself
                RadarPolygon(values: values)
                    .fill(tint.opacity(0.18))
                RadarPolygon(values: values)
                    .stroke(tint, lineWidth: 1.5)

                // Axis labels
                ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
                    let angle = self.angle(index)
                    Text(axis.capitalized)
                        .font(.system(size: 9, weight: .medium))
                        .fontDesign(.default)
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundStyle(Theme.inkSecondary)
                        .position(x: center.x + cos(angle) * (radius + 16),
                                  y: center.y + sin(angle) * (radius + 16))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attention radar: " + axes.map {
            "\($0) \(Int((attention[$0] ?? 0) * 100)) percent"
        }.joined(separator: ", "))
    }

    private var axes: [String] { ReaderProfileDigest.dimensionOrder }
    private var values: [Double] { axes.map { attention[$0] ?? 0 } }

    private func angle(_ index: Int) -> CGFloat {
        CGFloat(index) / CGFloat(axes.count) * 2 * .pi - .pi / 2
    }
}

private struct RadarPolygon: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 26
        var path = Path()
        for (index, value) in values.enumerated() {
            let angle = CGFloat(index) / CGFloat(values.count) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius * CGFloat(value),
                y: center.y + sin(angle) * radius * CGFloat(value))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct RadarSpokes: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 26
        var path = Path()
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius,
                                     y: center.y + sin(angle) * radius))
        }
        return path
    }
}
