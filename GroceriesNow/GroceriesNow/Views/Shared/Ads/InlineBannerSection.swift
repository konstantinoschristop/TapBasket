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
        VStack(alignment: .leading, spacing: 6) {
            // Tiny "Sponsored" cue — keeps the ad clearly labeled
            // without leaning on the loud divider treatment we used
            // to bracket the banner with.
            Text("ads.sponsored")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.leading, 4)

            ZStack {
                // Loading placeholder — calm warm wash, no jittery
                // fade-in when the real ad arrives.
                if adHeight == 0 {
                    Color("CardBackground")
                        .overlay {
                            Text("ads.placeholder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                }

                BannerAdView(adHeight: $adHeight, width: resolvedWidth)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: max(adHeight, placeholderHeight))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
            }
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
