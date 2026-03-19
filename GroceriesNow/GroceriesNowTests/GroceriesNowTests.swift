//
//  GroceriesNowTests.swift
//  GroceriesNowTests
//
//  Created by k.christopoulos on 15/3/26.
//

import Foundation
import SwiftData
import Testing
@testable import GroceriesNow

@MainActor
struct GroceriesNowTests {
    @Test("addItem creates and increments a basket item")
    func addItemCreatesAndIncrementsItem() throws {
        let harness = try TestHarness()
        let milk = QuickItem(name: "Milk", emoji: "🥛", sortOrder: 0)

        let firstPreviousQuantity = harness.manager.addItem(milk, in: harness.context, basketItems: harness.basketItems())
        let secondPreviousQuantity = harness.manager.addItem(milk, in: harness.context, basketItems: harness.basketItems())

        let items = harness.basketItems()
        #expect(firstPreviousQuantity == 0)
        #expect(secondPreviousQuantity == 1)
        #expect(items.count == 1)
        #expect(items.first?.name == "Milk")
        #expect(items.first?.quantity == 2)
        #expect(items.first?.isChecked == false)
    }

    @Test("undoAddItem removes newly created item and restores previous quantity")
    func undoAddItemRestoresPreviousState() throws {
        let harness = try TestHarness()
        let milk = QuickItem(name: "Milk", emoji: "🥛", sortOrder: 0)

        let createdPreviousQuantity = harness.manager.addItem(milk, in: harness.context, basketItems: harness.basketItems())
        harness.manager.undoAddItem(named: "Milk", previousQuantity: createdPreviousQuantity, in: harness.context, basketItems: harness.basketItems())
        #expect(harness.basketItems().isEmpty)

        _ = harness.manager.addItem(milk, in: harness.context, basketItems: harness.basketItems())
        let previousQuantity = harness.manager.addItem(milk, in: harness.context, basketItems: harness.basketItems())
        harness.manager.undoAddItem(named: "Milk", previousQuantity: previousQuantity, in: harness.context, basketItems: harness.basketItems())

        let items = harness.basketItems()
        #expect(items.count == 1)
        #expect(items.first?.quantity == 1)
    }

    @Test("increment, decrement, toggle, delete, clear and total count work")
    func basketMutationsWork() throws {
        let harness = try TestHarness()
        let milk = BasketItem(name: "Milk", emoji: "🥛", quantity: 2, isChecked: true)
        let bread = BasketItem(name: "Bread", emoji: "🍞", quantity: 3)
        harness.insert(milk)
        harness.insert(bread)

        harness.manager.increment(milk, in: harness.context)
        #expect(milk.quantity == 3)
        #expect(milk.isChecked == false)

        harness.manager.toggle(milk, in: harness.context)
        #expect(milk.isChecked == true)

        harness.manager.decrement(milk, in: harness.context)
        #expect(milk.quantity == 2)

        let eggs = BasketItem(name: "Eggs", emoji: "🥚", quantity: 1)
        harness.insert(eggs)
        harness.manager.decrement(eggs, in: harness.context)
        #expect(harness.basketItems().contains(where: { $0.name == "Eggs" }) == false)

        let total = harness.manager.totalItemCount(from: harness.basketItems())
        #expect(total == 5)

        harness.manager.delete(milk, in: harness.context)
        #expect(harness.basketItems().contains(where: { $0.name == "Milk" }) == false)

        harness.manager.clearBasket(harness.basketItems(), in: harness.context)
        #expect(harness.basketItems().isEmpty)
    }

    @Test("completeBasket stores history snapshots and clears current basket")
    func completeBasketMovesItemsIntoHistory() throws {
        let harness = try TestHarness()
        harness.insert(BasketItem(name: "Milk", emoji: "🥛", quantity: 2))
        harness.insert(BasketItem(name: "Bread", emoji: "🍞", quantity: 1))

        harness.manager.completeBasket(harness.basketItems(), in: harness.context)

        let completedBaskets = harness.completedBaskets()
        let completedEntries = harness.completedEntries()

        #expect(harness.basketItems().isEmpty)
        #expect(completedBaskets.count == 1)
        #expect(completedEntries.count == 2)
        #expect(Set(completedEntries.map(\.name)) == Set(["Milk", "Bread"]))
        #expect(completedEntries.first?.basketID == completedBaskets.first?.id)
    }

