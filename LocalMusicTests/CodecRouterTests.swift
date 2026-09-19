import Foundation
import Testing
@testable import LocalMusic

struct CodecRouterTests {

    @Test func nativeLosslessAndLossy() {
        for ext in ["flac", "FLAC", "wav", "alac", "aiff", "aif", "mp3", "m4a", "aac"] {
            #expect(CodecRouter.playPath(for: ext) == .native)
        }
    }

    @Test func needsDecodeFormats() {
        for ext in ["ogg", "opus", "wv", "oga"] {
            #expect(CodecRouter.playPath(for: ext) == .needsDecode)
        }
    }

    @Test func dsdFormats() {
        #expect(CodecRouter.playPath(for: "dsf") == .dsd)
        #expect(CodecRouter.playPath(for: "dff") == .dsd)
        #expect(DSDRouter.strategy(forFileExtension: "dsf") == .dop)
        #expect(DSDRouter.dopImplementedInFreeV1 == false)
    }
}

struct PlaylistSourceTests {

    @Test func appendMixedSources() {
        var playlist = Playlist(
            fileURL: URL(fileURLWithPath: "/tmp/test.json"),
            name: "Mixed"
        )
        playlist.appendLocal(
            url: URL(fileURLWithPath: "/music/a.flac"),
            displayPath: "a.flac"
        )
        playlist.appendStream(
            url: URL(string: "https://ice.example/stream")!,
            title: "Radio",
            artist: "Icecast"
        )
        playlist.appendPlex(
            serverURL: "http://192.168.1.2:32400",
            ratingKey: "123",
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 200
        )
        #expect(playlist.entries.count == 3)
        #expect(playlist.trackURLs.count == 1)
        #expect(playlist.isAppOwned)

        if case .stream = playlist.entries[1].source {} else {
            Issue.record("expected stream entry")
        }
    }

    @Test func appleMusicGate() {
        let entry = PlaylistEntry(source: .appleMusic(
            songID: "x",
            title: "T",
            artist: "A"
        ))
        let result = PlaylistResolver.resolve(entry)
        #expect(result == .failure(.needsAppleMusicSubscription))
    }
}
