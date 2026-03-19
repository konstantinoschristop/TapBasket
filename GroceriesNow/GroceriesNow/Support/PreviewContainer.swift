import SwiftData

@MainActor
enum PreviewContainer {
    static func make() -> ModelContainer {
        let schema = Schema([
            QuickItem.self,
            BasketItem.self,
            CompletedBasket.self,
            CompletedBasketEntry.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])

        for item in TapBasketApp.defaultQuickItems {
            container.mainContext.insert(
                QuickItem(
                    name: item.name,
                    emoji: item.emoji,
                    sortOrder: item.sortOrder,
                    category: item.category
                )
            )
        }

        return container
    }
}