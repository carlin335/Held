import Foundation

enum MultigameService {

    // MARK: - Price rows (detail view)

    static func loadPrices(for card: UICard) async throws -> [PriceRow] {
        switch card.game {
        case .pokemon:
            var rows = await PokemonProvider.loadPrices(for: card)
            if AppSecrets.hasPriceChartingToken,
               let priceChartingRows = try? await PriceChartingProvider.loadPrices(for: card) {
                rows += priceChartingRows
            }
            return withResearchFallback(rows, for: card)
        case .magic:
            return withResearchFallback((try? await ScryfallProvider.loadPrices(forID: card.id)) ?? [], for: card)
        case .yugioh:
            return withResearchFallback((try? await YGOProvider.loadPrices(forID: card.id)) ?? [], for: card)
        case .sports:
            if AppSecrets.hasPriceChartingToken,
               let rows = try? await PriceChartingProvider.loadPrices(for: card),
               !rows.isEmpty {
                return withResearchFallback(rows + SportsCardProvider.loadPrices(for: card), for: card)
            }
            return withResearchFallback(SportsCardProvider.loadPrices(for: card), for: card)
        case .coins:
            if AppSecrets.hasPriceChartingToken,
               let rows = try? await PriceChartingProvider.loadPrices(for: card),
               !rows.isEmpty {
                return withResearchFallback(rows + CoinProvider.researchRows(for: card), for: card)
            }
            return withResearchFallback(CoinProvider.researchRows(for: card), for: card)
        case .wine:
            return withResearchFallback(WineProvider.researchRows(for: card), for: card)
        case .other:
            if AppSecrets.hasPriceChartingToken,
               let rows = try? await PriceChartingProvider.loadPrices(for: card),
               !rows.isEmpty {
                return withResearchFallback(rows + GeneralCollectibleProvider.researchRows(for: card), for: card)
            }
            return withResearchFallback(GeneralCollectibleProvider.researchRows(for: card), for: card)
        }
    }

    private static func withResearchFallback(_ rows: [PriceRow], for card: UICard) -> [PriceRow] {
        rows.isEmpty ? MarketResearchFallback.rows(for: card) : rows
    }

    static func loadPricesOptional(for card: UICard) async -> [PriceRow]? {
        do { return try await loadPrices(for: card) }
        catch { return nil }
    }

    // MARK: - Tile price badge (lightweight, per-card)

    static func fetchBadge(for card: UICard) async -> PriceBadge? {
        switch card.game {
        case .pokemon:
            return try? await PokemonProvider.fetchPriceBadge(for: card)
        case .magic:
            return try? await ScryfallProvider.fetchPriceBadge(id: card.id)
        case .yugioh:
            return try? await YGOProvider.fetchPriceBadge(id: card.id)
        case .sports, .coins, .wine, .other:
            return nil
        }
    }

    // MARK: - Prewarm (Pokémon only)

    /// Old code prewarmed by calling searchLitePage; now we just issue the same resilient search once.
    /// `page` is ignored because Pokémon pagination is disabled in this simplified flow.
    static func prewarmPokemon(text: String, rarity: String?, number: String?, page: Int) {
        Task.detached(priority: .utility) {
            _ = try? await PokemonProvider.search(
                text: text,
                number: number,
                rarity: rarity,
                language: .english
            )
        }
    }

    // MARK: - Search facade

    struct SearchPage { let cards: [UICard]; let hasMore: Bool }

    /// First page search across games.
    /// - Important: Pokémon uses a single resilient call (no pagination).
    static func searchFirstPage(
        game: Game,
        text: String,
        rarity: String?,
        number: String?,
        printedNumber: String? = nil,
        sportsMetadata: SportsCardMetadata? = nil,
        coinMetadata: CoinMetadata? = nil,
        wineMetadata: WineMetadata? = nil,
        pokemonLanguage: PokemonScanLanguage = .english
    ) async throws -> SearchPage {
        switch game {
        case .pokemon:
            let cards = try await PokemonProvider.search(
                text: text,
                number: number,
                printedNumber: printedNumber,
                rarity: rarity,
                language: pokemonLanguage
            )
            return SearchPage(cards: cards, hasMore: false)

        case .magic:
            // Scryfall signature expects number before rarity.
            let cards = try await ScryfallProvider.search(text: text, number: number, rarity: rarity)
            // If your Scryfall provider paginates, adjust hasMore accordingly.
            return SearchPage(cards: cards, hasMore: false)

        case .yugioh:
            // YGO provider signature is (text, rarity, number).
            let cards = try await YGOProvider.search(text: text, rarity: rarity, number: number)
            // Adjust hasMore if your YGO path supports paging.
            return SearchPage(cards: cards, hasMore: false)

        case .sports:
            let metadata = sportsMetadata ?? SportsCardMetadata(player: text, cardNumber: number)
            if AppSecrets.hasCardSightAPIKey {
                let catalogueCards = try await CardSightProvider.search(metadata: metadata)
                return SearchPage(cards: catalogueCards, hasMore: false)
            }
            if AppSecrets.hasPriceChartingToken {
                let liveCards = try await PriceChartingProvider.searchSports(
                    query: metadata.searchTerms.joined(separator: " "),
                    metadata: metadata
                )
                return SearchPage(cards: liveCards, hasMore: false)
            }
            throw SportsSearchError.catalogueNotConnected

        case .coins:
            let metadata = coinMetadata ?? CoinMetadata(title: text, year: number)
            let cards = try await CoinProvider.search(query: text, metadata: metadata)
            return SearchPage(cards: cards, hasMore: false)

        case .wine:
            let metadata = wineMetadata ?? WineMetadata(wineName: text, vintage: number)
            let cards = try await WineProvider.search(query: text, metadata: metadata)
            return SearchPage(cards: cards, hasMore: false)

        case .other:
            return SearchPage(
                cards: GeneralCollectibleProvider.search(name: text, yearOrModel: number),
                hasMore: false
            )
        }
    }

