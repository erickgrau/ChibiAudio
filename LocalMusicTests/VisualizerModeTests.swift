import Foundation
import Testing
@testable import LocalMusic

@Suite("Visualizer Soft PASS")
struct VisualizerModeTests {

    @Test func loadPersisted_defaultsToAlbumArt() {
        UserDefaults.standard.removeObject(forKey: VisualizerMode.defaultsKey)
        #expect(VisualizerMode.loadPersisted() == .albumArt)
    }

    @Test func persist_roundTripsAllModes() {
        for mode in VisualizerMode.allCases {
            mode.persist()
            #expect(VisualizerMode.loadPersisted() == mode)
            #expect(UserDefaults.standard.string(forKey: VisualizerMode.defaultsKey) == mode.rawValue)
        }
        // Soft PASS default restore for other tests / app state.
        VisualizerMode.albumArt.persist()
    }

    @Test func needsAudioMetering_onlySpectrumFamily() {
        #expect(VisualizerMode.albumArt.needsAudioMetering == false)
        #expect(VisualizerMode.trackArt.needsAudioMetering == false)
        #expect(VisualizerMode.vinyl.needsAudioMetering == false)
        #expect(VisualizerMode.cassette.needsAudioMetering == false)

        #expect(VisualizerMode.vuMeters.needsAudioMetering == true)
        #expect(VisualizerMode.ledBar.needsAudioMetering == true)
        #expect(VisualizerMode.eqSpectrum.needsAudioMetering == true)
        #expect(VisualizerMode.kaleidoscope.needsAudioMetering == true)
        #expect(VisualizerMode.vectors.needsAudioMetering == true)
    }

    @Test func allCases_hasNineSoftPassModes() {
        #expect(VisualizerMode.allCases.count == 9)
    }
}

@Suite("VisualizerFFT Soft PASS")
struct VisualizerFFTTests {

    @Test func logBands_emptyInput_returnsZeros() {
        let bands = VisualizerFFT.logBands(from: [], bandCount: 8)
        #expect(bands.count == 8)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test func logBands_peakInHighBins_lightsUpperBands() {
        var mags = [Float](repeating: 0.01, count: 64)
        mags[50] = 1.0
        let bands = VisualizerFFT.logBands(from: mags, bandCount: 8)
        #expect(bands.count == 8)
        #expect(bands.last! > bands.first!)
    }

    @Test func decay_risesFastFallsSlow() {
        let current: [Float] = [0.2, 0.8]
        let target: [Float] = [1.0, 0.1]
        let next = VisualizerFFT.decay(current, toward: target, rise: 0.5, fall: 0.2)
        #expect(next[0] > current[0])
        #expect(next[1] < current[1])
        #expect(next[1] > target[1]) // not instantly to floor
    }

    @Test func waveform_downsamples() {
        let samples = (0..<1000).map { Float($0) / 1000 }
        let wave = VisualizerFFT.waveform(from: samples, count: 32)
        #expect(wave.count == 32)
    }

    @Test func beatEnergy_emphasizesLowBands() {
        var low = [Float](repeating: 0, count: 32)
        low[0] = 1
        low[1] = 1
        var high = [Float](repeating: 0, count: 32)
        high[30] = 1
        high[31] = 1
        #expect(VisualizerFFT.beatEnergy(from: low) > VisualizerFFT.beatEnergy(from: high))
    }
}
