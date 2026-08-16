import Foundation
import SwiftUI

@MainActor
final class CardSearchViewModel: ObservableObject {

    // Inputs
    @Published var query: String = ""
    @Published var numberFilter: String = ""
    @Published var selectedRarity: String? = nil
    @Published var selectedSport: Sport = .baseball
    @Published var sportsYear: String = ""
    @Published var sportsBrand: String = ""
    @Published var sportsSet: String = ""
    @Published var sportsTeam: String = ""
    @Published var sportsSerialNumber: String = ""
    @Published var sportsRookie: Bool = false
    @Published var sportsAutographed: Bool = false
    @Published var coinCountry: String = ""
    @Published var coinDenomination: String = ""
    @Published var coinMintMark: String = ""
    @Published var wineProducer: String = ""
    @Published var wineRegion: String = ""
    @Published var wineCountry: String = ""
    @Published var wineVarietal: String = ""
    @Published var pokemonLanguageMode: PokemonScanLanguage = .english
    @Published var game: Game = .pokemon {
        didSet { handleGameSwitch(from: oldValue, to: game) }
    }

    // Outputs
    @Published var results: [UICard] = []
    @Published var priceBadges: [String: PriceBadge] = [:]
    @Published var isLoading: Bool = false
    @Published var errorText: String? = nil
    @Published var rarityOptions: [String] = [""]
    @Published var hasSearched: Bool = false

    // Pokémon paging (now disabled; kept for compatibility with UI)
    @Published var hasMore: Bool = false
    private var nextPage: Int = 2
    private var lastSearchKey: SearchKey?

    // Badge streaming
    private var streamingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init() { updateRarityOptions() }

    // MARK: - Search

