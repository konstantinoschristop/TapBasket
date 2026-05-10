import Foundation
import SwiftData

/// CloudKit-ready: no `@Attribute(.unique)`, every stored property has a default.
@Model
final class CompletedBasket {
    var id: UUID = UUID()
    var completedAt: Date = Date.distantPast

    init(id: UUID = UUID(), completedAt: Date = .now) {
        self.id = id
        self.completedAt = completedAt
    }
}
