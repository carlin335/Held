import Foundation

enum SportsSearchError: LocalizedError {
    case catalogueNotConnected

    var errorDescription: String? {
        switch self {
        case .catalogueNotConnected:
            "Connect the free sports catalogue in Settings once, then search any player name."
        }
    }
}

enum SportsCardProvider {
    static func loadPrices(for card: UICard) -> [PriceRow] {
        let details = card.sportsMetadata ?? SportsCardMetadata(
            player: card.name,
            setName: card.setName,
            cardNumber: card.number
        )

        return [
            PriceRow(
                source: "eBay",
                label: "Completed sales",
                value: "Research",
                url: completedSalesURL(for: details)
            ),
            PriceRow(
                source: "SportsCardsPro",
                label: "Condition price guide",
                value: "Research",
                url: priceGuideURL(for: details)
            )
        ]
    }

    static func completedSalesURL(for details: SportsCardMetadata) -> URL? {
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: details.searchTerms.joined(separator: " ")),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "LH_Sold", value: "1")
        ]
        return components?.url
    }

    static func priceGuideURL(for details: SportsCardMetadata) -> URL? {
        var components = URLComponents(string: "https://www.sportscardspro.com/search-products")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: details.searchTerms.joined(separator: " "))
        ]
        return components?.url
    }

}

/// Full sports-card catalogue search. CardSight's free tier is used for real
/// player-name candidate lists; SportsCardsPro remains the optional price guide.
enum CardSightProvider {
    private struct SearchResponse: Decodable {
        let cards: [CardSummary]
    }

    private struct CardSummary: Decodable {
        let id: String
        let number: String?
        let name: String
        let isParallelOnly: Bool?
        let setName: String
        let releaseName: String?
        let releaseYear: String?
        let attributes: [String]?
    }

    static func search(metadata: SportsCardMetadata) async throws -> [UICard] {
        guard let apiKey = AppSecrets.cardSightAPIKey else {
            throw ProviderError.missingKey
        }

        var components = URLComponents(string: "https://api.cardsight.ai/v1/catalog/cards")
        var queryItems = [
            URLQueryItem(name: "take", value: "40"),
            URLQueryItem(name: "sort", value: "year"),
            URLQueryItem(name: "order", value: "desc")
        ]
        if let player = cleaned(metadata.player) {
            queryItems.append(URLQueryItem(name: "name", value: player))
        }
        if let number = cleaned(metadata.cardNumber) {
            queryItems.append(URLQueryItem(name: "number", value: number))
        }
        if let year = firstFourDigitYear(metadata.year) {
            queryItems.append(URLQueryItem(name: "year", value: year))
        }
        if let release = cleaned(metadata.setName) {
            queryItems.append(URLQueryItem(name: "releaseName", value: release))
        }
        if let manufacturer = cleaned(metadata.brand) {
            queryItems.append(URLQueryItem(name: "manufacturer", value: manufacturer))
        }
        guard queryItems.contains(where: { $0.name == "name" || $0.name == "number" }) else {
            return []
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw ProviderError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ProviderError.invalidKey }
        guard (200...299).contains(http.statusCode) else { throw ProviderError.badResponse }

        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        return payload.cards.map { card in
            var details = metadata
            details.player = card.name
            details.year = card.releaseYear ?? metadata.year
            details.cardNumber = card.number ?? metadata.cardNumber
            details.setName = displaySetName(for: card)
            let attributes = Set((card.attributes ?? []).map { $0.uppercased() })
            details.isRookie = metadata.isRookie || attributes.contains("RC")
            details.isAutographed = metadata.isAutographed
                || attributes.contains("AU")
                || attributes.contains("AUTO")

            return UICard(
                id: "cardsight:\(card.id)",
                game: .sports,
                name: card.name,
                number: details.cardNumber,
                imageSmallURL: nil,
                imageLargeURL: nil,
                apiURL: nil,
                webURL: SportsCardProvider.completedSalesURL(for: details),
                rarity: card.isParallelOnly == true ? "Parallel" : metadata.parallel,
                setName: details.setName,
                sportsMetadata: details
            )
        }
    }

