import Foundation
import SwiftData

/// CloudKit-ready: no `@Attribute(.unique)`, every stored property has a default.
@Model
final class CompletedBasketEntry {
    var id: UUID = UUID()
    var basketID: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var quantity: Int = 1
    var completedAt: Date = Date.distantPast
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
