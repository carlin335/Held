import SwiftUI

struct CardDetailView: View {
    let card: UICard

    @EnvironmentObject private var collection: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var priceRows: [PriceRow] = []
    @State private var isLoadingPrices = false
    @State private var priceError: String?
    @State private var sourceURLOverride: URL?
    @State private var isCollectionEditorPresented = false

    private var isCollected: Bool { collection.contains(card) }
    private var sourceURL: URL? { sourceURLOverride ?? card.webURL ?? card.apiURL }

    var body: some View {
        ZStack {
            CardSenseBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    artwork
                    identity
                    valuePanel
                    exactMatchPanel
                    collectionAction
                    disclaimer
                }
                .padding(.top, 8)
                .padding(.bottom, 30)
                .cardSensePagePadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CardSenseTheme.mint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let sourceURL {
                    Link(destination: sourceURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open item source")
                }
            }
        }
        .task { await loadPrices() }
        .sheet(isPresented: $isCollectionEditorPresented) {
            NavigationStack {
                CollectionEditorView(
                    card: cardWithBestPrice,
                    existingItem: collection.item(for: card)
                )
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(CardSenseTheme.canvas)
        }
    }

    private var artwork: some View {
        CardArtworkView(card: card, cornerRadius: 24)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.77, contentMode: .fit)
            .padding(.horizontal, 26)
            .shadow(color: card.game.accent.opacity(0.22), radius: 30, y: 18)
            .overlay(alignment: .bottomTrailing) {
                Label(card.game.shortLabel, systemImage: card.game.symbol)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.trailing, 34)
                    .padding(.bottom, 12)
            }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.name)
                .font(.system(size: 29, weight: .bold, design: .rounded))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    detailChip(card.game.shortLabel)
                    ForEach(identityDetails, id: \.self) { detailChip($0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func detailChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.08), lineWidth: 0.8) }
    }

    private var valuePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                [.sports, .coins, .wine, .other].contains(card.game) ? "Value research" : "Market snapshot",
                eyebrow: "Live + verification sources"
            )
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    if let savedValue = collection.item(for: card)?.formattedMarketValue {
                        HStack {
                            Label("Your saved value", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(savedValue).font(.headline.monospacedDigit())
                        }
                        .foregroundStyle(CardSenseTheme.mint)
                        if isLoadingPrices || !priceRows.isEmpty { Divider().overlay(.white.opacity(0.07)) }
                    }

                    if isLoadingPrices {
                        HStack(spacing: 12) {
                            ProgressView().tint(CardSenseTheme.mint)
                            Text("Checking current sources…")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let priceError {
                        Label(priceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(CardSenseTheme.coral)
                    } else if priceRows.isEmpty {
                        Text("A live quote is not available yet. Use the verified market links below or enter a confirmed value when saving.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.52))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(priceRows.enumerated()), id: \.element.id) { index, row in
                                priceRow(row)
                                if index < priceRows.count - 1 {
                                    Divider().overlay(.white.opacity(0.07)).padding(.leading, 42)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func priceRow(_ row: PriceRow) -> some View {
        let hasQuotedValue = row.value?.isEmpty == false
        return HStack(spacing: 12) {
            Image(systemName: hasQuotedValue ? "dollarsign.arrow.circlepath" : "magnifyingglass.circle.fill")
                .foregroundStyle(CardSenseTheme.mint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.subheadline.weight(.semibold))
                Text(row.source).font(.caption).foregroundStyle(.white.opacity(0.43))
            }
            Spacer()
            Text(row.value ?? "Open")
                .font(.headline.weight(.bold))
                .monospacedDigit()
            if let url = row.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CardSenseTheme.mint)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var exactMatchPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading("Verify the exact item", eyebrow: "Before you save")
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(CardSenseTheme.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verificationTitle)
                        .font(.subheadline.weight(.bold))
                    Text(verificationDetail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(17)
            .background(CardSenseTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CardSenseTheme.mint.opacity(0.14), lineWidth: 0.8)
            }
        }
    }

    private var collectionAction: some View {
        Button {
            isCollectionEditorPresented = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Label(isCollected ? "Edit collection entry" : "Add to collection", systemImage: isCollected ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(isCollected ? .white : CardSenseTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(isCollected ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(CardSenseTheme.accentGradient), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var disclaimer: some View {
        Text("Market values are informational estimates, not guarantees or certified appraisals. Always review actual comparable sales, condition and provenance.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.38))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
    }

    private var cardWithBestPrice: UICard {
        guard card.numericUSD == 0,
              let price = priceRows.first(where: {
                  $0.value?.contains("$") == true || $0.label.localizedCaseInsensitiveContains("USD")
              })?.value else {
            return card
        }
        var copy = card
        copy.priceUSD = price
        return copy
    }

    private var identityDetails: [String] {
        if let details = card.sportsMetadata {
            return [
                details.sport.rawValue, details.year, details.brand, details.setName,
                details.team, details.cardNumber.map { "#\($0)" }, details.parallel,
                details.serialNumber.map { "Serial \($0)" }, details.isRookie ? "Rookie" : nil,
                details.isAutographed ? "Autograph" : nil
            ].compactMap { $0 }.filter { !$0.isEmpty }
        }
        if let details = card.coinMetadata {
            return [details.year, details.country, details.denomination, details.mintMark.map { "Mint \($0)" }, details.composition]
                .compactMap { $0 }.filter { !$0.isEmpty }
        }
        if let details = card.wineMetadata {
            return [details.vintage, details.producer, details.region, details.country, details.varietal, details.bottleSize, details.alcoholByVolume]
                .compactMap { $0 }.filter { !$0.isEmpty }
        }
        let language = PokemonCatalogueLanguage(rawValue: card.languageCode ?? "")?.displayName
        return [language, card.setName ?? card.setCode, card.number.map { "#\($0)" }, card.rarity]
            .compactMap { $0 }.filter { !$0.isEmpty }
    }

    private var verificationTitle: String {
        switch card.game {
        case .sports: "Confirm the year, set, parallel and serial stamp"
        case .coins: "Confirm both sides, year, mint mark and composition"
        case .wine: "Confirm the producer, vintage, region and bottle size"
        case .other: "Confirm the maker, model, year and exact variation"
        case .pokemon, .magic, .yugioh: "Match the artwork, set and collector number"
        }
    }

    private var verificationDetail: String {
        switch card.game {
        case .sports: "Rookie marks, parallels, autographs, serial numbering, grade and condition can change value dramatically."
        case .coins: "Small mint marks, varieties, cleaning, strike quality and grade can create major value differences."
        case .wine: "Storage history, fill level, label condition, provenance and bottle format materially affect value."
        case .other: "Edition, model, completeness, authenticity and condition can produce very different sold prices."
        case .pokemon, .magic, .yugioh: "Parallels, foils, reprints, languages, grades and condition can change value substantially."
        }
    }

    private func loadPrices() async {
        await MainActor.run {
            isLoadingPrices = true
            priceError = nil
        }

        do {
            let rows = try await MultigameService.loadPrices(for: card)
            await MainActor.run {
                priceRows = rows
                sourceURLOverride = rows.compactMap(\.url).first
                isLoadingPrices = false
            }
        } catch is CancellationError {
            await MainActor.run { isLoadingPrices = false }
        } catch {
            await MainActor.run {
                priceError = "Current prices could not be loaded."
                isLoadingPrices = false
            }
        }
    }
}

private struct CollectionEditorView: View {
    let card: UICard
    let existingItem: CollectionItem?

    @EnvironmentObject private var collection: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Int
    @State private var condition: CardCondition
    @State private var grade: String
    @State private var gradingCompany: String
    @State private var certificationNumber: String
    @State private var purchasePrice: String
    @State private var customMarketValue: String
    @State private var notes: String

    init(card: UICard, existingItem: CollectionItem?) {
        self.card = card
        self.existingItem = existingItem
        _quantity = State(initialValue: existingItem?.quantity ?? 1)
        _condition = State(initialValue: existingItem?.condition ?? .raw)
        _grade = State(initialValue: existingItem?.grade ?? "")
        _gradingCompany = State(initialValue: existingItem?.gradingCompany ?? "")
        _certificationNumber = State(initialValue: existingItem?.certificationNumber ?? "")
        _purchasePrice = State(initialValue: existingItem?.purchasePrice.map { String(format: "%.2f", $0) } ?? "")
        _customMarketValue = State(initialValue: existingItem?.customMarketValue.map { String(format: "%.2f", $0) } ?? "")
        _notes = State(initialValue: existingItem?.notes ?? "")
    }

    var body: some View {
        ZStack {
            CardSenseBackground()

            Form {
                Section {
                    HStack(spacing: 14) {
                        CardArtworkView(card: card, cornerRadius: 12)
                            .frame(width: 72, height: 101)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.name).font(.headline)
                            Text([card.setName ?? card.setCode, card.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let value = card.formattedUSD {
                                Text("Known value \(value)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CardSenseTheme.mint)
                            }
                        }
                    }
                }

                Section("Collection details") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    Picker("Condition", selection: $condition) {
                        ForEach(CardCondition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if condition == .graded {
                        TextField("Grading company, for example PSA", text: $gradingCompany)
                            .textInputAutocapitalization(.characters)
                        TextField("Grade, for example PSA 9", text: $grade)
                            .textInputAutocapitalization(.characters)
                        TextField("Certification number", text: $certificationNumber)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                    }
                    HStack {
                        Text("Purchase price")
                        Spacer()
                        TextField("0.00", text: $purchasePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("Current value")
                        Spacer()
                        TextField("Optional", text: $customMarketValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if existingItem != nil {
                    Section {
                        Button("Remove from collection", role: .destructive) {
                            collection.remove(card)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(existingItem == nil ? "Add item" : "Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .foregroundStyle(CardSenseTheme.mint)
            }
        }
    }

    private func save() {
        var item = existingItem ?? CollectionItem(card: card)
        item.card = card
        item.quantity = quantity
        item.condition = condition
        item.grade = condition == .graded && !grade.isEmpty ? grade : nil
        item.gradingCompany = condition == .graded && !gradingCompany.isEmpty ? gradingCompany : nil
        item.certificationNumber = condition == .graded && !certificationNumber.isEmpty ? certificationNumber : nil
        item.purchasePrice = Double(purchasePrice.replacingOccurrences(of: ",", with: ""))
        item.customMarketValue = Double(customMarketValue.replacingOccurrences(of: ",", with: ""))
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        collection.upsert(item)
        dismiss()
    }
}
