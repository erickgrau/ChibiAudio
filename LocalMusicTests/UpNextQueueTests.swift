import Foundation
import Testing
@testable import LocalMusic

struct UpNextQueueTests {

    /// Queue of T0…T(count-1) playing the track at `index`, shuffle off.
    private func playing(_ count: Int, at index: Int) -> (PlaybackQueue, [Track]) {
        var q = PlaybackQueue()
        let tracks = Fixtures.tracks(count)
        _ = q.play(track: tracks[index], queue: tracks, startIndex: index)
        return (q, tracks)
    }

    private func extra(_ title: String) -> Track {
        Fixtures.track(title: title, path: "/fixtures/extra-\(title).mp3")
    }

    // MARK: - history / upNext

    @Test func splitsIntoHistoryCurrentAndUpNext() {
        let (q, tracks) = playing(5, at: 2)
        #expect(q.history.map(\.id) == tracks[0..<2].map(\.id))
        #expect(q.currentTrack?.id == tracks[2].id)
        #expect(q.upNext.map(\.id) == tracks[3...].map(\.id))
    }

    @Test func emptyQueueHasNoHistoryOrUpNext() {
        let q = PlaybackQueue()
        #expect(q.history.isEmpty)
        #expect(q.upNext.isEmpty)
        #expect(q.currentTrack == nil)
    }

    // MARK: - Play Next (insert)

    @Test func playNext_insertsDirectlyAfterCurrent() {
        var (q, tracks) = playing(4, at: 1)

        let action = q.playNext([extra("A")])

        #expect(action == .noop, "inserting must not interrupt the current track")
        #expect(q.currentTrack?.id == tracks[1].id)
        #expect(q.currentIndex == 1)
        #expect(q.upNext.map(\.title) == ["A", "T2", "T3"])
    }

    @Test func playNext_repeatedCallsStackMostRecentFirst() {
        var (q, _) = playing(3, at: 0)
        _ = q.playNext([extra("A")])
        _ = q.playNext([extra("B")])
        #expect(q.upNext.map(\.title) == ["B", "A", "T1", "T2"])
    }

    @Test func playNext_onEmptyQueueStartsPlayback() {
        var q = PlaybackQueue()
        let a = extra("A")

        #expect(q.playNext([a]) == .load(0))
        #expect(q.currentTrack?.id == a.id)
        #expect(q.upNext.isEmpty)
    }

    @Test func playNext_withShuffleKeepsTrackAfterUnshuffle() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(4)
        _ = q.play(track: tracks[1], queue: tracks, startIndex: 1)
        let a = extra("A")

        _ = q.playNext([a])
        #expect(q.upNext.first?.id == a.id)

