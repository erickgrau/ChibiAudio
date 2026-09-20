import Foundation

/// Locked App Store / home-screen branding for ChibiAudio.
enum AppBranding {
    /// Home-screen and SpringBoard name.
    static let displayName = "ChibiAudio"
    /// App Store Connect subtitle (30 characters max).
    static let appStoreSubtitle = "Offline HiFi Player"
    /// Bundle identifier — do not change without a coordinated App Store migrate.
    static let bundleIdentifier = "com.chibitek.ChibiAudio"
    /// StoreKit Plus monthly product.
    static let plusMonthlyProductID = "com.chibitek.ChibiAudio.plus.monthly"

    /// One-line marketing blurb for About / empty states.
    static let tagline = "\(displayName) — \(appStoreSubtitle)"
}
