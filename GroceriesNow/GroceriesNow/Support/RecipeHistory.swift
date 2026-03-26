import Foundation

struct RecipeHistory {
    private static let key = "com.tapbasket.recipe.history"
    private static let maxCount = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ recipe: String) {
        let trimmed = recipe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = all.filter { $0.lowercased() != trimmed.lowercased() }
        current.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(current.prefix(maxCount)), forKey: key)
    }

    static func remove(_ recipe: String) {
        let updated = all.filter { $0.lowercased() != recipe.lowercased() }
        UserDefaults.standard.set(updated, forKey: key)
    }
}