        q.toggleShuffle(currentTrackID: tracks[1].id)
        #expect(q.currentQueue.map(\.title) == ["T0", "T1", "A", "T2", "T3"])
        #expect(q.currentTrack?.id == tracks[1].id)
    }

    // MARK: - Add to Queue (append)

    @Test func addToQueue_appendsToEnd() {
        var (q, tracks) = playing(3, at: 0)

        let action = q.addToQueue([extra("A"), extra("B")])

        #expect(action == .noop)
        #expect(q.currentTrack?.id == tracks[0].id)
        #expect(q.upNext.map(\.title) == ["T1", "T2", "A", "B"])
    }

    @Test func addToQueue_onEmptyQueueStartsPlayback() {
        var q = PlaybackQueue()
        let added = [extra("A"), extra("B")]

        #expect(q.addToQueue(added) == .load(0))
        #expect(q.currentTrack?.id == added[0].id)
        #expect(q.upNext.map(\.title) == ["B"])
    }

    @Test func emptyInputIsNoop() {
        var (q, _) = playing(2, at: 0)
        let before = q
        #expect(q.addToQueue([]) == .noop)
        #expect(q.playNext([]) == .noop)
        #expect(q == before)
    }

    @Test func addToQueue_allowsSameTrackTwice() {
        var (q, tracks) = playing(2, at: 0)
        _ = q.addToQueue([tracks[1]])
        #expect(q.upNext.map(\.title) == ["T1", "T1"])
    }

    // MARK: - Reorder

    @Test func moveUpNext_movesDown() {
        var (q, tracks) = playing(5, at: 1)

        // Up Next is T2 T3 T4; SwiftUI reports "drop at end" as count.
        q.moveUpNext(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(q.upNext.map(\.title) == ["T3", "T4", "T2"])
        #expect(q.currentTrack?.id == tracks[1].id)
        #expect(q.history.map(\.title) == ["T0"])
    }

    @Test func moveUpNext_movesUp() {
        var (q, _) = playing(5, at: 1)
        q.moveUpNext(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(q.upNext.map(\.title) == ["T4", "T2", "T3"])
    }

    @Test func moveUpNext_multipleSelection() {
        var (q, _) = playing(6, at: 0)
        q.moveUpNext(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(q.upNext.map(\.title) == ["T2", "T4", "T1", "T3", "T5"])
    }

    @Test func moveUpNext_matchesSwiftUIArrayMove() {
        let (base, _) = playing(7, at: 1)
        for source in [IndexSet([0]), IndexSet([1, 3]), IndexSet([0, 4])] {
            for destination in 0...base.upNext.count {
                var q = base
                q.moveUpNext(fromOffsets: source, toOffset: destination)

                var expected = base.upNext
                let moving = source.map { expected[$0] }
                for i in source.reversed() { expected.remove(at: i) }
                expected.insert(contentsOf: moving,
                                at: destination - source.filter { $0 < destination }.count)

                #expect(q.upNext.map(\.title) == expected.map(\.title),
                        "source \(Array(source)) → \(destination)")
            }
        }
    }

    @Test func moveUpNext_onEmptyQueueDoesNothing() {
        var q = PlaybackQueue()
        q.moveUpNext(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        #expect(q.currentQueue.isEmpty)
    }

    // MARK: - Remove

    @Test func removeUpNext_removesOnlyThoseOffsets() {
        var (q, tracks) = playing(5, at: 1)

        q.removeUpNext(atOffsets: IndexSet([0, 2]))

        #expect(q.upNext.map(\.title) == ["T3"])
        #expect(q.currentTrack?.id == tracks[1].id)
        #expect(q.history.map(\.title) == ["T0"])
    }

    @Test func removeUpNext_outOfRangeIsIgnored() {
        var (q, _) = playing(3, at: 0)
        q.removeUpNext(atOffsets: IndexSet(integer: 9))
        #expect(q.upNext.map(\.title) == ["T1", "T2"])
    }

    @Test func removeUpNext_withShuffleStaysGoneAfterUnshuffle() {
        var q = PlaybackQueue()
        q.shuffleEnabled = true
        let tracks = Fixtures.tracks(4)
        _ = q.play(track: tracks[0], queue: tracks, startIndex: 0)
        let removed = q.upNext[0]

        q.removeUpNext(atOffsets: IndexSet(integer: 0))
        q.toggleShuffle(currentTrackID: tracks[0].id)

        #expect(!q.currentQueue.contains { $0.id == removed.id })
        #expect(q.currentQueue.count == 3)
    }

    // MARK: - Clear

    @Test func clearUpNext_keepsHistoryAndCurrent() {
        var (q, tracks) = playing(5, at: 2)

        q.clearUpNext()

        #expect(q.upNext.isEmpty)
        #expect(q.currentTrack?.id == tracks[2].id)
        #expect(q.history.map(\.title) == ["T0", "T1"])
    }

    @Test func clearUpNext_thenAdvanceStops() {
        var (q, _) = playing(3, at: 0)
        q.clearUpNext()
        #expect(q.next() == .stop)
        #expect(q.skipForward() == .stop)
    }

    @Test func clearUpNext_onEmptyQueueDoesNothing() {
        var q = PlaybackQueue()
        q.clearUpNext()
        #expect(q.currentQueue.isEmpty)
    }

    // MARK: - Advance follows queue order

    @Test func next_followsInsertedAndReorderedOrder() {
        var (q, _) = playing(3, at: 0)
        _ = q.addToQueue([extra("A")])
        _ = q.playNext([extra("B")])
        // Up Next: B T1 T2 A; move A to the front.
        q.moveUpNext(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        var played: [String] = []
        while case .load = q.next() {
            played.append(q.currentTrack!.title)
        }

        #expect(played == ["A", "B", "T1", "T2"])
    }

    @Test func autoAdvance_skipsRemovedTracks() {
        var (q, _) = playing(4, at: 0)
        q.removeUpNext(atOffsets: IndexSet(integer: 0))

        #expect(q.next() == .load(1))
        #expect(q.currentTrack?.title == "T2")
    }

    @Test func previous_walksBackThroughHistory() {
        var (q, _) = playing(3, at: 0)
        _ = q.playNext([extra("A")])
        _ = q.skipForward()
        #expect(q.currentTrack?.title == "A")

        #expect(q.previous(currentTime: 0) == .load(0))
        #expect(q.currentTrack?.title == "T0")
    }

    @Test func advancedTrackMovesIntoHistory() {
        var (q, _) = playing(3, at: 0)
        _ = q.next()
        #expect(q.history.map(\.title) == ["T0"])
        #expect(q.upNext.map(\.title) == ["T2"])
    }

    @Test func skipToUpNextOffset_jumpsAndPushesSkippedIntoHistory() {
        var (q, _) = playing(5, at: 0)

        #expect(q.skip(toUpNextOffset: 2) == .load(3))
        #expect(q.currentTrack?.title == "T3")
        #expect(q.history.map(\.title) == ["T0", "T1", "T2"])
        #expect(q.upNext.map(\.title) == ["T4"])
    }

    @Test func skipToUpNextOffset_outOfRangeIsNoop() {
        var (q, _) = playing(2, at: 0)
        #expect(q.skip(toUpNextOffset: 5) == .noop)
        #expect(q.skip(toUpNextOffset: -1) == .noop)
        #expect(q.currentTrack?.title == "T0")
    }

    // MARK: - Codable

    @Test func codableRoundTripPreservesQueue() throws {
        var (q, _) = playing(4, at: 1)
        _ = q.playNext([extra("A")])
        q.repeatMode = .all

        let decoded = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(q))

        #expect(decoded == q)
        #expect(decoded.upNext.map(\.title) == ["A", "T2", "T3"])
        #expect(decoded.repeatMode == .all)
    }
}
