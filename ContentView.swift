import SwiftUI

struct ContentView: View {
    @StateObject private var search = CardSearchViewModel()
    @State private var selectedTab: AppTab = .home
    @State private var selectedCard: UICard?
    @State private var isScannerPresented = false

    var body: some View {
        ZStack {
            CardSenseTheme.canvas.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        onScan: { presentScanner(for: $0) },
                        onDiscover: { selectedTab = .discover },
                        onCollection: { selectedTab = .collection },
                        onSelectCard: { selectedCard = $0 }
                    )
                case .discover:
                    DiscoverView(
                        viewModel: search,
                        onScan: { presentScanner() },
                        onSelectCard: { selectedCard = $0 }
                    )
                case .collection:
                    CollectionView(onSelectCard: { selectedCard = $0 })
                case .settings:
                    SettingsView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CardSenseTabBar(
                selection: $selectedTab,
                onScan: { presentScanner() }
            )
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            ScannerExperienceView(initialGame: search.game) { scannedGame, hit in
                search.game = scannedGame
                search.applyScan(hit)
                isScannerPresented = false
                selectedTab = .discover
            }
        }
        .sheet(item: $selectedCard) { card in
            NavigationStack {
                CardDetailView(card: card)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(CardSenseTheme.canvas)
        }
        .preferredColorScheme(.dark)
    }

