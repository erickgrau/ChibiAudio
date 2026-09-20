import Foundation

/// Now Playing hero visualizer modes.
/// Persisted so the last choice survives relaunch.
/// Core art modes are free; spectrum / vinyl suite requires ChibiAudio Plus.
enum VisualizerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case albumArt
    case trackArt
    case vuMeters
    case ledBar
    case eqSpectrum
    case kaleidoscope
    case vectors
    case vinyl
    case cassette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albumArt: return "Album Art"
        case .trackArt: return "Track Art"
        case .vuMeters: return "VU Meters"
        case .ledBar: return "LED Bar"
        case .eqSpectrum: return "EQ Spectrum"
        case .kaleidoscope: return "Kaleidoscope"
        case .vectors: return "Vectors"
        case .vinyl: return "Vinyl"
        case .cassette: return "Mixtape"
        }
    }

    var systemImage: String {
        switch self {
        case .albumArt: return "square.stack.fill"
        case .trackArt: return "photo"
        case .vuMeters: return "gauge"
        case .ledBar: return "chart.bar.fill"
        case .eqSpectrum: return "waveform.path.ecg"
        case .kaleidoscope: return "sparkles"
        case .vectors: return "waveform.path"
        case .vinyl: return "opticaldisc"
        case .cassette: return "recordingtape"
        }
    }

    /// Modes that need FFT / level metering from the parallel analysis bus.
    var needsAudioMetering: Bool {
        switch self {
        case .vuMeters, .ledBar, .eqSpectrum, .kaleidoscope, .vectors:
            return true
        case .albumArt, .trackArt, .vinyl, .cassette:
            return false
        }
    }

    /// Free core visuals (album / track art). Everything else is Plus.
    var isFreeCore: Bool {
        switch self {
        case .albumArt, .trackArt: return true
        default: return false
        }
    }

    var requiresPlus: Bool { !isFreeCore }

    static var freeModes: [VisualizerMode] {
        allCases.filter(\.isFreeCore)
    }

    static var plusModes: [VisualizerMode] {
        allCases.filter(\.requiresPlus)
    }

    /// Modes the user may select given Plus entitlement.
    static func availableModes(isPlusActive: Bool) -> [VisualizerMode] {
        isPlusActive ? Array(allCases) : freeModes
    }

    /// Clamp a persisted / swiped mode into what the entitlement allows.
    static func clamped(_ mode: VisualizerMode, isPlusActive: Bool) -> VisualizerMode {
        if mode.requiresPlus && !isPlusActive { return .albumArt }
        return mode
    }

    static let defaultsKey = "nowPlayingVisualizerMode"

    static func loadPersisted() -> VisualizerMode {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = VisualizerMode(rawValue: raw) else {
            return .albumArt
        }
        return mode
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
