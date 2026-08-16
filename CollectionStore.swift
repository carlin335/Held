import Foundation
import SwiftUI

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var items: [CollectionItem] = []

    private let storageKey = "cardsense.collection.v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    var totalMarketValue: Double {
        items.reduce(0) { $0 + $1.marketValue }
    }

    var totalCards: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var gamesRepresented: Int {
        Set(items.map(\.card.game)).count
    }

    var recentItems: [CollectionItem] {
        Array(items.sorted { $0.dateAdded > $1.dateAdded }.prefix(8))
    }

    func contains(_ card: UICard) -> Bool {
        items.contains { $0.card.id == card.id && $0.card.game == card.game }
    }

    func item(for card: UICard) -> CollectionItem? {
        items.first { $0.card.id == card.id && $0.card.game == card.game }
    }

    func add(
        _ card: UICard,
        quantity: Int = 1,
        condition: CardCondition = .raw,
        purchasePrice: Double? = nil
    ) {
        if let index = items.firstIndex(where: { $0.card.id == card.id && $0.card.game == card.game }) {
            items[index].quantity += max(1, quantity)
            if card.numericUSD > 0 { items[index].card = card }
        } else {
            items.append(
                CollectionItem(
                    card: card,
                    quantity: quantity,
                    condition: condition,
                    purchasePrice: purchasePrice
                )
            )
        }
        save()
    }

    func remove(_ card: UICard) {
        items.removeAll { $0.card.id == card.id && $0.card.game == card.game }
        save()
    }

    func remove(_ item: CollectionItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func update(_ item: CollectionItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func upsert(_ item: CollectionItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([CollectionItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
