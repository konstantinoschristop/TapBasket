import Foundation

/// A plain model returned to the UI — no availability restriction.
struct RecipeIngredient: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var emoji: String
    var quantity: Int
}

// MARK: - Foundation Models integration

#if canImport(FoundationModels)
import FoundationModels

// MARK: Step 1 — Dish validation (lightweight, fast)

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct _DishValidation {
    @Guide(description: """
        True if the input is a recognisable named recipe or dish that someone would cook, \
        in ANY language or culture. \
        False if the input is: a raw ingredient (onion, κρεμμύδι, milk, γάλα), \
        a person's name (μπουμπής, John), gibberish (asdfjkl), \
        or a generic food category (vegetables, λαχανικά). \
        A dish = something you cook with multiple ingredients following a recipe. \
        An ingredient = a single raw food item you buy at a store.
        """)
    var isDish: Bool
}

// MARK: Step 2 — Ingredient generation (only called for valid dishes)

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct _GeneratedIngredient {
    @Guide(description: "Ingredient name in English, concise (e.g. 'pasta', 'olive oil', 'ground beef')")
    var name: String

    @Guide(description: "A single food emoji that best represents this ingredient")
    var emoji: String

    @Guide(description: "Number of whole units to buy (e.g. 3 for 3 eggs, 2 for 2 cans). Use 1 if the ingredient is measured by weight, volume, or if you are unsure.")
    var quantity: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct _GeneratedIngredientList {
    @Guide(description: "Complete list of grocery ingredients needed to prepare the dish.")
    var ingredients: [_GeneratedIngredient]
}

@available(iOS 26.0, macOS 26.0, *)
@Observable @MainActor
final class RecipeBasketService {
    private(set) var isLoading = false
    private(set) var ingredients: [RecipeIngredient] = []
    private(set) var errorMessage: String?
    private(set) var hasSearched = false
    private(set) var isInvalidDish = false

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private var task: Task<Void, Never>?

    /// Pantry staples filtered out client-side (model can't be trusted to skip them).
    private static let pantryStaples: Set<String> = [
        "salt", "pepper", "black pepper", "white pepper",
        "water", "ice", "ice water",
        "sugar", "brown sugar", "powdered sugar",
        "flour", "all-purpose flour", "all purpose flour",
        "olive oil", "vegetable oil", "cooking oil", "oil", "canola oil", "sunflower oil",
        "butter", "unsalted butter", "salted butter",
        "vinegar", "white vinegar", "balsamic vinegar",
        "baking soda", "baking powder",
        "cornstarch", "corn starch"
    ]

    func suggest(for recipe: String) {
        task?.cancel()
        hasSearched = false
        task = Task { await run(recipe: recipe) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    /// Resets all state back to the initial "no search yet" screen.
    func reset() {
        task?.cancel()
        task = nil
        isLoading = false
        ingredients = []
        errorMessage = nil
        hasSearched = false
        isInvalidDish = false
    }

    // MARK: - Client-side validation (fast, no model needed)

    /// Quick rejection for obvious non-dish input before hitting the model.
    private func failsClientCheck(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Too short to be a dish
        if trimmed.count < 2 { return true }
        // Pure numbers / punctuation
        if trimmed.allSatisfy({ !$0.isLetter }) { return true }
        // Repeating character pattern (gibberish like "aaaa", "ababab")
        let letters = trimmed.filter(\.isLetter).lowercased()
        if letters.count >= 4, Set(letters).count <= 2 { return true }
        return false
    }

    private static func isPantryStaple(_ name: String) -> Bool {
        pantryStaples.contains(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Run

    private func run(recipe: String) async {
        isLoading = true
        ingredients = []
        errorMessage = nil
        isInvalidDish = false

        // Fast client-side rejection
        if failsClientCheck(recipe) {
            isInvalidDish = true
            hasSearched = true
            isLoading = false
            return
        }

        do {
            // ── Step 1: Model validation ──
            let validationSession = LanguageModelSession(
                instructions: """
                    You decide if user input is a real dish/recipe name or not. \
                    Answer isDish = true ONLY for a specific named dish that is cooked from a recipe. \
                    Answer isDish = false for EVERYTHING else: \
                    ingredients, names, gibberish, categories, adjectives, random words. \
                    If you are unsure or do not recognise it, answer false.
                    """
            )

            let validation = try await validationSession.respond(
                to: "Is the following a specific named dish or recipe that someone cooks? Input: '\(recipe)'",
                generating: _DishValidation.self
            )

            try Task.checkCancellation()

            guard validation.content.isDish else {
                isInvalidDish = true
                hasSearched = true
                isLoading = false
                return
            }

            // ── Step 2: Generate ingredients ──
            let ingredientSession = LanguageModelSession(
                instructions: """
                    You are a grocery shopping assistant. \
                    List grocery ingredients needed to cook a given dish. \
                    Be thorough and practical for a home cook. \
                    Do NOT include basic pantry staples (salt, pepper, water, sugar, \
                    flour, oil, butter, vinegar, baking soda, baking powder, cornstarch). \
                    Only list items a person would specifically go to the store to buy. \
                    Always write ingredient names in English regardless of input language.
                    """
            )

            let stream = ingredientSession.streamResponse(
                to: "List all grocery ingredients needed to make '\(recipe)'.",
                generating: _GeneratedIngredientList.self
            )

            for try await partial in stream {
                guard let partialIngredients = partial.content.ingredients else { continue }
                ingredients = partialIngredients.compactMap { item -> RecipeIngredient? in
                    guard let name = item.name, !name.isEmpty,
                          let emoji = item.emoji, !emoji.isEmpty
                    else { return nil }
                    // Client-side pantry filter as safety net
                    guard !Self.isPantryStaple(name) else { return nil }
                    let qty = item.quantity.map { $0 >= 1 && $0 <= 6 ? $0 : 1 } ?? 1
                    return RecipeIngredient(name: name, emoji: emoji, quantity: qty)
                }
            }
            hasSearched = true
        } catch is CancellationError {
            // User cancelled — don't show empty state
        } catch {
            errorMessage = String(localized: "recipe.error.generation_failed")
            hasSearched = true
        }

        isLoading = false
    }
}
#endif
