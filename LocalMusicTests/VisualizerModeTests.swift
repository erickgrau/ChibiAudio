import Foundation
import Testing
@testable import LocalMusic

@Suite("Visualizer modes")
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

    @Test func allCases_hasNineModes() {
        #expect(VisualizerMode.allCases.count == 9)
    }

    @Test func freeCore_isAlbumAndTrackArtOnly() {
        #expect(VisualizerMode.freeModes == [.albumArt, .trackArt])
        #expect(VisualizerMode.albumArt.requiresPlus == false)
        #expect(VisualizerMode.vuMeters.requiresPlus == true)
        #expect(VisualizerMode.vinyl.requiresPlus == true)
    }

    @Test func availableModes_gatesOnPlus() {
        #expect(VisualizerMode.availableModes(isPlusActive: false).count == 2)
        #expect(VisualizerMode.availableModes(isPlusActive: true).count == 9)
        #expect(VisualizerMode.clamped(.kaleidoscope, isPlusActive: false) == .albumArt)
        #expect(VisualizerMode.clamped(.kaleidoscope, isPlusActive: true) == .kaleidoscope)
    }
}

@Suite("VisualizerAudioAnalyzer")
struct VisualizerAudioAnalyzerTests {

    @Test func isLiveSource_fileURLsAreNotLive() {
        let fileURL = URL(fileURLWithPath: "/Library/Music/track.m4a")
        #expect(VisualizerAudioAnalyzer.isLiveSource(fileURL) == false)
    }

    @Test func isLiveSource_remoteURLsAreLive() {
        let radioURL = URL(string: "https://stream.example.com/radio.aac")!
        #expect(VisualizerAudioAnalyzer.isLiveSource(radioURL) == true)

        let httpURL = URL(string: "http://relay.example.net:8000/live.mp3")!
        #expect(VisualizerAudioAnalyzer.isLiveSource(httpURL) == true)
    }
}

@Suite("Cassette")
struct CassetteShapeTests {

    @Test func trapezoid_pathIsNonEmpty() {
        let shape = CustomShapeCassetteTrapezoid()
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 30))
        #expect(path.isEmpty == false)
        #expect(path.boundingRect.width > 0)
        #expect(path.boundingRect.height > 0)
    }

    @Test func trapezoid_narrowsTowardTop() {
        let shape = CustomShapeCassetteTrapezoid()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 30)
        let path = shape.path(in: rect)
        // Bottom corners lie inside the path...
        #expect(path.contains(CGPoint(x: 1, y: 29)))
        #expect(path.contains(CGPoint(x: 99, y: 29)))
        // ...while the top outer corners are cut away by the inset.
        #expect(path.contains(CGPoint(x: 1, y: 1)) == false)
        #expect(path.contains(CGPoint(x: 99, y: 1)) == false)
    }
}

@Suite("VisualizerFFT")
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