    private func presentScanner(for game: Game? = nil) {
        if let game { search.game = game }
        isScannerPresented = true
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case discover = "Discover"
    case collection = "Collection"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .discover: "sparkle.magnifyingglass"
        case .collection: "square.stack.3d.up"
        case .settings: "slider.horizontal.3"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: "house.fill"
        case .discover: "sparkle.magnifyingglass"
        case .collection: "square.stack.3d.up.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

private struct CardSenseTabBar: View {
    @Binding var selection: AppTab
    let onScan: () -> Void

    private let leadingTabs: [AppTab] = [.home, .discover]
    private let trailingTabs: [AppTab] = [.collection, .settings]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(leadingTabs) { tabButton($0) }
                // A Color without an explicit height greedily consumed the
                // safe-area proposal and made the tab bar half-screen tall.
                Color.clear.frame(width: 78, height: 1)
                ForEach(trailingTabs) { tabButton($0) }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 7)

            Button(action: onScan) {
                ZStack {
                    Circle()
                        .fill(CardSenseTheme.accentGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: CardSenseTheme.mint.opacity(0.34), radius: 18, y: 8)
                    Circle()
                        .stroke(.white.opacity(0.42), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(CardSenseTheme.ink)
                }
            }
            .buttonStyle(.plain)
            .offset(y: -24)
            .accessibilityLabel("Scan an item")
        }
        .frame(height: 62, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 0.5)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == tab ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(tab.rawValue)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(selection == tab ? CardSenseTheme.mint : .white.opacity(0.46))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct ScannerExperienceView: View {
    let onResult: (Game, ScanHit) -> Void

    @EnvironmentObject private var collection: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGame: Game
    @State private var pokemonScanLanguage: PokemonScanLanguage = .english
    @State private var sessionID = UUID()
    @State private var phase: ScannerPhase = .searching
    @State private var resolvedScan: ResolvedScan?
    @State private var isTorchOn = false
    @State private var isSaved = false
    @State private var resolutionTask: Task<Void, Never>?

    init(initialGame: Game, onResult: @escaping (Game, ScanHit) -> Void) {
        self.onResult = onResult
        _selectedGame = State(initialValue: initialGame)
    }

    var body: some View {
        ZStack {
            ScannerView(
                game: selectedGame,
                pokemonLanguage: pokemonScanLanguage,
                isTorchOn: $isTorchOn
            ) { hit in
                accept(hit)
            }
            .id(selectedGame.rawValue + pokemonScanLanguage.rawValue + sessionID.uuidString)

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScannerFocusFrame(game: selectedGame, phase: phase)

            VStack {
                scannerHeader
                categoryPicker
                if selectedGame == .pokemon {
                    pokemonLanguagePicker
                }

                Spacer()

                if let resolvedScan {
                    resultPanel(resolvedScan)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    liveStatus
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: phase)
        .tint(CardSenseTheme.mint)
        .preferredColorScheme(.dark)
        .onDisappear {
            resolutionTask?.cancel()
            isTorchOn = false
        }
    }

    private var scannerHeader: some View {
        HStack {
            scannerCircleButton(symbol: "xmark") {
                isTorchOn = false
                dismiss()
            }
            Spacer()
            VStack(spacing: 3) {
                Text("HELD")
                    .font(.caption2.weight(.black))
                    .tracking(1.8)
                    .foregroundStyle(CardSenseTheme.mint)
                Text(scannerTitle)
                    .font(.headline.weight(.bold))
            }
            Spacer()
            scannerCircleButton(symbol: isTorchOn ? "bolt.fill" : "bolt.slash") {
                isTorchOn.toggle()
            }
            .foregroundStyle(isTorchOn ? Color.yellow : Color.white)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func scannerCircleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Game.allCases) { category in
                    Button {
                        changeCategory(to: category)
                    } label: {
                        Label(category.shortLabel, systemImage: category.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selectedGame == category ? CardSenseTheme.ink : .white.opacity(0.72))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                selectedGame == category
                                    ? AnyShapeStyle(CardSenseTheme.accentGradient)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 10)
        .disabled(phase == .analyzing)
    }

    private var pokemonLanguagePicker: some View {
        HStack(spacing: 6) {
            ForEach([PokemonScanLanguage.english, .japanese]) { language in
                Button {
                    changePokemonLanguage(to: language)
                } label: {
                    Text(language.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            pokemonScanLanguage == language
                                ? CardSenseTheme.ink
                                : .white.opacity(0.66)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            pokemonScanLanguage == language
                                ? AnyShapeStyle(CardSenseTheme.accentGradient)
                                : AnyShapeStyle(.white.opacity(0.06)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8) }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .disabled(phase == .analyzing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pokémon card language")
    }

    private var liveStatus: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                if phase == .analyzing {
                    ProgressView().tint(CardSenseTheme.mint)
                } else {
                    ZStack {
                        Circle().fill(CardSenseTheme.mint.opacity(0.18)).frame(width: 26, height: 26)
                        Circle().fill(CardSenseTheme.mint).frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase == .analyzing ? "Item found" : "Automatic scan is ready")
                        .font(.subheadline.weight(.bold))
                    Text(phase == .analyzing ? "Matching identity and current value…" : liveInstruction)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text(scanModeBadge)
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(CardSenseTheme.mint)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 0.8)
            }

            Text("No shutter needed — hold the whole item in view")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    private func resultPanel(_ scan: ResolvedScan) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 14) {
                CardArtworkView(card: scan.card, cornerRadius: 13)
                    .frame(width: 72, height: 96)

                VStack(alignment: .leading, spacing: 5) {
                    Label("TOP MATCH", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(CardSenseTheme.mint)
                    Text(scan.card.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                    Text(scan.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(scan.valueText)
                        .font(.title3.weight(.black))
                        .foregroundStyle(scan.hasMarketValue ? CardSenseTheme.mint : .white)
                        .monospacedDigit()
                    Text(scan.valueSource)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.44))
                }
            }

            HStack(spacing: 10) {
                Button(action: scanAgain) {
                    Label("Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScannerSecondaryButtonStyle())

                Button {
                    onResult(selectedGame, scan.hit)
                } label: {
                    Label("Full details", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScannerPrimaryButtonStyle())
            }

            Button {
                save(scan)
            } label: {
                Label(isSaved ? "Saved to collection" : "Add to collection", systemImage: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSaved ? CardSenseTheme.mint : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var liveInstruction: String {
        switch selectedGame {
        case .coins: "Center one side of the coin; scan the reverse next if needed."
        case .wine: "Center the label and keep the producer and vintage visible."
        case .other: "Center the maker, item name, year or model number."
        case .sports: "Center the full card so the player, set and number are visible."
        case .pokemon:
            switch pokemonScanLanguage {
            case .auto: "Held will detect English or Japanese from the title, then verify the collector number."
            case .english: "Center the title and collector number. Western-language cards are supported here too."
            case .japanese: "日本語のカード名とコレクター番号が見えるようにしてください。"
            }
        case .magic, .yugioh: "Center the full card and keep glare off the title and number."
        }
    }

    private var scannerTitle: String {
        selectedGame == .pokemon
            ? "Pokémon · \(pokemonScanLanguage.shortLabel)"
            : selectedGame.shortLabel
    }

    private var scanModeBadge: String {
        selectedGame == .pokemon ? pokemonScanLanguage.shortLabel.uppercased() : "AUTO"
    }

    private func accept(_ hit: ScanHit) {
        guard phase == .searching else { return }
        phase = .analyzing
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        resolutionTask?.cancel()
        let game = selectedGame
        let language = pokemonScanLanguage
        resolutionTask = Task {
            let card = await resolveCard(for: hit, game: game, pokemonLanguage: language)
            let prices = await MultigameService.loadPricesOptional(for: card) ?? []
            guard !Task.isCancelled,
                  selectedGame == game,
                  game != .pokemon || pokemonScanLanguage == language else { return }
            resolvedScan = ResolvedScan(hit: hit, card: card, prices: prices)
            isSaved = collection.contains(card)
            phase = .found
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func resolveCard(
        for hit: ScanHit,
        game: Game,
        pokemonLanguage: PokemonScanLanguage
    ) async -> UICard {
        let name = hit.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let page = try? await MultigameService.searchFirstPage(
            game: game,
            text: name,
            rarity: hit.sportsMetadata?.parallel,
            number: hit.number,
            printedNumber: hit.printedNumber,
            sportsMetadata: hit.sportsMetadata,
            coinMetadata: hit.coinMetadata,
            wineMetadata: hit.wineMetadata,
            pokemonLanguage: pokemonLanguage
        ), var first = page.cards.first {
            if game == .pokemon,
               let printedNumber = hit.printedNumber,
               !printedNumber.isEmpty {
                first.number = printedNumber
            }
            return first
        }

        let fallbackName = name.isEmpty ? "Detected \(game.shortLabel) item" : name
        return UICard(
            id: "scan|\(game.rawValue)|\(fallbackName)|\(hit.number ?? "")".lowercased(),
            game: game,
            name: fallbackName,
            number: hit.printedNumber ?? hit.number,
            languageCode: hit.pokemonLanguageCode,
            rarity: hit.sportsMetadata?.parallel,
            setName: hit.sportsMetadata?.setName ?? hit.coinMetadata?.country ?? hit.wineMetadata?.producer,
            sportsMetadata: hit.sportsMetadata,
            coinMetadata: hit.coinMetadata,
            wineMetadata: hit.wineMetadata
        )
    }

    private func save(_ scan: ResolvedScan) {
        collection.add(scan.cardWithBestValue)
        isSaved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func scanAgain() {
        resolutionTask?.cancel()
        resolvedScan = nil
        phase = .searching
        isSaved = false
        sessionID = UUID()
    }

    private func changeCategory(to category: Game) {
        guard selectedGame != category else { return }
        resolutionTask?.cancel()
        isTorchOn = false
        selectedGame = category
        resolvedScan = nil
        phase = .searching
        isSaved = false
        sessionID = UUID()
    }

    private func changePokemonLanguage(to language: PokemonScanLanguage) {
        guard pokemonScanLanguage != language else { return }
        resolutionTask?.cancel()
        isTorchOn = false
        pokemonScanLanguage = language
        resolvedScan = nil
        phase = .searching
        isSaved = false
        sessionID = UUID()
    }
}

private enum ScannerPhase: Equatable {
    case searching
    case analyzing
    case found

    var tint: Color {
        switch self {
        case .searching, .analyzing: CardSenseTheme.mint
        case .found: Color.yellow
        }
    }
}

private struct ResolvedScan {
    let hit: ScanHit
    let card: UICard
    let prices: [PriceRow]

    var marketValue: String? {
        if let value = card.formattedUSD { return value }
        return prices.compactMap(\.value).first { value in
            (value.contains("$") || value.contains("€"))
                && value.range(of: #"\d"#, options: .regularExpression) != nil
        }
    }

    var hasMarketValue: Bool { marketValue != nil }
    var valueText: String { marketValue ?? "Research" }
    var valueSource: String {
        if card.formattedUSD != nil { return "market snapshot" }
        if let row = prices.first(where: { $0.value == marketValue }) { return row.source.lowercased() }
        return "verify value"
    }

    var cardWithBestValue: UICard {
        guard card.numericUSD == 0,
              let marketValue,
              marketValue.contains("$") else { return card }
        var copy = card
        copy.priceUSD = marketValue
        return copy
    }

    var metadataLine: String {
        if let sports = card.sportsMetadata {
            return [sports.year, sports.brand, sports.setName, sports.cardNumber.map { "#\($0)" }, sports.parallel]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let coin = card.coinMetadata {
            return [coin.year, coin.country, coin.denomination, coin.mintMark.map { "Mint \($0)" }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let wine = card.wineMetadata {
            return [wine.vintage, wine.producer, wine.region, wine.varietal]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let language = PokemonCatalogueLanguage(rawValue: card.languageCode ?? "")?.displayName
        return [language, card.setName ?? card.setCode, card.number.map { "#\($0)" }, card.rarity]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ScannerFocusFrame: View {
    let game: Game
    let phase: ScannerPhase

    var body: some View {
        GeometryReader { proxy in
            let dimensions = frameDimensions(in: proxy.size)
            ZStack {
                if game == .coins {
                    Circle()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                    Circle()
                        .trim(from: 0.06, to: phase == .analyzing ? 0.94 : 0.72)
                        .stroke(phase.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(phase == .analyzing ? 180 : -90))
                        .shadow(color: phase.tint.opacity(0.7), radius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                    ScannerCornerShape()
                        .stroke(phase.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .shadow(color: phase.tint.opacity(0.72), radius: 10)
                }
            }
            .frame(width: dimensions.width, height: dimensions.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)
            .opacity(phase == .found ? 0.42 : 1)
        }
        .allowsHitTesting(false)
    }

    private func frameDimensions(in size: CGSize) -> CGSize {
        let width = min(size.width - 48, 310)
        switch game {
        case .coins:
            return CGSize(width: width * 0.82, height: width * 0.82)
        case .wine:
            return CGSize(width: width, height: width * 0.72)
        case .other:
            return CGSize(width: width, height: width * 0.88)
        case .pokemon, .magic, .yugioh, .sports:
            return CGSize(width: width * 0.82, height: (width * 0.82) / 0.715)
        }
    }
}

private struct ScannerCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.13
        let radius: CGFloat = 15
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct ScannerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CardSenseTheme.ink)
            .padding(.vertical, 13)
            .background(CardSenseTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct ScannerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8) }
    }
}
