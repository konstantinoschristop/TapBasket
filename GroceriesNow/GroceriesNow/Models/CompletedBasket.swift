import Foundation
import SwiftData

@Model
final class CompletedBasket {
    @Attribute(.unique) var id: UUID
    var completedAt: Date

    init(id: UUID = UUID(), completedAt: Date = .now) {
        self.id = id
        self.completedAt = completedAt
    }
}
