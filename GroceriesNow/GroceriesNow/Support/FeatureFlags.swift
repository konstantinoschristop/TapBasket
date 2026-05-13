import Foundation

/// Central place for feature flags.
/// Flip a flag here — no other code needs to change.
/// During development the flag can also be toggled at runtime via the debug menu.
enum FeatureFlags {
    /// When `true`, the AI recipe button is shown in the toolbar.
    /// Set to `false` to hide the feature entirely (v1.0 launch).
    static var aiRecipeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "flag_aiRecipeEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "flag_aiRecipeEnabled") }
    }
}
