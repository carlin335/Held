import Foundation

struct ScryfallProvider {
    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Held/2.4.4 (iOS; com.carlinjon.held)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func search(text: String, number: String?, rarity: String?) async throws -> [UICard] {
        var parts: [String] = []
        if !text.isEmpty { parts.append(text) }
        if let n = number, !n.isEmpty { parts.append("number:\(n)") }
        if let r = rarity, !r.isEmpty { parts.append("r:\(r)") }
        let query = parts.joined(separator: " ")

        var comps = URLComponents(string: "https://api.scryfall.com/cards/search")!
        comps.queryItems = [.init(name: "q", value: query)]

        let data = try await fetch(comps.url!)

        struct Page: Decodable { let data: [Card] }
        struct Card: Decodable {
            let id: String
            let name: String
            let collector_number: String?
            let image_uris: [String:String]?
            let scryfall_uri: String?
            let set: String?
            let set_name: String?
            let rarity: String?
            let prices: Prices?

            struct Prices: Decodable {
                let usd: String?
                let eur: String?
            }
        }

        let page = try JSONDecoder().decode(Page.self, from: data)
        return page.data.map {
            let small = URL(string: $0.image_uris?["normal"] ?? $0.image_uris?["small"] ?? "")
            let large = URL(string: $0.image_uris?["large"] ?? $0.image_uris?["png"] ?? "")
            return UICard(
                id: $0.id, game: .magic, name: $0.name, number: $0.collector_number,
                setCode: $0.set, imageSmallURL: small, imageLargeURL: large,
                apiURL: nil, webURL: URL(safe: $0.scryfall_uri),
                priceUSD: $0.prices?.usd, priceEUR: $0.prices?.eur, sets: nil,
                rarity: $0.rarity?.capitalized, setName: $0.set_name
            )
        }
    }

    static func loadPrices(forID id: String) async throws -> [PriceRow] {
        let url = URL(string: "https://api.scryfall.com/cards/\(id)")!
        let data = try await fetch(url)

        struct Card: Decodable {
            let prices: Prices
            let scryfall_uri: String
            struct Prices: Decodable { let usd: String?; let usd_foil: String?; let eur: String?; let eur_foil: String? }
        }

        let card = try JSONDecoder().decode(Card.self, from: data)
        var rows: [PriceRow] = []
        let page = URL(string: card.scryfall_uri)

        func add(_ label: String, _ v: String?, currency: String) {
            guard let v, !v.isEmpty else { return }
            rows.append(.init(source: "Scryfall", label: label, value: currency + v, url: page))
        }
        add("Market", card.prices.usd, currency: "$")
        add("Foil market", card.prices.usd_foil, currency: "$")
        add("European market", card.prices.eur, currency: "€")
        add("European foil", card.prices.eur_foil, currency: "€")
        return rows
    }

    static func fetchPriceBadge(id: String) async throws -> PriceBadge? {
        let url = URL(string: "https://api.scryfall.com/cards/\(id)")!
        let data = try await fetch(url)
        struct Card: Decodable { struct Prices: Decodable { let usd: String?; let eur: String? }; let prices: Prices }
        let card = try JSONDecoder().decode(Card.self, from: data)
        let usd = (card.prices.usd?.isEmpty ?? true) ? nil : card.prices.usd
        let eur = (card.prices.eur?.isEmpty ?? true) ? nil : card.prices.eur
        if usd == nil && eur == nil { return nil }
        return PriceBadge(usd: usd, eur: eur)
    }
}
