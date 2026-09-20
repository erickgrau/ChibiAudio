import Foundation

/// CarPlay stub — **Apple Audio templates only** (Erick lock).
///
/// Maximize system templates:
/// - `CPNowPlayingTemplate` with large Now Playing artwork
/// - `CPListTemplate` / browse for library sections
/// - Queue / up-next via the system Now Playing queue UI
///
/// Explicitly out of scope:
/// - Custom dash canvas
/// - Dash visualizers, vinyl, or cassette/mixtape on CarPlay
/// - Invented Dist certificates or CarPlay entitlements in this repo
///
/// The full visualizer suite stays on iPhone / iPad. Requires ChibiAudio Plus.
enum CarPlayAudioTemplateStub {
    static let requiresPlus = true
    static let usesAppleAudioTemplatesOnly = true
    static let customDashCanvas = false
    static let visualizersOnCarPlay = false
    static let supportsBrowseTemplate = true
    static let supportsQueueTemplate = true
    static let maximizeNowPlayingArtwork = true

    static let featureTitle = "CarPlay"
    static let featureDetail =
        "Apple Audio templates only: large Now Playing art, browse, and queue. Visualizers stay on your iPhone or iPad — no custom dash canvas."

    /// Soft gate used by Settings / paywall — real `CPTemplateApplicationScene` wiring
    /// lands when the CarPlay entitlement is enabled on a developer account.
    static func isUnlocked(isPlusActive: Bool) -> Bool {
        requiresPlus ? isPlusActive : true
    }
}
