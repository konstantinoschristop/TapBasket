import Foundation

/// Central place for feature flags.
/// Flip a flag here — no other code needs to change.
enum FeatureFlags {
    /// When `true`, the AI recipe feature requires a Pro purchase.
    /// When `false`, it is free for everyone (paywall UI is never shown).
    static let aiRecipeRequiresPro: Bool = true
}
