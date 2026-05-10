import Foundation
import SwiftData

/// Tracks how many times an item has been purchased, when it was last used,
/// and how purchases are distributed across time-of-day slots.
///
/// CloudKit-ready: every stored property has a default value.
@Model
final class ItemUsageRecord {
    var itemName: String = ""   // lowercased canonical form
    var usageCount: Int = 0
    var lastUsedAt: Date = Date.distantPast
    /// Purchases made between 05:00–11:59
    var morningCount: Int = 0
    /// Purchases made between 12:00–16:59
    var afternoonCount: Int = 0
    /// Purchases made between 17:00–04:59
    var eveningCount: Int = 0

    init(itemName: String) {
        self.itemName = itemName.lowercased()
        self.usageCount = 0
        self.lastUsedAt = .distantPast
        self.morningCount = 0
        self.afternoonCount = 0
        self.eveningCount = 0
    }
}
