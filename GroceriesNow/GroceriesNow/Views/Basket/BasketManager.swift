import Foundation
import Observation
import SwiftData

struct PurchaseHint {
    let itemName: String
    let totalQuantity: Int
}

struct TopUsedShortcut: Identifiable {
    let id = UUID()
    let itemName: String
    let totalQuantity: Int
}

struct BoughtTogetherSuggestion: Identifiable {
    let id: String
    let itemNames: [String]
    let occurrenceCount: Int
}

struct BulkAddResult {
    let insertedNames: [String]
    let mergedNames: [String]

    var insertedCount: Int { insertedNames.count }
    var mergedCount: Int { mergedNames.count }
    var totalAffectedCount: Int { insertedCount + mergedCount }
    var hasChanges: Bool { totalAffectedCount > 0 }
}

struct RecentBasketSummary: Identifiable {
    let id: UUID
    let completedAt: Date
    let items: [RecentBasketItem]

    var title: String {
        items.map { "\($0.emoji) \($0.name) ×\($0.quantity)" }.joined(separator: ", ")
    }
}

struct RecentBasketItem: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let quantity: Int
    let note: String?
}

@Observable
final class BasketManager {
    private let haptics: BasketHapticProviding

    init(haptics: BasketHapticProviding = BasketHaptics()) {
        self.haptics = haptics
    }

    @discardableResult
    func addItem(_ item: QuickItem, in modelContext: ModelContext, basketItems: [BasketItem]) -> Int {
        let previousQuantity: Int

        if let existing = basketItems.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
            previousQuantity = existing.quantity
            existing.quantity += 1
            existing.isChecked = false
        } else {
            previousQuantity = 0
            let newItem = BasketItem(name: item.name, emoji: item.emoji, quantity: 1, isChecked: false)
            modelContext.insert(newItem)
        }

