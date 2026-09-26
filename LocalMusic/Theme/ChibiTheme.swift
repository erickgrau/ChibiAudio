import SwiftUI

/// Semantic tokens. Light (cream) is default. Dark is Onyx.
/// Accents: amber = PCM/CTA, teal = connected/USB.
enum ChibiTheme {

    static var canvasDeep: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.039, blue: 0.047, alpha: 1)
                : UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1) // #F4F1EA
        })
    }

    static var canvasElevated: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
                : UIColor(red: 1.0, green: 0.988, blue: 0.969, alpha: 1) // #FFFcf7
        })
    }

    static var canvasMid: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.090, green: 0.090, blue: 0.098, alpha: 1)
                : UIColor(red: 0.910, green: 0.886, blue: 0.839, alpha: 1) // #E8E2D6
        })
    }

    static var amber: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.961, green: 0.651, blue: 0.137, alpha: 1)
                : UIColor(red: 0.769, green: 0.478, blue: 0.071, alpha: 1) // #C47A12
        })
    }

    static var teal: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: 0.180, green: 0.769, blue: 0.714, alpha: 1)
                : UIColor(red: 0.102, green: 0.561, blue: 0.525, alpha: 1) // #1A8F86
        })
    }

    static var textPrimary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.94)
                : UIColor(red: 0.102, green: 0.094, blue: 0.078, alpha: 1)
        })
    }

    static var textSecondary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.55)
                : UIColor(red: 0.361, green: 0.337, blue: 0.298, alpha: 1)
        })
    }

    static var textTertiary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.38)
                : UIColor(red: 0.361, green: 0.337, blue: 0.298, alpha: 0.7)
        })
    }

    static var hairline: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.08)
        })
    }

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
        self.background(ChibiTheme.canvasDeep.ignoresSafeArea())
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
