import Accelerate
import AVFoundation
import Foundation
import MediaToolbox
import Observation

/// Soft PASS visualizer metering from a **parallel muted AVPlayer** bus.
///
/// The main bit-perfect DAC playback path (`AudioPlayerManager`’s AVPlayer) is
/// never given an audio mix, EQ, or tap. Analysis runs only on this muted twin
/// so USB / Hi-res Soft PASS stays clean.
@Observable
@MainActor
final class VisualizerAudioAnalyzer {

    static let shared = VisualizerAudioAnalyzer()

    /// Log-spaced spectrum bands (0…1), Soft PASS LED / EQ / kaleidoscope.
    private(set) var spectrum: [Float] = Array(repeating: 0, count: VisualizerFFT.bandCount)
    /// Left / right channel levels (0…1) for VU Soft PASS.
    private(set) var leftLevel: Float = 0
    private(set) var rightLevel: Float = 0
    /// Oscilloscope strip (−1…1).
    private(set) var waveform: [Float] = Array(repeating: 0, count: VisualizerFFT.waveformSampleCount)
    /// Beat / bass pulse 0…1.
    private(set) var beatEnergy: Float = 0
    /// True while the parallel analysis player is running.
    private(set) var isMetering: Bool = false

    @ObservationIgnored private var analysisPlayer: AVPlayer?
    @ObservationIgnored private var analysisItem: AVPlayerItem?
    @ObservationIgnored private var tapBridge: TapBridge?
    @ObservationIgnored private var audioTap: MTAudioProcessingTap?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var meteringDesired = false
    @ObservationIgnored private var trackedURL: URL?
    @ObservationIgnored private var mainIsPlaying = false
    /// Live-source mode Soft PASS: instead of a second network connection,
    /// we attach a passthrough tap to the main player's own item.
    @ObservationIgnored private var liveTapItem: AVPlayerItem?
    @ObservationIgnored private var liveTap: MTAudioProcessingTap?

    /// Nonisolated ring buffer: audio tap writes, MainActor publish loop reads.
    /// Keeps pending meters + `NSLock` off `@MainActor` / async contexts.
    @ObservationIgnored private let pendingMeters = PendingMeterBuffer()

    private init() {}

    /// Enable or disable metering Soft PASS (spectrum modes only).
    func setMeteringEnabled(_ enabled: Bool) {
        meteringDesired = enabled
        if enabled {
            startPublishing()
            if let url = trackedURL {
                ensureAnalysisPlayer(url: url)
                syncPlaybackState()
            }
        } else {
            tearDownAnalysisPlayer()
            removeLiveTap()
            decayToIdle()
        }
    }

    /// Keep the parallel bus aligned with the main Soft PASS player.
    func sync(trackURL: URL?, isPlaying: Bool, currentTime: Double) {
        mainIsPlaying = isPlaying
        let urlChanged = trackURL != trackedURL
        trackedURL = trackURL

        guard meteringDesired else {
            if !isPlaying { decayToIdle() }
            return
        }

        guard let trackURL else {
            tearDownAnalysisPlayer()
            decayToIdle()
            return
        }

        // Live sources (radio / remote streams) can't be seek-synced on a
        // second connection: attach a passthrough tap to the main item instead.
        if Self.isLiveSource(trackURL) {
            tearDownAnalysisPlayer()
            guard let item = liveItemProvider?() else {
                removeLiveTap()
                decayToIdle()
                return
            }
            installLiveTap(on: item)
            return
        }

        removeLiveTap()
        if urlChanged {
            ensureAnalysisPlayer(url: trackURL)
        }
        syncPlaybackState(seekHint: currentTime)
    }

    /// Non-file URLs (radio / remote streams) need the passthrough tap path:
    /// a live stream cannot be seek-synced onto a parallel analysis player.
    nonisolated static func isLiveSource(_ url: URL) -> Bool {
        !url.isFileURL
    }

    /// Provides the main player's current item for live-source metering.
    /// Set by `AudioPlayerManager` at init; a parallel muted AVPlayer is not
    /// opened for network streams (a live URL cannot be seek-synced).
    @ObservationIgnored var liveItemProvider: (() -> AVPlayerItem?)?