    private static func displaySetName(for card: CardSummary) -> String {
        var parts: [String] = []
        let values = [card.releaseName, card.setName, card.releaseName == nil ? card.releaseYear : nil]
        for value in values {
            guard let value = cleaned(value),
                  !parts.contains(where: {
                      $0.localizedCaseInsensitiveContains(value)
                          || value.localizedCaseInsensitiveContains($0)
                  }) else { continue }
            parts.append(value)
        }
        return parts.joined(separator: " · ")
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func firstFourDigitYear(_ value: String?) -> String? {
        guard let value,
              let range = value.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    private enum ProviderError: LocalizedError {
        case missingKey
        case invalidKey
        case invalidURL
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: "Connect the free sports catalogue in Settings."
            case .invalidKey: "The sports catalogue key was rejected. Check it in Settings."
            case .invalidURL: "The sports catalogue request was invalid."
            case .badResponse: "The sports catalogue is temporarily unavailable."
            }
        }
    }
}

enum SportsCardParser {
    private static let brands = [
        "Upper Deck", "O-Pee-Chee", "Press Pass", "Wild Card", "Topps", "Panini",
        "Bowman", "Donruss", "Fleer", "Score", "Leaf", "SkyBox", "Pacific",
        "Pinnacle", "SAGE"
    ]

    private static let products = [
        "Bowman Chrome", "Topps Chrome", "National Treasures", "Stadium Club",
        "Allen & Ginter", "Museum Collection", "Crown Royale", "Metal Universe",
        "Ultimate Collection", "SP Authentic", "Young Guns", "Match Attax",
        "Donruss Optic", "Contenders", "Immaculate", "Heritage", "Prizm", "Select",
        "Optic", "Mosaic", "Finest", "Flawless", "Impeccable", "Obsidian", "Spectra",
        "Chronicles", "Revolution", "Hoops", "The Cup", "Artifacts", "Merlin",
        "Gypsy Queen", "Archives", "Inception", "Transcendent", "Five Star", "Dynasty",
        "Sterling", "Tribute", "Absolute", "Certified", "Playoff", "Prestige",
        "Luminance", "Origins", "Phoenix", "Future Stars", "Rated Rookie",
        "Rookie Debut", "Prospects", "Chrome"
    ]

    private static let parallels = [
        "Gold Vinyl", "Black Finite", "Cracked Ice", "Silver Prizm", "Color Blast",
        "Downtown", "Kaboom", "Superfractor", "X-Fractor", "Refractor", "Atomic",
        "Sapphire", "Shimmer", "Wave", "Disco", "Genesis", "Nebula", "Tie-Dye",
        "Pulsar", "Scope", "Velocity", "Holo", "Foil", "Gold", "Black", "Purple",
        "Orange", "Red", "Blue", "Green", "Pink", "Sepia", "Negative"
    ]

    private static let playerNoise = [
        "rookie", "autograph", "certified", "authentic", "baseball", "basketball", "football",
        "hockey", "soccer", "racing", "wrestling", "golf", "tennis", "ufc", "trading card",
        "memorabilia", "congratulations", "major league", "national league", "american league",
        "licensed", "copyright", "printed in", "made in", "player worn", "game used",
        "guaranteed", "official", "statistics", "career totals", "draft pick", "card no",
        "all star", "hall of fame", "most valuable player", "mvp"
    ] + brands.map { $0.lowercased() } + products.map { $0.lowercased() } + parallels.map { $0.lowercased() }

    static func parse(_ text: String, defaultSport: Sport = .baseball) -> SportsCardMetadata {
        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: " ")

        let year = firstMatch(
            in: joined,
            pattern: #"\b(?:19|20)\d{2}(?:\s*[-/]\s*(?:(?:19|20)?\d{2}))?\b"#
        )?.replacingOccurrences(of: " ", with: "")
        let serial = serialNumber(in: joined)
        let number = cardNumber(in: joined, excluding: serial)
        let brand = canonicalMatch(in: joined, candidates: brands)
        let product = canonicalMatch(in: joined, candidates: products)
        let parallel = canonicalMatch(in: joined, candidates: parallels)
        let upper = joined.uppercased()

