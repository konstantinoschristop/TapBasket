import SwiftUI

/// Centralised animation tokens for the app.
///
/// Use these in place of ad-hoc `.spring(response: ..., dampingFraction: ...)`
/// values so the whole app shares a tempo. The naming describes the *feeling*,
/// not the values — pick the token that matches the interaction's intent.
///
/// Three tokens cover ~all of our needs:
/// * `.taplistTap` — instant feedback, press states, tile/row flashes.
/// * `.taplistTransition` — view appearance/dismissal, list updates, layout shifts.
/// * `.taplistCelebrate` — completion moments, badges that should feel rewarding.
///
/// All three respect `accessibilityReduceMotion` automatically when used inside
/// a SwiftUI `withAnimation` block — to fully disable motion, branch on
/// `@Environment(\.accessibilityReduceMotion)` at the call site, or use
/// `Animation.taplistOrNone(_:reduceMotion:)`.
extension Animation {
    /// Quick, snappy response for direct user input.
    /// ~220ms, light damping — feels immediate without being sloppy.
    static let taplistTap: Animation = .spring(response: 0.22, dampingFraction: 0.78)

    /// Standard transitions: views appearing, list re-orders, layout settling.
    /// Slower, well-damped — moves with intention, no overshoot worth noticing.
    static let taplistTransition: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    /// Celebratory bounce — completion overlays, success badges, post-add pulses.
    /// Lower damping = visible bounce; reserve for moments that should feel rewarding.
    static let taplistCelebrate: Animation = .spring(response: 0.30, dampingFraction: 0.55)

    /// Returns the token unchanged when motion is allowed, or a flat ease-out
    /// when reduce-motion is on. Use this for animations whose *value change*
    /// must still be communicated (e.g. fade in/out) but whose *bouncy spring*
    /// would feel disorienting under accessibilityReduceMotion.
    ///
    /// For decorative animations that can be skipped entirely (rings, pulses),
    /// branch on `reduceMotion` at the call site and skip the trigger.
    static func taplistOrNone(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.22) : animation
    }
}
