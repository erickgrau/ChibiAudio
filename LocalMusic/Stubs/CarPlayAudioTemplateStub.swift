import Foundation

/// CarPlay Now Playing stub — Apple Audio templates only.
///
/// - Uses `CPNowPlayingTemplate` / system audio templates when a CarPlay entitlement
///   is added in Xcode Signing & Capabilities (not invented or bundled here).
/// - Maximizes Now Playing artwork on the car screen.
/// - Visualizers remain iPhone / iPad only — no custom dash canvas.
/// - Requires ChibiAudio Plus. Dist certificates are out of scope for this repo.
enum CarPlayAudioTemplateStub {
    static let requiresPlus = true
    static let usesAppleAudioTemplatesOnly = true
    static let customDashCanvas = false
    static let visualizersOnCarPlay = false

    static let featureTitle = "CarPlay Now Playing"
    static let featureDetail =
        "Large album art via Apple’s audio templates. Visualizers stay on your iPhone or iPad."

    /// Soft gate used by Settings / paywall — real `CPTemplateApplicationScene` wiring
    /// lands when the CarPlay entitlement is enabled on a developer account.
    static func isUnlocked(isPlusActive: Bool) -> Bool {
        requiresPlus ? isPlusActive : true
    }
}
