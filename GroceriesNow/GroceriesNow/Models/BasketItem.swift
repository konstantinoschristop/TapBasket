import Foundation
import SwiftData

@Model
final class BasketItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var quantity: Int
    var isChecked: Bool
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