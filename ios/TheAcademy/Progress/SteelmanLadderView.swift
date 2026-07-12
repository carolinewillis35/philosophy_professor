import SwiftUI

/// The LADDER screen (§14.4/§14.5), reachable from the Worldview page:
/// per-claim max level against the four named ranks — Strawman, Sketch,
/// Competent, Signable — plus attempt counts. Level names, never "failure"
/// (§14.6): every rung is a place on a climb.
struct SteelmanLadderView: View {
    @Environment(AppModel.self) private var app

    private var store: WorldviewStore { app.worldview }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if store.ladder.isEmpty {
                    emptyState
                } else {
                    ForEach(store.ladder) { entry in
                        LadderRow(entry: entry)
                    }
                    rubricCard
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("The Ladder")
        .navigationBarTitleDisplayMode(.inline)
        .academyDestinations()
        .task {
            // Fixture scores in mock mode (§14.5); live mode reads the same
            // shapes from `steelman_scores`.
            if app.config.isMockMode { store.loadIfNeeded() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The Steelman Ladder").overline(Theme.accent)
            Text("The best case against your own positions, graded rung by rung. The rarest skill on the internet: stating the other side so well its holders would sign it.")
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
            Label("No climbs yet", systemImage: SessionKind.steelman.symbolName)
        } description: {
            Text("Pick any live position on your Worldview page and steelman the other side — the ladder starts on the first attempt.")
        }
    }

    /// The four ranks, named in full — the shared rubric every climb is
    /// graded against.
    private var rubricCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The four ranks").overline()
            ForEach(SteelmanLevel.allCases) { rank in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(rank.rawValue)")
                        .font(.caption.weight(.bold))
                        .fontDesign(.default)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 14, alignment: .trailing)
                    Text(rank.displayName)
                        .font(.caption.weight(.semibold))
                        .fontDesign(.default)
                        .foregroundStyle(Theme.ink)
                    Text(rank.descriptor)
                        .font(.caption2)
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            Rectangle().fill(Theme.rule).frame(height: 1)
            Text("Graded against the argument produced, never the person. Signable is rare, and said so when it lands.")
                .font(.caption2)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .bulletinCard()
    }
}

// MARK: - Ladder row

/// One target claim's climb: the four rungs with the best level lit, and the
/// attempt count underneath.
private struct LadderRow: View {
    let entry: SteelmanLadderEntry

    private var best: SteelmanLevel {
        SteelmanLevel(rawValue: entry.maxLevel) ?? .strawman
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.targetClaim)
                .font(.subheadline)
                .fontDesign(.serif)
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            rungs

            HStack(spacing: 8) {
                Text("Best: \(best.displayName)")
                    .font(.caption2.weight(.bold))
                    .fontDesign(.default)
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(Theme.accent)
                Text(entry.attempts == 1
                     ? "1 attempt"
                     : "\(entry.attempts) attempts")
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(entry.lastAttempt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
        }
        .bulletinCard(tint: Theme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.targetClaim): best level \(best.displayName), \(entry.attempts) attempts")
    }

    /// The four named rungs in a row; reached ones lit, the best one ringed.
    private var rungs: some View {
        HStack(spacing: 0) {
            ForEach(SteelmanLevel.allCases) { rank in
                if rank != .strawman {
                    Rectangle()
                        .fill(rank.rawValue <= best.rawValue
                              ? Theme.accent.opacity(0.5) : Theme.rule)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
                rungDot(rank)
            }
        }
        .padding(.vertical, 4)
    }

    private func rungDot(_ rank: SteelmanLevel) -> some View {
        let isBest = rank == best
        let isReached = rank.rawValue <= best.rawValue
        return VStack(spacing: 4) {
            Circle()
                .fill(isReached ? Theme.accent : Theme.rule)
                .frame(width: isBest ? 9 : 6, height: isBest ? 9 : 6)
                .overlay {
                    if isBest {
                        Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 3)
                            .frame(width: 17, height: 17)
                    }
                }
            Text(rank.displayName)
                .font(.system(size: 9, weight: isBest ? .bold : .medium))
                .fontDesign(.default)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(isBest ? Theme.accent : Theme.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
