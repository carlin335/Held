import SwiftUI

struct SettingsView: View {
    @State private var cardSightKeyDraft = ""
    @State private var sportsKeyStatus = ""

    var body: some View {
        ZStack {
            CardSenseBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    dataSources
                    privacy
                    about
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
                .cardSensePagePadding()
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if cardSightKeyDraft.isEmpty {
                cardSightKeyDraft = AppSecrets.cardSightAPIKey ?? ""
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(.caption.weight(.black))
                .tracking(2)
                .foregroundStyle(CardSenseTheme.mint)
            Text("Trust, sources & privacy")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
    }

    private var dataSources: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading("Connected catalogues", eyebrow: "Market data")
            GlassPanel(padding: 0) {
                VStack(spacing: 0) {
                    sourceRow(game: .pokemon, name: "Pokémon TCG API + TCGdex", detail: AppSecrets.hasPokemonTCGKey ? "Multilingual catalogues and pricing" : "Public multilingual catalogues")
                    divider
                    sourceRow(game: .magic, name: "Scryfall", detail: "Card catalogue & prices")
                    divider
                    sourceRow(game: .yugioh, name: "YGOPRODeck", detail: "Card catalogue & prices")
                    divider
                    sourceRow(
                        game: .sports,
                        name: "CardSight + SportsCardsPro",
                        detail: AppSecrets.hasCardSightAPIKey
                            ? "Real card candidates enabled"
                            : "Connect free key for player results"
                    )
                    sportsCatalogueAccess
                    divider
                    sourceRow(game: .coins, name: "Numista", detail: AppSecrets.hasNumistaAPIKey ? "Coin catalogue enabled" : "Add API key for catalogue matches")
                    divider
                    sourceRow(game: .wine, name: "Open Food Facts", detail: "Community bottle catalogue")
                    divider
                    sourceRow(game: .other, name: "PriceCharting + sold comps", detail: AppSecrets.hasPriceChartingToken ? "Live guide values when matched" : "Research links · add token for live values")
                }
            }
            Text("Prices are third-party estimates and may vary by printing, condition, language, seller, and timing. Held is not an appraisal service.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.46))
        }
    }

    private var sportsCatalogueAccess: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPORTS CARD SEARCH")
                .font(.caption2.weight(.black))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.46))
            HStack(spacing: 10) {
                SecureField("Paste free CardSight API key", text: $cardSightKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") {
                    let saved = AppSecrets.saveCardSightAPIKey(cardSightKeyDraft)
                    sportsKeyStatus = saved ? "Saved — ready to search players" : "Could not save key"
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CardSenseTheme.mint)
            }
            .padding(12)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Link("Get a free key", destination: URL(string: "https://app.cardsight.ai")!)
                    .font(.caption.weight(.semibold))
                Spacer()
                if !sportsKeyStatus.isEmpty {
                    Text(sportsKeyStatus)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func sourceRow(game: Game, name: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: game.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(game.accent)
                .frame(width: 38, height: 38)
                .background(game.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CardSenseTheme.mint)
        }
        .padding(16)
    }

    private var divider: some View {
        Divider().overlay(.white.opacity(0.07)).padding(.leading, 67)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading("Designed for privacy", eyebrow: "On your device")
            GlassPanel {
                VStack(alignment: .leading, spacing: 16) {
                    privacyRow(symbol: "camera.viewfinder", title: "Camera frames", detail: "Processed on-device with Apple Vision OCR in the current build.")
                    privacyRow(symbol: "internaldrive", title: "Your collection", detail: "Saved locally on this device in the current build.")
                    privacyRow(symbol: "key.horizontal", title: "API configuration", detail: "The sports catalogue key is stored in this device's Keychain. Build-time provider keys belong in an ignored local config.")
                }
            }
        }
    }

    private func privacyRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(CardSenseTheme.mint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.46))
            }
        }
    }

    private var about: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(CardSenseTheme.accentGradient)
                    .frame(width: 54, height: 54)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CardSenseTheme.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Held")
                    .font(.headline)
                Text("Universal collector preview · Version 2.4.4")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.top, 4)
    }
}
