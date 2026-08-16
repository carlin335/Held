import SwiftUI

enum CardSenseTheme {
    static let canvas = Color(red: 0.027, green: 0.043, blue: 0.078)
    static let raised = Color(red: 0.052, green: 0.074, blue: 0.118)
    static let ink = Color(red: 0.025, green: 0.075, blue: 0.085)
    static let mint = Color(red: 0.28, green: 0.96, blue: 0.76)
    static let cyan = Color(red: 0.27, green: 0.78, blue: 1.00)
    static let violet = Color(red: 0.56, green: 0.40, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.43, blue: 0.45)

    static let accentGradient = LinearGradient(
        colors: [mint, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.20, blue: 0.29), Color(red: 0.07, green: 0.10, blue: 0.19)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct CardSenseBackground: View {
    var body: some View {
        ZStack {
            CardSenseTheme.canvas
            Circle()
                .fill(CardSenseTheme.violet.opacity(0.16))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 190, y: -320)
            Circle()
                .fill(CardSenseTheme.mint.opacity(0.09))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: -210, y: 330)
        }
        .ignoresSafeArea()
    }
}

struct GlassPanel<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 0.8)
                    }
            )
    }
}

struct SectionHeading: View {
    let eyebrow: String?
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, eyebrow: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.15)
                        .foregroundStyle(CardSenseTheme.mint)
                }
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CardSenseTheme.mint)
            }
        }
    }
}

extension Game {
    var shortLabel: String {
        switch self {
        case .pokemon: "Pokémon"
        case .magic: "Magic"
        case .yugioh: "Yu-Gi-Oh!"
        case .sports: "Sports"
        case .coins: "Coins"
        case .wine: "Wine"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .pokemon: "bolt.fill"
        case .magic: "flame.fill"
        case .yugioh: "seal.fill"
        case .sports: "sportscourt.fill"
        case .coins: "centsign.circle.fill"
        case .wine: "wineglass.fill"
        case .other: "shippingbox.fill"
        }
    }

    var accent: Color {
        switch self {
        case .pokemon: CardSenseTheme.cyan
        case .magic: CardSenseTheme.coral
        case .yugioh: CardSenseTheme.violet
        case .sports: CardSenseTheme.mint
        case .coins: Color.yellow
        case .wine: Color(red: 0.76, green: 0.27, blue: 0.45)
        case .other: Color.orange
        }
    }
}

extension Sport {
    var symbol: String {
        switch self {
        case .baseball: "baseball.fill"
        case .basketball: "basketball.fill"
        case .football: "football.fill"
        case .hockey: "hockey.puck.fill"
        case .soccer: "soccerball"
        case .racing: "flag.checkered"
        case .wrestling: "figure.wrestling"
        case .golf: "figure.golf"
        case .other: "sportscourt.fill"
        }
    }
}

extension View {
    func cardSensePagePadding() -> some View {
        padding(.horizontal, 20)
    }
}
