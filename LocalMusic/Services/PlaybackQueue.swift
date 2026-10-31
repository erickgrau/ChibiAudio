import Foundation

/// Pure value-type state machine for the playback queue: track ordering,
/// shuffle, and repeat. Kept free of `AVPlayer` so the logic can be unit
/// tested without playing audio. `AudioPlayerManager` owns one of these,
/// applies mutations, and translates the returned `Action` into AVFoundation
/// calls.
///
/// The queue reads as history (`currentQueue[..<currentIndex]`), the current
/// track, and Up Next (`currentQueue[(currentIndex + 1)...]`). `Codable` so
/// `PersistenceManager` can restore it across launches.
struct PlaybackQueue: Equatable, Codable, Sendable {

    // MARK: - State

    var currentQueue: [Track] = []
    var currentIndex: Int = 0
    var unshuffledQueue: [Track] = []
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    // MARK: - Actions returned to the caller

    /// What the host should do after a queue mutation. Decoupling lets us
    /// verify behaviour in tests without an `AVPlayer` instance.
    enum Action: Equatable {
        /// Load and play the track at `currentIndex`.
        case load(Int)
        /// Restart the current item from 0 and force playback (next with
        /// `.one` repeat). Distinct from `.seekToZero` which preserves the
        /// play/pause state.
        case restart
        /// Seek the existing item back to 0 without changing play/pause
        /// state. Used by `previous()` when `currentTime > 3` or when at the
        /// head of a non-repeating queue.
        case seekToZero
        /// End of queue with no repeat — pause and stop advancing.
        case stop
        /// Nothing to do (queue was empty, etc.).
        case noop
    }

    // MARK: - Mutations

