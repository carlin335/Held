import Foundation

/// Primary Pokémon catalogue with a second independent price path.
/// - Search returns lightweight UI cards (and seeds badge cache).
/// - Detail prices prefer Pokémon TCG API, then fall back to TCGdex.
/// - Badges are fast (in-memory cached).
struct PokemonProvider {

    // MARK: - Public API -------------------------------------------------------

    /// First-page search. Returns UI cards; badges will be populated from cache quickly.
    static func search(
        text: String,
        number: String?,
        printedNumber: String? = nil,
        rarity: String?,
        language: PokemonScanLanguage = .english
    ) async throws -> [UICard] {
        var lastError: Error?

        for catalogue in language.catalogueOrder(for: text) {
            do {
                let cards: [UICard]
                switch catalogue {
                case .english:
                    let (_, results) = try await resilientSearch(
                        name: text,
                        number: number,
                        printedNumber: printedNumber,
                        rarity: rarity,
                        page: 1,
                        pageSize: 12,
                        overallDeadline: 45
                    )
                    if results.isEmpty {
                        // The primary English catalogue can lag a new release.
                        // TCGdex already supports the same exact name/localId
                        // filters used for other languages, so use it before
                        // treating a current English card as unknown.
                        cards = try await searchTCGDex(
                            name: text,
                            number: number,
                            printedNumber: printedNumber,
                            rarity: rarity,
                            language: .english,
                            pageSize: 12
                        )
                    } else {
                        cards = results
                    }
                case .japanese, .german, .spanish, .french, .italian, .portugueseBrazil:
                    cards = try await searchTCGDex(
                        name: text,
                        number: number,
                        printedNumber: printedNumber,
                        rarity: rarity,
                        language: catalogue,
                        pageSize: 12
                    )
                }

                if !cards.isEmpty { return cards }
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        return []
    }

    /// Detail price rows (Card Detail screen).
    static func loadPrices(for card: UICard) async -> [PriceRow] {
        if card.isTCGDexPokemonCard {
            return (try? await loadTCGDexValuation(for: card).rows) ?? []
        }

        // Search payloads already include the primary marketplace blocks. If
        // both snapshots are absent, avoid a duplicate slow request and go
        // straight to the independent fallback.
        if card.priceUSD != nil || card.priceEUR != nil,
           let officialRows = try? await loadPokemonTCGPrices(forID: card.id),
           !officialRows.isEmpty { return officialRows }

        if let fallback = try? await loadTCGDexValuation(for: card) {
            if !fallback.rows.isEmpty { return fallback.rows }
        }

        if let lateOfficialRows = try? await loadPokemonTCGPrices(forID: card.id),
           !lateOfficialRows.isEmpty { return lateOfficialRows }
        return []
    }

    private static func loadPokemonTCGPrices(forID id: String) async throws -> [PriceRow] {
        let d = try await fetchCardDetail(id: id, select: "id,name,tcgplayer,cardmarket")
        var rows: [PriceRow] = []

        if let tp = d.tcgplayer {
            let link = URL(safe: tp.url)
            let p = tp.prices
            func usd(_ v: Double?) -> String? { v.map { String(format: "$%.2f", $0) } }
            func add(_ label: String, _ v: Double?) { if let s = usd(v) { rows.append(.init(source: "TCGplayer", label: label, value: s, url: link)) } }
            add("Market", bestUSDMarket(from: p))
            add("Mid",    bestUSDMid(from: p))
            add("Low",    bestUSDLow(from: p))
        }

        if let cm = d.cardmarket {
            let link = URL(safe: cm.url)
            let p = cm.prices
            func eur(_ v: Double?) -> String? { v.map { String(format: "€%.2f", $0) } }
            func add(_ label: String, _ v: Double?) { if let s = eur(v) { rows.append(.init(source: "Cardmarket", label: label, value: s, url: link)) } }
            add("Trend",    p?.trendPrice)
            add("Avg Sold", p?.averageSellPrice)
            add("Low",      p?.lowPrice)
        }

        return rows
    }

    /// Lightweight price badge for grid tiles (USD/EUR); cached.
    static func fetchPriceBadge(for card: UICard) async throws -> PriceBadge? {
        if let cached = await badgeCache.get(card.id) { return cached }                 // cache hit

        var usd = card.numericUSD > 0 ? card.numericUSD : nil
        var eur = card.priceEUR.flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }

        if usd == nil && eur == nil, let fallback = try? await loadTCGDexValuation(for: card) {
            usd = fallback.bestUSD
            eur = fallback.bestEUR
        }

        if usd == nil && eur == nil,
           !card.isTCGDexPokemonCard,
           let detail = try? await fetchCardDetail(id: card.id, select: "id,name,tcgplayer,cardmarket") {
            usd = bestUSDMarket(from: detail.tcgplayer?.prices)
            eur = bestEUR(from: detail.cardmarket?.prices)
        }

        let badge = (usd == nil && eur == nil) ? nil : PriceBadge(
            usd: usd.map { String(format: "%.2f", $0) },
            eur: eur.map { String(format: "%.2f", $0) }
        )
        await badgeCache.set(card.id, badge)
        return badge
    }

    // MARK: - Internals: networking & search ----------------------------------

    private enum Net {
        static let base = URL(string: "https://api.pokemontcg.io/v2")!
        static let requestTimeout: TimeInterval  = 30
        static let resourceTimeout: TimeInterval = 90
        static let maxConnections = 8
    }

    private static let decoder: JSONDecoder = .init()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = true
        c.httpMaximumConnectionsPerHost = Net.maxConnections
        c.timeoutIntervalForRequest = Net.requestTimeout
        c.timeoutIntervalForResource = Net.resourceTimeout
        c.allowsConstrainedNetworkAccess = true
        c.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: c)
    }()

    /// Core GET with correct header + retries for timeouts/429/5xx.
    private static func getJSON(_ url: URL, attempt: Int = 1) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = AppSecrets.pokemonTCGApiKey {
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw URLError(.userAuthenticationRequired)
            case 429, 500..<600:
                guard attempt < 6 else { throw URLError(.badServerResponse) }
                try? await Task.sleep(nanoseconds: UInt64(200_000_000 * attempt)) // 0.2, 0.4, …
                return try await getJSON(url, attempt: attempt + 1)
            default:
                throw URLError(.badServerResponse)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut, attempt < 6 {
                try? await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
                return try await getJSON(url, attempt: attempt + 1)
            }
            throw error
        }
    }

    /// Patient search with a fast exact path, then fallbacks; seeds badge cache from the search payload.
    private static func resilientSearch(
        name: String,
        number: String?,
        printedNumber: String?,
        rarity: String?,
        page: Int,
        pageSize: Int,
        overallDeadline: TimeInterval
    ) async throws -> (hasMore: Bool, cards: [UICard]) {

        let deadline = Date().addingTimeInterval(overallDeadline)

        // --- Fast path: exact quoted name + number (when both present) ----------
        do {
            let (cleanName, inferred) = splitNameAndNumber(rawName: name, explicitNumber: number)
            let effectiveNumber = (number?.isEmpty == false) ? number! : (inferred ?? "")
            let hasName = !cleanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasName, !effectiveNumber.isEmpty {
                var items: [URLQueryItem] = [
                    .init(name: "q", value: #"name:"\#(cleanName)" AND number:"\#(effectiveNumber)""#),
                    .init(name: "page", value: "1"),
                    .init(name: "pageSize", value: String(pageSize)),
                    .init(name: "select", value: "id,name,number,rarity,set,images,tcgplayer,cardmarket")
                ]
                if let r = rarity?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
                    items[0].value = (items[0].value ?? "") + #" AND rarity:"\#(r)""#
                }
                var comps = URLComponents(url: Net.base.appendingPathComponent("cards"), resolvingAgainstBaseURL: false)!
                comps.queryItems = items

                let data = try await getJSON(comps.url!)
                struct Resp: Decodable { let data: [APICard]; let totalCount: Int? }
                let dec = try decoder.decode(Resp.self, from: data)
                let exactSet = cardsMatchingPrintedTotal(
                    dec.data,
                    printedNumber: printedNumber
                )
                if !exactSet.isEmpty {
                    let prioritized = prioritizeAPICards(
                        exactSet,
                        requestedName: name,
                        requestedNumber: number,
                        printedNumber: printedNumber
                    )
                    return (
                        (dec.totalCount ?? 0) > pageSize,
                        await mapAndSeed(cards: prioritized)
                    )
                }
                if !dec.data.isEmpty, printedTotal(from: printedNumber) != nil {
                    // Exact name/localId existed only in a differently sized
                    // set. Fuzzy retries cannot make that printing correct;
                    // move straight to the newer catalogue fallback.
                    return (false, [])
                }
            }
        } catch {
            // ignore and fall through to the general loop
        }

        // --- General loop with robust name handling -----------------------------
        func runQuery(simple: Bool, noOrder: Bool) async throws -> (Bool, [APICard]) {
            let q = buildQuery(name: name, number: number, rarity: rarity, simplePrefixOnly: simple)

            var items: [URLQueryItem] = [
                .init(name: "q", value: q),
                .init(name: "page", value: String(page)),
                .init(name: "pageSize", value: String(pageSize)),
                .init(name: "select", value: "id,name,number,rarity,set,images,tcgplayer,cardmarket"),
            ]
            if !noOrder { items.append(.init(name: "orderBy", value: "name")) }

            var comps = URLComponents(url: Net.base.appendingPathComponent("cards"), resolvingAgainstBaseURL: false)!
            comps.queryItems = items

            let data = try await getJSON(comps.url!)
            struct Resp: Decodable { let data: [APICard]; let totalCount: Int? }
            let decoded = try decoder.decode(Resp.self, from: data)
            let hasMore = decoded.totalCount.map { page * pageSize < $0 } ?? false
            return (hasMore, decoded.data)
        }

        // Try the three useful query shapes once. Repeating identical empty queries
        // made a miss feel like a 45-second hang and consumed unnecessary quota.
        let strategies: [(simple: Bool, noOrder: Bool)] = [
            (false, true),
            (false, false),
            (true, true)
        ]

        for strategy in strategies where Date() <= deadline {
            if let result = try? await runQuery(simple: strategy.simple, noOrder: strategy.noOrder),
               !result.1.isEmpty {
                let exactSet = cardsMatchingPrintedTotal(
                    result.1,
                    printedNumber: printedNumber
                )
                guard !exactSet.isEmpty else { continue }
                let prioritized = prioritizeAPICards(
                    exactSet,
                    requestedName: name,
                    requestedNumber: number,
                    printedNumber: printedNumber
                )
                return (result.0, await mapAndSeed(cards: prioritized))
            }
        }

        return (false, [])
    }

    // MARK: - Query building (spaces/'/./accent-safe) --------------------------

    /// Build the `q=` expression for PokemonTCG search.
    /// - Always includes a quoted exact clause so spaces/periods/apostrophes match.
    /// - Adds a tokenized **prefix AND** clause (name:Mr* AND name:Mime*) to catch partials.
    /// - If UI didn't supply a number, we try to peel one off the tail of the name (e.g., "Mr. Mime 179/161" -> 179).
    private static func buildQuery(name: String, number: String?, rarity: String?, simplePrefixOnly: Bool) -> String {
        // Normalize curly quotes/dashes and collapse whitespace
        func normalize(_ s: String) -> String {
            let map: [(String, String)] = [
                ("“", "\""), ("”", "\""), ("‘", "'"), ("’", "'"),
                ("–", "-"), ("—", "-"), ("·", " "), ("•", " ")
            ]
            var out = s
            for (a,b) in map { out = out.replacingOccurrences(of: a, with: b) }
            out = out.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let (rawName, inferredNumber) = splitNameAndNumber(rawName: name, explicitNumber: number)
        let cleanName = normalize(rawName)
        let effectiveNumber = (number?.isEmpty == false) ? number : inferredNumber

        var clauses: [String] = []

        if !cleanName.isEmpty {
            // Exact clause (quoted): handles spaces, periods, apostrophes safely
            let exact = #"name:"\#(cleanName)""#
            if simplePrefixOnly {
                // Prefix-only mode for very fuzzy typing: AND per-token prefixes
                let tokenPrefixes = tokenizedPrefixes(from: cleanName)
                if tokenPrefixes.isEmpty {
                    clauses.append(exact)
                } else {
                    clauses.append("(\(exact) OR (\(tokenPrefixes.joined(separator: " AND "))))")
                }
            } else {
                // Normal mode: exact + tokenized prefix as a fallback (keeps results broad but relevant)
                let tokenPrefixes = tokenizedPrefixes(from: cleanName)
                if tokenPrefixes.isEmpty {
                    clauses.append(exact)
                } else {
                    clauses.append("(\(exact) OR (\(tokenPrefixes.joined(separator: " AND "))))")
                }
            }
        }

        if let num = effectiveNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !num.isEmpty {
            clauses.append(#"number:"\#(num)""#)
        }
        if let r = rarity?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            clauses.append(#"rarity:"\#(r)""#)
        }

        return clauses.isEmpty ? "*" : clauses.joined(separator: " AND ")
    }

    /// Break "Mr. Mime" or "Farfetch'd" into safe prefix terms → ["name:Mr*", "name:Mime*"].
    /// We keep letters/digits and strip leading punctuation from each token.
    private static func tokenizedPrefixes(from name: String) -> [String] {
        // Split on whitespace and common punctuation, but keep apostrophes inside words (Farfetch'd)
        let parts = name
            .replacingOccurrences(of: "[\\.\\-:,;·•]+", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'\"()[]{}")) }
            .filter { !$0.isEmpty }

        // Build name:<token>* for each token
        return parts.map { "name:\($0)*" }
    }

    /// If UI didn't supply a number, try to peel one off the end of the name:
    ///  - "#179" or "179/161" or trailing "179a"
    private static func splitNameAndNumber(rawName: String, explicitNumber: String?) -> (String, String?) {
        // UI Number field wins if present
        if let n = explicitNumber, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (rawName, n.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Patterns: "#179", "179/161", "179a" at end
        let patterns = [
            #"(?:^|[\s])#\s*([0-9]+[A-Za-z]?)\s*$"#,
            #"(?:^|[\s])([0-9]+[A-Za-z]?)\s*/\s*[0-9A-Za-z\-]+\s*$"#,
            #"(?:^|[\s])([0-9]+[A-Za-z]?)\s*$"#
        ]

        for pat in patterns {
            if let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = re.firstMatch(in: name, options: [], range: NSRange(location: 0, length: name.utf16.count)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: name) {

                let extracted = String(name[r])
                // Remove the matched suffix from name for a cleaner name search
                if let rf = Range(match.range(at: 0), in: name) { name.removeSubrange(rf) }
                // Collapse extra spaces & trim punctuation (but NOT periods/apostrophes inside the string)
                name = name.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
                           .trimmingCharacters(in: .whitespacesAndNewlines)
                           .trimmingCharacters(in: CharacterSet(charactersIn: "-–—·•,;:")) // note: no '.' here
                return (name, extracted)
            }
        }

        return (name, nil)
    }

    // MARK: - TCGdex multilingual search -------------------------------------

    private static func searchTCGDex(
        name: String,
        number: String?,
        printedNumber: String?,
        rarity: String?,
        language: PokemonCatalogueLanguage,
        pageSize: Int
    ) async throws -> [UICard] {
        let (cleanName, inferredNumber) = splitNameAndNumber(
            rawName: name,
            explicitNumber: number
        )
        let requestedNumber = normalizedCollectorNumber(number ?? inferredNumber)
        let requestedPrintedTotal = printedTotal(from: printedNumber)
        guard !cleanName.isEmpty || requestedNumber != nil else { return [] }

        var components = URLComponents(
            url: tcgDexCardsURL(language: language),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = []
        if !cleanName.isEmpty {
            queryItems.append(URLQueryItem(name: "name", value: cleanName))
        }
        if let requestedNumber {
            // TCGdex combines filters, so asking for both visible clues avoids
            // downloading a broad name list and picking the wrong printing.
            queryItems.append(URLQueryItem(name: "localId", value: requestedNumber))
        }
        if let rarity = rarity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rarity.isEmpty,
           rarity.containsJapaneseScriptForHeld {
            queryItems.append(URLQueryItem(name: "rarity", value: rarity))
        }
        queryItems += [
            URLQueryItem(name: "sort:field", value: "releaseDate"),
            URLQueryItem(name: "sort:order", value: "DESC"),
            URLQueryItem(name: "pagination:page", value: "1"),
            URLQueryItem(name: "pagination:itemsPerPage", value: requestedNumber == nil ? String(pageSize) : "50")
        ]
        components.queryItems = queryItems

        let data = try await getPublicJSON(components.url!)
        let decoded = try decoder.decode([TCGDexCardBrief].self, from: data)
        let numberMatched: [TCGDexCardBrief]
        if let requestedNumber {
            numberMatched = decoded.filter {
                normalizedCollectorNumber($0.localId) == requestedNumber
            }
        } else {
            numberMatched = decoded
        }

        // The API's default name filter is intentionally fuzzy. Exact printed
        // names must lead variants such as "Pikachu ex" when OCR read "Pikachu".
        let wantedName = normalizedText(cleanName)
        let candidates = numberMatched.enumerated().sorted { lhs, rhs in
            let lhsExact = !wantedName.isEmpty && normalizedText(lhs.element.name) == wantedName
            let rhsExact = !wantedName.isEmpty && normalizedText(rhs.element.name) == wantedName
            if lhsExact != rhsExact { return lhsExact }
            return lhs.offset < rhs.offset
        }.map(\.element)

        let shortlist = Array(candidates.prefix(pageSize))
        return await withTaskGroup(of: (Int, UICard)?.self) { group in
            for (index, brief) in shortlist.enumerated() {
                group.addTask {
                    let localized = try? await fetchTCGDexCard(
                        id: brief.id,
                        language: language
                    )
                    let english: TCGDexCardDetail?
                    if language != .english {
                        english = try? await fetchTCGDexCard(id: brief.id, language: .english)
                    } else {
                        english = localized
                    }
                    if let requestedPrintedTotal,
                       let knownTotal = localized?.set?.cardCount?.official
                            ?? localized?.set?.cardCount?.total,
                       knownTotal != requestedPrintedTotal {
                        return nil
                    }
                    let card = mapTCGDexCard(
                        brief: brief,
                        detail: localized,
                        englishDetail: english,
                        language: language,
                        printedNumber: printedNumber
                    )
                    return (index, card)
                }
            }

            var indexed: [(Int, UICard)] = []
            for await result in group {
                if let result { indexed.append(result) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private static func mapTCGDexCard(
        brief: TCGDexCardBrief,
        detail: TCGDexCardDetail?,
        englishDetail: TCGDexCardDetail?,
        language: PokemonCatalogueLanguage,
        printedNumber: String?
    ) -> UICard {
        let name = detail?.name ?? brief.name
        let localID = detail?.localId ?? brief.localId
        let setName = detail?.set?.name
        let setCode = detail?.set?.id
        let image = detail?.image ?? brief.image
        let usd = bestTCGDexUSD(detail?.pricing?.tcgplayer)
        let eur = bestTCGDexEUR(detail?.pricing?.cardmarket)
        let marketQuery = marketSearchQuery(
            localizedName: name,
            localizedSet: setName,
            localID: printedNumber ?? localID,
            language: language,
            englishDetail: englishDetail
        )

        return UICard(
            id: "tcgdex:\(language.rawValue):\(brief.id)",
            game: .pokemon,
            name: name,
            number: printedNumber ?? localID,
            setCode: setCode,
            imageSmallURL: tcgDexImageURL(base: image, quality: "low"),
            imageLargeURL: tcgDexImageURL(base: image, quality: "high"),
            apiURL: tcgDexCardsURL(language: language).appendingPathComponent(brief.id),
            webURL: priceChartingResearchURL(query: marketQuery),
            priceUSD: usd.map { String(format: "%.2f", $0) },
            priceEUR: eur.map { String(format: "%.2f", $0) },
            languageCode: language.rawValue,
            marketSearchQuery: marketQuery,
            rarity: detail?.rarity,
            setName: setName
        )
    }

    private static func marketSearchQuery(
        localizedName: String,
        localizedSet: String?,
        localID: String?,
        language: PokemonCatalogueLanguage,
        englishDetail: TCGDexCardDetail?
    ) -> String {
        let languageTerm: String
        switch language {
        case .english: languageTerm = "Pokemon"
        case .japanese: languageTerm = "Pokemon Japanese"
        case .german: languageTerm = "Pokemon German"
        case .spanish: languageTerm = "Pokemon Spanish"
        case .french: languageTerm = "Pokemon French"
        case .italian: languageTerm = "Pokemon Italian"
        case .portugueseBrazil: languageTerm = "Pokemon Portuguese"
        }
        let valueName = englishDetail?.name ?? localizedName
        let valueSet = englishDetail?.set?.name ?? localizedSet
        return [languageTerm, valueName, valueSet, localID.map { "#\($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tcgDexCardsURL(language: PokemonCatalogueLanguage) -> URL {
        URL(string: "https://api.tcgdex.net/v2/\(language.rawValue)/cards")!
    }

    private static func tcgDexImageURL(base: String?, quality: String) -> URL? {
        guard let base, let url = URL(string: base) else { return nil }
        return url.appendingPathComponent("\(quality).webp")
    }

    private static func priceChartingResearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://www.pricecharting.com/search-products")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "prices"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    // MARK: - Mapping & detail fetch ------------------------------------------

    /// Map API cards to UI and seed badge cache (so tiles don't need another round-trip).
    private static func mapAndSeed(cards: [APICard]) async -> [UICard] {
        for c in cards {
            let usd = bestUSDMarket(from: c.tcgplayer?.prices)
            let eur = bestEUR(from: c.cardmarket?.prices)
            if usd != nil || eur != nil {
                let badge = PriceBadge(
                    usd: usd.map { String(format: "%.2f", $0) },
                    eur: eur.map { String(format: "%.2f", $0) }
                )
                await badgeCache.set(c.id, badge)
            }
        }
        return cards.map { $0.asUICard }
    }

    private static func fetchCardDetail(id: String, select: String) async throws -> APIDetail {
        var comps = URLComponents(url: Net.base.appendingPathComponent("cards/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [ .init(name: "select", value: select) ]
        let data = try await getJSON(comps.url!)
        struct Wrap: Decodable { let data: APIDetail }
        return try decoder.decode(Wrap.self, from: data).data
    }

    // MARK: - Internal API models ---------------------------------------------

    private struct APICard: Decodable {
        let id: String
        let name: String
        let number: String?
        let rarity: String?
        let set: APISet?
        let images: Images?
        let tcgplayer: TCGPlayerBlock?       // included to seed badge cache
        let cardmarket: CardmarketBlock?

        struct Images: Decodable { let small: String?; let large: String? }

        var asUICard: UICard {
            // Prefer human-friendly commerce page; fallback to pokemontcg.io card page
            let humanURL =
                URL(safe: tcgplayer?.url) ??
                URL(safe: cardmarket?.url) ??
                URL(string: "https://pokemontcg.io/card/\(id)")
            let usd = PokemonProvider.bestUSDMarket(from: tcgplayer?.prices)
            let eur = PokemonProvider.bestEUR(from: cardmarket?.prices)

            return UICard(
                id: id,
                game: .pokemon,
                name: name,
                number: number,
                setCode: set?.id,
                imageSmallURL: URL(safe: images?.small),
                imageLargeURL: URL(safe: images?.large),
                apiURL: URL(string: "https://api.pokemontcg.io/v2/cards/\(id)"),
                webURL: humanURL, // ✅ now points to a real product/details page
                priceUSD: usd.map { String(format: "%.2f", $0) },
                priceEUR: eur.map { String(format: "%.2f", $0) },
                languageCode: PokemonCatalogueLanguage.english.rawValue,
                sets: nil,
                rarity: rarity,
                setName: set?.name
            )
        }
    }

    private struct APISet: Decodable {
        let id: String?
        let name: String?
        let printedTotal: Int?
    }

    private struct APIDetail: Decodable {
        let id: String
        let name: String
        let tcgplayer: TCGPlayerBlock?
        let cardmarket: CardmarketBlock?
    }

    private struct TCGPlayerBlock: Decodable {
        let url: String?
        let prices: TCGPrices?
    }
    private struct TCGPrices: Decodable {
        let normal: TCGPrice?
        let holofoil: TCGPrice?
        let reverseHolofoil: TCGPrice?
        let firstEdition: TCGPrice?
        let firstEditionHolofoil: TCGPrice?
        private enum CodingKeys: String, CodingKey {
            case normal, holofoil, reverseHolofoil
            case firstEdition = "1stEdition"
            case firstEditionHolofoil = "1stEditionHolofoil"
        }
    }
    private struct TCGPrice: Decodable {
        let low: Double?
        let mid: Double?
        let high: Double?
        let market: Double?
    }

    private struct CardmarketBlock: Decodable {
        let url: String?
        let prices: CardmarketPrices?
    }
    private struct CardmarketPrices: Decodable {
        let averageSellPrice: Double?
        let lowPrice: Double?
        let trendPrice: Double?
    }

    // MARK: - Price helpers ----------------------------------------------------

    private static func bestUSDMarket(from p: TCGPrices?) -> Double? {
        guard let p = p else { return nil }
        return p.holofoil?.market
            ?? p.reverseHolofoil?.market
            ?? p.normal?.market
            ?? p.firstEditionHolofoil?.market
            ?? p.firstEdition?.market
    }
    private static func bestUSDMid(from p: TCGPrices?) -> Double? {
        guard let p = p else { return nil }
        return p.holofoil?.mid
            ?? p.reverseHolofoil?.mid
            ?? p.normal?.mid
            ?? p.firstEditionHolofoil?.mid
            ?? p.firstEdition?.mid
    }
    private static func bestUSDLow(from p: TCGPrices?) -> Double? {
        guard let p = p else { return nil }
        return p.holofoil?.low
            ?? p.reverseHolofoil?.low
            ?? p.normal?.low
            ?? p.firstEditionHolofoil?.low
            ?? p.firstEdition?.low
    }
    private static func bestEUR(from p: CardmarketPrices?) -> Double? {
        guard let p = p else { return nil }
        return p.trendPrice ?? p.averageSellPrice ?? p.lowPrice
    }

    private static func bestTCGDexUSD(_ prices: TCGDexTCGplayer?) -> Double? {
        guard let prices else { return nil }
        let quotes = [
            prices.holofoil ?? prices.holo,
            prices.reverseHolofoil ?? prices.reverse,
            prices.normal
        ]
        for quote in quotes {
            if let value = positive(quote?.marketPrice ?? quote?.midPrice ?? quote?.lowPrice) {
                return value
            }
        }
        return nil
    }

    private static func bestTCGDexEUR(_ prices: TCGDexCardmarket?) -> Double? {
        guard let prices else { return nil }
        return positive(
            prices.trendHolo ?? prices.avgHolo
                ?? prices.trend ?? prices.avg
                ?? prices.lowHolo ?? prices.low
        )
    }

    // MARK: - TCGdex pricing fallback ----------------------------------------

    /// The Pokémon TCG API can publish a newly released card before its
    /// marketplace blocks are populated. TCGdex is queried only when that
    /// primary response has no usable value.
    private static func loadTCGDexValuation(for card: UICard) async throws -> TCGDexValuation {
        let detail = try await findTCGDexCard(for: card)
        let tcgplayerURL = providerSearchURL(for: card, provider: .tcgplayer)
        let cardmarketURL = providerSearchURL(for: card, provider: .cardmarket)
        var rows: [PriceRow] = []
        var bestUSD: Double?
        var bestEUR: Double?

        if let prices = detail.pricing?.tcgplayer {
            let variants: [(String, TCGDexQuote?)] = [
                ("Holo market", prices.holofoil ?? prices.holo),
                ("Reverse holo market", prices.reverseHolofoil ?? prices.reverse),
                ("Normal market", prices.normal)
            ]
            for (label, quote) in variants {
                guard let value = positive(quote?.marketPrice ?? quote?.midPrice ?? quote?.lowPrice) else { continue }
                if bestUSD == nil { bestUSD = value }
                rows.append(
                    PriceRow(
                        source: "TCGdex · TCGplayer",
                        label: label,
                        value: String(format: "$%.2f", value),
                        url: tcgplayerURL
                    )
                )
            }
        }

        if let prices = detail.pricing?.cardmarket {
            let variants: [(String, Double?)] = [
                ("Holo trend", prices.trendHolo ?? prices.avgHolo),
                ("Market trend", prices.trend ?? prices.avg),
                ("Market low", prices.lowHolo ?? prices.low)
            ]
            for (label, candidate) in variants {
                guard let value = positive(candidate) else { continue }
                if bestEUR == nil { bestEUR = value }
                rows.append(
                    PriceRow(
                        source: "TCGdex · Cardmarket",
                        label: label,
                        value: String(format: "€%.2f", value),
                        url: cardmarketURL
                    )
                )
            }
        }

        return TCGDexValuation(rows: rows, bestUSD: bestUSD, bestEUR: bestEUR)
    }

    private static func findTCGDexCard(for card: UICard) async throws -> TCGDexCardDetail {
        let language = PokemonCatalogueLanguage(rawValue: card.languageCode ?? "") ?? .english
        let directID = rawTCGDexID(from: card.id)
        if let direct = try? await fetchTCGDexCard(id: directID, language: language),
           isLikelyMatch(direct, card: card) {
            return direct
        }

        var comps = URLComponents(
            url: tcgDexCardsURL(language: language),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "name", value: card.name),
            URLQueryItem(name: "sort:field", value: "releaseDate"),
            URLQueryItem(name: "sort:order", value: "DESC"),
            URLQueryItem(name: "pagination:page", value: "1"),
            URLQueryItem(name: "pagination:itemsPerPage", value: "50")
        ]
        let data = try await getPublicJSON(comps.url!)
        let candidates = try decoder.decode([TCGDexCardBrief].self, from: data)
            .filter { normalizedText($0.name) == normalizedText(card.name) }

        let wantedNumber = normalizedCollectorNumber(card.number)
        let numbered = candidates.filter {
            wantedNumber == nil || normalizedCollectorNumber($0.localId) == wantedNumber
        }
        let shortlist = numbered.isEmpty ? candidates : numbered

        var firstUsable: TCGDexCardDetail?
        for candidate in shortlist.prefix(10) {
            guard let detail = try? await fetchTCGDexCard(id: candidate.id, language: language) else { continue }
            if firstUsable == nil { firstUsable = detail }
            if setMatches(detail.set?.name, expected: card.setName) { return detail }
        }

        if let firstUsable { return firstUsable }
        throw URLError(.cannotFindHost)
    }

    private static func fetchTCGDexCard(
        id: String,
        language: PokemonCatalogueLanguage
    ) async throws -> TCGDexCardDetail {
        let url = tcgDexCardsURL(language: language).appendingPathComponent(id)
        let data = try await getPublicJSON(url)
        return try decoder.decode(TCGDexCardDetail.self, from: data)
    }

    private static func rawTCGDexID(from value: String) -> String {
        guard value.hasPrefix("tcgdex:") else { return value }
        return value.split(separator: ":", maxSplits: 2).last.map(String.init) ?? value
    }

    private static func getPublicJSON(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func isLikelyMatch(_ detail: TCGDexCardDetail, card: UICard) -> Bool {
        guard normalizedText(detail.name) == normalizedText(card.name) else { return false }
        guard let expected = normalizedCollectorNumber(card.number) else { return true }
        return normalizedCollectorNumber(detail.localId) == expected
    }

    private static func setMatches(_ candidate: String?, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return true }
        guard let candidate else { return false }
        let lhs = normalizedText(candidate)
        let rhs = normalizedText(expected)
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func normalizedText(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Catalogue spellings vary around suffix punctuation (Charizard EX vs
        // Charizard-EX, V STAR vs VSTAR, and LV X vs LV.X). Compare the actual
        // letters and numbers so those formatting differences do not outrank
        // a collector-number match.
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func prioritizeAPICards(
        _ cards: [APICard],
        requestedName: String,
        requestedNumber: String?,
        printedNumber: String?
    ) -> [APICard] {
        let (cleanName, inferredNumber) = splitNameAndNumber(
            rawName: requestedName,
            explicitNumber: requestedNumber
        )
        let wantedName = normalizedText(cleanName)
        let wantedNumber = normalizedCollectorNumber(requestedNumber ?? inferredNumber)
        let wantedPrintedTotal = printedTotal(from: printedNumber)

        return cards.enumerated().sorted { lhs, rhs in
            func score(_ card: APICard) -> Int {
                var value = 0
                if !wantedName.isEmpty, normalizedText(card.name) == wantedName { value += 2 }
                if let wantedNumber,
                   normalizedCollectorNumber(card.number) == wantedNumber { value += 4 }
                if let wantedPrintedTotal,
                   card.set?.printedTotal == wantedPrintedTotal { value += 8 }
                return value
            }
            let lhsScore = score(lhs.element)
            let rhsScore = score(rhs.element)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func cardsMatchingPrintedTotal(
        _ cards: [APICard],
        printedNumber: String?
    ) -> [APICard] {
        guard let wantedTotal = printedTotal(from: printedNumber) else { return cards }
        let cardsWithKnownTotals = cards.filter { $0.set?.printedTotal != nil }
        guard !cardsWithKnownTotals.isEmpty else { return cards }
        return cardsWithKnownTotals.filter { $0.set?.printedTotal == wantedTotal }
    }

    private static func printedTotal(from value: String?) -> Int? {
        guard let value,
              let denominator = value.split(separator: "/", maxSplits: 1).dropFirst().first else {
            return nil
        }
        let digits = denominator.filter(\.isNumber)
        return Int(digits)
    }

    private static func normalizedCollectorNumber(_ value: String?) -> String? {
        guard let value else { return nil }
        let head = String(value.split(separator: "/", maxSplits: 1).first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return nil }
        let digits = head.prefix { $0.isNumber }
        guard !digits.isEmpty else { return head.uppercased() }
        let stripped = digits.drop { $0 == "0" }
        let normalizedDigits = stripped.isEmpty ? "0" : String(stripped)
        return normalizedDigits + head.dropFirst(digits.count).uppercased()
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private enum PriceSearchProvider { case tcgplayer, cardmarket }

    private static func providerSearchURL(for card: UICard, provider: PriceSearchProvider) -> URL? {
        let query = card.marketSearchQuery ?? [
            card.name,
            card.setName,
            card.number.map { "#\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        switch provider {
        case .tcgplayer:
            var comps = URLComponents(string: "https://www.tcgplayer.com/search/pokemon/product")
            comps?.queryItems = [
                URLQueryItem(name: "productLineName", value: "pokemon"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "view", value: "grid")
            ]
            return comps?.url
        case .cardmarket:
            var comps = URLComponents(string: "https://www.cardmarket.com/en/Pokemon/Products/Search")
            comps?.queryItems = [URLQueryItem(name: "searchString", value: query)]
            return comps?.url
        }
    }

    private struct TCGDexValuation: Sendable {
        let rows: [PriceRow]
        let bestUSD: Double?
        let bestEUR: Double?
    }

    private struct TCGDexCardBrief: Decodable, Sendable {
        let id: String
        let localId: String?
        let name: String
        let image: String?

        private enum CodingKeys: String, CodingKey { case id, localId, name, image }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            localId = container.decodeLossyStringIfPresent(forKey: .localId)
            name = try container.decode(String.self, forKey: .name)
            image = try container.decodeIfPresent(String.self, forKey: .image)
        }
    }

    private struct TCGDexCardDetail: Decodable, Sendable {
        let id: String
        let localId: String?
        let name: String
        let image: String?
        let rarity: String?
        let set: TCGDexSet?
        let pricing: TCGDexPricing?

        private enum CodingKeys: String, CodingKey {
            case id, localId, name, image, rarity, set, pricing
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            localId = container.decodeLossyStringIfPresent(forKey: .localId)
            name = try container.decode(String.self, forKey: .name)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
            set = try container.decodeIfPresent(TCGDexSet.self, forKey: .set)
            pricing = try container.decodeIfPresent(TCGDexPricing.self, forKey: .pricing)
        }
    }

    private struct TCGDexSet: Decodable, Sendable {
        let id: String?
        let name: String?
        let cardCount: TCGDexCardCount?
    }

    private struct TCGDexCardCount: Decodable, Sendable {
        let total: Int?
        let official: Int?
    }

    private struct TCGDexPricing: Decodable, Sendable {
        let cardmarket: TCGDexCardmarket?
        let tcgplayer: TCGDexTCGplayer?
    }

    private struct TCGDexTCGplayer: Decodable, Sendable {
        let normal: TCGDexQuote?
        let holo: TCGDexQuote?
        let reverse: TCGDexQuote?
        let holofoil: TCGDexQuote?
        let reverseHolofoil: TCGDexQuote?

        private enum CodingKeys: String, CodingKey {
            case normal, holo, reverse, holofoil
            case reverseHolofoil = "reverse-holofoil"
        }
    }

    private struct TCGDexQuote: Decodable, Sendable {
        let lowPrice: Double?
        let midPrice: Double?
        let highPrice: Double?
        let marketPrice: Double?
        let directLowPrice: Double?
    }

    private struct TCGDexCardmarket: Decodable, Sendable {
        let avg: Double?
        let low: Double?
        let trend: Double?
        let avgHolo: Double?
        let lowHolo: Double?
        let trendHolo: Double?

        private enum CodingKeys: String, CodingKey {
            case avg, low, trend
            case avgHolo = "avg-holo"
            case lowHolo = "low-holo"
            case trendHolo = "trend-holo"
        }
    }

    // MARK: - Badge cache ------------------------------------------------------

    private actor BadgeCache {
        private var map: [String: PriceBadge?] = [:]  // store nil to remember “no badge”
        func get(_ id: String) -> PriceBadge?? { map[id] }
        func set(_ id: String, _ value: PriceBadge?) { map[id] = value }
    }
    private static let badgeCache = BadgeCache()
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        return nil
    }
}

private extension UICard {
    var isTCGDexPokemonCard: Bool {
        game == .pokemon && id.hasPrefix("tcgdex:")
    }
}
