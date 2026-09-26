import SwiftUI

/// Onyx Dark + Soft Glass. Locked dark — no light/system variant.
/// Accents: amber = PCM/CTA, teal = connected/USB.
enum ChibiTheme {

    static let canvasDeep = Color(red: 0.039, green: 0.039, blue: 0.047)
    static let canvasElevated = Color(red: 0.071, green: 0.071, blue: 0.078)
    static let canvasMid = Color(red: 0.090, green: 0.090, blue: 0.098)
    static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)
    static let teal = Color(red: 0.180, green: 0.769, blue: 0.714)
    static let textPrimary = Color(white: 1).opacity(0.94)
    static let textSecondary = Color(white: 1).opacity(0.55)
    static let textTertiary = Color(white: 1).opacity(0.38)
    static let hairline = Color(white: 1).opacity(0.10)

    static var softGlass: Material { .ultraThinMaterial }
    static var softGlassThick: Material { .thinMaterial }

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

extension View {
    func chibiCanvas() -> some View {
        self
            .background(ChibiTheme.canvasDeep.ignoresSafeArea())
            .preferredColorScheme(.dark)
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
