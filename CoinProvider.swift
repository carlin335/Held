import Foundation

enum CoinProvider {
    private struct SearchResponse: Decodable {
        let types: [CoinType]
    }

    private struct CoinType: Decodable {
        let id: Int
        let url: URL?
        let title: String
        let issuer: Issuer?
        let minYear: Int?
        let maxYear: Int?

        enum CodingKeys: String, CodingKey {
            case id, url, title, issuer
            case minYear = "min_year"
            case maxYear = "max_year"
        }
    }

    private struct Issuer: Decodable {
        let name: String
    }

    static func search(query: String, metadata: CoinMetadata) async throws -> [UICard] {
        guard let key = AppSecrets.numistaAPIKey else {
            return [manualCard(query: query, metadata: metadata)]
        }

        var components = URLComponents(string: "https://api.numista.com/v3/types")
        var queryItems = [URLQueryItem(name: "q", value: metadata.searchTerms.joined(separator: " "))]
        if let year = metadata.year { queryItems.append(URLQueryItem(name: "year", value: year)) }
        queryItems.append(URLQueryItem(name: "lang", value: "en"))
        components?.queryItems = queryItems
        guard let url = components?.url else { return [manualCard(query: query, metadata: metadata)] }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "Numista-API-Key")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return [manualCard(query: query, metadata: metadata)]
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let cards = decoded.types.prefix(20).map { type in
                var details = metadata
                details.title = type.title
                details.country = type.issuer?.name ?? details.country
                if details.year == nil, type.minYear == type.maxYear, let year = type.minYear {
                    details.year = String(year)
                }
                return UICard(
                    id: "numista:\(type.id)",
                    game: .coins,
                    name: type.title,
                    number: details.year,
                    webURL: type.url,
                    setName: type.issuer?.name,
                    coinMetadata: details
                )
            }
            return cards.isEmpty ? [manualCard(query: query, metadata: metadata)] : cards
        } catch {
            return [manualCard(query: query, metadata: metadata)]
        }
    }

    static func researchRows(for card: UICard) -> [PriceRow] {
        let query = (card.coinMetadata?.searchTerms ?? [card.name]).joined(separator: " ")
        return [
            PriceRow(source: "PriceCharting", label: "Coin price search", value: "Research", url: priceChartingURL(query: query)),
            PriceRow(source: "Numista", label: "Catalogue & issue details", value: "Research", url: numistaURL(query: query))
        ]
    }

    private static func manualCard(query: String, metadata: CoinMetadata) -> UICard {
        let preferredName = metadata.title ?? query
        let name = preferredName.isEmpty ? metadata.searchTerms.joined(separator: " ") : preferredName
        let identity = metadata.searchTerms.joined(separator: "|").lowercased()
        return UICard(
            id: "coin|\(identity)",
            game: .coins,
            name: name,
            number: metadata.year,
            webURL: numistaURL(query: metadata.searchTerms.joined(separator: " ")),
            setName: metadata.country,
            coinMetadata: metadata
        )
    }

    private static func priceChartingURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.pricecharting.com/search-products")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    private static func numistaURL(query: String) -> URL? {
        var components = URLComponents(string: "https://en.numista.com/catalogue/index.php")
        components?.queryItems = [
            URLQueryItem(name: "r", value: query),
            URLQueryItem(name: "ct", value: "coin")
        ]
        return components?.url
    }
}

enum CoinParser {
    static func parse(_ text: String) -> CoinMetadata {
        let cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let year = firstMatch(cleaned, #"\b(?:1[0-9]{3}|20[0-9]{2})\b"#)
        let denomination = firstMatch(
            cleaned,
            #"(?i)\b(?:\d+(?:\.\d+)?\s*)?(?:cent|cents|penny|pence|quarter|dime|nickel|dollar|euro|pound|peso|franc|yen|yuan|rupee)s?\b"#
        )?.capitalized
        let countries = [
            "United States", "Canada", "Mexico", "Australia", "France", "Germany", "Italy", "Spain",
            "United Kingdom", "England", "Japan", "China", "India", "Brazil", "Switzerland"
        ]
        let country = countries.first { cleaned.localizedCaseInsensitiveContains($0) }
        let mint = firstMatch(cleaned, #"(?i)\bMINT\s*(?:MARK\s*)?([PDSW])\b"#)
            .flatMap { $0.split(separator: " ").last }
            .map(String.init)
        let title = [year, country, denomination].compactMap { $0 }.joined(separator: " ")

        return CoinMetadata(
            title: title.isEmpty ? "Unidentified coin" : title,
            year: year,
            country: country,
            denomination: denomination,
            mintMark: mint
        )
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
