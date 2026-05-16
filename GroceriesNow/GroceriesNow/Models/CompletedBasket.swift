import Foundation
import SwiftData

/// CloudKit-ready: no `@Attribute(.unique)`, every stored property has a default.
@Model
final class CompletedBasket {
    var id: UUID = UUID()
    var completedAt: Date = Date.distantPast
    /// Optional user-supplied nickname ("Meal prep", "Costco run"). When
    /// `nil`, the history sheet falls back to the auto-generated
    /// `friendlyLabel` and finally to the date.
    var customName: String? = nil
    /// Starred baskets get a small marker in the history sheet and float
    /// to the top of their section. Used for recurring shops the user
    /// wants to come back to (the lightweight "bundle" equivalent).
    var isStarred: Bool = false

    init(
        id: UUID = UUID(),
        completedAt: Date = .now,
        customName: String? = nil,
        isStarred: Bool = false
    ) {
        self.id = id
        self.completedAt = completedAt
        self.customName = customName
        self.isStarred = isStarred
    }
}