    /// Begin playback of `track` from a fresh `queue`. With shuffle enabled,
    /// the played track is pinned at index 0 and the rest of the queue is
    /// shuffled around it. Returns `.noop` on an invalid `startIndex` so the
    /// caller's `track` is never silently swapped for a different element.
    mutating func play(track: Track, queue: [Track], startIndex: Int) -> Action {
        guard queue.indices.contains(startIndex) else { return .noop }
        unshuffledQueue = queue
        if shuffleEnabled {
            var shuffled = queue
            shuffled.remove(at: startIndex)
            shuffled.shuffle()
            shuffled.insert(track, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else {
            currentQueue = queue
            currentIndex = startIndex
        }
        return .load(currentIndex)
    }

    /// Replace the queue without specifying the "current" track separately.
    /// The track at `startIndex` becomes the head when shuffling.
    mutating func setQueue(_ tracks: [Track], startIndex: Int) -> Action {
        guard tracks.indices.contains(startIndex) else { return .noop }
        unshuffledQueue = tracks
        if shuffleEnabled {
            let track = tracks[startIndex]
            var shuffled = tracks
            shuffled.remove(at: startIndex)
            shuffled.shuffle()
            shuffled.insert(track, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else {
            currentQueue = tracks
            currentIndex = startIndex
        }
        return .load(currentIndex)
    }

    /// Natural end of the current track. Repeat One restarts the same item;
    /// user-initiated Next goes through `skipForward()` so it can leave the
    /// song even when Repeat One is on.
    mutating func next() -> Action {
        guard !currentQueue.isEmpty else { return .noop }
        if repeatMode == .one { return .restart }
        return advance()
    }

    /// User-initiated Next (UI / lock-screen). Always advances, including
    /// when `repeatMode == .one`. Wrap/stop follow `.all` / `.off` the same
    /// way as a natural advance: wrap to 0 on `.all`, stop at the end otherwise.
    mutating func skipForward() -> Action {
        guard !currentQueue.isEmpty else { return .noop }
        return advance()
    }

    /// Remap queue entries by URL after a library rescan so title/artist/
    /// album/duration stay current. `currentIndex` and the shuffle layout
    /// are preserved; tracks the lookup doesn't know about are left as-is.
    mutating func refreshTrackMetadata(using lookup: (URL) -> Track?) {
        func remap(_ tracks: [Track]) -> [Track] {
            tracks.map { lookup($0.url.standardized) ?? $0 }
        }
        currentQueue = remap(currentQueue)
        unshuffledQueue = remap(unshuffledQueue)
    }

    /// Advance to the next index, ignoring Repeat One. Wraps to 0 when
    /// `repeatMode == .all`; otherwise stops at the end.
    private mutating func advance() -> Action {
        let nextIndex = currentIndex + 1
        if nextIndex < currentQueue.count {
            currentIndex = nextIndex
            return .load(currentIndex)
        }
        if repeatMode == .all {
            currentIndex = 0
            return .load(0)
        }
        return .stop
    }

    mutating func previous(currentTime: Double) -> Action {
        guard !currentQueue.isEmpty else { return .noop }
        if currentTime > 3 { return .seekToZero }

        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            currentIndex = prevIndex
            return .load(currentIndex)
        }
        if repeatMode == .all {
            currentIndex = currentQueue.count - 1
            return .load(currentIndex)
        }
        return .seekToZero
    }

    /// Toggle the shuffle flag. When turning shuffle on, the supplied
    /// `currentTrackID` (if present in the queue) is pinned at index 0 so the
    /// listener doesn't experience an abrupt track change.
    mutating func toggleShuffle(currentTrackID: UUID?) {
        shuffleEnabled.toggle()
        guard !currentQueue.isEmpty,
              let id = currentTrackID,
              let current = currentQueue.first(where: { $0.id == id })
        else { return }

        if shuffleEnabled {
            unshuffledQueue = currentQueue
            var shuffled = currentQueue.filter { $0.id != id }
            shuffled.shuffle()
            shuffled.insert(current, at: 0)
            currentQueue = shuffled
            currentIndex = 0
        } else if let idx = unshuffledQueue.firstIndex(where: { $0.id == id }) {
            currentQueue = unshuffledQueue
            currentIndex = idx
        }
    }

    // MARK: - Up Next

    /// Insert `tracks` directly after the current track. Starts playback
    /// when the queue is empty, otherwise leaves the current track alone.
    mutating func playNext(_ tracks: [Track]) -> Action {
        guard !tracks.isEmpty else { return .noop }
        guard let current = currentTrack else { return start(tracks) }
        currentQueue.insert(contentsOf: tracks, at: currentIndex + 1)
        if shuffleEnabled {
            let anchor = unshuffledQueue.firstIndex(where: { $0.id == current.id })
                .map { $0 + 1 } ?? unshuffledQueue.endIndex
            unshuffledQueue.insert(contentsOf: tracks, at: anchor)
        }
        return .noop
    }

    /// Append `tracks` to the end of Up Next. Starts playback when the
    /// queue is empty.
    mutating func addToQueue(_ tracks: [Track]) -> Action {
        guard !tracks.isEmpty else { return .noop }
        guard currentTrack != nil else { return start(tracks) }
        currentQueue.append(contentsOf: tracks)
        if shuffleEnabled {
            unshuffledQueue.append(contentsOf: tracks)
        }
        return .noop
    }

    /// Reorder within Up Next. Offsets are relative to `upNext`, matching
    /// SwiftUI's `onMove` contract.
    mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard currentQueue.indices.contains(currentIndex) else { return }
        var tracks = upNext
        let valid = source.filter(tracks.indices.contains)
        let moving = valid.map { tracks[$0] }
        let insertAt = destination - valid.filter { $0 < destination }.count
        for offset in valid.reversed() {
            tracks.remove(at: offset)
        }
        tracks.insert(contentsOf: moving, at: min(max(insertAt, 0), tracks.count))
        currentQueue.replaceSubrange((currentIndex + 1)..., with: tracks)
    }

    /// Remove Up Next entries at `offsets` (relative to `upNext`).
    mutating func removeUpNext(atOffsets offsets: IndexSet) {
        let base = currentIndex + 1
        let removed = offsets.sorted(by: >)
            .filter { currentQueue.indices.contains(base + $0) }
            .map { currentQueue.remove(at: base + $0) }
        forgetUnshuffled(removed)
    }

    /// Drop everything after the current track. History is kept so
    /// Previous still walks back through what already played.
    mutating func clearUpNext() {
        guard currentQueue.indices.contains(currentIndex) else { return }
        let removed = Array(currentQueue[(currentIndex + 1)...])
        currentQueue.removeSubrange((currentIndex + 1)...)
        forgetUnshuffled(removed)
    }

    /// Jump to the Up Next entry at `offset`. The tracks skipped over move
    /// into history, as if each had played.
    mutating func skip(toUpNextOffset offset: Int) -> Action {
        let target = currentIndex + 1 + offset
        guard offset >= 0, currentQueue.indices.contains(target) else { return .noop }
        currentIndex = target
        return .load(target)
    }

    private mutating func start(_ tracks: [Track]) -> Action {
        currentQueue = tracks
        unshuffledQueue = tracks
        currentIndex = 0
        return .load(0)
    }

    /// Keep the pre-shuffle order in step with removals so turning shuffle
    /// off doesn't resurrect tracks the listener took out.
    private mutating func forgetUnshuffled(_ removed: [Track]) {
        guard shuffleEnabled else { return }
        for track in removed {
            if let idx = unshuffledQueue.lastIndex(where: { $0.id == track.id }) {
                unshuffledQueue.remove(at: idx)
            }
        }
    }

    mutating func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Lookups

    var currentTrack: Track? {
        currentQueue.indices.contains(currentIndex) ? currentQueue[currentIndex] : nil
    }

    var upNext: [Track] {
        currentQueue.indices.contains(currentIndex) ? Array(currentQueue[(currentIndex + 1)...]) : []
    }

    var history: [Track] {
        Array(currentQueue.prefix(min(max(currentIndex, 0), currentQueue.count)))
    }
}
