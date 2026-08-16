import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var collection: CollectionStore

    let onScan: (Game?) -> Void
    let onDiscover: () -> Void
    let onCollection: () -> Void
    let onSelectCard: (UICard) -> Void

    var body: some View {
        ZStack {
            CardSenseBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    portfolioHero
                    quickActions

                    if collection.items.isEmpty {
                        EmptyCollectionCard(onScan: { onScan(nil) })
                    } else {
                        recentCollection
                    }

                    supportedGames
                    confidenceNote
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
                .cardSensePagePadding()
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("HELD")
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(CardSenseTheme.mint)
                Text("Know what you hold.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            ZStack {
                Circle().fill(.white.opacity(0.07)).frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CardSenseTheme.mint)
            }
        }
    }

    private var portfolioHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(CardSenseTheme.heroGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.11), lineWidth: 0.8)
                }

            Circle()
                .fill(CardSenseTheme.mint.opacity(0.12))
                .frame(width: 170, height: 170)
                .blur(radius: 4)
                .offset(x: 54, y: -72)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Collection value", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("KNOWN VALUE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(CardSenseTheme.mint)
                }

                Text(collection.totalMarketValue.formatted(.currency(code: "USD")))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 0) {
                    portfolioMetric(value: "\(collection.totalCards)", label: collection.totalCards == 1 ? "item" : "items")
                    Divider().overlay(.white.opacity(0.12)).padding(.horizontal, 18)
                    portfolioMetric(value: "\(collection.gamesRepresented)", label: "categories")
                    Divider().overlay(.white.opacity(0.12)).padding(.horizontal, 18)
                    portfolioMetric(value: "\(collection.items.filter { $0.unitMarketValue > 0 }.count)", label: "priced")
                }
            }
            .padding(22)
        }
        .frame(minHeight: 216)
    }

    private func portfolioMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.48))
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction(
                title: "Scan item",
                subtitle: "Camera + OCR",
                symbol: "viewfinder",
                primary: true,
                action: { onScan(nil) }
            )
            quickAction(title: "Search", subtitle: "Name or number", symbol: "magnifyingglass", primary: false, action: onDiscover)
        }
    }

    private func quickAction(title: String, subtitle: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(primary ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(CardSenseTheme.mint.opacity(0.11)), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(subtitle).font(.caption2).opacity(0.62)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(primary ? CardSenseTheme.ink : .white)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(primary ? AnyShapeStyle(CardSenseTheme.accentGradient) : AnyShapeStyle(.white.opacity(0.055)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recentCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Recently added", eyebrow: "Your collection", actionTitle: "See all", action: onCollection)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 13) {
                    ForEach(collection.recentItems) { item in
                        Button { onSelectCard(item.card) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CardArtworkView(card: item.card, cornerRadius: 15)
                                    .frame(width: 116, height: 162)
                                Text(item.card.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(item.formattedMarketValue ?? "Unpriced")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(item.unitMarketValue > 0 ? CardSenseTheme.mint : .white.opacity(0.42))
                            }
                            .frame(width: 116, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var supportedGames: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("One scanner, every collection", eyebrow: "Seven categories")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Game.allCases) { game in
                    Button {
                        onScan(game)
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: game.symbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(game.accent)
                                .frame(width: 48, height: 48)
                                .background(game.accent.opacity(0.11), in: Circle())
                            Text(game.shortLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan \(game.rawValue)")
                    .accessibilityHint("Opens the scanner in the \(game.rawValue) category")
                }
            }
        }
    }

    private var confidenceNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(CardSenseTheme.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Confidence before convenience")
                    .font(.subheadline.weight(.bold))
                Text("Held shows the OCR clues, candidate record, variation and source so you can verify the exact item before saving it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(.vertical, 6)
    }
}
