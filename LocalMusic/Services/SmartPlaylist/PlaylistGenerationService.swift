import Foundation
import Observation

/// Orchestrates multi-seed playlist generation from owned music only.
///
/// Offline-first: local metadata scoring always runs. MusicBrainz / ListenBrainz
/// enrich when online. Optional `PlaylistLLMEnriching` hook stays unused in v1.
@Observable
@MainActor
final class PlaylistGenerationService {

    private(set) var isGenerating = false
    private(set) var statusMessage: String?
    private(set) var lastResults: [ScoredPlaylistTrack] = []
    private(set) var lastSeeds: [PlaylistSeed] = []
    private(set) var usedOnlineEnrichment = false

    @ObservationIgnored private var llm: any PlaylistLLMEnriching
    @ObservationIgnored private var regenerateSalt: UInt64 = 0

    init(llm: any PlaylistLLMEnriching = NullPlaylistLLMEnricher()) {
        self.llm = llm
    }

    /// Swap in a Stiki / house LLM enricher later without changing the UI.
    func setLLMEnricher(_ enricher: any PlaylistLLMEnriching) {
        llm = enricher
    }

    /// Build a playlist preview from 1…5 seeds using owned candidates.
    func generate(
        seeds: [PlaylistSeed],
        library: LibraryStore,
        recents: RecentsStore,
        targetCount: Int = 40,
        allowOnlineEnrichment: Bool = true
    ) async -> [ScoredPlaylistTrack] {
        let clipped = Array(seeds.prefix(PlaylistSeed.maxSeeds))
        guard !clipped.isEmpty else {
            lastResults = []
            statusMessage = "Pick at least one song or artist."
            return []
        }

        isGenerating = true
        statusMessage = "Scoring your library…"
        usedOnlineEnrichment = false
        defer { isGenerating = false }

        let seedTracks = resolveSeedTracks(clipped, library: library)
        var candidates = library.tracks

        // Optional owned remotes — never scrape Spotify / Apple Music catalogs.
        if allowOnlineEnrichment {
            statusMessage = "Checking connected libraries…"
            let remote = await fetchRemoteOwnedCandidates(matching: clipped, seedTracks: seedTracks)
            candidates = mergeCandidates(candidates, remote)
        }

        var related: [String] = []
        if allowOnlineEnrichment {
            statusMessage = "Looking up related artists…"
            related = await enrichRelatedArtists(seeds: clipped, seedTracks: seedTracks)
            usedOnlineEnrichment = !related.isEmpty
        }

        if let llmRelated = await llm.relatedArtists(for: clipped) {
            related.append(contentsOf: llmRelated)
            usedOnlineEnrichment = true
        }

        regenerateSalt &+= 1
        let input = PlaylistScoringEngine.Input(
            seeds: clipped,
            candidates: candidates,
            seedTracks: seedTracks,
            playlists: library.playlists,
            recentTrackIDs: recents.entries.map(\.id),
            relatedArtists: related,
            targetCount: targetCount,
            excludeSeedTracks: false,
            shuffleSalt: regenerateSalt
        )

        statusMessage = "Building playlist…"
        let ranked = PlaylistScoringEngine.generate(input)
        lastSeeds = clipped
        lastResults = ranked
        if ranked.isEmpty {
            statusMessage = "Not enough matching tracks in your library yet."
        } else if usedOnlineEnrichment {
            statusMessage = "Ready — \(ranked.count) tracks from your music."
        } else {
            statusMessage = "Ready — built offline from your tags and playlists."
        }
        return ranked
    }

    /// Re-run with a new salt using the last seed set.
    func regenerate(
        library: LibraryStore,
        recents: RecentsStore,
        targetCount: Int = 40,
        allowOnlineEnrichment: Bool = true
    ) async -> [ScoredPlaylistTrack] {
        await generate(
            seeds: lastSeeds,
            library: library,
            recents: recents,
            targetCount: targetCount,
            allowOnlineEnrichment: allowOnlineEnrichment
        )
    }

    /// Persist preview as an app-owned playlist.
    @discardableResult
    func savePreview(
        named name: String,
        tracks: [Track],
        library: LibraryStore
    ) -> Playlist? {
        guard let playlist = library.createPlaylist(name: name) else { return nil }
        var mutable = playlist
        for track in tracks {
            let kind = MediaSourceKind.infer(from: track.url)
            switch kind {
            case .plex:
                // Stream URLs from Plex still append as localFile/stream via path;
                // prefer stream entry when not a file URL.
                if track.url.isFileURL {
                    mutable.appendLocal(url: track.url, displayPath: track.url.path)
                } else {
                    mutable.appendStream(url: track.url, title: track.title, artist: track.artist)
                }
            case .bandcamp, .radio:
                mutable.appendStream(url: track.url, title: track.title, artist: track.artist)
            case .onDevice, .iCloud, .drive, .appleMusic:
                if track.url.isFileURL {
                    mutable.appendLocal(url: track.url, displayPath: track.url.path)
                } else {
                    mutable.appendStream(url: track.url, title: track.title, artist: track.artist)
                }
            }
        }
        library.savePlaylist(mutable)
        return mutable
    }

