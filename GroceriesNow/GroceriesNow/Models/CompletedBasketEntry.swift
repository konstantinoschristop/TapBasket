import Foundation
import SwiftData

@Model
final class CompletedBasketEntry {
    @Attribute(.unique) var id: UUID
    var basketID: UUID
    var name: String
    var emoji: String
    var quantity: Int
    var completedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        basketID: UUID,
        name: String,
        emoji: String,
        quantity: Int,
        completedAt: Date,
        note: String? = nil
    ) {
        self.id = id
        self.basketID = basketID
        self.name = name
        self.emoji = emoji
        self.quantity = quantity
        self.completedAt = completedAt
        self.note = note
    }
}