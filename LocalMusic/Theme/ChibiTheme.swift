import SwiftUI

/// Design tokens: **Onyx Dark** canvas + **Soft Glass** materials.
/// Accents are indicators only (amber = hi-res/PCM, teal = USB/DAC) — not a rainbow UI.
enum ChibiTheme {

    // MARK: - Canvas

    /// Near-black, not crushed OLED pure black.
    static let canvasDeep = Color(red: 0.039, green: 0.039, blue: 0.047)      // #0A0A0C
    static let canvasElevated = Color(red: 0.071, green: 0.071, blue: 0.078)  // #121214
    static let canvasMid = Color(red: 0.090, green: 0.090, blue: 0.098)       // #171719

    // MARK: - Accents (small indicators)

    /// Hi-res / PCM “LED” vibe.
    static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)            // #F5A623
    /// USB / DAC connected.
    static let teal = Color(red: 0.180, green: 0.769, blue: 0.714)             // #2EC4B6

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.10)

    // MARK: - Materials

    static var softGlass: Material { .ultraThinMaterial }
    static var softGlassThick: Material { .thinMaterial }

    // MARK: - Typography

    static func sampleRateFont() -> Font {
        .system(.caption, design: .monospaced).weight(.medium)
    }

    static func chipFont() -> Font {
        .system(.caption2, design: .rounded).weight(.semibold)
    }

    static func titleFont() -> Font {
        .system(.title3, design: .default).weight(.semibold)
    }

    static func heroTitleFont() -> Font {
        .system(.title2, design: .default).weight(.bold)
    }
}

// MARK: - Source identity (display only)

enum MediaSourceKind: String, Sendable {
    case onDevice
    case iCloud
    case drive
    case plex
    case radio
    case bandcamp
    case appleMusic

    var label: String {
        switch self {
        case .onDevice: return "On Device"
        case .iCloud: return "iCloud"
        case .drive: return "Drive"
        case .plex: return "Plex"
        case .radio: return "Radio"
        case .bandcamp: return "Bandcamp"
        case .appleMusic: return "Apple Music"
        }
    }

    /// Infer a chip from a playable URL / playlist entry (theming hook only).
    static func infer(from url: URL) -> MediaSourceKind {
        if !url.isFileURL {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            if host.contains("bandcamp") || path.contains("/api/subsonic") {
                return .bandcamp
            }
            if host.contains("plex") || path.contains("/library/metadata/") {
                return .plex
            }
            return .radio
        }
        let path = url.path.lowercased()
        if path.contains("mobile documents") || path.contains("icloud") || path.contains("com~apple~clouddocs") {
            return .iCloud
        }
        if path.contains("google") || path.contains("googledrive") || path.contains("drive") {
            return .drive
        }
        return .onDevice
    }

    static func infer(from entry: PlaylistSourceRef) -> MediaSourceKind {
        switch entry {
        case .localFile(let urlString, _):
            if let url = URL(string: urlString) { return infer(from: url) }
            return .onDevice
        case .stream(let urlString, _, _):
            if let url = URL(string: urlString) { return infer(from: url) }
            return .radio
        case .plex: return .plex
        case .appleMusic: return .appleMusic
        }
    }
}

// MARK: - View helpers

extension View {
    /// Root Onyx canvas + forced dark appearance (light optional later).
    func chibiCanvas() -> some View {
        self
            .preferredColorScheme(.dark)
            .background(ChibiTheme.canvasDeep.ignoresSafeArea())
    }

    func chibiGlassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(ChibiTheme.softGlass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
            )
    }

    func chibiListChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ChibiTheme.canvasDeep.ignoresSafeArea())
    }
}
