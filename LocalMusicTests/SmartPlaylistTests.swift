import Foundation
import Testing
@testable import LocalMusic

struct SmartPlaylistTests {

    @Test func scoring_blendsMultipleSeedsAndPrefersSharedGenre() {
        let seedA = Fixtures.track(
            title: "Seed A",
            artist: "Alpha",
            album: "A1",
            path: "/lib/a.mp3",
            genre: "Jazz",
            year: 1998
        )
        let seedB = Fixtures.track(
            title: "Seed B",
            artist: "Beta",
            album: "B1",
            path: "/lib/b.mp3",
            genre: "Jazz",
            year: 2001
        )
        let related = Fixtures.track(
            title: "Related Jazz",
            artist: "Gamma",
            album: "G1",
            path: "/lib/g.mp3",
            genre: "Jazz",
            year: 1999
        )
        let unrelated = Fixtures.track(
            title: "Metal",
            artist: "Omega",
            album: "O1",
            path: "/lib/o.mp3",
            genre: "Metal",
            year: 2018
        )
        let sameArtist = Fixtures.track(
            title: "Alpha Deep Cut",
            artist: "Alpha",
            album: "A2",
            path: "/lib/a2.mp3",
            genre: "Jazz",
            year: 1997
        )

        let results = PlaylistScoringEngine.generate(.init(
            seeds: [.song(from: seedA), .song(from: seedB)],
            candidates: [seedA, seedB, related, unrelated, sameArtist],
            seedTracks: [seedA, seedB],
            relatedArtists: ["Gamma"],
            targetCount: 10,
            shuffleSalt: 0
        ))

        let ids = results.map(\.track.id)
        #expect(ids.contains(seedA.id))
        #expect(ids.contains(seedB.id))
        #expect(ids.contains(sameArtist.id))
        #expect(ids.contains(related.id))

        let relatedScore = results.first { $0.track.id == related.id }?.score ?? 0
        let unrelatedScore = results.first { $0.track.id == unrelated.id }?.score ?? 0
        #expect(relatedScore > unrelatedScore)
    }

    @Test func scoring_artistSeedMatchesLibraryArtist() {
        let t1 = Fixtures.track(title: "One", artist: "Nora", path: "/n/1.mp3", genre: "Soul", year: 1972)
        let t2 = Fixtures.track(title: "Two", artist: "Nora", path: "/n/2.mp3", genre: "Soul", year: 1973)
        let other = Fixtures.track(title: "Other", artist: "Sam", path: "/n/3.mp3", genre: "Pop", year: 2020)

        let results = PlaylistScoringEngine.generate(.init(
            seeds: [.artist(name: "Nora")],
            candidates: [t1, t2, other],
            seedTracks: [t1],
            targetCount: 10
        ))

        #expect(results.contains { $0.track.id == t2.id })
        let nora = results.filter { $0.track.artist == "Nora" }
        #expect(nora.count >= 1)
    }

    @Test func scoring_coOccurrenceBoostsPlaylistMates() {
        let seed = Fixtures.track(title: "Seed", artist: "A", path: "/c/seed.mp3", genre: "Rock", year: 2005)
        let mate = Fixtures.track(title: "Mate", artist: "B", path: "/c/mate.mp3", genre: "Folk", year: 2010)
        let stranger = Fixtures.track(title: "Stranger", artist: "C", path: "/c/str.mp3", genre: "Folk", year: 2010)

        let playlist = Playlist(
            fileURL: URL(fileURLWithPath: "/tmp/mix.json"),
            name: "Mix",
            trackURLs: [seed.url, mate.url],
            rawPaths: [seed.url.path, mate.url.path]
        )

        let results = PlaylistScoringEngine.generate(.init(
            seeds: [.song(from: seed)],
            candidates: [seed, mate, stranger],
            seedTracks: [seed],
            playlists: [playlist],
            targetCount: 10
        ))

        let mateScore = results.first { $0.track.id == mate.id }?.score ?? 0
        let strangerScore = results.first { $0.track.id == stranger.id }?.score ?? 0
        #expect(mateScore > strangerScore)
    }

    @Test func normalizeAndSplitTags() {
        #expect(PlaylistScoringEngine.normalize("  Café ") == "cafe")
        let tags = PlaylistScoringEngine.splitTags("Jazz / Fusion, Cool")
        #expect(tags.contains("jazz"))
        #expect(tags.contains("fusion"))
        #expect(tags.contains("cool"))
    }

    @Test func parseYearFromMetadataStrings() {
        #expect(MetadataLoader.parseYear(from: "1999") == 1999)
        #expect(MetadataLoader.parseYear(from: "2001-06-15") == 2001)
        #expect(MetadataLoader.parseYear(from: "released 1984") == 1984)
        #expect(MetadataLoader.parseYear(from: "nope") == nil)
    }

    @Test func musicBrainzParsersExtractRelatedAndTags() throws {
        let artistJSON = """
        {"artists":[{"id":"mbid-1","name":"Test"}]}
        """.data(using: .utf8)!
        #expect(MusicCatalogClient.parseMusicBrainzArtistID(artistJSON) == "mbid-1")

        let relJSON = """
        {
          "relations": [
            {"type": "member of band", "artist": {"name": "Side Project"}},
            {"type": "collaboration", "artist": {"name": "Friend"}}
          ]
        }
        """.data(using: .utf8)!
        let related = MusicCatalogClient.parseMusicBrainzRelatedArtists(relJSON)
        #expect(related.contains("Side Project"))
        #expect(related.contains("Friend"))

        let tagsJSON = """
        {"tags":[{"name":"indie","count":12},{"name":"dream pop","count":4}]}
        """.data(using: .utf8)!
        let tags = MusicCatalogClient.parseMusicBrainzTags(tagsJSON)
        #expect(tags.first == "indie")
    }

    @Test func listenBrainzSimilarParserAcceptsVariants() throws {
        let json = """
        {"artists":[{"artist_name":"One"},{"name":"Two"},"Three"]}
        """.data(using: .utf8)!
        let names = MusicCatalogClient.parseListenBrainzSimilar(json)
        #expect(names.contains("One"))
        #expect(names.contains("Two"))
        #expect(names.contains("Three"))
    }

    @Test func playlistSeedMaxAndIdentity() {
        let t = Fixtures.track(title: "X", path: "/s/x.mp3")
        let song = PlaylistSeed.song(from: t)
        let artist = PlaylistSeed.artist(name: "X")
        #expect(song.id != artist.id)
        #expect(PlaylistSeed.maxSeeds == 5)
        #expect(song.displayTitle == "X")
    }
}
