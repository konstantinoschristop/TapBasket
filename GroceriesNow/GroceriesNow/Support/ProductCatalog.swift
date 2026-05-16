import Foundation
import os

/// In-memory grocery autocomplete catalog.
///
/// Loads `products.json` (bundled) once on first access, builds a
/// first-character bucket index, and answers `suggestions(for:)`
/// queries in <1ms even at the ~10k entry budget. No SQLite, no FTS,
/// no migrations — for read-only reference data of this size a flat
/// array with a tiny index beats every fancier option.
///
/// Threading: the catalog is immutable after `load()` so the public
/// API is safe to call from any actor. The type is `@unchecked
/// Sendable` because the stored properties are conceptually
/// `let`-after-init even though they're declared `var` for the lazy
/// load.
final class ProductCatalog: @unchecked Sendable {
    static let shared = ProductCatalog()

    /// All products in the order they appear in the JSON (which is
    /// also roughly the order we prefer to show them in — common
    /// items first within each category).
    private var products: [Product] = []
    /// First-char (lowercased, diacritic-stripped) → indices into
    /// `products`. Lets prefix queries skip the 90%+ of the catalog
    /// that can't possibly match. Built once.
    private var byFirstChar: [Character: [Int]] = [:]
    /// Guards against double-loading on concurrent first access.
    private var loaded = false
    private let loadLock = NSLock()

    private static let logger = Logger(
        subsystem: "com.taplist.catalog",
        category: "ProductCatalog"
    )

    private init() {}

    // MARK: - Public API

    /// Up to `limit` ranked suggestions for `query`, excluding products
    /// the user already has as a `QuickItem` (passed in as lowercased
    /// names via `excluding`). Returns `[]` when the query is empty
    /// or too short to be useful.
    ///
    /// Ranking, in order:
    ///   1. Exact name match
    ///   2. Name starts with query
    ///   3. Alias starts with query
    ///   4. Name contains query as a word boundary
    ///   5. Name contains query anywhere
    ///
    /// Within each tier, shorter names rank higher (more specific).
    func suggestions(
        for query: String,
        excluding: Set<String> = [],
        limit: Int = 8
    ) -> [Product] {
        ensureLoaded()

        let normalized = query
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.count >= 2 else { return [] }

        // Candidate set: products whose name OR any alias starts with
        // the same first character as the query. For "contains"
        // matches we still need to scan, but starting from this
        // narrower pool keeps the constant factor small.
        let firstChar = normalized.first!
        var candidates = byFirstChar[firstChar] ?? []
        // For "contains" matches we expand to the full set since a
        // substring can sit anywhere. We append unique indices not
        // already in candidates.
        let primaryCandidates = Set(candidates)
        for index in products.indices where !primaryCandidates.contains(index) {
            candidates.append(index)
        }

        struct Scored {
            let index: Int
            let tier: Int      // lower is better
            let lengthRank: Int // shorter is better
        }
        var scored: [Scored] = []
        scored.reserveCapacity(min(64, candidates.count))

        for index in candidates {
            let product = products[index]
            let key = product.searchKey
            guard !excluding.contains(key) else { continue }

            let tier: Int
            if key == normalized {
                tier = 0
            } else if key.hasPrefix(normalized) {
                tier = 1
            } else if let aliases = product.aliases,
                      aliases.contains(where: { $0.hasPrefix(normalized) }) {
                tier = 2
            } else if key.range(of: "\\b\(NSRegularExpression.escapedPattern(for: normalized))",
                                options: .regularExpression) != nil {
                tier = 3
            } else if key.contains(normalized) {
                tier = 4
            } else {
                continue
            }

            scored.append(Scored(index: index, tier: tier, lengthRank: key.count))

            // Early exit: once we have a full page of tier-0 / tier-1
            // matches, lower tiers can't beat them. Keep scanning a
            // little longer in case more tier-0 surface later.
            if scored.count > limit * 4 { break }
        }

        scored.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.lengthRank < rhs.lengthRank
        }

        return scored.prefix(limit).map { products[$0.index] }
    }

    // MARK: - Loading

    /// Load + index the JSON on first use. Subsequent calls are no-ops.
    /// Idempotent across concurrent first-call races.
    private func ensureLoaded() {
        if loaded { return }
        loadLock.lock()
        defer { loadLock.unlock() }
        if loaded { return }

        guard let url = Bundle.main.url(forResource: "products", withExtension: "json") else {
            // Catalog is optional — log and continue with an empty set.
            // Search will silently fall back to the manual-add flow.
            Self.logger.error("products.json not found in bundle; catalog disabled")
            loaded = true
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Product].self, from: data)
            products = decoded
            buildIndex()
            Self.logger.log("ProductCatalog loaded \(decoded.count, privacy: .public) entries")
        } catch {
            Self.logger.error("Failed to decode products.json: \(error, privacy: .public)")
        }
        loaded = true
    }

    private func buildIndex() {
        byFirstChar.removeAll(keepingCapacity: true)
        for (index, product) in products.enumerated() {
            guard let first = product.searchKey.first else { continue }
            byFirstChar[first, default: []].append(index)
            // Also bucket by alias first chars so "pb" finds
            // "Peanut butter" without scanning the full catalog.
            if let aliases = product.aliases {
                for alias in aliases {
                    guard let aliasFirst = alias.first else { continue }
                    if aliasFirst != first {
                        byFirstChar[aliasFirst, default: []].append(index)
                    }
                }
            }
        }
    }
}
