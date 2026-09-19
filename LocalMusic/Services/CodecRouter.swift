import Foundation

/// Where a file's audio is expected to be decoded for playback.
/// Prefer native AVFoundation for lossless/common lossy so we never
/// quality-kill with a needless transcode when iOS can play as-is.
enum PlayPath: String, Sendable, Equatable {
    /// AVFoundation plays it as-is (hi-res FLAC/ALAC/WAV/AIFF on modern iOS).
    case native
    /// No reliable native path (OGG/Opus/WavPack) without an external decoder.
    case needsDecode
    /// DSD containers — no native iOS input; DAC-side or PCM transcode.
    case dsd
}

/// Extension → play-path table. Pure Foundation — unit-testable without AVFoundation.
enum CodecRouter {

    /// Formats accepted into the local/cloud library scanner.
    static let libraryExtensions: Set<String> = [
        "flac", "alac", "wav", "aiff", "aif",
        "mp3", "m4a", "m4b", "aac", "mp4", "caf",
        "ogg", "oga", "opus", "wv",
        "dsf", "dff",
    ]

    static func playPath(for extensionName: String) -> PlayPath {
        switch extensionName.lowercased() {
        case "mp3", "aac", "m4a", "m4b", "alac", "wav", "aif", "aiff",
             "flac", "mp4", "caf", "3gp":
            return .native
        case "ogg", "oga", "opus", "wv":
            return .needsDecode
        case "dsf", "dff":
            return .dsd
        default:
            return .needsDecode
        }
    }

    static func playPath(forFileURL url: URL) -> PlayPath {
        playPath(for: url.pathExtension)
    }

    static func displayLabel(for path: PlayPath) -> String {
        switch path {
        case .native: return "Native PCM"
        case .needsDecode: return "Needs decode"
        case .dsd: return "DSD · DAC/transcode"
        }
    }
}
