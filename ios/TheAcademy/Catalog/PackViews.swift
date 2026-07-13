import SwiftUI

/// Dinner-party packs (§16.4/§16.5): questions that leave the app. The shelf
/// entry is deliberately low-key — a quiet row below the cards, not an
/// event. NOTHING here is tracked: no store, no counters, no "cards viewed"
/// (§16.6) — the packs exist to push philosophy OFF the screen.
struct PacksEntryCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.packs.isEmpty {
            NavigationLink(value: PacksRoute()) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dinner-party packs")
                            .font(.subheadline.weight(.medium))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Text("Questions for a real table — take them with you.")
                            .font(.caption)
                            .fontDesign(.serif)
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - The shelf

/// The pack list: title, blurb, card count. Reading is browsing; nothing is
/// recorded (§16.6).
struct PacksShelfView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("For the table").overline(Theme.accent)
                    Text("Philosophy is older than screens. Pick a pack, share it whole, and let the table do the rest.")
                        .font(.footnote)
                        .fontDesign(.serif)
                        .italic()
                        .lineSpacing(3)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
                }
                .padding(.top, 4)

                ForEach(app.packs) { pack in
                    NavigationLink(value: pack) {
                        packRow(pack)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.paper)
        .navigationTitle("Dinner-party packs")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Pack.self) { PackDetailView(pack: $0) }
    }

    private func packRow(_ pack: Pack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(pack.title)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(pack.cards.count) cards")
                    .font(.caption)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text(pack.blurb)
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: Theme.accent)
    }
}

// MARK: - One pack: the swipeable deck

/// The deck: question large, one card per page; the follow-up stays face
/// down until the table needs it. The whole pack exports as clean plain text
/// via ShareLink — sent to a group chat or printed, no link back (§16.4).
struct PackDetailView: View {
    let pack: Pack

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ForEach(Array(pack.cards.enumerated()), id: \.offset) { index, card in
                    PackCardView(card: card, index: index, count: pack.cards.count)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 44)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            ShareLink(item: pack.exportText,
                      preview: SharePreview(pack.title)) {
                Label("Share the whole pack", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.serif)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Theme.paper)
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One card: the question, set large; "if the table stalls" revealed on tap.
private struct PackCardView: View {
    let card: Pack.Card
    let index: Int
    let count: Int

    @State private var showFollowUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Card \(index + 1) of \(count)").overline()

            Spacer()

            Text(card.question)
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
                .lineSpacing(5)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if showFollowUp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If the table stalls").overline(Theme.accent)
                    Text(card.followUp)
                        .font(.subheadline)
                        .fontDesign(.serif)
                        .italic()
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showFollowUp = true }
                } label: {
                    Label("If the table stalls…", systemImage: "hand.tap")
                        .font(.footnote.weight(.medium))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.rule, lineWidth: 1))
    }
}
