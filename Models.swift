import Foundation

// MARK: - Game

public enum Game: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case pokemon = "Pokémon"
    case magic   = "Magic"
    case yugioh  = "Yu-Gi-Oh!"
    case sports  = "Sports"
    case coins   = "Coins"
    case wine    = "Wine"
    case other   = "Other"

    public var id: String { rawValue }
}

// MARK: - Pokémon language

/// Language behavior used by Pokémon OCR and catalogue matching.
/// `auto` keeps both OCR models available, then prioritizes the catalogue that
/// matches the recognized title script.
public enum PokemonScanLanguage: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case auto = "Auto"
    case english = "English"
    case japanese = "Japanese"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .auto: "Auto"
        case .english: "EN"
        case .japanese: "日本語"
        }
    }

    public var ocrLanguageHints: [String] {
        switch self {
        case .auto: ["ja-JP", "ja", "en-US", "en", "de-DE", "es-ES", "fr-FR", "it-IT", "pt-BR"]
        case .english: ["en-US", "en", "de-DE", "es-ES", "fr-FR", "it-IT", "pt-BR"]
        case .japanese: ["ja-JP", "ja"]
        }
    }

    public func catalogueOrder(for recognizedText: String) -> [PokemonCatalogueLanguage] {
        switch self {
        case .english: [.english, .german, .spanish, .french, .italian, .portugueseBrazil]
        case .japanese: [.japanese]
        case .auto:
            recognizedText.containsJapaneseScriptForHeld
                ? [.japanese, .english, .german, .spanish, .french, .italian, .portugueseBrazil]
                : [.english, .german, .spanish, .french, .italian, .portugueseBrazil, .japanese]
        }
    }

    public static func from(catalogueCode: String?) -> PokemonScanLanguage {
        catalogueCode == PokemonCatalogueLanguage.japanese.rawValue ? .japanese : .english
    }
}

public enum PokemonCatalogueLanguage: String, Codable, Hashable, Sendable {
    case english = "en"
    case japanese = "ja"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portugueseBrazil = "pt-br"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "Japanese"
        case .german: "German"
        case .spanish: "Spanish"
        case .french: "French"
        case .italian: "Italian"
        case .portugueseBrazil: "Portuguese (Brazil)"
        }
    }
}

extension String {
    var containsJapaneseScriptForHeld: Bool {
        range(of: #"[ぁ-んァ-ンｦ-ﾟ一-龯々〆ヵヶー]"#, options: .regularExpression) != nil
    }
}

public enum Sport: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case baseball = "Baseball"
    case basketball = "Basketball"
    case football = "Football"
    case hockey = "Hockey"
    case soccer = "Soccer"
    case racing = "Racing"
    case wrestling = "Wrestling"
    case golf = "Golf"
    case other = "Other"

    public var id: String { rawValue }
}

public struct SportsCardMetadata: Equatable, Hashable, Sendable, Codable {
    public var sport: Sport
    public var player: String?
    public var year: String?
    public var brand: String?
    public var setName: String?
    public var team: String?
    public var cardNumber: String?
    public var parallel: String?
    public var serialNumber: String?
    public var isRookie: Bool
    public var isAutographed: Bool

    public init(
        sport: Sport = .baseball,
        player: String? = nil,
        year: String? = nil,
        brand: String? = nil,
        setName: String? = nil,
        team: String? = nil,
        cardNumber: String? = nil,
        parallel: String? = nil,
        serialNumber: String? = nil,
        isRookie: Bool = false,
        isAutographed: Bool = false
    ) {
        self.sport = sport
        self.player = player
        self.year = year
        self.brand = brand
        self.setName = setName
        self.team = team
        self.cardNumber = cardNumber
        self.parallel = parallel
        self.serialNumber = serialNumber
        self.isRookie = isRookie
        self.isAutographed = isAutographed
    }

    public var searchTerms: [String] {
        // SportsCardsPro's own documented search examples lead with player and
        // card number, then use year/product clues to narrow the printing.
        var terms = [player, cardNumber.map { "#\($0)" }, year, brand, setName, team, parallel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let printRun = serialNumber?.split(separator: "/").last {
            terms.append("/\(printRun)")
        }
        if isRookie { terms.append("rookie") }
        if isAutographed { terms.append("autograph") }
        return terms
    }
}

public struct CoinMetadata: Equatable, Hashable, Sendable, Codable {
    public var title: String?
    public var year: String?
    public var country: String?
    public var denomination: String?
    public var mintMark: String?
    public var composition: String?

