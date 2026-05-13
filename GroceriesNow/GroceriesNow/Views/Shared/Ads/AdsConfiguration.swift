import Foundation

/// Central toggle for ad visibility.
///
/// Set `hideForScreenshots = true` before capturing App Store screenshots
/// so no ad placements appear in any view. Flip back to `false` before
/// submitting to the App Store.
enum AdsConfiguration {
    static let hideForScreenshots = false
}
