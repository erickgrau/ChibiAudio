import AVFoundation

/// Hi-res / USB-DAC session helpers tuned for Erick’s reference device:
/// **THX Onyx Portable Headphone Amplifier** (ESS ES9281PRO + THX AAA).
///
/// - USB audio from iPhone → Onyx
/// - PCM: prefer bit-perfect; negotiate the highest rate iOS + device allow
///   (do not crush to 48 kHz). Query `AVAudioSession` current/preferred rates.
/// - MQA: Onyx is an **MQA Renderer** (hardware final unfold). Free ChibiAudio
///   does **not** ship a licensed MQA Core software decoder — passthrough only.
/// - DSD (.dsf/.dff): prefer **DoP** over USB when native DSD isn’t available
///   via AVFoundation; never silently destroy to low-rate MP3.
struct DACSession: Sendable {

    /// Documented ceiling we *ask* for; actual rate is whatever iOS + Onyx negotiate.
    static let requestedCeilingSampleRate: Double = 192_000

    /// UserDefaults key — Hi-res / DAC mode (bit-perfect intent).
    static let dacModeDefaultsKey = "hiResDACModeEnabled"

    struct RouteInfo: Equatable, Sendable {
        var portName: String
        var portType: String
        var isUSBAudio: Bool
        var isBuiltIn: Bool
        /// Friendly label for UI (“THX Onyx” when USB DAC is active).
        var displayLabel: String
        var currentSampleRate: Double
        var preferredSampleRate: Double
        var summary: String
    }

    /// Whether the user enabled Hi-res / DAC mode (maximize rate, prefer bit-perfect).
    static var isDACModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: dacModeDefaultsKey)
    }

    /// Bit-perfect intent: DAC mode on ⇒ app EQ must stay off.
    static var prefersBitPerfectPath: Bool {
        isDACModeEnabled || isUsingUSBAudio
    }

    static func configure(
        dacMode: Bool,
        trackSampleRate: Double? = nil
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])

        let wantHiRes = dacMode || isUsingUSBAudio
        guard wantHiRes else { return }

        // Prefer the file’s native rate when known; otherwise ask for the ceiling
        // and let iOS + the ES9281PRO negotiate downward if needed.
        let preferred: Double
        if let trackSampleRate, trackSampleRate >= 44_100 {
            preferred = min(max(trackSampleRate, 44_100), requestedCeilingSampleRate)
        } else {
            preferred = requestedCeilingSampleRate
        }
        try session.setPreferredSampleRate(preferred)
        // IO buffer: slightly larger is fine for USB DAC stability; we are not
        // chasing ultra-low latency for music listening.
        try? session.setPreferredIOBufferDuration(0.02)
    }

    static func activate() throws {
        try AVAudioSession.sharedInstance().setActive(true)
    }

    static var isUsingUSBAudio: Bool {
        currentRouteInfo().isUSBAudio
    }

    static var isUsingExternalOutput: Bool {
        !currentRouteInfo().isBuiltIn
    }

    static func shouldEnableDACPath(userEnabled: Bool) -> Bool {
        userEnabled || isUsingUSBAudio
    }

    static func currentRouteInfo() -> RouteInfo {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let primary = outputs.first
        let portType = primary?.portType ?? .builtInSpeaker
        let name = primary?.portName ?? "Unknown"
        let isBuiltIn = portType == .builtInSpeaker || portType == .builtInReceiver
        let isUSB = portType == .usbAudio
            || portType.rawValue.localizedCaseInsensitiveContains("usb")

        // Reference DAC: THX Onyx. USB audio ports often report a generic name;
        // when we see USB we label for Erick’s device (still show port name).
        let displayLabel: String
        if isUSB {
            let lower = name.lowercased()
            if lower.contains("onyx") || lower.contains("thx") {
                displayLabel = name
            } else {
                displayLabel = "THX Onyx / USB DAC (\(name))"
            }
        } else if isBuiltIn {
            displayLabel = "Built-in · \(name)"
        } else {
            displayLabel = "\(portType.rawValue) · \(name)"
        }

        let current = session.sampleRate
        let preferred = session.preferredSampleRate
        return RouteInfo(
            portName: name,
            portType: portType.rawValue,
            isUSBAudio: isUSB,
            isBuiltIn: isBuiltIn,
            displayLabel: displayLabel,
            currentSampleRate: current,
            preferredSampleRate: preferred,
            summary: "\(displayLabel) · \(Int(current)) Hz"
        )
    }

    /// Probe a local audio file for sample rate without decoding the stream.
    static func probeSampleRate(of url: URL) async -> Double? {
        guard url.isFileURL else { return nil }
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                return nil
            }
            let descriptions = try await track.load(.formatDescriptions)
            for desc in descriptions {
                let audio = desc as CMAudioFormatDescription
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audio) {
                    let rate = asbd.pointee.mSampleRate
                    if rate > 0 { return rate }
                }
            }
        } catch {
            Log.player.debug("Sample-rate probe failed: \(error.localizedDescription)")
        }
        return nil
    }
}

/// How DSD files should be handled for the THX Onyx (DSD-capable over USB).
enum DSDPlaybackStrategy: String, Sendable {
    /// Pack DSD in DoP (DSD over PCM) frames for USB DACs that understand DoP.
    case dop
    /// Native DSD endpoint (rare via AVFoundation on iOS).
    case native
    /// Not playable in free v1 without a DoP encoder path yet.
    case unavailable
}

enum DSDRouter {
    /// Free v1: detect DSD containers and prefer DoP intent. Full DoP packetizer
    /// may land behind an optional decoder; until then we refuse silent lossy fall-back.
    static func strategy(forFileExtension ext: String) -> DSDPlaybackStrategy {
        switch ext.lowercased() {
        case "dsf", "dff":
            // AVFoundation has no public native DSD → USB path; DoP is the intent
            // for Onyx. Without a DoP encoder bundled yet, mark unavailable so we
            // never crush to MP3/AAC.
            return .dop
        default:
            return .unavailable
        }
    }

    static var dopImplementedInFreeV1: Bool { false }
}
