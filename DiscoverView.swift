import SwiftUI

struct DiscoverView: View {
    @ObservedObject var viewModel: CardSearchViewModel

    let onScan: () -> Void
    let onSelectCard: (UICard) -> Void

    @FocusState private var focusedField: Field?
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private enum Field: Hashable {
        case name, number, year, brand, set, team, serial
        case coinCountry, denomination, mintMark
        case producer, wineRegion, wineCountry, varietal
    }

    var body: some View {
        ZStack {
            CardSenseBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    gamePicker
                    searchPanel
                    resultSection
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
                Text("DISCOVER")
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(CardSenseTheme.mint)
                Text("Identify the exact item")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Spacer()
            Button(action: onScan) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CardSenseTheme.ink)
                    .frame(width: 46, height: 46)
                    .background(CardSenseTheme.accentGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan an item")
        }
    }

    private var gamePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(Game.allCases) { game in
                    GameChip(game: game, isSelected: viewModel.game == game) {
                        withAnimation(.snappy(duration: 0.22)) { viewModel.game = game }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var searchPanel: some View {
        GlassPanel {
            VStack(spacing: 13) {
                searchField(
                    title: primaryFieldTitle,
                    placeholder: namePlaceholder,
                    symbol: "magnifyingglass",
                    text: $viewModel.query,
                    field: .name
                )
                searchField(
                    title: secondaryFieldTitle,
                    placeholder: secondaryPlaceholder,
                    symbol: "number",
                    text: $viewModel.numberFilter,
                    field: .number
                )

                if viewModel.game == .sports {
                    sportsMetadataEditor
                } else if viewModel.game == .coins {
                    coinMetadataEditor
                } else if viewModel.game == .wine {
                    wineMetadataEditor
                }

                if !viewModel.rarityOptions.filter({ !$0.isEmpty }).isEmpty {
                    rarityScroller
                }

                Button {
                    focusedField = nil
                    viewModel.startSearch()
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(CardSenseTheme.ink)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text(viewModel.isLoading
                             ? "Building the record…"
                             : searchButtonTitle)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(CardSenseTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CardSenseTheme.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
        }
    }

    private func searchField(
        title: String,
        placeholder: String,
        symbol: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.44))
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(CardSenseTheme.mint)
                    .frame(width: 18)
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(field == .name ? .words : .never)
                    .keyboardType(field == .number ? .numbersAndPunctuation : .default)
                    .focused($focusedField, equals: field)
                    .submitLabel(.search)
                    .onSubmit { viewModel.startSearch() }
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focusedField == field ? CardSenseTheme.mint.opacity(0.65) : .white.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var rarityScroller: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.game == .sports ? "PARALLEL / VARIATION" : "RARITY")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.44))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    rarityChip("Any", value: nil)
                    ForEach(viewModel.rarityOptions.filter { !$0.isEmpty }, id: \.self) {
                        rarityChip($0, value: $0)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var sportsMetadataEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPORT & PRINTING CLUES")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.44))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Sport.allCases) { sport in
                        Button {
                            viewModel.selectedSport = sport
                        } label: {
                            Label(sport.rawValue, systemImage: sport.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(viewModel.selectedSport == sport ? CardSenseTheme.ink : .white.opacity(0.62))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    viewModel.selectedSport == sport
                                        ? AnyShapeStyle(CardSenseTheme.accentGradient)
                                        : AnyShapeStyle(.white.opacity(0.055)),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            searchField(title: "Year", placeholder: "2024", symbol: "calendar", text: $viewModel.sportsYear, field: .year)
            searchField(title: "Brand", placeholder: "Topps, Panini, Upper Deck…", symbol: "building.2", text: $viewModel.sportsBrand, field: .brand)
            searchField(title: "Set / product", placeholder: "Chrome, Prizm, Select…", symbol: "square.stack.3d.up", text: $viewModel.sportsSet, field: .set)
            searchField(title: "Team", placeholder: "Optional", symbol: "person.3", text: $viewModel.sportsTeam, field: .team)
            searchField(title: "Serial stamp", placeholder: "Optional — e.g. 12/99", symbol: "number.square", text: $viewModel.sportsSerialNumber, field: .serial)

            HStack(spacing: 10) {
                traitToggle("Rookie", symbol: "star.fill", isOn: $viewModel.sportsRookie)
                traitToggle("Autograph", symbol: "signature", isOn: $viewModel.sportsAutographed)
            }
        }
        .padding(.top, 2)
    }

    private var coinMetadataEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            contextualEditorTitle("COIN CLUES")
            searchField(title: "Country / issuer", placeholder: "United States, Canada…", symbol: "globe.americas", text: $viewModel.coinCountry, field: .coinCountry)
            searchField(title: "Denomination", placeholder: "Quarter, 5 cents, 1 dollar…", symbol: "centsign.circle", text: $viewModel.coinDenomination, field: .denomination)
            searchField(title: "Mint mark", placeholder: "Optional — P, D, S, W…", symbol: "m.circle", text: $viewModel.coinMintMark, field: .mintMark)
            verificationHint(symbol: "arrow.triangle.2.circlepath.camera", text: "For reliable coin identification, scan both sides and verify year, mint mark and composition.")
        }
        .padding(.top, 2)
    }

