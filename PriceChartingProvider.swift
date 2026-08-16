import Foundation

enum PriceChartingProvider {
    private static let rateLimiter = RateLimiter()

    private actor RateLimiter {
        private var lastRequest = Date.distantPast

        func waitForTurn() async throws {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < 1.05 {
                let nanoseconds = UInt64((1.05 - elapsed) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            }
            lastRequest = Date()
        }
    }

    private struct SearchResponse: Decodable {
        let status: String
        let products: [ProductSummary]?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case status, products
            case errorMessage = "error-message"
        }
    }

    private struct ProductSummary: Decodable {
        let id: String
        let productName: String
        let consoleName: String

        enum CodingKeys: String, CodingKey {
            case id
            case productName = "product-name"
            case consoleName = "console-name"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let stringID = try? container.decode(String.self, forKey: .id) {
                id = stringID
            } else {
                id = String(try container.decode(Int.self, forKey: .id))
            }
            productName = try container.decode(String.self, forKey: .productName)
            consoleName = try container.decode(String.self, forKey: .consoleName)
        }
    }

    private struct ProductResponse: Decodable {
        let status: String
        let loosePrice: Int?
        let gradeSevenPrice: Int?
        let gradeEightPrice: Int?
        let gradeNinePrice: Int?
        let gradeNineFivePrice: Int?
        let psaTenPrice: Int?
        let bgsTenPrice: Int?
        let cgcTenPrice: Int?
        let sgcTenPrice: Int?
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case status
            case loosePrice = "loose-price"
            case gradeSevenPrice = "cib-price"
            case gradeEightPrice = "new-price"
            case gradeNinePrice = "graded-price"
            case gradeNineFivePrice = "box-only-price"
            case psaTenPrice = "manual-only-price"
            case bgsTenPrice = "bgs-10-price"
            case cgcTenPrice = "condition-17-price"
            case sgcTenPrice = "condition-18-price"
            case errorMessage = "error-message"
        }
    }

    static func searchSports(
        query: String,
        metadata: SportsCardMetadata
    ) async throws -> [UICard] {
        let queries = sportsSearchQueries(metadata: metadata, fallback: query)
        var products: [ProductSummary] = []
        var seen = Set<String>()

        // Start with the exact OCR clues. A second, broader query is used only
        // when those clues returned nothing convincing, respecting the API's
        // one-request-per-second limit while rescuing one noisy field.
        for (index, searchText) in queries.enumerated() {
            let response: SearchResponse = try await request(
                path: "products",
                queryItems: [URLQueryItem(name: "q", value: searchText)],
                host: "www.sportscardspro.com"
            )
            guard response.status == "success" else {
                throw ProviderError.message(response.errorMessage ?? "SportsCardsPro search failed.")
            }
            for product in response.products ?? [] where seen.insert(product.id).inserted {
                products.append(product)
            }
            let strongest = products.map { sportsMatchScore($0, metadata: metadata) }.max() ?? 0
            if strongest >= 70 || index == queries.count - 1 { break }
        }

        let ranked = products.sorted {
            let lhs = sportsMatchScore($0, metadata: metadata)
            let rhs = sportsMatchScore($1, metadata: metadata)
            if lhs == rhs { return $0.productName < $1.productName }
            return lhs > rhs
        }

        return ranked.prefix(12).map { product in
            var details = metadata
            details.player = playerName(from: product.productName)
            details.cardNumber = cardNumber(from: product.productName) ?? metadata.cardNumber
            details.year = metadata.year ?? year(from: product.consoleName)
            details.setName = product.consoleName
            details.parallel = metadata.parallel ?? parallelName(from: product.productName)

            return UICard(
                id: "pricecharting:\(product.id)",
                game: .sports,
                name: product.productName,
                number: details.cardNumber,
                webURL: SportsCardProvider.priceGuideURL(for: details),
                rarity: details.parallel,
                setName: product.consoleName,
                sportsMetadata: details
            )
        }
    }

    static func loadPrices(for card: UICard) async throws -> [PriceRow] {
        let host = card.game == .sports ? "www.sportscardspro.com" : "www.pricecharting.com"
        let id = card.id.hasPrefix("pricecharting:")
            ? String(card.id.dropFirst("pricecharting:".count))
            : nil
        let queryItems: [URLQueryItem]
        if let id {
            queryItems = [URLQueryItem(name: "id", value: id)]
        } else {
            queryItems = [URLQueryItem(name: "q", value: searchQuery(for: card))]
        }

        let product: ProductResponse = try await request(
            path: "product",
            queryItems: queryItems,
            host: host
        )
        guard product.status == "success" else {
            throw ProviderError.message(product.errorMessage ?? "PriceCharting lookup failed.")
        }

        let sourceURL = researchURL(for: card)
        let values: [(String, Int?)] = [
            ("Ungraded", product.loosePrice),
            ("Grade 7 / 7.5", product.gradeSevenPrice),
            ("Grade 8 / 8.5", product.gradeEightPrice),
            ("Grade 9", product.gradeNinePrice),
            ("Grade 9.5", product.gradeNineFivePrice),
            ("PSA 10", product.psaTenPrice),
            ("BGS 10", product.bgsTenPrice),
            ("CGC 10", product.cgcTenPrice),
            ("SGC 10", product.sgcTenPrice)
        ]

        let rows = values.compactMap { entry -> PriceRow? in
            let (label, cents) = entry
            guard let cents, cents > 0 else { return nil }
            return PriceRow(
                source: card.game == .sports ? "SportsCardsPro" : "PriceCharting",
                label: label,
                value: (Double(cents) / 100).formatted(.currency(code: "USD")),
                url: sourceURL
            )
        }
        return rows
    }

    private static func sportsSearchQueries(
        metadata: SportsCardMetadata,
        fallback: String
    ) -> [String] {
        let exact = metadata.searchTerms.joined(separator: " ")
        let broad = [
            metadata.player,
            metadata.cardNumber.map { "#\($0)" },
            metadata.year,
            metadata.brand ?? metadata.setName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let supplied = fallback.trimmingCharacters(in: .whitespacesAndNewlines)

        var result: [String] = []
        for value in [exact, broad, supplied] where !value.isEmpty {
            if !result.contains(where: { normalizedSportsText($0) == normalizedSportsText(value) }) {
                result.append(value)
            }
        }
        return Array(result.prefix(2))
    }

    private static func sportsMatchScore(
        _ product: ProductSummary,
        metadata: SportsCardMetadata
    ) -> Int {
        let title = normalizedSportsText(product.productName)
        let set = normalizedSportsText(product.consoleName)
        let combined = title + " " + set
        var score = 0

        if let player = metadata.player {
            let tokens = sportsTokens(player)
            let matched = tokens.filter { combined.contains($0) }.count
            score += matched * 12
            if !tokens.isEmpty, matched == tokens.count { score += 24 }
        }
        if let expected = normalizedSportsNumber(metadata.cardNumber) {
            if let candidate = normalizedSportsNumber(cardNumber(from: product.productName)) {
                score += candidate == expected ? 80 : -80
            } else {
                score -= 10
            }
        }
        if let year = metadata.year {
            score += combined.contains(normalizedSportsText(year)) ? 24 : -4
        }
        if let brand = metadata.brand {
            score += combined.contains(normalizedSportsText(brand)) ? 16 : 0
        }
        if let productName = metadata.setName {
            let tokens = sportsTokens(productName)
            score += tokens.filter { combined.contains($0) }.count * 7
        }
        if let parallel = metadata.parallel {
            score += combined.contains(normalizedSportsText(parallel)) ? 18 : 0
        }
        if metadata.isRookie, combined.contains("rookie") { score += 8 }
        if metadata.isAutographed,
           (combined.contains("autograph") || combined.contains(" auto")) { score += 8 }
        if let printRun = metadata.serialNumber?.split(separator: "/").last {
            let rawCombined = (product.productName + " " + product.consoleName).lowercased()
            if rawCombined.contains("/\(printRun)") { score += 20 }
        }
        if combined.contains(normalizedSportsText(metadata.sport.rawValue)) { score += 6 }
        return score
    }

    private static func normalizedSportsText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sportsTokens(_ value: String) -> [String] {
        normalizedSportsText(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func normalizedSportsNumber(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedSportsText(value).replacingOccurrences(of: " ", with: "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        host: String
    ) async throws -> Response {
        guard let token = AppSecrets.priceChartingAPIToken else {
            throw ProviderError.missingToken
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/\(path)"
        components.queryItems = [URLQueryItem(name: "t", value: token)] + queryItems
        guard let url = components.url else { throw ProviderError.invalidURL }

        try await rateLimiter.waitForTurn()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProviderError.badResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func searchQuery(for card: UICard) -> String {
        if let details = card.sportsMetadata {
            return details.searchTerms.joined(separator: " ")
        }
        if let marketSearchQuery = card.marketSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !marketSearchQuery.isEmpty {
            return marketSearchQuery
        }
        return [
            card.languageCode == PokemonCatalogueLanguage.japanese.rawValue ? "Pokemon Japanese" : nil,
            card.name,
            card.setName,
            card.number.map { "#\($0)" },
            card.rarity
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func researchURL(for card: UICard) -> URL? {
        if let details = card.sportsMetadata {
            return SportsCardProvider.priceGuideURL(for: details)
        }
        var components = URLComponents(string: "https://www.pricecharting.com/search-products")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: searchQuery(for: card))
        ]
        return components?.url
    }

    private static func playerName(from productName: String) -> String {
        productName.components(separatedBy: "#").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? productName
    }

    private static func year(from value: String) -> String? {
        guard let range = value.range(
            of: #"\b(?:19|20)\d{2}(?:[-/](?:(?:19|20)?\d{2}))?\b"#,
            options: .regularExpression
        ) else { return nil }
        return String(value[range])
    }

    private static func parallelName(from productName: String) -> String? {
        guard let range = productName.range(of: #"\[[^\]]+\]"#, options: .regularExpression) else {
            return nil
        }
        return String(productName[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func cardNumber(from productName: String) -> String? {
        guard let range = productName.range(of: #"(?i)#\s*([A-Z0-9\-]+)"#, options: .regularExpression) else {
            return nil
        }
        return String(productName[range])
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ProviderError: LocalizedError {
        case missingToken
        case invalidURL
        case badResponse
        case message(String)

        var errorDescription: String? {
            switch self {
            case .missingToken: "Add PRICECHARTING_API_TOKEN to Config.local.xcconfig."
            case .invalidURL: "The PriceCharting request URL was invalid."
            case .badResponse: "PriceCharting returned an unexpected response."
            case .message(let message): message
            }
        }
    }
}
