import Foundation
import SwiftData

/// A single line in the active basket. Persisted via SwiftData; CloudKit-ready.
///
/// Schema notes for CloudKit compatibility:
/// * No `@Attribute(.unique)` — CloudKit doesn't support unique constraints.
///   `id` is still effectively unique because SwiftData uses it as the primary
///   key and the app only ever inserts with a fresh UUID.
/// * Every stored property has a default value — CloudKit needs to be able to
///   materialise records without all fields populated.
@Model
final class BasketItem {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var quantity: Int = 1
    var isChecked: Bool = false
    var note: String?
    var recipeName: String?

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        quantity: Int = 1,
        isChecked: Bool = false,
        note: String? = nil,
        recipeName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.quantity = quantity
        self.isChecked = isChecked
        self.note = note
        self.recipeName = recipeName
    }
}
