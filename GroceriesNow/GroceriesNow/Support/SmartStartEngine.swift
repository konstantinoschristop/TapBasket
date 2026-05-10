import Foundation
import SwiftData

/// Scores items for the Smart Start section using:
///   score = frequency * 0.5 + recency * 0.3 + timeOfDay * 0.2
///
/// - frequency:  log-normalised purchase count
/// - recency:    exp(-daysSince / 14) — ~14-day half-life
/// - timeOfDay:  fraction of purchases in the current time slot (morning / afternoon / evening)
final class SmartStartEngine {

    static let shared = SmartStartEngine()
    private init() {}

    private enum TimeSlot { case morning, afternoon, evening }

    func items(
        quickItems: [QuickItem],
        basketItems: [BasketItem],
        in context: ModelContext,
        limit: Int = 6
    ) -> [QuickItem] {
        let excludedNames = Set(basketItems.map { $0.name.lowercased() })
        let now = Date()
        let slot = currentSlot(for: now)

        let descriptor = FetchDescriptor<ItemUsageRecord>()
        guard let records = try? context.fetch(descriptor) else { return [] }

        let eligible = records.filter { $0.usageCount >= 2 && !excludedNames.contains($0.itemName) }
        guard !eligible.isEmpty else { return [] }

        let maxUsage = Double(eligible.map(\.usageCount).max() ?? 1)

        let scored = eligible.map { record -> (name: String, score: Double) in
            let freq = log1p(Double(record.usageCount)) / log1p(maxUsage)
            let daysSince = now.timeIntervalSince(record.lastUsedAt) / 86_400
            let recency = exp(-daysSince / 14)
            let total = record.morningCount + record.afternoonCount + record.eveningCount
            let slotCount = Double(count(for: slot, record: record))
            let timeOfDay = total > 0 ? slotCount / Double(total) : 0.0
            return (record.itemName, freq * 0.5 + recency * 0.3 + timeOfDay * 0.2)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)

        let byName = Dictionary(
            quickItems.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return scored.compactMap { byName[$0.name] }
    }

    // MARK: - Private

    private func currentSlot(for date: Date) -> TimeSlot {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        default:     return .evening
        }
    }

    private func count(for slot: TimeSlot, record: ItemUsageRecord) -> Int {
        switch slot {
        case .morning:   return record.morningCount
        case .afternoon: return record.afternoonCount
        case .evening:   return record.eveningCount
        }
    }
}
