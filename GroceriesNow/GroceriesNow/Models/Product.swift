import Foundation

/// One entry in the bundled grocery catalog.
///
/// Immutable, value-type reference data — the catalog is read-only at
/// runtime. User-created items live in SwiftData as `QuickItem`; the
/// catalog only feeds search autocompletion.
///
/// Decoded from `products.json` shipped in the app bundle.
struct Product: Codable, Sendable, Identifiable, Hashable {
    /// Canonical display name (English, title-case). Used as the stable
    /// identity for de-duplication against existing `QuickItem`s.
    let name: String
    /// Single representative emoji. Doesn't need to be unique — many
    /// products share the same emoji (all wines → 🍷).
    let emoji: String
    /// Raw value of `QuickItemCategory`. Stored as String here so the
    /// JSON stays decoupled from the Swift enum's compilation order
    /// and so future categories can be added without churning the
    /// catalog file. Note: bakery's raw value is `"more"` for legacy
    /// migration reasons — the JSON uses that raw value.
    let category: String
    /// Optional alternative names / abbreviations the user might type
    /// instead of the canonical name. Stored lowercase. Helps the
    /// search ranker prefer "PB" → "Peanut butter".
    let aliases: [String]?

    /// Stable identity for SwiftUI / Identifiable. Uses lowercased name
    /// so two entries with the same name (different casing) collide —
    /// the catalog file is expected to keep names unique.
    var id: String { name.lowercased() }

    /// Lowercased, diacritic-stripped form used for fast prefix /
    /// contains matching. Computed once per query, not stored, so the
    /// JSON stays compact.
    var searchKey: String {
        name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}
