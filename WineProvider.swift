import Foundation

enum WineProvider {
    private struct SearchResponse: Decodable {
        let products: [Product]
    }

    private struct Product: Decodable {
        let code: String?
        let productName: String?
        let brands: String?
        let origins: String?
        let countries: String?
        let imageURL: URL?
        let quantity: String?

        enum CodingKeys: String, CodingKey {
            case code, brands, origins, countries, quantity
            case productName = "product_name"
            case imageURL = "image_url"
        }
    }

    static func search(query: String, metadata: WineMetadata) async throws -> [UICard] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: metadata.searchTerms.joined(separator: " ")),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "12"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,origins,countries,image_url,quantity")
        ]
        guard let url = components?.url else { return [manualCard(query: query, metadata: metadata)] }

        var request = URLRequest(url: url)
        request.setValue("Held/2.4.4 (github.com/carlin335/Card-Sense)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return [manualCard(query: query, metadata: metadata)]
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let cards = decoded.products.compactMap { product -> UICard? in
                guard let productName = product.productName, !productName.isEmpty else { return nil }
                var details = metadata
                details.wineName = productName
                details.producer = product.brands ?? details.producer
                details.region = product.origins ?? details.region
                details.country = product.countries ?? details.country
                details.bottleSize = product.quantity ?? details.bottleSize
                return UICard(
                    id: "openfoodfacts:\(product.code ?? productName.lowercased())",
                    game: .wine,
                    name: productName,
                    number: details.vintage,
                    imageSmallURL: product.imageURL,
                    imageLargeURL: product.imageURL,
                    webURL: product.code.flatMap { URL(string: "https://world.openfoodfacts.org/product/\($0)") },
                    setName: product.brands,
                    wineMetadata: details
                )
            }
            return cards.isEmpty ? [manualCard(query: query, metadata: metadata)] : cards
        } catch {
            return [manualCard(query: query, metadata: metadata)]
        }
    }

    static func researchRows(for card: UICard) -> [PriceRow] {
        let details = card.wineMetadata ?? WineMetadata(wineName: card.name, vintage: card.number)
        return [
            PriceRow(source: "Wine-Searcher", label: "Retail market search", value: "Research", url: wineSearcherURL(details)),
            PriceRow(source: "Open Food Facts", label: "Community product record", value: "Open", url: card.webURL)
        ]
    }

    private static func manualCard(query: String, metadata: WineMetadata) -> UICard {
        let preferredName = metadata.wineName ?? query
        let name = preferredName.isEmpty ? metadata.searchTerms.joined(separator: " ") : preferredName
        let identity = metadata.searchTerms.joined(separator: "|").lowercased()
        return UICard(
            id: "wine|\(identity)",
            game: .wine,
            name: name,
            number: metadata.vintage,
            webURL: wineSearcherURL(metadata),
            setName: metadata.producer,
            wineMetadata: metadata
        )
    }

    private static func wineSearcherURL(_ metadata: WineMetadata) -> URL? {
        var components = URLComponents(string: "https://www.wine-searcher.com")
        components?.path = "/find/" + metadata.searchTerms.joined(separator: " ")
        return components?.url
    }
}

enum WineParser {
    private static let varietals = [
        "Cabernet Sauvignon", "Sauvignon Blanc", "Pinot Noir", "Pinot Grigio", "Chardonnay",
        "Merlot", "Malbec", "Syrah", "Shiraz", "Riesling", "Tempranillo", "Sangiovese", "Nebbiolo",
        "Zinfandel", "Grenache", "Champagne", "Prosecco"
    ]

    static func parse(_ text: String) -> WineMetadata {
        let lines = text.split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: " ")
        let vintage = firstMatch(joined, #"\b(?:19|20)\d{2}\b"#)
        let abv = firstMatch(joined, #"(?i)\b\d{1,2}(?:\.\d)?\s*%\s*(?:ALC\.?|ABV|VOL\.?)?"#)
        let bottleSize = firstMatch(joined, #"(?i)\b(?:375|500|750|1500)\s*ML\b|\b1\.5\s*L\b"#)
        let varietal = varietals.first { joined.localizedCaseInsensitiveContains($0) }
        let countries = ["France", "Italy", "Spain", "Portugal", "United States", "Argentina", "Chile", "Australia", "New Zealand", "Germany", "Austria", "South Africa"]
        let country = countries.first { joined.localizedCaseInsensitiveContains($0) }
        let candidates = lines.filter { line in
            line.range(of: #"\d"#, options: .regularExpression) == nil && line.count >= 4 && line.count <= 45
        }
        let producer = candidates.first
        let wineName = candidates.dropFirst().first ?? producer ?? "Unidentified wine"

        return WineMetadata(
            wineName: wineName,
            producer: producer == wineName ? nil : producer,
            vintage: vintage,
            country: country,
            varietal: varietal,
            bottleSize: bottleSize,
            alcoholByVolume: abv
        )
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
