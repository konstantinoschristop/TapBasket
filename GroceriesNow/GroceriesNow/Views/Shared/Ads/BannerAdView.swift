import SwiftUI
import GoogleMobileAds

// MARK: - Ad unit ID

private enum AdUnit {
    /// AdMob banner unit ID. Format: "ca-app-pub-XXXX/YYYY".
    /// Fill this in before submitting to the App Store.
    static let banner = "ca-app-pub-5275868523622377/5805061870"
}

// MARK: - BannerAdView

/// Inline adaptive banner wrapped for SwiftUI.
///
/// Zero height until the ad resolves; expands smoothly once a creative is
/// ready. Pass a `@State var adHeight` from the parent and constrain the
/// view's frame to that value.
///
/// The container width is passed in explicitly to avoid the zero-width issue
/// that occurs when `UIScreen.main` is read inside a `LazyVStack` before the
/// cell has been laid out.
struct BannerAdView: UIViewRepresentable {

    /// Set to the banner's pixel height once the ad loads.
    /// Stays 0 on error so the parent collapses the reserved space.
    @Binding var adHeight: CGFloat
    /// Container width passed in from SwiftUI layout.
    let width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(adHeight: $adHeight)
    }

    func makeUIView(context: Context) -> BannerView {
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        let banner       = BannerView(adSize: adaptiveSize)
        banner.adUnitID  = AdUnit.banner
        banner.delegate  = context.coordinator
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        banner.load(Self.nonPersonalizedRequest())
        return banner
    }

    /// Build a GMA ad request that explicitly opts out of personalised
    /// ads. We don't request `NSUserTrackingUsageDescription` (no ATT
    /// prompt) and our `PrivacyInfo.xcprivacy` declares
    /// `NSPrivacyTracking: false`, so the SDK should already serve
    /// non-personalised creatives — this sets `npa = 1` as an
    /// explicit, defensive signal so the behaviour is locked in
    /// regardless of upstream SDK defaults.
    private static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding private var adHeight: CGFloat

        init(adHeight: Binding<CGFloat>) {
            _adHeight = adHeight
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            let height = bannerView.adSize.size.height
            DispatchQueue.main.async { self.adHeight = height }
        }

        func bannerView(_ bannerView: BannerView,
                        didFailToReceiveAdWithError error: Error) {
            DispatchQueue.main.async { self.adHeight = 0 }
        }
    }
}