    func teardown() {
        meteringDesired = false
        tearDownAnalysisPlayer()
        removeLiveTap()
        publishTask?.cancel()
        publishTask = nil
        syncTask?.cancel()
        syncTask = nil
        decayToIdle()
    }

    // MARK: - Parallel player Soft PASS

    private func ensureAnalysisPlayer(url: URL) {
        tearDownAnalysisPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false

        analysisPlayer = player
        analysisItem = item
        isMetering = true

        Task { [weak self] in
            await self?.installTap(on: item, forLiveSource: false)
        }
    }

    private func tearDownAnalysisPlayer() {
        syncTask?.cancel()
        syncTask = nil
        if let item = analysisItem {
            item.audioMix = nil
        }
        analysisPlayer?.pause()
        analysisPlayer?.replaceCurrentItem(with: nil)
        analysisPlayer = nil
        analysisItem = nil
        tapBridge = nil
        audioTap = nil
        isMetering = false
    }

    private func syncPlaybackState(seekHint: Double? = nil) {
        guard let analysisPlayer else { return }

        if let seekHint, seekHint >= 0, !seekHint.isNaN {
            let t = CMTime(seconds: seekHint, preferredTimescale: 600)
            let current = CMTimeGetSeconds(analysisPlayer.currentTime())
            if current.isNaN || abs(current - seekHint) > 0.45 {
                analysisPlayer.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        if mainIsPlaying {
            if analysisPlayer.rate == 0 {
                analysisPlayer.play()
            }
        } else {
            analysisPlayer.pause()
        }

        // Soft resync loop Soft PASS — start once while playing, don’t thrash.
        if mainIsPlaying {
            if syncTask == nil {
                syncTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard let self, self.meteringDesired, self.mainIsPlaying else { return }
                        if self.analysisPlayer?.rate == 0 {
                            self.analysisPlayer?.play()
                        }
                    }
                }
            }
        } else {
            syncTask?.cancel()
            syncTask = nil
        }
    }

    private func installTap(on item: AVPlayerItem, forLiveSource: Bool) async {
        let asset = item.asset
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            Log.player.debug("Visualizer tap: no audio tracks — \(error.localizedDescription)")
            return
        }
        guard let audioTrack = tracks.first else { return }
        guard itemStillTracked(item, live: forLiveSource) else { return }

