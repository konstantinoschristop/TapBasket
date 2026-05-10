import SwiftUI
import UIKit

/// Self-contained inline adaptive banner row.
///
/// Reserves a 50 pt loading placeholder until the ad resolves — this
/// guarantees the row is laid out by the enclosing `List`/`LazyVStack`
/// (a zero-size row can be skipped by the lazy system) and that the
/// `GeometryReader` fires with a real width on the first pass.
///
/// Once the ad resolves the row animates to the actual banner height.
/// On failure it stays at the placeholder height so the UI doesn't jump —
/// Google often retries silently and the slot stays ready.
struct InlineBannerSection: View {

    private let placeholderHeight: CGFloat = 50

    @State private var adHeight: CGFloat       = 0
    @State private var containerWidth: CGFloat = 0

    /// Width of the key window — fallback when `GeometryReader` reports 0
    /// (e.g. when this view is laid out before the surrounding scroll
    /// container has propagated a width down to it).
    private var fallbackWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .bounds.width ?? 320
    }

    private var resolvedWidth: CGFloat {
        containerWidth > 0 ? containerWidth : fallbackWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.25)

            ZStack {
                // Loading placeholder — visible until the ad resolves.
                if adHeight == 0 {
                    Color(.tertiarySystemFill)
                        .opacity(0.15)
                        .overlay {
                            Text("Ad")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                }

                BannerAdView(adHeight: $adHeight, width: resolvedWidth)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: max(adHeight, placeholderHeight))
            .clipped()

            Divider().opacity(0.25)
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: BannerWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(BannerWidthKey.self) { containerWidth = $0 }
        .animation(.easeInOut(duration: 0.35), value: adHeight)
    }
}

// MARK: - Preference key

private struct BannerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
