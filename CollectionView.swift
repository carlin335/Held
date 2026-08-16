import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var collection: CollectionStore
    let onSelectCard: (UICard) -> Void

    @State private var query = ""
    @State private var selectedGame: Game?
    @State private var sort: CollectionSort = .newest

    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            CardSenseBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    collectionSummary

                    if collection.items.isEmpty {
                        emptyState
                    } else {
                        controls
                        cardGrid
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 26)
                .cardSensePagePadding()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COLLECTION")
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(CardSenseTheme.mint)
                Text("Everything you own")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Spacer()
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(CollectionSort.allCases) { option in
                        Label(option.rawValue, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.07), in: Circle())
            }
        }
    }

    private var collectionSummary: some View {
        GlassPanel {
            HStack(spacing: 0) {
                summaryMetric(collection.totalMarketValue.formatted(.currency(code: "USD")), "known value")
                Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 16)
                summaryMetric("\(collection.totalCards)", "items")
                Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 16)
                summaryMetric("\(collection.gamesRepresented)", "categories")
            }
        }
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(CardSenseTheme.mint)
            Text("No items saved yet")
                .font(.title3.weight(.bold))
            Text("Open any result and tap Add to collection. Your items stay saved on this device.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CardSenseTheme.mint)
                TextField("Search your collection", text: $query)
                    .textInputAutocapitalization(.words)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterChip("All", game: nil)
                    ForEach(Game.allCases) { game in
                        filterChip(game.shortLabel, game: game)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func filterChip(_ title: String, game: Game?) -> some View {
        let selected = selectedGame == game
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedGame = game }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? CardSenseTheme.ink : .white.opacity(0.62))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(selected ? AnyShapeStyle(CardSenseTheme.accentGradient) : AnyShapeStyle(.white.opacity(0.055)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var cardGrid: some View {
        LazyVGrid(columns: grid, spacing: 12) {
            ForEach(filteredItems) { item in
                Button { onSelectCard(item.card) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        CardArtworkView(card: item.card)
                            .aspectRatio(0.715, contentMode: .fit)
                            .overlay(alignment: .bottomTrailing) {
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(8)
                                }
                            }
                        Text(item.card.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        HStack {
                            Text(item.condition.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.46))
                            Spacer()
                            Text(item.formattedMarketValue ?? "Unpriced")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(item.unitMarketValue > 0 ? CardSenseTheme.mint : .white.opacity(0.4))
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { collection.remove(item) } label: {
                        Label("Remove from collection", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var filteredItems: [CollectionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = collection.items.filter { item in
            let matchesGame = selectedGame == nil || item.card.game == selectedGame
            let categoryMetadata = [
                item.card.sportsMetadata?.searchTerms.joined(separator: " "),
                item.card.coinMetadata?.searchTerms.joined(separator: " "),
                item.card.wineMetadata?.searchTerms.joined(separator: " ")
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            let matchesQuery = trimmed.isEmpty
                || item.card.name.localizedCaseInsensitiveContains(trimmed)
                || (item.card.setName?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (item.card.number?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || categoryMetadata.localizedCaseInsensitiveContains(trimmed)
            return matchesGame && matchesQuery
        }

        switch sort {
        case .newest:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .name:
            return filtered.sorted {
                $0.card.name.localizedCaseInsensitiveCompare($1.card.name) == .orderedAscending
            }
        case .valueHigh:
            return filtered.sorted { $0.marketValue > $1.marketValue }
        case .valueLow:
            return filtered.sorted { $0.marketValue < $1.marketValue }
        }
    }
}

private enum CollectionSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case name = "Name"
    case valueHigh = "Value: high to low"
    case valueLow = "Value: low to high"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .newest: "clock"
        case .name: "textformat"
        case .valueHigh: "arrow.down"
        case .valueLow: "arrow.up"
        }
    }
}