        // Capture the nonisolated buffer — not `self` — so the @Sendable
        // tap handler never touches MainActor-isolated state.
        let pending = pendingMeters
        let bridge = TapBridge { spectrum, left, right, wave, beat in
            pending.write(spectrum: spectrum, left: left, right: right, wave: wave, beat: beat)
        }
        tapBridge = bridge

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(bridge).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { _, _, _ in },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                var frames = numberFrames
                // MTAudioProcessingTapFlags is a UInt32 typealias (not OptionSet)
                // on current SDKs — `[]` fails as `[Any]` → UInt32.
                var flags: MTAudioProcessingTapFlags = 0
                MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferListInOut,
                    &flags,
                    nil,
                    &frames
                )
                numberFramesOut.pointee = frames
                flagsOut.pointee = flags

                let storage = MTAudioProcessingTapGetStorage(tap)
                let bridge = Unmanaged<TapBridge>.fromOpaque(storage).takeUnretainedValue()
                bridge.consume(bufferList: bufferListInOut, frameCount: Int(frames))
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Log.player.debug("Visualizer tap create failed: \(status)")
            return
        }

        let params = AVMutableAudioMixInputParameters(track: audioTrack)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]

        await MainActor.run {
            guard self.itemStillTracked(item, live: forLiveSource) else { return }
            if forLiveSource {
                self.liveTapItem = item
                self.liveTap = tap
            } else {
                self.audioTap = tap
            }
            item.audioMix = mix
        }
    }

    /// Whether `item` is still the one we should be tapping after the async
    /// tap setup (tracks can load while the player moves on to another item).
    private func itemStillTracked(_ item: AVPlayerItem, live: Bool) -> Bool {
        live ? liveTapItem === item : analysisItem === item
    }

    /// Attach a passthrough metering tap to the main player's current item
    /// for live sources (radio / remote streams). The tap only reads frames —
    /// audio reaching the output is bit-identical to the un-tapped path, and
    /// no second network connection is opened.
    private func installLiveTap(on item: AVPlayerItem) {
        guard liveTapItem !== item else { return } // already tapping this item
        removeLiveTap()
        liveTapItem = item
        Task { [weak self] in
            await self?.installTap(on: item, forLiveSource: true)
        }
    }

    private func removeLiveTap() {
        if let item = liveTapItem {
            item.audioMix = nil
        }
        liveTap = nil
        liveTapItem = nil
    }

    private func startPublishing() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Lock lives inside PendingMeterBuffer (nonisolated), not here —
                // NSLock.lock/unlock are unavailable from async contexts.
                let snap = self.pendingMeters.snapshot()
                let nextSpectrum = VisualizerFFT.decay(self.spectrum, toward: snap.spectrum)
                let nextLeft = self.spectrumSmooth(self.leftLevel, toward: snap.left)
                let nextRight = self.spectrumSmooth(self.rightLevel, toward: snap.right)
                let nextWave = snap.wave
                let nextBeat = self.spectrumSmooth(self.beatEnergy, toward: snap.beat, rise: 0.7, fall: 0.25)

                self.spectrum = nextSpectrum
                self.leftLevel = nextLeft
                self.rightLevel = nextRight
                self.waveform = nextWave
                self.beatEnergy = nextBeat

                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 fps Soft PASS
            }
        }
    }

    private func spectrumSmooth(_ current: Float, toward target: Float, rise: Float = 0.5, fall: Float = 0.2) -> Float {
        if target >= current {
            return current + (target - current) * rise
        }
        return max(0, current - (current - target) * fall)
    }

    private func decayToIdle() {
        spectrum = Array(repeating: 0, count: VisualizerFFT.bandCount)
        leftLevel = 0
        rightLevel = 0
        waveform = Array(repeating: 0, count: VisualizerFFT.waveformSampleCount)
        beatEnergy = 0
        pendingMeters.reset()
    }
}

// MARK: - Pending meter buffer (tap thread ↔ MainActor)

/// Thread-safe pending Soft PASS meter samples. Written from the audio
/// render thread via `TapBridge`, read from the MainActor publish loop.
/// Owns its own `NSLock` so locking never happens on `@MainActor` state
/// or inside an `async` function body.
private final class PendingMeterBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var spectrum = [Float](repeating: 0, count: VisualizerFFT.bandCount)
    private var left: Float = 0
    private var right: Float = 0
    private var wave = [Float](repeating: 0, count: VisualizerFFT.waveformSampleCount)
    private var beat: Float = 0

    func write(spectrum: [Float], left: Float, right: Float, wave: [Float], beat: Float) {
        lock.lock()
        self.spectrum = spectrum
        self.left = left
        self.right = right
        self.wave = wave
        self.beat = beat
        lock.unlock()
    }

    func snapshot() -> (spectrum: [Float], left: Float, right: Float, wave: [Float], beat: Float) {
        lock.lock()
        let result = (spectrum, left, right, wave, beat)
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        spectrum = [Float](repeating: 0, count: VisualizerFFT.bandCount)
        left = 0
        right = 0
        wave = [Float](repeating: 0, count: VisualizerFFT.waveformSampleCount)
        beat = 0
        lock.unlock()
    }
}

// MARK: - Tap bridge (audio render thread)

/// Owns FFT state for the Soft PASS parallel tap. Not MainActor — called from
/// the audio render thread via `MTAudioProcessingTap` callbacks.
final class TapBridge: @unchecked Sendable {
    typealias Handler = @Sendable (
        _ spectrum: [Float],
        _ left: Float,
        _ right: Float,
        _ waveform: [Float],
        _ beat: Float
    ) -> Void

    private let handler: Handler
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    private var window: [Float]
    private var mono: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var log2n: vDSP_Length