    func startSearch() {
        searchTask?.cancel()
        streamingTask?.cancel()
        errorText = nil

        let text   = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNumber = numberFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = cleanNumber.isEmpty ? nil : cleanNumber
        let rarity = selectedRarity

        guard !text.isEmpty || number != nil else {
            hasSearched = false
            isLoading = false
            results = []
            priceBadges = [:]
            errorText = "Enter a name, year, or collector number."
            return
        }

        isLoading = true
        hasSearched = true
        results = []
        priceBadges.removeAll()
        hasMore = false
        nextPage = 2
        lastSearchKey = nil

        let key = SearchKey(
            game: game,
            text: text,
            number: number,
            rarity: rarity,
            pokemonLanguage: pokemonLanguageMode
        )

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch game {
                case .pokemon:
                    // Simplified: single resilient call via PokemonProvider.search(...)
                    let uiCards = try await PokemonProvider.search(
                        text: text,
                        number: number,
                        rarity: rarity,
                        language: pokemonLanguageMode
                    )

                    self.results = uiCards
                    self.hasMore = false          // pagination disabled for Pokémon
                    self.nextPage = 2
                    self.lastSearchKey = key
                    self.isLoading = false

                    if !uiCards.isEmpty { streamBadges(for: uiCards) }

                case .magic:
                    let first = try await MultigameService.searchFirstPage(game: .magic, text: text, rarity: rarity, number: number)
                    self.results = first.cards
                    self.hasMore = first.hasMore
                    self.nextPage = 2
                    self.lastSearchKey = key
                    self.isLoading = false
                    if !first.cards.isEmpty { streamBadges(for: first.cards) }

                case .yugioh:
                    let first = try await MultigameService.searchFirstPage(game: .yugioh, text: text, rarity: rarity, number: number)
                    self.results = first.cards
                    self.hasMore = first.hasMore
                    self.nextPage = 2
                    self.lastSearchKey = key
                    self.isLoading = false
                    if !first.cards.isEmpty { streamBadges(for: first.cards) }

                case .sports:
                    let first = try await MultigameService.searchFirstPage(
                        game: .sports,
                        text: text,
                        rarity: rarity,
                        number: number,
                        sportsMetadata: sportsMetadata
                    )
                    self.results = first.cards
                    self.hasMore = false
                    self.nextPage = 2
                    self.lastSearchKey = key
                    self.isLoading = false

                case .coins:
                    let first = try await MultigameService.searchFirstPage(
                        game: .coins,
                        text: text,
                        rarity: nil,
                        number: number,
                        coinMetadata: coinMetadata
                    )
                    self.results = first.cards
                    self.hasMore = false
                    self.lastSearchKey = key
                    self.isLoading = false

                case .wine:
                    let first = try await MultigameService.searchFirstPage(
                        game: .wine,
                        text: text,
                        rarity: nil,
                        number: number,
                        wineMetadata: wineMetadata
                    )
                    self.results = first.cards
                    self.hasMore = false
                    self.lastSearchKey = key
                    self.isLoading = false

                case .other:
                    let first = try await MultigameService.searchFirstPage(
                        game: .other,
                        text: text,
                        rarity: nil,
                        number: number
                    )
                    self.results = first.cards
                    self.hasMore = false
                    self.lastSearchKey = key
                    self.isLoading = false
                }
            } catch is CancellationError {
                // ignore
            } catch {
                self.isLoading = false
                self.results = []
                self.priceBadges = [:]
                self.errorText = "Search failed. " + (error as NSError).localizedDescription
            }
        }
    }

    func loadMoreIfAvailable() {
        guard hasMore, let key = lastSearchKey, !isLoading else { return }

        // Pokémon no longer paginates; just bail out cleanly.
        if key.game == .pokemon || key.game == .sports || key.game == .coins || key.game == .wine || key.game == .other {
            hasMore = false
            return
        }

        isLoading = true
        Task {
            do {
                let pageIndex = nextPage
                switch key.game {
                case .magic, .yugioh:
                    let next = try await MultigameService.searchNextPage(
                        game: key.game, text: key.text, rarity: key.rarity, number: key.number, afterPage: pageIndex - 1
                    )
                    self.results += next.cards
                    self.hasMore = next.hasMore
                    self.nextPage = pageIndex + 1
                    self.isLoading = false
                    if !next.cards.isEmpty { streamBadges(for: next.cards) }

                case .pokemon, .sports, .coins, .wine, .other:
                    // already handled above; keep compiler happy
                    self.isLoading = false
                }
            } catch {
                self.isLoading = false
                self.errorText = error.localizedDescription
            }
        }
    }

    func applyScan(_ hit: ScanHit) {
        self.query = hit.name ?? ""
        self.numberFilter = hit.number ?? ""
        self.pokemonLanguageMode = PokemonScanLanguage.from(catalogueCode: hit.pokemonLanguageCode)
        self.selectedRarity = nil
        if let metadata = hit.sportsMetadata {
            // A sports scan can identify a set/card number even when a stylized
            // player name is unreadable. Do not turn the generated clue label
            // into a fake player-name filter for the catalogue request.
            self.query = metadata.player
                ?? (metadata.cardNumber == nil ? SportsCardParser.identityLabel(for: metadata) : nil)
                ?? ""
            selectedSport = metadata.sport
            sportsYear = metadata.year ?? ""
            sportsBrand = metadata.brand ?? ""
            sportsSet = metadata.setName ?? ""
            sportsTeam = metadata.team ?? ""
            sportsSerialNumber = metadata.serialNumber ?? ""
            sportsRookie = metadata.isRookie
            sportsAutographed = metadata.isAutographed
            selectedRarity = metadata.parallel
        }
        if let metadata = hit.coinMetadata {
            coinCountry = metadata.country ?? ""
            coinDenomination = metadata.denomination ?? ""
            coinMintMark = metadata.mintMark ?? ""
        }
        if let metadata = hit.wineMetadata {
            wineProducer = metadata.producer ?? ""
            wineRegion = metadata.region ?? ""
            wineCountry = metadata.country ?? ""
            wineVarietal = metadata.varietal ?? ""
        }
        startSearch()
    }

    var sportsMetadata: SportsCardMetadata {
        SportsCardMetadata(
            sport: selectedSport,
            player: nonempty(query),
            year: nonempty(sportsYear),
            brand: nonempty(sportsBrand),
            setName: nonempty(sportsSet),
            team: nonempty(sportsTeam),
            cardNumber: nonempty(numberFilter),
            parallel: selectedRarity,
            serialNumber: nonempty(sportsSerialNumber),
            isRookie: sportsRookie,
            isAutographed: sportsAutographed
        )
    }

    var coinMetadata: CoinMetadata {
        CoinMetadata(
            title: nonempty(query),
            year: nonempty(numberFilter),
            country: nonempty(coinCountry),
            denomination: nonempty(coinDenomination),
            mintMark: nonempty(coinMintMark)
        )
    }

    var wineMetadata: WineMetadata {
        WineMetadata(
            wineName: nonempty(query),
            producer: nonempty(wineProducer),
            vintage: nonempty(numberFilter),
            region: nonempty(wineRegion),
            country: nonempty(wineCountry),
            varietal: nonempty(wineVarietal)
        )
    }

    deinit {
        searchTask?.cancel()
        streamingTask?.cancel()
    }

    // MARK: - Price badges
    private func streamBadges(for cards: [UICard]) {
        streamingTask?.cancel()
        for card in cards where card.priceUSD != nil || card.priceEUR != nil {
            priceBadges[card.id] = PriceBadge(usd: card.priceUSD, eur: card.priceEUR)
        }
        let items = cards.filter { $0.priceUSD == nil && $0.priceEUR == nil }
        guard !items.isEmpty else { return }

        streamingTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let maxConcurrent = 8
            await withTaskGroup(of: (String, PriceBadge?).self) { group in
                var idx = 0, inflight = 0
                func enqueue() {
                    while idx < items.count && inflight < maxConcurrent {
                        let card = items[idx]; idx += 1; inflight += 1
                        group.addTask {
                            let badge = await MultigameService.fetchBadge(for: card)
                            return (card.id, badge)
                        }
                    }
                }
                enqueue()
                for await (id, badge) in group {
                    inflight -= 1
                    if Task.isCancelled { break }
                    if let badge { await MainActor.run { self.priceBadges[id] = badge } }
                    enqueue()
                }
            }
        }
    }

    // MARK: - Rarities / game switch
    private func updateRarityOptions() {
        switch game {
        case .pokemon:
            rarityOptions = ["", "Common","Uncommon","Rare","Rare Holo","Rare Holo EX","Rare Ultra","Illustration Rare","Special Illustration Rare","Hyper Rare","Promo"]
        case .magic:
            rarityOptions = ["", "Common","Uncommon","Rare","Mythic"]
        case .yugioh:
            rarityOptions = ["", "Common","Rare","Super Rare","Ultra Rare","Secret Rare","Ultimate Rare","Ghost Rare","Starlight Rare"]
        case .sports:
            rarityOptions = ["", "Base", "Refractor", "Silver Prizm", "Gold", "Black", "Red", "Blue", "Green", "Purple", "Orange", "Cracked Ice", "Wave", "Shimmer", "X-Fractor"]
        case .coins, .wine, .other:
            rarityOptions = [""]
        }
    }

    private func handleGameSwitch(from old: Game, to new: Game) {
        searchTask?.cancel()
        streamingTask?.cancel()
        query = ""; numberFilter = ""; selectedRarity = nil
        selectedSport = .baseball
        sportsYear = ""; sportsBrand = ""; sportsSet = ""; sportsTeam = ""; sportsSerialNumber = ""
        sportsRookie = false; sportsAutographed = false
        coinCountry = ""; coinDenomination = ""; coinMintMark = ""
        wineProducer = ""; wineRegion = ""; wineCountry = ""; wineVarietal = ""
        pokemonLanguageMode = .english
        isLoading = false; errorText = nil
        results = []; priceBadges = [:]
        hasSearched = false
        hasMore = false; nextPage = 2; lastSearchKey = nil
        updateRarityOptions()
    }

    private struct SearchKey: Hashable {
        let game: Game
        let text: String
        let number: String?
        let rarity: String?
        let pokemonLanguage: PokemonScanLanguage
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
