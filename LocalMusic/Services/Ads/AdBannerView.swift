import SwiftUI

/// Free-tier banner ads. Never placed over Now Playing, DAC chrome, or the visualizer hero.
///
/// When `ADMOB_APP_ID` / `GADApplicationIdentifier` is empty (CI / local default),
/// this is a complete no-op so builds and tests never need AdMob credentials or the SDK.
/// Real Google Mobile Ads load only when the SDK is linked **and** an app ID is set.
struct AdBannerView: View {
    @Environment(PlusStore.self) private var plus

    var body: some View {
        Group {
            if AdMobConfig.shouldShowBanner(isPlusActive: plus.isPlusActive) {
                bannerContent
            }
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
#if canImport(GoogleMobileAds)
        GoogleAdBannerRepresentable()
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(ChibiTheme.canvasElevated)
#else
        // SDK not linked — still respect the “configured” path with a reserved
        // slot so layout can be verified without pulling AdMob into CI.
        Color.clear
            .frame(height: 0)
            .accessibilityHidden(true)
#endif
    }
}

enum AdMobConfig {
    /// Info.plist `GADApplicationIdentifier`, or process env `ADMOB_APP_ID`.
    static var appID: String {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
           !plist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let env = ProcessInfo.processInfo.environment["ADMOB_APP_ID"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static var isConfigured: Bool { !appID.isEmpty }

    static func shouldShowBanner(isPlusActive: Bool) -> Bool {
        !isPlusActive && isConfigured
    }

    /// Call once at launch. No-ops when unconfigured or SDK absent.
    static func configureIfNeeded() {
        guard isConfigured else {
            Log.ui.debug("AdMob skipped — ADMOB_APP_ID / GADApplicationIdentifier empty")
            return
        }
#if canImport(GoogleMobileAds)
        // Import is optional; production App Store builds that link the SDK
        // should set GADApplicationIdentifier in Info.plist.
        GoogleMobileAds.MobileAds.shared.start(completionHandler: nil)
        Log.ui.info("AdMob started")
#else
        Log.ui.warning("ADMOB_APP_ID set but GoogleMobileAds is not linked — ads remain no-op")
#endif
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit

private struct GoogleAdBannerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = Bundle.main.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String
            ?? "ca-app-pub-3940256099942544/2934735716" // Google sample banner
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
#endif

// MARK: - Tab chrome (ads + mini player)

/// Banner above the mini player on browsing tabs. Never used on Now Playing.
struct AdAwareMiniPlayerModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(PlusStore.self) private var plus
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if AdMobConfig.shouldShowBanner(isPlusActive: plus.isPlusActive) {
                    AdBannerView()
                }
                if player.currentTrack != nil {
                    MiniPlayerView(onTap: onTap)
                }
            }
        }
    }
}

extension View {
    /// Mini player with optional free-tier ad banner (not for Now Playing).
    func adAwareMiniPlayer(onTap: @escaping () -> Void) -> some View {
        modifier(AdAwareMiniPlayerModifier(onTap: onTap))
    }
}