        return SportsCardMetadata(
            sport: inferredSport(from: upper) ?? defaultSport,
            player: playerCandidate(from: lines),
            year: year,
            brand: brand,
            setName: product,
            team: nil,
            cardNumber: number,
            parallel: parallel,
            serialNumber: serial,
            isRookie: upper.range(of: #"\b(?:RC|ROOKIE)\b"#, options: .regularExpression) != nil,
            isAutographed: upper.range(of: #"\b(?:AUTO|AUTOGRAPH|SIGNED)\b"#, options: .regularExpression) != nil
        )
    }

    static func identityLabel(for metadata: SportsCardMetadata) -> String? {
        let clues = [
            metadata.year,
            metadata.brand,
            metadata.setName,
            metadata.cardNumber.map { "#\($0)" }
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard clues.count >= 2 else { return nil }
        return clues.joined(separator: " ")
    }

    private static func playerCandidate(from lines: [String]) -> String? {
        // Some designs stack first and last names on separate lines. Include
        // adjacent pairs as candidates; manufacturer/product pairs are removed
        // by the same noise vocabulary below.
        let adjacent = zip(lines, lines.dropFirst()).map { "\($0) \($1)" }
        return (lines + adjacent).compactMap { line -> (String, Int)? in
            let cleaned = line.replacingOccurrences(
                of: #"[^A-Za-zÀ-ÖØ-öø-ÿ.'\- ]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            let words = cleaned.split(separator: " ")
            guard (1...5).contains(words.count), cleaned.count >= 4 else { return nil }

            let lower = cleaned.lowercased()
            guard !playerNoise.contains(where: { lower.contains($0) }) else { return nil }
            let letters = cleaned.filter { $0.isLetter }.count
            guard letters >= max(4, cleaned.count / 2) else { return nil }
            if words.count == 1, line != line.uppercased() { return nil }

            var score = min(cleaned.count, 24)
            if line == line.uppercased() { score += 5 }
            if words.count == 2 || words.count == 3 { score += 4 }
            if words.count >= 4 { score -= 6 }
            if lower.contains(" inc") || lower.contains(" llc") || lower.contains(" company") { return nil }
            return (smartTitleCase(cleaned), score)
        }
        .max { $0.1 < $1.1 }?
        .0
    }

    private static func cardNumber(in text: String, excluding serial: String?) -> String? {
        var scrubbed = text.replacingOccurrences(
            of: #"\b\d{1,4}\s*(?:/|OF)\s*\d{1,4}\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        if let serial { scrubbed = scrubbed.replacingOccurrences(of: serial, with: " ") }
        let patterns = [
            #"(?i)(?:CARD\s*)?#\s*([A-Z0-9]{1,5}(?:-[A-Z0-9]{1,6})?)"#,
            #"(?i)\b(?:CARD\s*)?(?:NO\.?|NUMBER)\s*[:#-]?\s*([A-Z0-9]{1,5}(?:-[A-Z0-9]{1,6})?)\b"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: scrubbed,
                    range: NSRange(scrubbed.startIndex..., in: scrubbed)
                  ),
                  let range = Range(match.range(at: 1), in: scrubbed) else { continue }
            let candidate = String(scrubbed[range]).uppercased()
            if candidate.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func serialNumber(in text: String) -> String? {
        if text.range(of: #"(?i)\b(?:ONE\s+OF\s+ONE|ONE/ONE)\b"#, options: .regularExpression) != nil {
            return "1/1"
        }
        guard let raw = firstMatch(
            in: text,
            pattern: #"(?i)\b\d{1,4}\s*(?:/|OF)\s*\d{1,4}\b"#
        ) else { return nil }
        return raw.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "OF", with: "/")
    }

    private static func smartTitleCase(_ value: String) -> String {
        value.split(separator: " ").map { word in
            let upper = word.uppercased()
            if ["II", "III", "IV", "JR.", "SR."].contains(upper) { return upper }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func canonicalMatch(in text: String, candidates: [String]) -> String? {
        candidates.first { text.localizedCaseInsensitiveContains($0) }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func inferredSport(from text: String) -> Sport? {
        if text.contains("MLB") || text.contains("BASEBALL") { return .baseball }
        if text.contains("NBA") || text.contains("BASKETBALL") { return .basketball }
        if text.contains("NFL") || text.contains("FOOTBALL") { return .football }
        if text.contains("NHL") || text.contains("HOCKEY") { return .hockey }
        if text.contains("MLS") || text.contains("SOCCER") || text.contains("FIFA") { return .soccer }
        if text.contains("NASCAR") || text.contains("RACING") { return .racing }
        if text.contains("WWE") || text.contains("WRESTLING") { return .wrestling }
        if text.contains("PGA") || text.contains("GOLF") { return .golf }
        return nil
    }
}