    /// Next page search for games that support it.
    /// Pokémon returns an empty page by design (pagination disabled).
    static func searchNextPage(
        game: Game,
        text: String,
        rarity: String?,
        number: String?,
        afterPage: Int
    ) async throws -> SearchPage {
        switch game {
        case .pokemon:
            // No further pages in the simplified Pokémon flow.
            return .init(cards: [], hasMore: false)

        case .magic:
            // If you have a paged Scryfall implementation, forward to it here.
            // Example (adjust to your provider’s API):
            // let next = try await ScryfallProvider.searchNextPage(text: text, number: number, rarity: rarity, afterPage: afterPage)
            // return SearchPage(cards: next.cards, hasMore: next.hasMore)
            return .init(cards: [], hasMore: false)

        case .yugioh:
            // If you add YGO paging later, wire it here similarly.
            return .init(cards: [], hasMore: false)

        case .sports:
            return .init(cards: [], hasMore: false)
        case .coins, .wine, .other:
            return .init(cards: [], hasMore: false)
        }
    }
}

private enum MarketResearchFallback {
    static func rows(for card: UICard) -> [PriceRow] {
        let customQuery = card.marketSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String
        if let customQuery, !customQuery.isEmpty {
            query = customQuery
        } else {
            query = [
                card.languageCode == PokemonCatalogueLanguage.japanese.rawValue ? "Pokemon Japanese" : nil,
                card.name,
                card.setName ?? card.setCode,
                card.number.map { "#\($0)" },
                card.rarity
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        }

        var rows: [PriceRow] = []
        if card.game == .pokemon, let url = tcgplayerURL(query: query) {
            rows.append(
                PriceRow(
                    source: "TCGplayer",
                    label: "Check current listings",
                    value: nil,
                    url: url
                )
            )
        }
        if let url = priceChartingURL(query: query) {
            rows.append(
                PriceRow(
                    source: "PriceCharting",
                    label: "Check current guide",
                    value: nil,
                    url: url
                )
            )
        }
        if let url = soldListingsURL(query: query) {
            rows.append(
                PriceRow(
                    source: "eBay",
                    label: "Review completed sales",
                    value: nil,
                    url: url
                )
            )
        }
        return rows
    }

    private static func tcgplayerURL(query: String) -> URL? {
        var comps = URLComponents(string: "https://www.tcgplayer.com/search/pokemon/product")
        comps?.queryItems = [
            URLQueryItem(name: "productLineName", value: "pokemon"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "view", value: "grid")
        ]
        return comps?.url
    }

    private static func priceChartingURL(query: String) -> URL? {
        var comps = URLComponents(string: "https://www.pricecharting.com/search-products")
        comps?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: query)
        ]
        return comps?.url
    }

    private static func soldListingsURL(query: String) -> URL? {
        var comps = URLComponents(string: "https://www.ebay.com/sch/i.html")
        comps?.queryItems = [
            URLQueryItem(name: "_nkw", value: query),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "LH_Sold", value: "1")
        ]
        return comps?.url
    }
}

private enum GeneralCollectibleProvider {
    static func search(name: String, yearOrModel: String?) -> [UICard] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }
        let clue = yearOrModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = [trimmedName, clue ?? ""].filter { !$0.isEmpty }
        return [
            UICard(
                id: "collectible|" + terms.joined(separator: "|").lowercased(),
                game: .other,
                name: trimmedName,
                number: clue,
                webURL: completedSalesURL(query: terms.joined(separator: " ")),
                setName: clue
            )
        ]
    }

    static func researchRows(for card: UICard) -> [PriceRow] {
        let query = [card.name, card.number ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return [
            PriceRow(
                source: "eBay",
                label: "Completed sales",
                value: "Research",
                url: completedSalesURL(query: query)
            ),
            PriceRow(
                source: "PriceCharting",
                label: "Collectible price search",
                value: "Research",
                url: priceChartingURL(query: query)
            )
        ]
    }

    private static func completedSalesURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: query),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "LH_Sold", value: "1")
        ]
        return components?.url
    }

    private static func priceChartingURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.pricecharting.com/search-products")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }
}