    @Test("purchase hints and recent basket summaries are derived from history")
    func purchaseHintsAndRecentSummariesWork() throws {
        let harness = try TestHarness()
        let olderBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 10))
        let newerBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 20))
        harness.insert(olderBasket)
        harness.insert(newerBasket)

        harness.insert(CompletedBasketEntry(basketID: olderBasket.id, name: "Milk", emoji: "🥛", quantity: 2, completedAt: olderBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: olderBasket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: olderBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: newerBasket.id, name: "Milk", emoji: "🥛", quantity: 3, completedAt: newerBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: newerBasket.id, name: "Eggs", emoji: "🥚", quantity: 4, completedAt: newerBasket.completedAt))

        let hints = harness.manager.topPurchaseHints(from: harness.completedEntries())
        let milkHint = harness.manager.purchaseHint(for: "milk", from: hints)
        let summaries = harness.manager.recentBasketSummaries(baskets: harness.completedBaskets(), entries: harness.completedEntries())

        #expect(hints.count == 3)
        #expect(hints.first?.itemName == "Milk")
        #expect(hints.first?.totalQuantity == 5)
        #expect(milkHint?.totalQuantity == 5)
        #expect(summaries.count == 2)
        #expect(summaries.first?.id == newerBasket.id)
        #expect(summaries.first?.items.first?.name == "Eggs")
    }

    @Test("re-adding recent items and baskets merges quantities into current basket")
    func reAddingRecentHistoryMergesIntoBasket() throws {
        let harness = try TestHarness()
        let existingMilk = BasketItem(name: "Milk", emoji: "🥛", quantity: 1)
        harness.insert(existingMilk)

        let milkItem = RecentBasketItem(name: "Milk", emoji: "🥛", quantity: 2)
        let eggsItem = RecentBasketItem(name: "Eggs", emoji: "🥚", quantity: 3)
        let basket = RecentBasketSummary(id: UUID(), completedAt: .now, items: [milkItem, eggsItem])

        harness.manager.addRecentItem(milkItem, in: harness.context, basketItems: harness.basketItems())
        #expect(harness.basketItems().first(where: { $0.name == "Milk" })?.quantity == 3)

        harness.manager.addRecentBasket(basket, in: harness.context, basketItems: harness.basketItems())

        let items = harness.basketItems()
        #expect(items.first(where: { $0.name == "Milk" })?.quantity == 5)
        #expect(items.first(where: { $0.name == "Eggs" })?.quantity == 3)
    }

    @Test("removeRecentBasket deletes the chosen completed basket and linked entries")
    func removeRecentBasketDeletesHistory() throws {
        let harness = try TestHarness()
        let firstBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 10))
        let secondBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 20))
        harness.insert(firstBasket)
        harness.insert(secondBasket)

        harness.insert(CompletedBasketEntry(basketID: firstBasket.id, name: "Milk", emoji: "🥛", quantity: 2, completedAt: firstBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: secondBasket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: secondBasket.completedAt))

        let summaries = harness.manager.recentBasketSummaries(baskets: harness.completedBaskets(), entries: harness.completedEntries())
        let basketToRemove = try #require(summaries.first(where: { $0.id == firstBasket.id }))

        harness.manager.removeRecentBasket(
            basketToRemove,
            completedBaskets: harness.completedBaskets(),
            completedEntries: harness.completedEntries(),
            in: harness.context
        )

        #expect(harness.completedBaskets().contains(where: { $0.id == firstBasket.id }) == false)
        #expect(harness.completedEntries().contains(where: { $0.basketID == firstBasket.id }) == false)
        #expect(harness.completedBaskets().contains(where: { $0.id == secondBasket.id }))
        #expect(harness.completedEntries().contains(where: { $0.basketID == secondBasket.id }))
    }

    @Test("default expanded browse categories favor essentials, produce, home care, and custom when present")
    func defaultExpandedCategoriesFavorPrimarySections() {
        let categoriesWithCustom: [QuickItemCategory] = [.essentials, .produce, .homeCare, .more, .custom]
        let categoriesWithoutPriority: [QuickItemCategory] = [.proteins, .pantry, .drinks, .more]

        let expandedWithCustom = HomeBrowseState.defaultExpandedCategories(for: categoriesWithCustom)
        let expandedWithoutPriority = HomeBrowseState.defaultExpandedCategories(for: categoriesWithoutPriority)

        #expect(expandedWithCustom == Set([.essentials, .produce, .homeCare, .custom]))
        #expect(expandedWithoutPriority.isEmpty)
    }

    @Test("bought together suggestions require at least five completed baskets")
    func boughtTogetherSuggestionsRequireFiveCompletedBaskets() throws {
        let harness = try TestHarness()

        for offset in 0..<4 {
            let basket = CompletedBasket(completedAt: Date(timeIntervalSince1970: Double(offset)))
            harness.insert(basket)
            harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Milk", emoji: "🥛", quantity: 1, completedAt: basket.completedAt))
            harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: basket.completedAt))
        }

        let suggestions = harness.manager.boughtTogetherSuggestions(from: harness.completedEntries())
        #expect(suggestions.isEmpty)
    }

    @Test("bought together suggestions rank the most frequent pair first")
    func boughtTogetherSuggestionsRankMostFrequentPairFirst() throws {
        let harness = try TestHarness()

        for offset in 0..<5 {
            let basket = CompletedBasket(completedAt: Date(timeIntervalSince1970: Double(offset)))
            harness.insert(basket)
            harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Milk", emoji: "🥛", quantity: 1, completedAt: basket.completedAt))
            harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: basket.completedAt))

            if offset < 3 {
                harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Eggs", emoji: "🥚", quantity: 1, completedAt: basket.completedAt))
            }
        }

        let suggestions = harness.manager.boughtTogetherSuggestions(from: harness.completedEntries())

        #expect(suggestions.first?.itemNames == ["Bread", "Milk"])
        #expect(suggestions.first?.occurrenceCount == 5)
        #expect(suggestions.contains(where: { $0.itemNames == ["Bread", "Eggs"] && $0.occurrenceCount == 3 }))
    }

    @Test("adding a bought together suggestion increments each suggested item")
    func addingBoughtTogetherSuggestionAddsAllItems() throws {
        let harness = try TestHarness()
        let milk = QuickItem(name: "Milk", emoji: "🥛", sortOrder: 0)
        let bread = QuickItem(name: "Bread", emoji: "🍞", sortOrder: 1)
        harness.insert(milk)
        harness.insert(bread)
        harness.insert(BasketItem(name: "Milk", emoji: "🥛", quantity: 1))

        let suggestion = BoughtTogetherSuggestion(id: "Bread|Milk", itemNames: ["Bread", "Milk"], occurrenceCount: 5)
        harness.manager.addBoughtTogetherSuggestion(suggestion, quickItems: [milk, bread], in: harness.context, basketItems: harness.basketItems())

        let items = harness.basketItems()
        #expect(items.first(where: { $0.name == "Milk" })?.quantity == 2)
        #expect(items.first(where: { $0.name == "Bread" })?.quantity == 1)
    }

    @Test("recent basket add all reports inserted and merged items")
    func recentBasketAddAllReportsInsertedAndMergedItems() throws {
        let harness = try TestHarness()
        harness.insert(BasketItem(name: "Milk", emoji: "🥛", quantity: 1))

        let basket = RecentBasketSummary(
            id: UUID(),
            completedAt: .now,
            items: [
                RecentBasketItem(name: "Milk", emoji: "🥛", quantity: 2),
                RecentBasketItem(name: "Bread", emoji: "🍞", quantity: 1)
            ]
        )

        let result = harness.manager.addRecentBasket(basket, in: harness.context, basketItems: harness.basketItems())
        let items = harness.basketItems()

        #expect(result.insertedNames == ["Bread"])
        #expect(result.mergedNames == ["Milk"])
        #expect(items.first(where: { $0.name == "Milk" })?.quantity == 3)
        #expect(items.first(where: { $0.name == "Bread" })?.quantity == 1)
    }

    @Test("bought together add all reports inserted and merged items")
    func boughtTogetherAddAllReportsInsertedAndMergedItems() throws {
        let harness = try TestHarness()
        let milk = QuickItem(name: "Milk", emoji: "🥛", sortOrder: 0)
        let bread = QuickItem(name: "Bread", emoji: "🍞", sortOrder: 1)
        harness.insert(milk)
        harness.insert(bread)
        harness.insert(BasketItem(name: "Milk", emoji: "🥛", quantity: 1))

        let suggestion = BoughtTogetherSuggestion(id: "Bread|Milk", itemNames: ["Bread", "Milk"], occurrenceCount: 5)
        let result = harness.manager.addBoughtTogetherSuggestion(suggestion, quickItems: [milk, bread], in: harness.context, basketItems: harness.basketItems())
        let items = harness.basketItems()

        #expect(result.insertedNames == ["Bread"])
        #expect(result.mergedNames == ["Milk"])
        #expect(items.first(where: { $0.name == "Milk" })?.quantity == 2)
        #expect(items.first(where: { $0.name == "Bread" })?.quantity == 1)
    }

    @Test("saving a basket item note trims whitespace and persists the note")
    func savingBasketItemNotePersistsTrimmedValue() throws {
        let harness = try TestHarness()
        let bread = BasketItem(name: "Bread", emoji: "🍞", quantity: 1)
        harness.insert(bread)

        harness.manager.saveNote("  whole grain bread  ", for: bread, in: harness.context)
        #expect(harness.basketItems().first?.note == "whole grain bread")

        harness.manager.saveNote("   ", for: bread, in: harness.context)
        #expect(harness.basketItems().first?.note == nil)
    }

    @Test("completing a basket carries item notes into history")
    func completeBasketCarriesNotesIntoHistory() throws {
        let harness = try TestHarness()
        harness.insert(BasketItem(name: "Bread", emoji: "🍞", quantity: 1, note: "whole grain"))

        harness.manager.completeBasket(harness.basketItems(), in: harness.context)

        #expect(harness.completedEntries().first?.note == "whole grain")
    }

    @Test("seed alias map canonicalizes known duplicate seeded names")
    func seededAliasMapCanonicalizesKnownDuplicates() {
        #expect(TapBasketApp.canonicalSeedName(for: "Oranges") == "orange")
        #expect(TapBasketApp.canonicalSeedName(for: "Lemons") == "lemon")
        #expect(TapBasketApp.canonicalSeedName(for: "Bread") == "bread")
    }

    @Test("re-adding a recent item restores its note into the basket")
    func reAddingRecentItemRestoresNote() throws {
        let harness = try TestHarness()
        let item = RecentBasketItem(name: "Bread", emoji: "🍞", quantity: 1, note: "whole grain")

        harness.manager.addRecentItem(item, in: harness.context, basketItems: harness.basketItems())

        let restoredItem = try #require(harness.basketItems().first(where: { $0.name == "Bread" }))
        #expect(restoredItem.note == "whole grain")
    }

    @Test("re-adding a recent basket restores notes for its items")
    func reAddingRecentBasketRestoresNotes() throws {
        let harness = try TestHarness()
        let basket = RecentBasketSummary(
            id: UUID(),
            completedAt: .now,
            items: [
                RecentBasketItem(name: "Bread", emoji: "🍞", quantity: 1, note: "whole grain"),
                RecentBasketItem(name: "Milk", emoji: "🥛", quantity: 1, note: "lactose free")
            ]
        )

        _ = harness.manager.addRecentBasket(basket, in: harness.context, basketItems: harness.basketItems())

        let items = harness.basketItems()
        #expect(items.first(where: { $0.name == "Bread" })?.note == "whole grain")
        #expect(items.first(where: { $0.name == "Milk" })?.note == "lactose free")
    }

    @Test("preferred existing item keeps seeded item over custom duplicate and renames custom safely")
    func preferredExistingItemAndUniqueCustomNameSupportDuplicateRepair() {
        let seeded = QuickItem(name: "Biscuits", emoji: "🍪", sortOrder: 41, category: .pantry)
        let custom = QuickItem(name: "Biscuits", emoji: "🍪", sortOrder: 999, category: .custom)

        let preferred = TapBasketApp.preferredExistingItem(from: [custom, seeded])
        let uniqueName = TapBasketApp.uniqueCustomName(from: "Biscuits", excluding: [seeded, custom])

        #expect(preferred?.id == seeded.id)
        #expect(uniqueName == "Biscuits 2")
    }

    @Test("top used shortcuts rank repeat purchases by quantity")
    func topUsedShortcutsRankRepeatPurchases() throws {
        let harness = try TestHarness()
        let basket = CompletedBasket(completedAt: .now)
        harness.insert(basket)
        harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Milk", emoji: "🥛", quantity: 5, completedAt: basket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Bread", emoji: "🍞", quantity: 3, completedAt: basket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: basket.id, name: "Eggs", emoji: "🥚", quantity: 1, completedAt: basket.completedAt))

        let shortcuts = harness.manager.topUsedShortcuts(from: harness.completedEntries())

        #expect(shortcuts.map(\.itemName) == ["Milk", "Bread", "Eggs"])
        #expect(shortcuts.first?.totalQuantity == 5)
    }

    @Test("contextual bought together suggestions only surface missing pair items")
    func contextualBoughtTogetherSuggestionsOnlySurfaceMissingPairItems() throws {
        let harness = try TestHarness()
        let olderBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 10))
        let newerBasket = CompletedBasket(completedAt: Date(timeIntervalSince1970: 20))
        harness.insert(olderBasket)
        harness.insert(newerBasket)

        harness.insert(CompletedBasketEntry(basketID: olderBasket.id, name: "Milk", emoji: "🥛", quantity: 1, completedAt: olderBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: olderBasket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: olderBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: newerBasket.id, name: "Milk", emoji: "🥛", quantity: 1, completedAt: newerBasket.completedAt))
        harness.insert(CompletedBasketEntry(basketID: newerBasket.id, name: "Bread", emoji: "🍞", quantity: 1, completedAt: newerBasket.completedAt))

        let suggestionsWithoutBasket = harness.manager.contextualBoughtTogetherSuggestions(
            triggeredBy: "Milk",
            entries: harness.completedEntries(),
            basketItems: []
        )
        #expect(suggestionsWithoutBasket.first?.itemNames == ["Bread", "Milk"])

        harness.insert(BasketItem(name: "Milk", emoji: "🥛", quantity: 1))
        let suggestionsWithMilk = harness.manager.contextualBoughtTogetherSuggestions(
            triggeredBy: "Milk",
            entries: harness.completedEntries(),
            basketItems: harness.basketItems()
        )
        #expect(suggestionsWithMilk.first?.itemNames == ["Bread", "Milk"])

        harness.insert(BasketItem(name: "Bread", emoji: "🍞", quantity: 1))
        let suggestionsWithBoth = harness.manager.contextualBoughtTogetherSuggestions(
            triggeredBy: "Milk",
            entries: harness.completedEntries(),
            basketItems: harness.basketItems()
        )
        #expect(suggestionsWithBoth.isEmpty)
    }

    @Test("snackbar state preserves queue payload details")
    func snackBarStatePreservesQueuePayloadDetails() {
        let state = SnackBarState(
            id: UUID(),
            title: "Added 🥛 Milk",
            undoName: "Milk",
            previousQuantity: 1,
            basketSnapshot: ["Milk"],
            progress: 1
        )

        #expect(state.title == "Added 🥛 Milk")
        #expect(state.undoName == "Milk")
        #expect(state.previousQuantity == 1)
        #expect(state.basketSnapshot == ["Milk"])
        #expect(state.progress == 1)
    }

    @Test("product display name provider localizes seeded items and falls back for custom names")
    func productDisplayNameProviderResolvesSeededAndCustomNames() {
        let milkDisplayName = ProductDisplayNameProvider.displayName(for: "Milk")
        let customDisplayName = ProductDisplayNameProvider.displayName(for: "My Special Bread")

        #expect(!milkDisplayName.isEmpty)
        #expect(customDisplayName == "My Special Bread")
    }
}

@MainActor
private struct TestHarness {
    let container: ModelContainer
    let context: ModelContext
    let manager = BasketManager()

    init() throws {
        let schema = Schema([
            QuickItem.self,
            BasketItem.self,
            CompletedBasket.self,
            CompletedBasketEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
    }

    func insert(_ model: some PersistentModel) {
        context.insert(model)
        try? context.save()
    }

    func basketItems() -> [BasketItem] {
        (try? context.fetch(FetchDescriptor<BasketItem>())) ?? []
    }

    func completedBaskets() -> [CompletedBasket] {
        (try? context.fetch(FetchDescriptor<CompletedBasket>())) ?? []
    }

    func completedEntries() -> [CompletedBasketEntry] {
        (try? context.fetch(FetchDescriptor<CompletedBasketEntry>())) ?? []
    }
}