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
    @Guide(description: "Complete list of grocery ingredients needed to prepare the dish")
    var ingredients: [_GeneratedIngredient]
}

@available(iOS 26.0, macOS 26.0, *)
@Observable @MainActor
final class RecipeBasketService {
    private(set) var isLoading = false
    private(set) var ingredients: [RecipeIngredient] = []
    private(set) var errorMessage: String?
    /// True after at least one generation completes (success or failure, not cancellation).
    private(set) var hasSearched = false

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private var task: Task<Void, Never>?

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

    private func run(recipe: String) async {
        isLoading = true
        ingredients = []
        errorMessage = nil

        do {
            let session = LanguageModelSession(
                instructions: "You are a grocery shopping assistant. Always write ingredient names in English."
            )

            let stream = session.streamResponse(
                to: "List all the grocery ingredients I need to buy to make \(recipe). Be thorough and practical for a home cook.",
                generating: _GeneratedIngredientList.self
            )

            for try await partial in stream {
                guard let partialIngredients = partial.content.ingredients else { continue }
                ingredients = partialIngredients.compactMap { item -> RecipeIngredient? in
                    guard let name = item.name, !name.isEmpty,
                          let emoji = item.emoji, !emoji.isEmpty
                    else { return nil }
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