    // MARK: - Seeds

    private func resolveSeedTracks(_ seeds: [PlaylistSeed], library: LibraryStore) -> [Track] {
        var out: [Track] = []
        for seed in seeds {
            switch seed {
            case .song(let trackID, let title, let artist, let album, let url):
                if let live = library.tracks.first(where: { $0.id == trackID }) {
                    out.append(live)
                } else if let live = library.track(forURL: url) {
                    out.append(live)
                } else {
                    out.append(Track(
                        id: trackID,
                        url: url,
                        title: title,
                        artist: artist,
                        album: album,
                        duration: 0,
                        hasArtwork: false,
                        hasLyrics: false
                    ))
                }
            case .artist(let name):
                let key = PlaylistScoringEngine.normalize(name)
                let matches = library.tracks.filter {
                    PlaylistScoringEngine.normalize($0.artist) == key
                }
                // One representative per artist seed for genre/year inference.
                if let first = matches.first {
                    out.append(first)
                }
            }
        }
        return out
    }

    // MARK: - Remote owned candidates

    private func fetchRemoteOwnedCandidates(
        matching seeds: [PlaylistSeed],
        seedTracks: [Track]
    ) async -> [Track] {
        var artists = Set(seedTracks.map { PlaylistScoringEngine.normalize($0.artist) })
        for seed in seeds {
            if case .artist(let name) = seed {
                artists.insert(PlaylistScoringEngine.normalize(name))
            }
            if case .song(_, _, let artist, _, _) = seed {
                artists.insert(PlaylistScoringEngine.normalize(artist))
            }
        }
        artists = Set(artists.filter { !$0.isEmpty })

        var remote: [Track] = []
        remote.append(contentsOf: await plexCandidates(matchingArtists: artists))
        remote.append(contentsOf: await bandcampCandidates(matchingArtists: artists))
        return remote
    }

    private func plexCandidates(matchingArtists artists: Set<String>) async -> [Track] {
        let plex = PlexClient.shared
        guard plex.isConfigured else { return [] }
        if plex.musicSections.isEmpty {
            await plex.refreshMusicLibraries()
        }
        var tracks: [Track] = []
        for section in plex.musicSections.prefix(3) {
            let plexTracks = await plex.fetchTracks(sectionKey: section.key)
            for pt in plexTracks {
                let key = PlaylistScoringEngine.normalize(pt.artist)
                guard artists.contains(key) else { continue }
                guard let url = plex.directPlayURL(serverURL: plex.serverURLString, ratingKey: pt.ratingKey)
                else { continue }
                tracks.append(Track(
                    id: Track.stableID(for: url),
                    url: url,
                    title: pt.title,
                    artist: pt.artist,
                    album: pt.album,
                    duration: pt.durationMs / 1000.0,
                    hasArtwork: false,
                    hasLyrics: false
                ))
                if tracks.count >= 400 { break }
            }
            if tracks.count >= 400 { break }
        }
        return tracks
    }

    private func bandcampCandidates(matchingArtists artists: Set<String>) async -> [Track] {
        let client = BandcampSubsonicClient.shared
        guard client.isConfigured else { return [] }
        if client.albums.isEmpty {
            await client.refreshCollection(size: 200)
        }
        var tracks: [Track] = []
        let matchingAlbums = client.albums.filter {
            artists.contains(PlaylistScoringEngine.normalize($0.artist))
        }
        // Prefer albums from seed artists; fall back to a small sample.
        let albums = matchingAlbums.isEmpty ? Array(client.albums.prefix(8)) : Array(matchingAlbums.prefix(20))
        for album in albums {
            let songs = await client.fetchAlbumTracks(albumID: album.id)
            for song in songs {
                guard let url = client.streamURL(forSongID: song.id) else { continue }
                tracks.append(Track(
                    id: Track.stableID(for: url),
                    url: url,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    duration: song.durationSeconds,
                    hasArtwork: song.coverArtID != nil,
                    hasLyrics: false
                ))
            }
            if tracks.count >= 300 { break }
        }
        return tracks
    }

    private func mergeCandidates(_ primary: [Track], _ extra: [Track]) -> [Track] {
        var seen = Set(primary.map(\.id))
        var out = primary
        for track in extra where seen.insert(track.id).inserted {
            out.append(track)
        }
        return out
    }

    // MARK: - Online enrichment

    private func enrichRelatedArtists(seeds: [PlaylistSeed], seedTracks: [Track]) async -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for seed in seeds {
            switch seed {
            case .artist(let name):
                let key = PlaylistScoringEngine.normalize(name)
                if seen.insert(key).inserted { names.append(name) }
            case .song(_, _, let artist, _, _):
                let key = PlaylistScoringEngine.normalize(artist)
                if seen.insert(key).inserted { names.append(artist) }
            }
        }
        for track in seedTracks {
            let key = PlaylistScoringEngine.normalize(track.artist)
            if seen.insert(key).inserted { names.append(track.artist) }
        }
        guard !names.isEmpty else { return [] }
        return await MusicCatalogClient.shared.relatedArtists(
            forArtists: Array(names.prefix(3)),
            perArtist: 5
        )
    }
}
