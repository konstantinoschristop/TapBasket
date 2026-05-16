import SwiftUI
import SwiftData
import TipKit
import GoogleMobileAds
import UserMessagingPlatform

@main
struct TapBasketApp: App {
    init() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])

        // Start the SDK immediately and unconditionally. Per Google's docs,
        // start() should be called at app launch regardless of consent status —
        // consent governs personalisation, not whether the SDK runs at all.
        MobileAds.shared.start(completionHandler: nil)
    }

    // MARK: - iCloud sync configuration
    //
    // To enable iCloud sync of baskets + history across the user's devices:
    //
    //   1. In Xcode: Target → Signing & Capabilities → + Capability → iCloud.
    //      Tick "CloudKit". Add a container ID matching `cloudKitContainerID`
    //      below (or change the constant to match your existing container).
    //   2. Set `enableCloudKitSync = true`.
    //   3. Build. SwiftData will auto-create the schema in the user's private
    //      CloudKit database the first time the app runs.
    //
    // Until both steps are done the app falls back to local-only storage.
    // Models are already CloudKit-compatible (no `@Attribute(.unique)`, every
    // stored property has a default), so flipping this on is a one-liner.
    private static let enableCloudKitSync = false
    private static let cloudKitContainerID = "iCloud.com.taplist.app"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            QuickItem.self,
            BasketItem.self,
            CompletedBasket.self,
            CompletedBasketEntry.self,
            CoOccurrenceRecord.self
        ])

        let modelConfiguration: ModelConfiguration
        if enableCloudKitSync {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        } else {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            seedQuickItemsIfNeeded(in: container.mainContext)
            return container
        } catch {
            // If CloudKit was requested but the capability isn't enabled in
            // the project, container creation fails — fall back to local-only
            // so the app still launches.
            if enableCloudKitSync {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
                    seedQuickItemsIfNeeded(in: container.mainContext)
                    return container
                }
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Run consent flow once the UI is on screen so we have
                    // a guaranteed root view controller for the UMP form.
                    await Self.requestConsent()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Consent flow

    /// Requests consent info and presents the GDPR consent form if required.
    /// Runs after the UI is on screen so the form has a valid presenter.
    @MainActor
    private static func requestConsent() async {
        let parameters = RequestParameters()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                Task { @MainActor in
                    guard
                        let rootVC = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .flatMap({ $0.windows })
                            .first(where: { $0.isKeyWindow })?
                            .rootViewController
                    else {
                        continuation.resume()
                        return
                    }

                    ConsentForm.loadAndPresentIfRequired(from: rootVC) { _ in
                        continuation.resume()
                    }
                }
            }
        }
    }

    static let defaultQuickItems: [QuickItem] = [
        QuickItem(name: "Milk", emoji: "🥛", sortOrder: 0, category: .essentials),
        QuickItem(name: "Bread", emoji: "🍞", sortOrder: 1, category: .essentials),
        QuickItem(name: "Egg", emoji: "🥚", sortOrder: 2, category: .essentials),
        QuickItem(name: "Cheese", emoji: "🧀", sortOrder: 3, category: .essentials),
        QuickItem(name: "Butter", emoji: "🧈", sortOrder: 4, category: .essentials),
        QuickItem(name: "Yogurt", emoji: "🥣", sortOrder: 5, category: .essentials),
        QuickItem(name: "Water", emoji: "💧", sortOrder: 6, category: .essentials),
        QuickItem(name: "Salt", emoji: "🧂", sortOrder: 7, category: .essentials),
        QuickItem(name: "Olive Oil", emoji: "🫒", sortOrder: 8, category: .essentials),

        QuickItem(name: "Tomato", emoji: "🍅", sortOrder: 9, category: .produce),
        QuickItem(name: "Potato", emoji: "🥔", sortOrder: 10, category: .produce),
        QuickItem(name: "Carrot", emoji: "🥕", sortOrder: 11, category: .produce),
        QuickItem(name: "Cucumber", emoji: "🥒", sortOrder: 12, category: .produce),
        QuickItem(name: "Lettuce", emoji: "🥬", sortOrder: 13, category: .produce),
        QuickItem(name: "Spinach", emoji: "🥬", sortOrder: 14, category: .produce),
        QuickItem(name: "Broccoli", emoji: "🥦", sortOrder: 15, category: .produce),
        QuickItem(name: "Peppers", emoji: "🫑", sortOrder: 16, category: .produce),
        QuickItem(name: "Onion", emoji: "🧅", sortOrder: 17, category: .produce),
        QuickItem(name: "Garlic", emoji: "🧄", sortOrder: 18, category: .produce),
        // Ginger removed from seed — monthly-ish cooking ingredient,
        // catalog covers it (Ginger + Ginger powder).
        QuickItem(name: "Mushrooms", emoji: "🍄", sortOrder: 20, category: .produce),
        QuickItem(name: "Avocado", emoji: "🥑", sortOrder: 21, category: .produce),
        QuickItem(name: "Apple", emoji: "🍎", sortOrder: 22, category: .produce),
        QuickItem(name: "Banana", emoji: "🍌", sortOrder: 23, category: .produce),
        QuickItem(name: "Grapes", emoji: "🍇", sortOrder: 24, category: .produce),
        QuickItem(name: "Orange", emoji: "🍊", sortOrder: 25, category: .produce),
        QuickItem(name: "Lemon", emoji: "🍋", sortOrder: 26, category: .produce),
        QuickItem(name: "Strawberries", emoji: "🍓", sortOrder: 27, category: .produce),
        QuickItem(name: "Blueberries", emoji: "🫐", sortOrder: 28, category: .produce),
        // Pineapple / Kiwi / Coconut removed from seed — niche fruits,
        // occasional purchases. Catalog covers all three.

        QuickItem(name: "Chicken", emoji: "🍗", sortOrder: 32, category: .proteins),
        QuickItem(name: "Ground Meat", emoji: "🥩", sortOrder: 33, category: .proteins),
        QuickItem(name: "Fish", emoji: "🐟", sortOrder: 34, category: .proteins),
        QuickItem(name: "Salmon", emoji: "🐟", sortOrder: 35, category: .proteins),
        QuickItem(name: "Tuna", emoji: "🐟", sortOrder: 36, category: .proteins),
        QuickItem(name: "Bacon", emoji: "🥓", sortOrder: 37, category: .proteins),
        QuickItem(name: "Sausage", emoji: "🌭", sortOrder: 38, category: .proteins),
        QuickItem(name: "Ham", emoji: "🥓", sortOrder: 39, category: .proteins),
        QuickItem(name: "Tofu", emoji: "🥡", sortOrder: 40, category: .proteins),
        QuickItem(name: "Beans", emoji: "🫘", sortOrder: 41, category: .proteins),
        // Lentils removed from seed — catalog has Lentils + Red/Green
        // lentils for users who buy them regularly.
        QuickItem(name: "Nuts", emoji: "🥜", sortOrder: 43, category: .proteins),

        QuickItem(name: "Rice", emoji: "🍚", sortOrder: 44, category: .pantry),
        QuickItem(name: "Pasta", emoji: "🍝", sortOrder: 45, category: .pantry),
        QuickItem(name: "Flour", emoji: "🌾", sortOrder: 46, category: .pantry),
        QuickItem(name: "Sugar", emoji: "🍚", sortOrder: 47, category: .pantry),
        QuickItem(name: "Oats", emoji: "🥣", sortOrder: 48, category: .pantry),
        QuickItem(name: "Coffee", emoji: "☕️", sortOrder: 49, category: .pantry),
        QuickItem(name: "Tea", emoji: "🍵", sortOrder: 50, category: .pantry),
        QuickItem(name: "Cereal", emoji: "🥣", sortOrder: 51, category: .pantry),
        // Biscuits removed from seed — ambiguous term (UK=cookies,
        // US=dinner roll). "Cookies" lives in treats; "Biscuits" lives
        // in the bakery catalog. Cleaner without it on the home grid.
        QuickItem(name: "Honey", emoji: "🍯", sortOrder: 53, category: .pantry),
        QuickItem(name: "Jam", emoji: "🍓", sortOrder: 54, category: .pantry),
        QuickItem(name: "Peanut Butter", emoji: "🥜", sortOrder: 55, category: .pantry),
        QuickItem(name: "Ketchup", emoji: "🍅", sortOrder: 56, category: .pantry),
        QuickItem(name: "Mayonnaise", emoji: "🥚", sortOrder: 57, category: .pantry),
        QuickItem(name: "Mustard", emoji: "🌭", sortOrder: 58, category: .pantry),
        QuickItem(name: "Soy Sauce", emoji: "🍶", sortOrder: 59, category: .pantry),
        QuickItem(name: "Black Pepper", emoji: "🧂", sortOrder: 60, category: .pantry),

        QuickItem(name: "Frozen Vegetables", emoji: "🧊", sortOrder: 61, category: .frozen),
        QuickItem(name: "Frozen Pizza", emoji: "🍕", sortOrder: 62, category: .frozen),
        QuickItem(name: "Frozen Fries", emoji: "🍟", sortOrder: 63, category: .frozen),
        QuickItem(name: "Frozen Fish", emoji: "🐟", sortOrder: 64, category: .frozen),
        QuickItem(name: "Ice Cream", emoji: "🍨", sortOrder: 65, category: .frozen),

        QuickItem(name: "Sparkling Water", emoji: "🥤", sortOrder: 66, category: .drinks),
        QuickItem(name: "Juice", emoji: "🧃", sortOrder: 67, category: .drinks),
        QuickItem(name: "Soda", emoji: "🥤", sortOrder: 68, category: .drinks),
        // Oat Milk removed from seed — was mis-categorised (milk
        // variants belong in essentials, not drinks). Catalog has Oat
        // milk under essentials alongside almond/soy/coconut milks.
        QuickItem(name: "Beer", emoji: "🍺", sortOrder: 70, category: .drinks),
        QuickItem(name: "Wine", emoji: "🍷", sortOrder: 71, category: .drinks),

        QuickItem(name: "Dish Soap", emoji: "🧴", sortOrder: 72, category: .homeCare),
        QuickItem(name: "Laundry Detergent", emoji: "🧺", sortOrder: 73, category: .homeCare),
        QuickItem(name: "Multi-Surface Cleaner", emoji: "🧽", sortOrder: 74, category: .homeCare),
        QuickItem(name: "Sponges", emoji: "🧽", sortOrder: 75, category: .homeCare),
        QuickItem(name: "Trash Bags", emoji: "🗑️", sortOrder: 76, category: .homeCare),
        QuickItem(name: "Paper Towels", emoji: "🧻", sortOrder: 77, category: .homeCare),
        QuickItem(name: "Toilet Paper", emoji: "🧻", sortOrder: 78, category: .homeCare),
        QuickItem(name: "Tissues", emoji: "🧻", sortOrder: 79, category: .homeCare),
        QuickItem(name: "Hand Soap", emoji: "🧼", sortOrder: 80, category: .homeCare),
        QuickItem(name: "Shampoo", emoji: "🧴", sortOrder: 81, category: .homeCare),
        QuickItem(name: "Toothpaste", emoji: "🪥", sortOrder: 82, category: .homeCare),

        QuickItem(name: "Chocolate", emoji: "🍫", sortOrder: 83, category: .treats),
        QuickItem(name: "Cookies", emoji: "🍪", sortOrder: 84, category: .treats),
        QuickItem(name: "Chips", emoji: "🍟", sortOrder: 85, category: .treats),
        QuickItem(name: "Popcorn", emoji: "🍿", sortOrder: 86, category: .treats),

        QuickItem(name: "Croissant", emoji: "🥐", sortOrder: 87, category: .bakery),
        QuickItem(name: "Bagel", emoji: "🥯", sortOrder: 88, category: .bakery),
        QuickItem(name: "Waffle", emoji: "🧇", sortOrder: 89, category: .bakery),
        QuickItem(name: "Pancakes", emoji: "🥞", sortOrder: 90, category: .bakery),
        QuickItem(name: "Cake", emoji: "🍰", sortOrder: 91, category: .bakery)
    ]

    /// Maps a user-typed name variant to the canonical seed name so
    /// the migration in `seedQuickItemsIfNeeded` can group both forms
    /// under a single entry and delete duplicates.
    ///
    /// Direction is `user-form` → `seed-default-form`. The seed uses
    /// inconsistent plurality (singular for "Egg", "Tomato", "Apple";
    /// plural for "Mushrooms", "Grapes", "Strawberries"), and the
    /// catalog uses the opposite form for several of these, so users
    /// who add items via catalog can end up with both. This map
    /// canonicalises them after the fact.
    static let seededAliasMap: [String: String] = [
        // Singular ↔ plural pairs where the seed uses one form and
        // the catalog uses the other.
        "oranges": "orange",
        "lemons": "lemon",
        "eggs": "egg",
        "tomatoes": "tomato",
        "potatoes": "potato",
        "carrots": "carrot",
        "onions": "onion",
        "apples": "apple",
        "bananas": "banana",
        "mushroom": "mushrooms",
        "grape": "grapes",
        "strawberry": "strawberries",
        "blueberry": "blueberries",
        "sausages": "sausage",
        "mince": "ground meat",
        "minced meat": "ground meat",
        "shrimps": "shrimp",
        "prawns": "shrimp"
    ]

    static func canonicalSeedName(for name: String) -> String {
        seededAliasMap[name.lowercased()] ?? name.lowercased()
    }

    private static func seedQuickItemsIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<QuickItem>()
        let existingItems = (try? context.fetch(descriptor)) ?? []
        let defaultsByName = Dictionary(uniqueKeysWithValues: defaultQuickItems.map { ($0.name.lowercased(), $0) })

        var itemsByCanonicalName: [String: [QuickItem]] = [:]
        for item in existingItems {
            let canonicalName = canonicalSeedName(for: item.name)
            itemsByCanonicalName[canonicalName, default: []].append(item)
        }

        var didChange = false
        var repairedItems: [QuickItem] = []

        for (canonicalName, items) in itemsByCanonicalName {
            guard let primaryItem = preferredExistingItem(from: items) else { continue }

            if primaryItem.name.lowercased() != canonicalName, let canonicalDefault = defaultsByName[canonicalName] {
                primaryItem.name = canonicalDefault.name
                primaryItem.emoji = canonicalDefault.emoji
                primaryItem.sortOrder = canonicalDefault.sortOrder
                primaryItem.category = canonicalDefault.category
                didChange = true
            }

            repairedItems.append(primaryItem)

            for duplicate in items where duplicate.id != primaryItem.id {
                if duplicate.category == .custom {
                    duplicate.category = .custom
                    if duplicate.name.caseInsensitiveCompare(primaryItem.name) == .orderedSame {
                        duplicate.name = uniqueCustomName(from: duplicate.name, excluding: existingItems + repairedItems)
                    }
                } else {
                    context.delete(duplicate)
                }
                didChange = true
            }
        }

        var existingByName: [String: QuickItem] = [:]
        for item in repairedItems {
            let key = item.name.lowercased()
            if existingByName[key] == nil {
                existingByName[key] = item
            }
        }

        for defaultItem in defaultQuickItems {
            let key = defaultItem.name.lowercased()

            if let existingItem = existingByName[key] {
                if existingItem.emoji != defaultItem.emoji {
                    existingItem.emoji = defaultItem.emoji
                    didChange = true
                }

                if existingItem.sortOrder != defaultItem.sortOrder {
                    existingItem.sortOrder = defaultItem.sortOrder
                    didChange = true
                }

                if existingItem.category != defaultItem.category {
                    existingItem.category = defaultItem.category
                    didChange = true
                }
            } else {
                context.insert(
                    QuickItem(
                        name: defaultItem.name,
                        emoji: defaultItem.emoji,
                        sortOrder: defaultItem.sortOrder,
                        category: defaultItem.category
                    )
                )
                didChange = true
            }
        }

        for existingItem in repairedItems {
            let key = existingItem.name.lowercased()
            guard defaultsByName[key] == nil, existingItem.categoryRawValue.isEmpty else { continue }
            existingItem.category = .custom
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }

    static func preferredExistingItem(from items: [QuickItem]) -> QuickItem? {
        items.sorted { lhs, rhs in
            if lhs.category == .custom, rhs.category != .custom { return false }
            if lhs.category != .custom, rhs.category == .custom { return true }
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }.first
    }

    static func uniqueCustomName(from baseName: String, excluding items: [QuickItem]) -> String {
        let usedNames = Set(items.map { $0.name.lowercased() })
        guard usedNames.contains(baseName.lowercased()) else { return baseName }

        var index = 2
        while true {
            let candidate = "\(baseName) \(index)"
            if !usedNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }
}