        try? modelContext.save()
        haptics.itemAdded()
        return previousQuantity
    }

    func undoAddItem(named name: String, previousQuantity: Int, in modelContext: ModelContext, basketItems: [BasketItem]) {
        guard let existing = basketItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }

        if previousQuantity <= 0 {
            modelContext.delete(existing)
        } else {
            existing.quantity = previousQuantity
        }

        try? modelContext.save()
    }

    func toggle(_ item: BasketItem, in modelContext: ModelContext) {
        item.isChecked.toggle()
        try? modelContext.save()
    }

    func delete(_ item: BasketItem, in modelContext: ModelContext) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    func clearBasket(_ items: [BasketItem], in modelContext: ModelContext) {
        for item in items {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    func totalItemCount(from items: [BasketItem]) -> Int {
        items.count
    }

    func increment(_ item: BasketItem, in modelContext: ModelContext) {
        item.quantity += 1
        item.isChecked = false
        try? modelContext.save()
    }

    func decrement(_ item: BasketItem, in modelContext: ModelContext) {
        if item.quantity > 1 {
            item.quantity -= 1
        } else {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    func saveNote(_ note: String?, for item: BasketItem, in modelContext: ModelContext) {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        try? modelContext.save()
    }

    func completeBasket(_ items: [BasketItem], in modelContext: ModelContext) {
        guard !items.isEmpty else { return }

        let completedBasket = CompletedBasket()
        modelContext.insert(completedBasket)

        for item in items {
            let entry = CompletedBasketEntry(
                basketID: completedBasket.id,
                name: item.name,
                emoji: item.emoji,
                quantity: item.quantity,
                completedAt: completedBasket.completedAt,
                note: item.note
            )
            modelContext.insert(entry)
            modelContext.delete(item)
        }

        try? modelContext.save()
        haptics.basketCompleted()
    }

    func topPurchaseHints(from entries: [CompletedBasketEntry], limit: Int = 3) -> [PurchaseHint] {
        let totals = entries.reduce(into: [String: Int]()) { result, entry in
            result[entry.name, default: 0] += entry.quantity
        }

        return totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { PurchaseHint(itemName: $0.key, totalQuantity: $0.value) }
    }

    func topUsedShortcuts(from entries: [CompletedBasketEntry], limit: Int = 6) -> [TopUsedShortcut] {
        let totals = entries.reduce(into: [String: Int]()) { result, entry in
            result[entry.name, default: 0] += entry.quantity
        }

        return totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { TopUsedShortcut(itemName: $0.key, totalQuantity: $0.value) }
    }

    func boughtTogetherSuggestions(
        from entries: [CompletedBasketEntry],
        minimumCompletedBaskets: Int = 5,
        limit: Int = 3
    ) -> [BoughtTogetherSuggestion] {
        let groupedEntries = Dictionary(grouping: entries, by: \.basketID)
        guard groupedEntries.count >= minimumCompletedBaskets else { return [] }

        var comboCounts: [String: Int] = [:]

        for basketEntries in groupedEntries.values {
            let names = Array(Set(basketEntries.map { $0.name.capitalized })).sorted()
            guard names.count >= 2 else { continue }

            for firstIndex in 0..<(names.count - 1) {
                for secondIndex in (firstIndex + 1)..<names.count {
                    let combo = [names[firstIndex], names[secondIndex]]
                    let key = combo.joined(separator: "|")
                    comboCounts[key, default: 0] += 1
                }
            }
        }

        return comboCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { key, count in
                let names = key.components(separatedBy: "|")
                return BoughtTogetherSuggestion(id: key, itemNames: names, occurrenceCount: count)
            }
    }

    func addBoughtTogetherSuggestion(
        _ suggestion: BoughtTogetherSuggestion,
        quickItems: [QuickItem],
        in modelContext: ModelContext,
        basketItems: [BasketItem]
    ) -> BulkAddResult {
        let quickItemsToAdd = suggestion.itemNames.compactMap { name in
            quickItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        return bulkAddQuickItems(quickItemsToAdd, in: modelContext, basketItems: basketItems)
    }

    func purchaseHint(for itemName: String, from hints: [PurchaseHint]) -> PurchaseHint? {
        hints.first { $0.itemName.caseInsensitiveCompare(itemName) == .orderedSame }
    }

    func recentBasketSummaries(
        baskets: [CompletedBasket],
        entries: [CompletedBasketEntry],
        limit: Int = 10
    ) -> [RecentBasketSummary] {
        let recentBaskets = baskets
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(limit)

        return recentBaskets.map { basket in
            let basketItems = entries
                .filter { $0.basketID == basket.id }
                .sorted { lhs, rhs in
                    if lhs.quantity == rhs.quantity {
                        return lhs.name < rhs.name
                    }
                    return lhs.quantity > rhs.quantity
                }
                .map {
                    RecentBasketItem(
                        name: $0.name,
                        emoji: $0.emoji,
                        quantity: $0.quantity,
                        note: $0.note
                    )
                }

            return RecentBasketSummary(
                id: basket.id,
                completedAt: basket.completedAt,
                items: basketItems
            )
        }
    }

    func addRecentItem(_ item: RecentBasketItem, in modelContext: ModelContext, basketItems: [BasketItem]) {
        _ = mergeBasketItems(
            [(name: item.name, emoji: item.emoji, quantity: item.quantity, note: item.note)],
            in: modelContext,
            basketItems: basketItems
        )
    }

    func addRecentBasket(_ basket: RecentBasketSummary, in modelContext: ModelContext, basketItems: [BasketItem]) -> BulkAddResult {
        let items = basket.items.map { (name: $0.name, emoji: $0.emoji, quantity: $0.quantity, note: $0.note) }
        return mergeBasketItems(items, in: modelContext, basketItems: basketItems)
    }

    func removeRecentBasket(
        _ basket: RecentBasketSummary,
        completedBaskets: [CompletedBasket],
        completedEntries: [CompletedBasketEntry],
        in modelContext: ModelContext
    ) {
        if let storedBasket = completedBaskets.first(where: { $0.id == basket.id }) {
            modelContext.delete(storedBasket)
        }

        let matchingEntries = completedEntries.filter { $0.basketID == basket.id }
        for entry in matchingEntries {
            modelContext.delete(entry)
        }

        try? modelContext.save()
    }

    private func bulkAddQuickItems(_ items: [QuickItem], in modelContext: ModelContext, basketItems: [BasketItem]) -> BulkAddResult {
        let mergedItems = items.map { (name: $0.name, emoji: $0.emoji, quantity: 1, note: Optional<String>.none) }
        return mergeBasketItems(mergedItems, in: modelContext, basketItems: basketItems)
    }

    private func mergeBasketItems(
        _ items: [(name: String, emoji: String, quantity: Int, note: String?)],
        in modelContext: ModelContext,
        basketItems: [BasketItem]
    ) -> BulkAddResult {
        var insertedNames: [String] = []
        var mergedNames: [String] = []

        for item in items {
            if let existing = basketItems.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                existing.quantity += item.quantity
                existing.isChecked = false
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    existing.note = note
                }
                mergedNames.append(existing.name)
            } else {
                modelContext.insert(BasketItem(name: item.name, emoji: item.emoji, quantity: item.quantity, isChecked: false, note: item.note))
                insertedNames.append(item.name)
            }
        }

        try? modelContext.save()

        let result = BulkAddResult(insertedNames: insertedNames, mergedNames: mergedNames)
        if result.hasChanges {
            haptics.itemAdded()
        }
        return result
    }

    func contextualBoughtTogetherSuggestions(
        triggeredBy itemName: String,
        entries: [CompletedBasketEntry],
        basketItems: [BasketItem],
        limit: Int = 2
    ) -> [BoughtTogetherSuggestion] {
        let currentBasketNames = Set(basketItems.map { $0.name.lowercased() })

        return boughtTogetherSuggestions(from: entries, limit: 8)
            .filter { suggestion in
                let lowercasedNames = suggestion.itemNames.map { $0.lowercased() }
                guard lowercasedNames.contains(itemName.lowercased()) else { return false }
                return suggestion.itemNames.contains { !currentBasketNames.contains($0.lowercased()) }
            }
            .prefix(limit)
            .map { $0 }
    }
}