    private var wineMetadataEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            contextualEditorTitle("BOTTLE CLUES")
            searchField(title: "Producer", placeholder: "Winery or château", symbol: "building.columns", text: $viewModel.wineProducer, field: .producer)
            searchField(title: "Region", placeholder: "Napa Valley, Bordeaux…", symbol: "map", text: $viewModel.wineRegion, field: .wineRegion)
            searchField(title: "Country", placeholder: "France, Italy, United States…", symbol: "globe.europe.africa", text: $viewModel.wineCountry, field: .wineCountry)
            searchField(title: "Varietal", placeholder: "Cabernet Sauvignon, Pinot Noir…", symbol: "leaf", text: $viewModel.wineVarietal, field: .varietal)
            verificationHint(symbol: "wineglass", text: "Label data comes from OCR and community catalogues. Confirm the exact producer, vintage and bottle size.")
        }
        .padding(.top, 2)
    }

    private func contextualEditorTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(.white.opacity(0.44))
    }

    private func verificationHint(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func traitToggle(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn.wrappedValue ? CardSenseTheme.ink : .white.opacity(0.62))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isOn.wrappedValue ? AnyShapeStyle(CardSenseTheme.accentGradient) : AnyShapeStyle(.white.opacity(0.055)),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func rarityChip(_ title: String, value: String?) -> some View {
        let isSelected = viewModel.selectedRarity == value
        return Button {
            viewModel.selectedRarity = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? CardSenseTheme.ink : .white.opacity(0.6))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(CardSenseTheme.accentGradient) : AnyShapeStyle(.white.opacity(0.055)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultSection: some View {
        if let error = viewModel.errorText, !viewModel.isLoading {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CardSenseTheme.coral)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSenseTheme.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        if viewModel.results.isEmpty && !viewModel.isLoading {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(CardSenseTheme.mint.opacity(0.8))
                Text(viewModel.hasSearched
                     ? ([.sports, .coins, .wine, .other].contains(viewModel.game) ? "Add more identifying clues" : "No exact match found")
                     : "Search or scan to begin")
                    .font(.headline)
                Text(viewModel.hasSearched
                     ? ([.sports, .coins, .wine, .other].contains(viewModel.game)
                        ? "Correct the OCR fields above, then build the record again."
                        : "Try a shorter name, remove the rarity filter, or verify the collector number.")
                     : ([.sports, .coins, .wine, .other].contains(viewModel.game)
                        ? "Scan, correct the OCR clues, and verify the exact item against trusted sources."
                        : "A collector number dramatically improves matches for cards with many versions and parallels."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        } else if !viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    contextualResultTitle,
                    eyebrow: [.sports, .coins, .wine, .other].contains(viewModel.game) ? "Verify every clue" : "Verify before saving"
                )
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(viewModel.results) { card in
                        Button {
                            onSelectCard(card.applying(viewModel.priceBadges[card.id]))
                        } label: {
                            CardTile(card: card, badge: viewModel.priceBadges[card.id])
                        }
                        .buttonStyle(.plain)
                        .task {
                            if card.id == viewModel.results.last?.id {
                                viewModel.loadMoreIfAvailable()
                            }
                        }
                    }
                }
            }
        }
    }

    private var namePlaceholder: String {
        switch viewModel.game {
        case .pokemon: "Pikachu, Charizard ex…"
        case .magic: "Black Lotus, Sol Ring…"
        case .yugioh: "Blue-Eyes White Dragon…"
        case .sports: "Shohei Ohtani, Caitlin Clark…"
        case .coins: "Morgan dollar, Lincoln cent…"
        case .wine: "Château Margaux, Opus One…"
        case .other: "LEGO set, comic, collectible…"
        }
    }

    private var primaryFieldTitle: String {
        switch viewModel.game {
        case .sports: "Player name"
        case .coins: "Coin type or ruler"
        case .wine: "Wine name"
        case .other: "Item name"
        case .pokemon, .magic, .yugioh: "Card name"
        }
    }

    private var secondaryFieldTitle: String {
        switch viewModel.game {
        case .sports: "Card number"
        case .coins: "Year"
        case .wine: "Vintage"
        case .other: "Year / model"
        case .pokemon, .magic, .yugioh: "Collector number"
        }
    }

    private var secondaryPlaceholder: String {
        switch viewModel.game {
        case .sports: "Optional — e.g. 300"
        case .coins: "Optional — e.g. 1921"
        case .wine: "Optional — e.g. 2019"
        case .other: "Optional — year, model or issue"
        case .pokemon, .magic, .yugioh: "Optional — for a precise match"
        }
    }

    private var searchButtonTitle: String {
        switch viewModel.game {
        case .sports: "Review sports card"
        case .coins: "Identify coin"
        case .wine: "Identify wine"
        case .other: "Build research record"
        case .pokemon, .magic, .yugioh: "Search cards"
        }
    }

    private var contextualResultTitle: String {
        switch viewModel.game {
        case .sports: "Sports card candidates"
        case .coins: "Coin candidates"
        case .wine: "Wine candidates"
        case .other: "Collectible record"
        case .pokemon, .magic, .yugioh: "\(viewModel.results.count) possible matches"
        }
    }
}