    init(handler: @escaping Handler) {
        self.handler = handler
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        mono = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func consume(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0, let fftSetup else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !abl.isEmpty, let first = abl.first, let data = first.mData else { return }

        let channelsInFirst = Int(first.mNumberChannels)
        let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let samples = data.assumingMemoryBound(to: Float.self)

        // Planar Soft PASS: separate L/R buffers with mNumberChannels == 1.
        if abl.count >= 2, channelsInFirst == 1,
           let rightBuf = abl[1].mData {
            let leftPtr = samples
            let rightPtr = rightBuf.assumingMemoryBound(to: Float.self)
            let frames = min(frameCount, fftSize, floatCount, Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size)
            guard frames > 16 else { return }
            analyzeStereoPlanar(left: leftPtr, right: rightPtr, frames: frames)
            return
        }

        let channels = max(channelsInFirst, 1)
        let frames = min(frameCount, fftSize, floatCount / channels)
        guard frames > 16 else { return }

        if channels >= 2 {
            analyzeStereoInterleaved(samples: samples, channels: channels, frames: frames)
        } else {
            analyzeMono(samples: samples, frames: frames)
        }
    }

    private func analyzeStereoInterleaved(samples: UnsafePointer<Float>, channels: Int, frames: Int) {
        guard let fftSetup else { return }
        var leftSum: Float = 0
        var rightSum: Float = 0
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        for i in 0..<frames {
            let l = samples[i * channels]
            let r = samples[i * channels + 1]
            mono[i] = (l + r) * 0.5
            leftSum += l * l
            rightSum += r * r
            leftPeak = max(leftPeak, abs(l))
            rightPeak = max(rightPeak, abs(r))
        }
        for i in frames..<fftSize { mono[i] = 0 }

        let bands = runFFT()
        let leftRMS = min(1, sqrtf(leftSum / Float(frames)) * 3.5)
        let rightRMS = min(1, sqrtf(rightSum / Float(frames)) * 3.5)
        let left = max(leftRMS, min(1, leftPeak))
        let right = max(rightRMS, min(1, rightPeak))
        let wave = VisualizerFFT.waveform(from: Array(mono.prefix(frames)))
        let beat = VisualizerFFT.beatEnergy(from: bands)
        handler(bands, left, right, wave, beat)
    }

    private func analyzeStereoPlanar(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        guard fftSetup != nil else { return }
        var leftSum: Float = 0
        var rightSum: Float = 0
        var leftPeak: Float = 0
        var rightPeak: Float = 0
        for i in 0..<frames {
            let l = left[i]
            let r = right[i]
            mono[i] = (l + r) * 0.5
            leftSum += l * l
            rightSum += r * r
            leftPeak = max(leftPeak, abs(l))
            rightPeak = max(rightPeak, abs(r))
        }
        for i in frames..<fftSize { mono[i] = 0 }

        let bands = runFFT()
        let leftRMS = min(1, sqrtf(leftSum / Float(frames)) * 3.5)
        let rightRMS = min(1, sqrtf(rightSum / Float(frames)) * 3.5)
        handler(
            bands,
            max(leftRMS, min(1, leftPeak)),
            max(rightRMS, min(1, rightPeak)),
            VisualizerFFT.waveform(from: Array(mono.prefix(frames))),
            VisualizerFFT.beatEnergy(from: bands)
        )
    }

    private func analyzeMono(samples: UnsafePointer<Float>, frames: Int) {
        guard fftSetup != nil else { return }
        for i in 0..<frames { mono[i] = samples[i] }
        for i in frames..<fftSize { mono[i] = 0 }
        let bands = runFFT()
        let level = VisualizerFFT.rmsLevel(samples: samples, count: frames)
        handler(
            bands,
            level,
            level,
            VisualizerFFT.waveform(from: Array(mono.prefix(frames))),
            VisualizerFFT.beatEnergy(from: bands)
        )
    }

    private func runFFT() -> [Float] {
        guard let fftSetup else {
            return Array(repeating: 0, count: VisualizerFFT.bandCount)
        }
        var windowed = mono
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var norm = [Float](repeating: 0, count: magnitudes.count)
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &norm, 1, vDSP_Length(magnitudes.count))
        for i in 0..<norm.count {
            norm[i] = sqrtf(max(0, norm[i]))
        }
        return VisualizerFFT.logBands(from: Array(norm.dropFirst()))
    }
}
