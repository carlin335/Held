import SwiftUI

struct CardArtworkView: View {
    let card: UICard
    var cornerRadius: CGFloat = 18

    var body: some View {
        AsyncImage(url: card.imageLargeURL ?? card.imageSmallURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                fallback
            case .empty:
                ZStack {
                    fallback
                    ProgressView().tint(.white.opacity(0.72))
                }
            @unknown default:
                fallback
            }
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [card.game.accent.opacity(0.7), CardSenseTheme.raised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: max(8, cornerRadius - 5), style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .padding(9)
            VStack(spacing: 8) {
                Image(systemName: card.game.symbol)
                    .font(.system(size: 34, weight: .bold))
                Text(card.name)
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
            }
            .foregroundStyle(.white)
        }
    }
}

struct CardTile: View {
    let card: UICard
    let badge: PriceBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardArtworkView(card: card)
                .aspectRatio(0.715, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(card.game.shortLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                HStack {
                    Text(price)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(hasPrice ? CardSenseTheme.mint : .white.opacity(0.42))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.8)
                }
        )
    }

    private var metadata: String {
        if let sports = card.sportsMetadata {
            return [sports.year, sports.brand, sports.setName, sports.cardNumber.map { "#\($0)" }, sports.parallel]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        if let coin = card.coinMetadata {
            return [coin.year, coin.country, coin.denomination, coin.mintMark.map { "Mint \($0)" }]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        if let wine = card.wineMetadata {
            return [wine.vintage, wine.producer, wine.region, wine.varietal]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        return [card.setName ?? card.setCode, card.number.map { "#\($0)" }, card.rarity]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var price: String {
        if let value = badge?.usd, let number = Double(value.filter { $0.isNumber || $0 == "." }) {
            return number.formatted(.currency(code: "USD"))
        }
        if let value = card.formattedUSD { return value }
        if let value = badge?.eur ?? card.priceEUR,
           let number = Double(value.filter { $0.isNumber || $0 == "." }) {
            return number.formatted(.currency(code: "EUR"))
        }
        return [.sports, .coins, .wine, .other].contains(card.game) ? "Research sources" : "Check market sources"
    }

    private var hasPrice: Bool {
        badge?.usd != nil || badge?.eur != nil || card.formattedUSD != nil || card.priceEUR != nil
    }
}

struct GameChip: View {
    let game: Game
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: game.symbol)
                Text(game.shortLabel)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? CardSenseTheme.ink : .white.opacity(0.68))
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(isSelected ? AnyShapeStyle(CardSenseTheme.accentGradient) : AnyShapeStyle(.white.opacity(0.06)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyCollectionCard: View {
    let onScan: () -> Void

    var body: some View {
        GlassPanel {
            VStack(spacing: 15) {
                ZStack {
                    Circle().fill(CardSenseTheme.mint.opacity(0.12)).frame(width: 66, height: 66)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(CardSenseTheme.mint)
                }
                Text("Your collection starts here")
                    .font(.headline)
                Text("Scan an item, confirm the match, and keep its details and latest known market value close at hand.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                Button(action: onScan) {
                    Label("Scan your first item", systemImage: "viewfinder")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CardSenseTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(CardSenseTheme.accentGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
