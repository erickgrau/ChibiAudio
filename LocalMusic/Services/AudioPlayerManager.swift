import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
@MainActor
final class AudioPlayerManager {

    // MARK: - Observed State

    var currentTrack: Track?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    var shuffleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled")
            queue.shuffleEnabled = shuffleEnabled
        }
    }
    var repeatMode: RepeatMode = .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
            queue.repeatMode = repeatMode
        }
    }
    var currentQueue: [Track] = []
    var currentIndex: Int = 0

    // MARK: - Private

    /// Pure state machine for queue/shuffle/repeat. We mirror the relevant
    /// fields onto the observed properties above after each mutation so the
    /// existing view code keeps observing the same surface.
    @ObservationIgnored private var queue = PlaybackQueue()

    /// AVFoundation/UIKit handles read-and-cleared from `deinit`, which
    /// Swift 6 treats as nonisolated even when the enclosing class is
    /// `@MainActor`. They're only ever written from MainActor methods, but
    /// the deinit is the one place we need to reach them off-actor; the
    /// `nonisolated(unsafe)` escape hatch keeps the rest of the type
    /// MainActor-isolated without a separate cleanup actor.
    @ObservationIgnored nonisolated(unsafe) private var player: AVPlayer?
    @ObservationIgnored nonisolated(unsafe) private var timeObserver: Any?
    @ObservationIgnored nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var routeChangeTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var activeSecurityScopedURL: URL?

    /// Remembered across an audio-session interruption so we can resume
    /// only when the system says we should and we were actually playing.
    @ObservationIgnored private var wasPlaying = false

    /// Consecutive `.failed` item loads. Reset on `.readyToPlay`. Capped so
    /// a run of broken files (or Repeat One on one broken file) cannot loop.
    @ObservationIgnored private var consecutiveLoadFailures = 0

    /// `ProcessInfo.systemUptime` of the last now-playing center progress
    /// write from the periodic time observer. UI `currentTime` still updates
    /// every 0.5s; center writes are throttled to ~1s.
    @ObservationIgnored private var lastNowPlayingProgressWrite: TimeInterval = 0

    // MARK: - Init

    init() {
        let storedShuffle = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        let storedMode: RepeatMode = {
            guard let raw = UserDefaults.standard.string(forKey: "repeatMode"),
                  let mode = RepeatMode(rawValue: raw) else { return .off }
            return mode
        }()
        shuffleEnabled = storedShuffle
        repeatMode = storedMode
        queue.shuffleEnabled = storedShuffle
        queue.repeatMode = storedMode
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSessionEvents()
    }

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        interruptionTask?.cancel()
        routeChangeTask?.cancel()
        statusObserver?.invalidate()
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Audio Session

    private func configureAudioSession(trackSampleRate: Double? = nil) {
        let dacMode = UserDefaults.standard.bool(forKey: DACSession.dacModeDefaultsKey)
        let enable = DACSession.shouldEnableDACPath(userEnabled: dacMode)
        do {
            try DACSession.configure(dacMode: enable, trackSampleRate: trackSampleRate)
            let route = DACSession.currentRouteInfo()
            if enable {
                Log.player.info(
                    "DAC mode · \(route.summary) · preferred=\(Int(route.preferredSampleRate))Hz"
                )
            }
            EqualizerController.shared.noteDACModeChanged()
        } catch {
            Log.player.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func activateAudioSession(trackSampleRate: Double? = nil) {
        configureAudioSession(trackSampleRate: trackSampleRate)
        do {
            try DACSession.activate()
        } catch {
            Log.player.error("Failed to activate audio session: \(error.localizedDescription)")
        }
    }

    /// Call from Settings when Hi-res/DAC mode toggles.
    func reloadAudioSessionPreference() {
        configureAudioSession()
        if isPlaying {
            activateAudioSession()
        }
    }

    /// Latest output route summary for Settings / Now Playing (THX Onyx when USB).
    var audioRouteSummary: String {
        DACSession.currentRouteInfo().summary
    }

    /// Apple's interruption and route-change articles observe via
    /// `NotificationCenter.notifications(named:)`. That API's docs state
    /// `Notification` is not `Sendable` (`object` / `userInfo` may not be),
    /// and that crossing an actor boundary requires `compactMap`/`map` to
    /// extract sendable `userInfo` values first.
    private func observeAudioSessionEvents() {
        interruptionTask = Task { [weak self] in
            let events = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            ).compactMap { notification -> (UInt, UInt)? in
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
                else { return nil }
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                return (typeValue, optionsValue)
            }
            for await (typeValue, optionsValue) in events {
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }

        routeChangeTask = Task { [weak self] in
            let events = NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ).compactMap { notification -> UInt? in
                notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            }
            for await reasonValue in events {
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
    }

    private func handleInterruption(typeValue: UInt, optionsValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            wasPlaying = isPlaying
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && wasPlaying {
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Remote Commands

    /// `player` is `nonisolated(unsafe)`, so the command-center callback
    /// (which may run off-main) can decide whether there is an item without
    /// hopping first. The actual play/pause still hops to MainActor.
    nonisolated private var hasNowPlayingItem: Bool {
        player?.currentItem != nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.hasNowPlayingItem else {
                return .noActionableNowPlayingItem
            }
            Task { @MainActor in self.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.hasNowPlayingItem else {
                return .noActionableNowPlayingItem
            }
            Task { @MainActor in self.pause() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    // MARK: - Folder Access

    /// Begin security-scoped access for a URL and keep it open
    /// until a new folder is opened or the manager is deallocated.
    func startAccessingFolder(_ url: URL) {
        stopAccessingCurrentFolder()
        // Return value is intentionally ignored: `false` can mean access is
        // already cached via a sandbox extension, so files may still be
        // readable. We only need to call stopAccessing to balance the count.
        _ = url.startAccessingSecurityScopedResource()
        activeSecurityScopedURL = url
    }

    private func stopAccessingCurrentFolder() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    // MARK: - Playback Control

    func play(track: Track, queue tracks: [Track], startIndex: Int) {
        Log.player.info("Play: \(track.title) — \(track.artist) (queue: \(tracks.count), index: \(startIndex))")
        consecutiveLoadFailures = 0
        let action = queue.play(track: track, queue: tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
    }

    func setQueue(_ tracks: [Track], startIndex: Int) {
        Log.player.info("Set queue: \(tracks.count) tracks, startIndex: \(startIndex)")
        consecutiveLoadFailures = 0
        let action = queue.setQueue(tracks, startIndex: startIndex)
        syncPublishedFromQueue()
        apply(action)
    }

    /// Resume playback. Idempotent: never pauses.
    func play() {
        guard let player else { return }
        activateAudioSession()
        player.play()
        isPlaying = true
        updateNowPlayingElapsed()
        syncVisualizerAnalyzer()
    }

    /// Pause playback. Idempotent: never resumes.
    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingElapsed()
        syncVisualizerAnalyzer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        Log.player.debug("Toggle play/pause → \(isPlaying ? "playing" : "paused")")
    }

    /// User-initiated Next (in-app button and remote `nextTrackCommand`).
    /// Uses `skipForward()` so Repeat One cannot trap the listener.
    func next() {
        Log.player.debug("Skip to next")
        let action = queue.skipForward()
        syncPublishedFromQueue()
        apply(action)
    }

    func previous() {
        Log.player.debug("Skip to previous (currentTime: \(String(format: "%.1f", currentTime)))")
        let action = queue.previous(currentTime: currentTime)
        syncPublishedFromQueue()
        apply(action)
    }

    func seek(to time: Double, completion: (@MainActor () -> Void)? = nil) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        currentTime = time
        updateNowPlayingElapsed()
        syncVisualizerAnalyzer()

        guard let player else {
            completion?()
            return
        }

        let observedItemRef = player.currentItem.map { ObjectIdentifier($0) }
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, finished else { return }
                if let observedItemRef {
                    guard let currentItem = self.player?.currentItem,
                          ObjectIdentifier(currentItem) == observedItemRef
                    else { return }
                }
                completion?()
            }
        }
    }

    /// Remap the playing queue (and current track) after a library rescan
    /// so displayed metadata matches the store. Index and shuffle order
    /// are preserved; lookup is by standardized URL.
    func refreshTrackMetadata(using lookup: (URL) -> Track?) {
        queue.refreshTrackMetadata(using: lookup)
        currentQueue = queue.currentQueue
        currentIndex = queue.currentIndex
        currentTrack = queue.currentTrack
        if let track = currentTrack {
            duration = track.duration
            updateNowPlayingInfo()
        }
    }

    // MARK: - Shuffle Toggle

    func toggleShuffle() {
        queue.toggleShuffle(currentTrackID: currentTrack?.id)
        // Keep the published flag in sync without retriggering the didSet
        // (which would write back into `queue`).
        if shuffleEnabled != queue.shuffleEnabled {
            shuffleEnabled = queue.shuffleEnabled
        }
        Log.player.info("Shuffle: \(shuffleEnabled ? "on" : "off")")
        syncPublishedFromQueue()
    }

    func cycleRepeatMode() {
        queue.cycleRepeatMode()
        if repeatMode != queue.repeatMode {
            repeatMode = queue.repeatMode
        }
        Log.player.info("Repeat mode: \(repeatMode.rawValue)")
    }

    // MARK: - Action Dispatch

    private func apply(_ action: PlaybackQueue.Action) {
        switch action {
        case .load(let index):
            if let track = queue.currentQueue[safe: index] {
                loadAndPlay(track)
            }
        case .restart:
            seek(to: 0) { [weak self] in
                self?.play()
            }
        case .seekToZero:
            seek(to: 0)
        case .stop:
            isPlaying = false
            player?.pause()
            updateNowPlayingElapsed()
        case .noop:
            break
        }
    }

    private func syncPublishedFromQueue() {
        if currentQueue != queue.currentQueue { currentQueue = queue.currentQueue }
        if currentIndex != queue.currentIndex { currentIndex = queue.currentIndex }
    }

    /// Natural end-of-track. Goes through `queue.next()` so Repeat One
    /// restarts the same item instead of advancing.
    private func handleTrackDidPlayToEnd() {
        Log.player.debug("Track ended")
        let action = queue.next()
        syncPublishedFromQueue()
        apply(action)
    }

    private func handleLoadFailure() {
        consecutiveLoadFailures += 1
        let cap = min(5, max(currentQueue.count, 1))
        if consecutiveLoadFailures >= cap {
            Log.player.error("Stopping after \(consecutiveLoadFailures) consecutive load failures")
            consecutiveLoadFailures = 0
            apply(.stop)
            return
        }
        Log.player.debug("Auto-skip after load failure")
        let action = queue.skipForward()
        syncPublishedFromQueue()
        apply(action)
    }

    // MARK: - Private Helpers

    private func loadAndPlay(_ track: Track) {
        removeTimeObserver()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil

        // HTTP(S) streams (radio / Plex) — AVPlayer handles them; skip file codec table.
        if !track.url.isFileURL {
            currentTrack = track
            duration = track.duration
            currentTime = 0
            updateNowPlayingInfo()
            finishLoadAndPlay(track, trackSampleRate: nil)
            return
        }

        let path = CodecRouter.playPath(forFileURL: track.url)
        switch path {
        case .native:
            break
        case .needsDecode:
            Log.player.error("Skipping \(track.url.lastPathComponent) — needs external decode (OGG/Opus/WV); native AVFoundation path unavailable")
            currentTrack = track
            handleLoadFailure()
            return
        case .dsd:
            // THX Onyx supports DSD; free v1 prefers DoP but the encoder isn’t shipped yet.
            // Never silently transcode to low-rate MP3/AAC.
            let strategy = DSDRouter.strategy(forFileExtension: track.url.pathExtension)
            if strategy == .dop, !DSDRouter.dopImplementedInFreeV1 {
                Log.player.error(
                    "DSD \(track.url.lastPathComponent) — DoP-to-USB intended for THX Onyx; DoP encoder not in free v1 (refusing lossy fall-back)"
                )
                currentTrack = track
                handleLoadFailure()
                return
            }
            Log.player.error("Skipping DSD \(track.url.lastPathComponent) — unavailable")
            currentTrack = track
            handleLoadFailure()
            return
        }

        currentTrack = track
        duration = track.duration
        currentTime = 0
        updateNowPlayingInfo()

        Task { [weak self] in
            await CloudFileAccess.prepareForPlayback(at: track.url)
            let probedRate = await DACSession.probeSampleRate(of: track.url)
            await MainActor.run {
                self?.finishLoadAndPlay(track, trackSampleRate: probedRate)
            }
        }
    }

    private func finishLoadAndPlay(_ track: Track, trackSampleRate: Double? = nil) {
        // Another track may have been requested while we waited on cloud I/O.
        guard currentTrack?.id == track.id else { return }

        activateAudioSession(trackSampleRate: trackSampleRate)

        let item: AVPlayerItem
        if MediaSourceKind.infer(from: track.url) == .plex {
            item = AVPlayerItem(asset: PlexClient.shared.authorizedAsset(url: track.url))
        } else {
            item = AVPlayerItem(url: track.url)
        }

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        // Soft PASS: keep system AirPlay / external routes available.
        // Selecting a USB DAC via the route picker still uses the bit-perfect DAC path.
        player?.allowsExternalPlayback = true
        player?.usesExternalPlaybackWhileExternalScreenIsActive = false

        // Wait for the item to be ready before playing.
        //
        // The KVO callback runs on a background thread; hop to MainActor and
        // re-check that the player is still pointing at the same item, since
        // rapid track changes can leave a queued .readyToPlay block in flight
        // after we've moved on.
        let observedItemRef = ObjectIdentifier(item)
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let errorDescription = observedItem.error.map { String(describing: $0) } ?? "nil"
            Task { @MainActor [weak self] in
                guard let self,
                      let currentItem = self.player?.currentItem,
                      ObjectIdentifier(currentItem) == observedItemRef
                else { return }
                switch status {
                case .readyToPlay:
                    self.consecutiveLoadFailures = 0
                    self.play()
                    self.updateNowPlayingInfo()
                case .failed:
                    Log.player.error("AVPlayerItem failed: \(errorDescription)")
                    self.handleLoadFailure()
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        addTimeObserver()

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackDidPlayToEnd() }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            // Already scheduled on `.main`; assign directly instead of
            // wrapping in another Task hop.
            MainActor.assumeIsolated {
                guard let self else { return }
                if !seconds.isNaN && !seconds.isInfinite {
                    self.currentTime = seconds
                }
                if let itemDuration = self.player?.currentItem?.duration {
                    let dur = CMTimeGetSeconds(itemDuration)
                    if !dur.isNaN && !dur.isInfinite {
                        self.duration = dur
                    }
                }
                self.refreshNowPlayingProgressIfNeeded()
                self.syncVisualizerAnalyzer()
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let image = ArtworkCache.cachedFullImage(for: track.url)
            ?? ArtworkCache.cachedThumbnail(for: track.url) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if track.hasArtwork
            && ArtworkCache.cachedFullImage(for: track.url) == nil
            && ArtworkCache.cachedThumbnail(for: track.url) == nil {
            let url = track.url
            let scale = UIScreen.main.scale
            Task { [weak self] in
                guard let image = await ArtworkCache.thumbnail(for: url, pointSize: 256, scale: scale)
                else { return }
                await MainActor.run {
                    guard let self,
                          self.currentTrack?.url == url,
                          var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
                    else { return }
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingProgressIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastNowPlayingProgressWrite >= 1 else { return }
        lastNowPlayingProgressWrite = now
        updateNowPlayingElapsed()
    }

    /// Soft PASS: keep the parallel visualizer bus aligned. No-ops when metering is off.
    private func syncVisualizerAnalyzer() {
        VisualizerAudioAnalyzer.shared.sync(
            trackURL: currentTrack?.url,
            isPlaying: isPlaying,
            currentTime: currentTime
        )
    }
}

// MARK: - Safe Collection Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