    public init(
        title: String? = nil,
        year: String? = nil,
        country: String? = nil,
        denomination: String? = nil,
        mintMark: String? = nil,
        composition: String? = nil
    ) {
        self.title = title
        self.year = year
        self.country = country
        self.denomination = denomination
        self.mintMark = mintMark
        self.composition = composition
    }

    public var searchTerms: [String] {
        [year, country, denomination, title, mintMark]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct WineMetadata: Equatable, Hashable, Sendable, Codable {
    public var wineName: String?
    public var producer: String?
    public var vintage: String?
    public var region: String?
    public var country: String?
    public var varietal: String?
    public var bottleSize: String?
    public var alcoholByVolume: String?

    public init(
        wineName: String? = nil,
        producer: String? = nil,
        vintage: String? = nil,
        region: String? = nil,
        country: String? = nil,
        varietal: String? = nil,
        bottleSize: String? = nil,
        alcoholByVolume: String? = nil
    ) {
        self.wineName = wineName
        self.producer = producer
        self.vintage = vintage
        self.region = region
        self.country = country
        self.varietal = varietal
        self.bottleSize = bottleSize
        self.alcoholByVolume = alcoholByVolume
    }

    public var searchTerms: [String] {
        [producer, wineName, vintage, region, country, varietal]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - ScanHit (scanner result)

/// Result of one scan pass. Fields are optional so the engine can emit
/// partial guesses (e.g., a name before a number) without blocking.
public struct ScanHit: Equatable, Sendable, Codable {
    public let name: String?
    /// Full printed identifier when visible, such as "021/086". `number`
    /// remains the provider-friendly local ID ("21") used for catalogue APIs.
    public let printedNumber: String?
    public let number: String?
    public let pokemonLanguageCode: String?
    public let sportsMetadata: SportsCardMetadata?
    public let coinMetadata: CoinMetadata?
    public let wineMetadata: WineMetadata?

    public init(
        name: String?,
        number: String?,
        printedNumber: String? = nil,
        pokemonLanguageCode: String? = nil,
        sportsMetadata: SportsCardMetadata? = nil,
        coinMetadata: CoinMetadata? = nil,
        wineMetadata: WineMetadata? = nil
    ) {
        self.name = name
        self.number = number
        self.printedNumber = printedNumber
        self.pokemonLanguageCode = pokemonLanguageCode
        self.sportsMetadata = sportsMetadata
        self.coinMetadata = coinMetadata
        self.wineMetadata = wineMetadata
    }

    /// True if at least one field is non-empty after trimming.
    public var hasContent: Bool {
        let ws = CharacterSet.whitespacesAndNewlines
        return !(name?.trimmingCharacters(in: ws).isEmpty ?? true)
            || !(number?.trimmingCharacters(in: ws).isEmpty ?? true)
    }

    /// Normalized (trimmed) values.
    public var normalized: ScanHit {
        let ws = CharacterSet.whitespacesAndNewlines
        return ScanHit(
            name: name?.trimmingCharacters(in: ws),
            number: number?.trimmingCharacters(in: ws),
            printedNumber: printedNumber?.trimmingCharacters(in: ws),
            pokemonLanguageCode: pokemonLanguageCode,
            sportsMetadata: sportsMetadata,
            coinMetadata: coinMetadata,
            wineMetadata: wineMetadata
        )
    }

    /// Merge two hits, preferring non-empty fields from `rhs`.
    public func merging(_ rhs: ScanHit) -> ScanHit {
        let ws = CharacterSet.whitespacesAndNewlines
        let leftName = name?.trimmingCharacters(in: ws)
        let rightName = rhs.name?.trimmingCharacters(in: ws)
        let leftNum = number?.trimmingCharacters(in: ws)
        let rightNum = rhs.number?.trimmingCharacters(in: ws)
        let leftPrintedNum = printedNumber?.trimmingCharacters(in: ws)
        let rightPrintedNum = rhs.printedNumber?.trimmingCharacters(in: ws)

        return ScanHit(
            name: (rightName?.isEmpty == false ? rightName : leftName),
            number: (rightNum?.isEmpty == false ? rightNum : leftNum),
            printedNumber: (rightPrintedNum?.isEmpty == false ? rightPrintedNum : leftPrintedNum),
            pokemonLanguageCode: rhs.pokemonLanguageCode ?? pokemonLanguageCode,
            sportsMetadata: rhs.sportsMetadata ?? sportsMetadata,
            coinMetadata: rhs.coinMetadata ?? coinMetadata,
            wineMetadata: rhs.wineMetadata ?? wineMetadata
        )
    }

    public func tagged(with pokemonLanguage: PokemonCatalogueLanguage) -> ScanHit {
        ScanHit(
            name: name,
            number: number,
            printedNumber: printedNumber,
            pokemonLanguageCode: pokemonLanguage.rawValue,
            sportsMetadata: sportsMetadata,
            coinMetadata: coinMetadata,
            wineMetadata: wineMetadata
        )
    }
}

// MARK: - UICard

/// Lightweight UI model used across the app for grid tiles & detail pages.
/// Keep this independent from any specific provider’s raw API schema.
public struct UICard: Identifiable, Hashable, Codable, Sendable {
    // Stable identity for navigation/favorites. Prefer provider ID (UUID/string/int) as string.
    public let id: String

    public let game: Game
    public let name: String

    /// Printed card/collector number (e.g., "096", "96", "123a"). Optional for YGO.
    public var number: String?

    /// Provider set code (e.g., Scryfall's "khm", Poke Set ID like "base1")
    public var setCode: String?

    /// Preferred images
    public var imageSmallURL: URL?
    public var imageLargeURL: URL?

    /// Source links
    public var apiURL: URL?
    public var webURL: URL?

    /// Basic price snapshots (strings so we can show "—" or formatted)
    public var priceUSD: String?
    public var priceEUR: String?

    /// Catalogue language for language-specific identities such as Japanese
    /// Pokémon printings ("en" or "ja").
    public var languageCode: String?

    /// Provider-normalized query used for value sources when the displayed card
    /// title is localized (for example, an English PriceCharting query for a
    /// Japanese TCGdex card).
    public var marketSearchQuery: String?

    /// Optional set info list (useful for YGO client-side rarity filtering)
    public var sets: [SetInfo]?

    // Extra metadata that some views show
    public var rarity: String?
    public var setName: String?
    public var sportsMetadata: SportsCardMetadata?
    public var coinMetadata: CoinMetadata?
    public var wineMetadata: WineMetadata?

    public init(
        id: String,
        game: Game,
        name: String,
        number: String? = nil,
        setCode: String? = nil,
        imageSmallURL: URL? = nil,
        imageLargeURL: URL? = nil,
        apiURL: URL? = nil,
        webURL: URL? = nil,
        priceUSD: String? = nil,
        priceEUR: String? = nil,
        languageCode: String? = nil,
        marketSearchQuery: String? = nil,
        sets: [SetInfo]? = nil,
        rarity: String? = nil,
        setName: String? = nil,
        sportsMetadata: SportsCardMetadata? = nil,
        coinMetadata: CoinMetadata? = nil,
        wineMetadata: WineMetadata? = nil
    ) {
        self.id = id
        self.game = game
        self.name = name
        self.number = number
        self.setCode = setCode
        self.imageSmallURL = imageSmallURL
        self.imageLargeURL = imageLargeURL
        self.apiURL = apiURL
        self.webURL = webURL
        self.priceUSD = priceUSD
        self.priceEUR = priceEUR
        self.languageCode = languageCode
        self.marketSearchQuery = marketSearchQuery
        self.sets = sets
        self.rarity = rarity
        self.setName = setName
        self.sportsMetadata = sportsMetadata
        self.coinMetadata = coinMetadata
        self.wineMetadata = wineMetadata
    }

    // Hash/Equatable by (id + game) to keep favorites stable across sessions
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(game.rawValue)
    }

    public static func == (lhs: UICard, rhs: UICard) -> Bool {
        lhs.id == rhs.id && lhs.game == rhs.game
    }

    // Normalizes numbers like "096" -> "96" (keeps letters like "123a")
    public var normalizedNumber: String? {
        guard let n = number, !n.isEmpty else { return nil }
        let prefix = n.prefix { $0.isNumber }
        if prefix.isEmpty { return n }
        let trimmed = String(prefix).drop { $0 == "0" }
        let normalizedDigits = trimmed.isEmpty ? "0" : String(trimmed)
        if prefix.count == n.count {
            return normalizedDigits
        } else {
            // preserve trailing letters/suffix after the numeric portion
            let suffix = n.dropFirst(prefix.count)
            return normalizedDigits + suffix
        }
    }

    // Nested set info used by YGO rarity filtering and display
    public struct SetInfo: Hashable, Codable, Sendable {
        public var name: String?
        public var code: String?
        public var rarity: String?

        public init(name: String? = nil, code: String? = nil, rarity: String? = nil) {
            self.name = name
            self.code = code
            self.rarity = rarity
        }
    }
}

// MARK: - PriceBadge (for grid tiles)

public struct PriceBadge: Codable, Hashable, Sendable {
    public var usd: String? = nil
    public var eur: String? = nil

    public init(usd: String? = nil, eur: String? = nil) {
        self.usd = usd
        self.eur = eur
    }
}

// MARK: - PriceRow (detail view list items)

/// If your detail page shows multiple sources (TCGplayer/Cardmarket/etc.)
/// this compact model renders well in a simple list.
public struct PriceRow: Identifiable, Hashable, Codable, Sendable {
    public var id: String { source + "|" + label + "|" + (value ?? "—") }

    public let source: String          // e.g. "TCGplayer", "Cardmarket", "Scryfall"
    public let label: String           // e.g. "Market", "Trend", "Low", "Foil Market"
    public let value: String?          // e.g. "$3.25", "€2.10"
    public let url: URL?               // deep link to the source page

    public init(source: String, label: String, value: String?, url: URL?) {
        self.source = source
        self.label = label
        self.value = value
        self.url = url
    }
}

// MARK: - Personal collection

public enum CardCondition: String, CaseIterable, Identifiable, Codable {
    case raw = "Raw"
    case nearMint = "Near Mint"
    case excellent = "Excellent"
    case played = "Played"
    case graded = "Graded"

    public var id: String { rawValue }
}

public struct CollectionItem: Identifiable, Hashable, Codable {
    public let id: UUID
    public var card: UICard
    public var quantity: Int
    public var condition: CardCondition
    public var grade: String?
    public var gradingCompany: String?
    public var certificationNumber: String?
    public var purchasePrice: Double?
    public var customMarketValue: Double?
    public var notes: String
    public var dateAdded: Date

    public init(
        id: UUID = UUID(),
        card: UICard,
        quantity: Int = 1,
        condition: CardCondition = .raw,
        grade: String? = nil,
        gradingCompany: String? = nil,
        certificationNumber: String? = nil,
        purchasePrice: Double? = nil,
        customMarketValue: Double? = nil,
        notes: String = "",
        dateAdded: Date = .now
    ) {
        self.id = id
        self.card = card
        self.quantity = max(1, quantity)
        self.condition = condition
        self.grade = grade
        self.gradingCompany = gradingCompany
        self.certificationNumber = certificationNumber
        self.purchasePrice = purchasePrice
        self.customMarketValue = customMarketValue
        self.notes = notes
        self.dateAdded = dateAdded
    }

    public var marketValue: Double {
        (customMarketValue ?? card.numericUSD) * Double(quantity)
    }

    public var unitMarketValue: Double {
        customMarketValue ?? card.numericUSD
    }

    public var formattedMarketValue: String? {
        guard unitMarketValue > 0 else { return nil }
        return unitMarketValue.formatted(.currency(code: "USD"))
    }
}

public extension UICard {
    var numericUSD: Double {
        guard let priceUSD else { return 0 }
        let allowed = priceUSD.filter { $0.isNumber || $0 == "." }
        return Double(allowed) ?? 0
    }

    var formattedUSD: String? {
        guard numericUSD > 0 else { return nil }
        return numericUSD.formatted(.currency(code: "USD"))
    }

    func applying(_ badge: PriceBadge?) -> UICard {
        guard let badge else { return self }
        var copy = self
        if let usd = badge.usd { copy.priceUSD = usd }
        if let eur = badge.eur { copy.priceEUR = eur }
        return copy
    }
}

// MARK: - Small URL helpers

public extension URL {
    /// Convenience: URL(string:) that accepts nil/empty gracefully.
    init?(safe string: String?) {
        guard let s = string, !s.isEmpty else { return nil }
        self.init(string: s)
    }
}

public extension String {
    /// Percent-encode for use in a single query value.
    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
