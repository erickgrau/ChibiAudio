import Foundation

/// App version and build, read from the bundle (configured in project.yml).
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
    }

    static var buildInt: Int {
        Int(build) ?? 1
    }

    static var versionString: String {
        "v\(version) (\(build))"
    }
}

/// A single release note entry with motivations and key feature changes.
struct AppRelease: Identifiable, Sendable {
    var id: Int { build }
    let build: Int
    let version: String
    let date: String
    let headline: String
    /// Motivation for the release explaining why these changes were made.
    let why: String
    let changes: [ReleaseChange]

    init(
        build: Int,
        version: String,
        date: String,
        headline: String,
        why: String = "",
        changes: [ReleaseChange]
    ) {
        self.build = build
        self.version = version
        self.date = date
        self.headline = headline
        self.why = why
        self.changes = changes
    }
}

struct ReleaseChange: Identifiable, Sendable {
    var id: String { text }
    let icon: String // SF Symbol name
    let text: String
}

/// Release changelog, newest first.
let APP_RELEASES: [AppRelease] = [
    AppRelease(
        build: 91,
        version: "1.1.0",
        date: "September 25, 2026",
        headline: "Official Plex PIN Sign-In and Warm Cream Light Mode",
        why: "Sign in securely to your personal Plex music library with official PIN authentication and Keychain-guarded tokens. Enjoy a warm cream light mode by default alongside our signature dark aesthetic.",
        changes: [
            ReleaseChange(
                icon: "lock.shield",
                text: "Official Plex PIN authentication with Keychain token storage instead of plaintext queries."
            ),
            ReleaseChange(
                icon: "sun.max",
                text: "Adaptive appearance system with warm cream Light Mode as default, plus Dark and System options."
            ),
            ReleaseChange(
                icon: "server.rack",
                text: "Streamlined Plex server cards displaying connection status for LAN, Remote, and Relay."
            ),
            ReleaseChange(
                icon: "square.grid.2x2",
                text: "Rich album art grid for high-fidelity music browsing across your libraries."
            ),
            ReleaseChange(
                icon: "waveform",
                text: "Secure audio streaming passing authentication headers rather than query string tokens."
            )
        ]
    ),
    AppRelease(
        build: 89,
        version: "1.0.0",
        date: "September 20, 2026",
        headline: "Initial ChibiAudio Release",
        why: "High-fidelity offline music player with DAC support, bit-perfect playback, and local file management.",
        changes: [
            ReleaseChange(
                icon: "music.note",
                text: "Bit-perfect offline music playback for local and cloud folders."
            ),
            ReleaseChange(
                icon: "slider.horizontal.3",
                text: "THX Onyx DAC route support with equalizer controls."
            ),
            ReleaseChange(
                icon: "antenna.radiowaves.left.and.right",
                text: "Radio Browser and Bandcamp Subsonic collection streaming."
            )
        ]
    )
]

/// Tracks which release the user has seen and manages popup display.
enum WhatsNew {
    static let lastSeenKey = "chibiaudio.lastSeenBuild"

    static var unseen: [AppRelease] {
        let last = UserDefaults.standard.integer(forKey: lastSeenKey)
        return APP_RELEASES.filter { $0.build > last }.sorted { $0.build > $1.build }
    }

    static var hasUnseen: Bool {
        !unseen.isEmpty
    }

    static var all: [AppRelease] {
        APP_RELEASES.sorted { $0.build > $1.build }
    }

    static var latest: AppRelease {
        APP_RELEASES.max(by: { $0.build < $1.build }) ?? APP_RELEASES[0]
    }

    static func markSeen() {
        let targetBuild = max(AppInfo.buildInt, latest.build)
        UserDefaults.standard.set(targetBuild, forKey: lastSeenKey)
    }
}
