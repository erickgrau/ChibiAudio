import Foundation

/// Apple Watch companion stub — Plus unlocks the companion path.
///
/// No Watch app target or Dist certs are invented here. This documents the
/// Plus-gated surface and provides copy for Settings / paywall.
enum WatchCompanionStub {
    static let requiresPlus = true
    static let featureTitle = "Apple Watch"
    static let featureDetail =
        "Companion playback controls for a future Watch app. Unlocked with ChibiAudio Plus."

    static func isUnlocked(isPlusActive: Bool) -> Bool {
        requiresPlus ? isPlusActive : true
    }
}
