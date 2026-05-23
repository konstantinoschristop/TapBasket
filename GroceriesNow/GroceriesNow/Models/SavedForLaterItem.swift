import Foundation
import SwiftData

/// Items the user removed from a basket via "Save for later" — kept
/// around so they can be restored to the next basket session without
/// having to remember and re-add them by hand.
///
/// Lifecycle:
///   * Created when the user swipes a `BasketItem` and picks "Save".
///   * Restored to the basket as a `BasketItem` when the user taps the
///     row in the "Saved for later" section.
///   * Deleted permanently if the user swipes-to-forget, or if its
///     `savedAt` is older than the 14-day expiry window (cleaned up
///     by `BasketManager.purgeExpiredSaved`).
///
/// Schema notes for CloudKit compatibility:
///   * No `@Attribute(.unique)` — CloudKit doesn't support unique
///     constraints.
///   * Every stored property has a default value — CloudKit needs to
///     be able to materialise records without all fields populated.
@Model
final class SavedForLaterItem {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    /// Quantity the item carried when it was saved. Restored as-is
    /// when the user taps to move it back into a basket.
    var quantity: Int = 1
    /// Optional note preserved from the original basket item.
    var note: String?
    /// When the user saved this item. Drives the 14-day expiry sweep
    /// and the "Saved N days ago" caption in the UI.
    var savedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        quantity: Int = 1,
        note: String? = nil,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.quantity = quantity
        self.note = note
        self.savedAt = savedAt
    }
}
