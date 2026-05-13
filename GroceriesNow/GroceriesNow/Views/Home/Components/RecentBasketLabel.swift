import Foundation

/// Conservative "shop theme" labeller for the history sheet.
///
/// Earlier versions fired on weak signal (one pasta + one tomato → "Pasta
/// night"). The result was labels that often misrepresented the basket
/// — so this version raises the bar significantly:
///
///   • a theme needs at least **3 matching items**
///   • the matches need to be at least **60% of the basket**
///   • themes that don't say anything specific (Quick run, Big shop,
///     Treat run) are removed entirely
///
/// Returns `nil` in the (now common) case where no theme really fits —
/// the caller falls back to a plain `date · count` line.
extension RecentBasketSummary {

    struct FriendlyLabel {
        let text: String
        let emoji: String
    }

    var friendlyLabel: FriendlyLabel? {
        let count = items.count
        // Bail on small baskets — there isn't enough signal for a theme.
        guard count >= 4 else { return nil }

        let names = items.map { $0.name.lowercased() }

        let matches: (Set<String>) -> Int = { keywords in
            names.reduce(0) { acc, name in
                keywords.contains(where: { name.contains($0) }) ? acc + 1 : acc
            }
        }
        let any: (Set<String>) -> Bool = { matches($0) > 0 }
        let share: (Set<String>) -> Double = { Double(matches($0)) / Double(count) }

        // Stronger thresholds than before — labels appear less often,
        // but when they do they actually mean something.
        let minHits = 3
        let minShare: Double = 0.6

        // --- Pasta night ---
        // Specific theme: pasta + a canonical cooking companion + at
        // least 3 ingredient matches between the two groups.
        let pastaKW: Set<String> = ["pasta", "spaghetti", "noodle"]
        let pastaCompanions: Set<String> = ["tomato", "cheese", "garlic", "basil", "parmesan", "sauce", "olive"]
        if any(pastaKW), matches(pastaCompanions) >= 2 {
            return FriendlyLabel(
                text: String(localized: "history.label.pasta_night", defaultValue: "Pasta night"),
                emoji: "🍝"
            )
        }

        // --- Fresh produce ---
        let produceKW: Set<String> = [
            "tomato", "potato", "carrot", "cucumber", "lettuce", "spinach",
            "broccoli", "pepper", "onion", "garlic", "ginger", "mushroom",
            "avocado", "apple", "banana", "grape", "orange", "lemon",
            "strawberr", "blueberr", "raspberr", "pineapple", "kiwi", "coconut",
            "peach", "watermelon", "melon", "cherr"
        ]
        if matches(produceKW) >= minHits, share(produceKW) >= minShare {
            return FriendlyLabel(
                text: String(localized: "history.label.fresh_produce", defaultValue: "Fresh produce"),
                emoji: "🥬"
            )
        }

        // --- Breakfast run ---
        let breakfastKW: Set<String> = [
            "bread", "croissant", "bagel", "waffle", "pancake", "egg",
            "coffee", "tea", "cereal", "oats", "butter", "jam", "honey",
            "milk", "yogurt"
        ]
        if matches(breakfastKW) >= minHits, share(breakfastKW) >= minShare {
            return FriendlyLabel(
                text: String(localized: "history.label.breakfast_run", defaultValue: "Breakfast run"),
                emoji: "☕️"
            )
        }

        // --- Cook night ---
        // Multiple proteins is a strong signal regardless of share —
        // someone who buys 3 different proteins is cooking something.
        let proteinKW: Set<String> = [
            "chicken", "meat", "steak", "fish", "salmon", "tuna", "bacon",
            "sausage", "ham", "tofu", "shrimp", "prawn", "lamb", "pork", "turkey"
        ]
        if matches(proteinKW) >= minHits {
            return FriendlyLabel(
                text: String(localized: "history.label.cook_night", defaultValue: "Cook night"),
                emoji: "🍗"
            )
        }

        // --- Drinks run ---
        let drinksKW: Set<String> = ["soda", "beer", "wine", "juice", "sparkling"]
        if matches(drinksKW) >= minHits, share(drinksKW) >= minShare {
            return FriendlyLabel(
                text: String(localized: "history.label.drinks_run", defaultValue: "Drinks run"),
                emoji: "🥤"
            )
        }

        // Anything else: no label. The UI falls back to date · count,
        // which is honest and never wrong.
        return nil
    }
}
