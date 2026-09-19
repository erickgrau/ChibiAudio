import AVFoundation
import Foundation

/// 10-band graphic EQ + presets. Processing runs in float PCM when engaged.
///
/// **Bit-perfect / DAC mode:** when Hi-res/DAC mode is on (or a USB DAC like
/// the THX Onyx is the route), EQ is forced off so the path to the ES9281PRO
/// stays clean. Documented in README Hardware section.
@Observable
@MainActor
final class EqualizerController {

    static let shared = EqualizerController()

    static let bandFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    struct Preset: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        /// Gain per band in dB (−12…+12).
        let gains: [Float]
    }

    static let presets: [Preset] = [
        Preset(id: "flat", name: "Flat", gains: Array(repeating: 0, count: 10)),
        Preset(id: "bass", name: "Bass Boost", gains: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]),
        Preset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        Preset(id: "treble", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        Preset(id: "electronic", name: "Electronic", gains: [4, 3, 0, -2, -1, 0, 2, 3, 4, 4]),
    ]

    private static let gainsKey = "eqBandGains"
    private static let enabledKey = "eqEnabled"
    private static let presetKey = "eqPresetID"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            rebuildUnitIfNeeded()
        }
    }

    var gains: [Float] {
        didSet {
            UserDefaults.standard.set(gains.map { Double($0) }, forKey: Self.gainsKey)
            applyGainsToUnit()
        }
    }

    var activePresetID: String {
        didSet { UserDefaults.standard.set(activePresetID, forKey: Self.presetKey) }
    }

    /// True when DAC / bit-perfect mode forbids EQ.
    var isForcedOffForBitPerfect: Bool {
        DACSession.prefersBitPerfectPath
    }

    /// Effective: user wants EQ **and** bit-perfect path is not forcing it off.
    var isEffectivelyActive: Bool {
        isEnabled && !isForcedOffForBitPerfect && gains.contains(where: { abs($0) > 0.01 })
    }

    @ObservationIgnored private var eqUnit: AVAudioUnitEQ?

    private init() {
        let storedGains = UserDefaults.standard.array(forKey: Self.gainsKey) as? [Double]
        if let storedGains, storedGains.count == Self.bandFrequencies.count {
            gains = storedGains.map { Float($0) }
        } else {
            gains = Array(repeating: 0, count: Self.bandFrequencies.count)
        }
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        activePresetID = UserDefaults.standard.string(forKey: Self.presetKey) ?? "flat"
    }

    func applyPreset(_ preset: Preset) {
        activePresetID = preset.id
        gains = preset.gains
        if preset.id != "flat" {
            isEnabled = true
        }
    }

    func saveCustomPresetName() -> String { "Custom" }

    /// Attach EQ into an `AVAudioEngine` graph when effectively active.
    /// Returns nil when EQ must stay out of the path (Flat or DAC bit-perfect).
    func audioUnit() -> AVAudioUnitEQ? {
        guard isEffectivelyActive else { return nil }
        if eqUnit == nil {
            let unit = AVAudioUnitEQ(numberOfBands: Self.bandFrequencies.count)
            for (i, freq) in Self.bandFrequencies.enumerated() {
                let band = unit.bands[i]
                band.filterType = .parametric
                band.frequency = freq
                band.bandwidth = 1.0
                band.bypass = false
            }
            eqUnit = unit
            applyGainsToUnit()
        }
        return eqUnit
    }

    func noteDACModeChanged() {
        // Force observation updates for Settings / EQ views.
        if isForcedOffForBitPerfect, isEnabled {
            Log.player.info("EQ bypassed — Hi-res/DAC bit-perfect path (THX Onyx)")
        }
        rebuildUnitIfNeeded()
    }

    private func rebuildUnitIfNeeded() {
        if !isEffectivelyActive {
            eqUnit = nil
        } else {
            _ = audioUnit()
        }
    }

    private func applyGainsToUnit() {
        guard let eqUnit else { return }
        for i in 0..<min(gains.count, eqUnit.bands.count) {
            eqUnit.bands[i].gain = max(-12, min(12, gains[i]))
        }
    }
}
