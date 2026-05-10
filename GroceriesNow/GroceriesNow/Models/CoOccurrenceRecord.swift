import Foundation
import SwiftData

/// Tracks how often two items appear in the same completed basket.
/// `itemA` is always alphabetically ≤ `itemB` (canonical ordering).
///
/// CloudKit-ready: every stored property has a default value.
@Model
final class CoOccurrenceRecord {
    var itemA: String = ""
    var itemB: String = ""
    var count: Int = 0
    var lastOccurredAt: Date = Date.distantPast

    init(itemA: String, itemB: String) {
        let sorted = [itemA.lowercased(), itemB.lowercased()].sorted()
        self.itemA = sorted[0]
        self.itemB = sorted[1]
        self.count = 0
        self.lastOccurredAt = .distantPast
    }
}
