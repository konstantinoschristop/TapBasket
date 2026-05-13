import Foundation
import SwiftData

/// Lightweight recommendation engine backed by SwiftData.
///
/// Records pair co-occurrences at basket completion time, then surfaces
/// suggestions using:
///
///   score = coOccurrence * 0.7 + recency * 0.3
///
/// - coOccurrence: count / maxCount  (relative among candidates)
/// - recency:      exp(-daysSince / 30)  — ~30-day exponential decay
final class RecommendationEngine {

    static let shared = RecommendationEngine()
    private init() {}

    // MARK: - Record

    /// Call when a basket is completed.
    /// Updates all pair co-occurrences for the items in the basket.
    func record(completedItemNames: [String], at date: Date, in context: ModelContext) {
        let names = Array(Set(completedItemNames.map { $0.lowercased() })).sorted()
        guard names.count >= 2 else { return }

        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let record = fetchOrCreateCoOccurrence(a: names[i], b: names[j], in: context)
                record.count += 1
                record.lastOccurredAt = max(record.lastOccurredAt, date)
            }
        }

        try? context.save()
    }

    // MARK: - Single Suggestion

    /// Returns the highest-scored single partner for `itemName`, excluding `excluding`.
    /// Returns `nil` when no co-occurrence data exists (caller should fall back).
    func bestSuggestion(
        for itemName: String,
        excluding: Set<String>,
        in context: ModelContext
    ) -> String? {
        let name = itemName.lowercased()
        let excludedLower = Set(excluding.map { $0.lowercased() })

        let descriptor = FetchDescriptor<CoOccurrenceRecord>(
            predicate: #Predicate { $0.itemA == name || $0.itemB == name }
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return nil }

        let candidates: [(partner: String, count: Int, lastOccurredAt: Date)] = records.compactMap { r in
            let partner = r.itemA == name ? r.itemB : r.itemA
            guard !excludedLower.contains(partner) else { return nil }
            return (partner, r.count, r.lastOccurredAt)
        }
        guard !candidates.isEmpty else { return nil }

        let maxCount = Double(candidates.map(\.count).max() ?? 1)
        let now = Date()

        return candidates.max { lhs, rhs in
            let lKey = [name, lhs.partner].sorted().joined(separator: "|")
            let rKey = [name, rhs.partner].sorted().joined(separator: "|")
            let lScore = scored(lhs.count, maxCount: maxCount, lastOccurredAt: lhs.lastOccurredAt, now: now) * ignorePenalty(for: lKey)
            let rScore = scored(rhs.count, maxCount: maxCount, lastOccurredAt: rhs.lastOccurredAt, now: now) * ignorePenalty(for: rKey)
            return lScore < rScore
        }?.partner
    }

    // MARK: - Bundle Suggestion

    /// Greedily finds a clique of 3–5 items that all co-occur with each other.
    /// Returns the bundle members *excluding* the trigger item, or `nil` if no bundle
    /// of `targetSize` or larger can be formed.
    func bestBundle(
        for itemName: String,
        excluding: Set<String>,
        targetSize: Int = 3,
        maxSize: Int = 5,
        in context: ModelContext
    ) -> [String]? {
        let name = itemName.lowercased()
        let excludedLower = Set(excluding.map { $0.lowercased() })

        // Fetch all co-occurrence records once and build an in-memory graph
        let descriptor = FetchDescriptor<CoOccurrenceRecord>()
        guard let allRecords = try? context.fetch(descriptor) else { return nil }

        // Build pair-count map: "a|b" → count  (a ≤ b always)
        var pairCounts: [String: Int] = [:]
        for r in allRecords {
            pairCounts["\(r.itemA)|\(r.itemB)"] = r.count
        }

        func pairKey(_ a: String, _ b: String) -> String {
            let s = [a, b].sorted(); return "\(s[0])|\(s[1])"
        }
        func coOccurs(_ a: String, _ b: String) -> Bool {
            (pairCounts[pairKey(a, b)] ?? 0) >= 2
        }

        // Find trigger's co-occurrence records to score candidates
        let triggerRecords = allRecords.filter { $0.itemA == name || $0.itemB == name }
        guard !triggerRecords.isEmpty else { return nil }

        let now = Date()
        let maxCount = Double(triggerRecords.map(\.count).max() ?? 1)
        let candidates = triggerRecords
            .compactMap { r -> (partner: String, score: Double)? in
                let partner = r.itemA == name ? r.itemB : r.itemA
                guard !excludedLower.contains(partner) else { return nil }
                return (partner, scored(r.count, maxCount: maxCount, lastOccurredAt: r.lastOccurredAt, now: now))
            }
            .sorted { $0.score > $1.score }

        guard !candidates.isEmpty else { return nil }

        // Greedy clique expansion: add a candidate only if it co-occurs with every
        // item already in the bundle (minimum count of 2 to filter noise)
        var bundle = [name]
        for candidate in candidates.map(\.partner) {
            guard bundle.count < maxSize else { break }
            if bundle.allSatisfy({ coOccurs($0, candidate) }) {
                bundle.append(candidate)
            }
        }

        guard bundle.count >= targetSize else { return nil }

        // Suppress recently-ignored bundles
        let bundleID = bundle.sorted().joined(separator: "|")
        guard ignorePenalty(for: bundleID) > 0.1 else { return nil }

        return bundle.filter { $0 != name }
    }

    // MARK: - Ignore Tracking

    private let ignoredKey = "rec_ignoredSuggestions"

    /// Call when a suggestion is dismissed without being acted on.
    /// The pair/bundle will be score-penalised for the next 24 hours.
    func recordIgnored(suggestionID: String) {
        var store = loadIgnored()
        store[suggestionID] = Date().timeIntervalSince1970
        // Cap stored entries to prevent unbounded growth
        if store.count > 60 {
            let trimmed = store.sorted { $0.value < $1.value }.dropFirst(store.count - 60)
            store = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: ignoredKey)
        }
    }

    private func ignorePenalty(for suggestionID: String) -> Double {
        guard let ts = loadIgnored()[suggestionID] else { return 1.0 }
        let minutes = (Date().timeIntervalSince1970 - ts) / 60
        switch minutes {
        case ..<30:   return 0.05   // Strongly suppress for 30 min
        case ..<240:  return 0.35   // Moderate for 4 hours
        case ..<1440: return 0.65   // Light for 24 hours
        default:      return 1.0    // Expired — full score restored
        }
    }

    private func loadIgnored() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: ignoredKey),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return dict
    }

    // MARK: - Private

    private func scored(_ count: Int, maxCount: Double, lastOccurredAt: Date, now: Date) -> Double {
        let coScore = Double(count) / maxCount
        let daysSince = now.timeIntervalSince(lastOccurredAt) / 86_400
        let recency = exp(-daysSince / 30)
        return coScore * 0.7 + recency * 0.3
    }

    private func fetchOrCreateCoOccurrence(a: String, b: String, in context: ModelContext) -> CoOccurrenceRecord {
        let descriptor = FetchDescriptor<CoOccurrenceRecord>(
            predicate: #Predicate { $0.itemA == a && $0.itemB == b }
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let record = CoOccurrenceRecord(itemA: a, itemB: b)
        context.insert(record)
        return record
    }
}
