import Foundation

/// Pure local scorer for multi-seed playlists.
///
/// Blends the *set* of seeds (not single-track radio). Works fully offline on
/// embedded metadata + playlist co-occurrence + recents. Online MusicBrainz /
/// ListenBrainz tags are optional boosts only.
enum PlaylistScoringEngine {

    struct Profile: Sendable, Equatable {
        var seedTrackIDs: Set<UUID>
        var artists: Set<String>
        var genres: Set<String>
        var years: [Int]
        var albums: Set<String>
        /// Related artists from MusicBrainz / ListenBrainz / LLM (normalized).
        var relatedArtists: Set<String>
        /// Artists that co-occur with seed tracks in existing playlists.
        var coArtists: Set<String>
        /// Track IDs that co-occur with seeds in existing playlists.
        var coTrackIDs: Set<UUID>
        /// Recently played track IDs (soft boost).
        var recentTrackIDs: Set<UUID>
    }

    struct Input: Sendable {
        var seeds: [PlaylistSeed]
        var candidates: [Track]
        var seedTracks: [Track]
        var playlists: [Playlist]
        var recentTrackIDs: [UUID]
        var relatedArtists: [String]
        var targetCount: Int
        var excludeSeedTracks: Bool
        var shuffleSalt: UInt64

        init(
            seeds: [PlaylistSeed],
            candidates: [Track],
            seedTracks: [Track] = [],
            playlists: [Playlist] = [],
            recentTrackIDs: [UUID] = [],
            relatedArtists: [String] = [],
            targetCount: Int = 40,
            excludeSeedTracks: Bool = false,
            shuffleSalt: UInt64 = 0
        ) {
            self.seeds = seeds
            self.candidates = candidates
            self.seedTracks = seedTracks
            self.playlists = playlists
            self.recentTrackIDs = recentTrackIDs
            self.relatedArtists = relatedArtists
            self.targetCount = targetCount
            self.excludeSeedTracks = excludeSeedTracks
            self.shuffleSalt = shuffleSalt
        }
    }

    /// Build the blended seed profile, then score / rank owned candidates.
    static func generate(_ input: Input) -> [ScoredPlaylistTrack] {
        guard !input.seeds.isEmpty, !input.candidates.isEmpty else { return [] }
        let profile = buildProfile(input)
        let seedIDs = profile.seedTrackIDs

        var scored: [ScoredPlaylistTrack] = []
        scored.reserveCapacity(input.candidates.count)

        for track in input.candidates {
            if input.excludeSeedTracks, seedIDs.contains(track.id) { continue }
            let (score, reasons) = score(track: track, profile: profile, salt: input.shuffleSalt)
            guard score > 0.05 else { continue }
            scored.append(ScoredPlaylistTrack(track: track, score: score, reasons: reasons))
        }

        scored.sort { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.0001 {
                return lhs.score > rhs.score
            }
            return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
        }

        // Light diversification: avoid dumping one artist's entire catalog first.
        let diversified = diversify(scored, target: max(input.targetCount, 1))

        // Prefer leading with seed songs (when present in candidates) so the
        // playlist clearly starts from what the user picked.
        if !input.excludeSeedTracks {
            return prependSeeds(seedTracks: input.seedTracks, ranked: diversified, target: input.targetCount)
        }
        return Array(diversified.prefix(input.targetCount))
    }

    // MARK: - Profile

    static func buildProfile(_ input: Input) -> Profile {
        var artists: Set<String> = []
        var genres: Set<String> = []
        var years: [Int] = []
        var albums: Set<String> = []
        var seedIDs: Set<UUID> = []

        for seed in input.seeds {
            switch seed {
            case .song(_, _, let artist, let album, _):
                artists.insert(normalize(artist))
                if !album.isEmpty { albums.insert(normalize(album)) }
            case .artist(let name):
                artists.insert(normalize(name))
            }
        }

        for track in input.seedTracks {
            seedIDs.insert(track.id)
            artists.insert(normalize(track.artist))
            if !track.album.isEmpty { albums.insert(normalize(track.album)) }
            for g in splitTags(track.genre) { genres.insert(g) }
            if let y = track.year { years.append(y) }
        }

        // Infer genre / year from candidates that match seed artists when seed
        // tracks themselves lack tags (common for Plex / Bandcamp stream rows).
        if genres.isEmpty || years.isEmpty {
            for track in input.candidates where artists.contains(normalize(track.artist)) {
                if genres.count < 12 {
                    for g in splitTags(track.genre) { genres.insert(g) }
                }
                if let y = track.year { years.append(y) }
            }
        }

        let related = Set(input.relatedArtists.map(normalize).filter { !$0.isEmpty && !artists.contains($0) })

        var coArtists: Set<String> = []
        var coTrackIDs: Set<UUID> = []
        let seedURLKeys = Set(input.seedTracks.map { $0.url.standardized.absoluteString })
        let seedArtistKeys = artists

        for playlist in input.playlists {
            let urls = playlist.trackURLs.map(\.standardized)
            let touchesSeed = urls.contains { seedURLKeys.contains($0.absoluteString) }
                || playlist.entries.contains { entry in
                    switch entry.source {
                    case .localFile(_, _), .stream, .appleMusic:
                        return false
                    case .plex(_, _, _, let artist, _, _):
                        return seedArtistKeys.contains(normalize(artist))
                    }
                }
            guard touchesSeed else { continue }

            for url in urls {
                if let match = input.candidates.first(where: { $0.url.standardized == url }) {
                    coTrackIDs.insert(match.id)
                    coArtists.insert(normalize(match.artist))
                }
            }
            for entry in playlist.entries {
                if case .plex(_, _, _, let artist, _, _) = entry.source {
                    coArtists.insert(normalize(artist))
                }
            }
        }

        return Profile(
            seedTrackIDs: seedIDs,
            artists: artists.filter { !$0.isEmpty && $0 != "unknown artist" },
            genres: genres,
            years: years,
            albums: albums.filter { !$0.isEmpty && $0 != "unknown album" },
            relatedArtists: related,
            coArtists: coArtists.subtracting(artists),
            coTrackIDs: coTrackIDs.subtracting(seedIDs),
            recentTrackIDs: Set(input.recentTrackIDs)
        )
    }

    // MARK: - Scoring

    static func score(track: Track, profile: Profile, salt: UInt64) -> (Double, [String]) {
        var score = 0.0
        var reasons: [String] = []
        let artist = normalize(track.artist)

        if profile.seedTrackIDs.contains(track.id) {
            score += 12
            reasons.append("Your pick")
        }

        if profile.artists.contains(artist) {
            score += 5.0
            reasons.append("Same artist")
        } else if profile.relatedArtists.contains(artist) {
            score += 3.2
            reasons.append("Related artist")
        } else if profile.coArtists.contains(artist) {
            score += 2.4
            reasons.append("Often together")
        }

        let trackGenres = splitTags(track.genre)
        let sharedGenres = trackGenres.intersection(profile.genres)
        if !sharedGenres.isEmpty {
            score += min(2.8, 1.1 * Double(sharedGenres.count))
            if let first = sharedGenres.sorted().first {
                reasons.append(first.capitalized)
            }
        }

        if let year = track.year, !profile.years.isEmpty {
            let nearest = profile.years.map { abs($0 - year) }.min() ?? 99
            if nearest == 0 {
                score += 1.6
                reasons.append("Same year")
            } else if nearest <= 3 {
                score += 1.1
                reasons.append("Same era")
            } else if nearest <= 8 {
                score += 0.45
            }
        }

        if profile.albums.contains(normalize(track.album)) && !profile.seedTrackIDs.contains(track.id) {
            // Soft boost — keep album mates available without flooding.
            score += 0.55
        }

        if profile.coTrackIDs.contains(track.id) {
            score += 1.8
            reasons.append("In your playlists")
        }

        if profile.recentTrackIDs.contains(track.id) {
            score += 0.7
            reasons.append("Recent")
        }

        // Tiny salt-stable jitter so regenerate feels fresh without chaos.
        if salt != 0 {
            score += jitter(for: track.id, salt: salt) * 0.35
        }

        return (score, reasons)
    }

    // MARK: - Diversify / order

    private static func diversify(_ ranked: [ScoredPlaylistTrack], target: Int) -> [ScoredPlaylistTrack] {
        guard ranked.count > 1 else { return ranked }
        var result: [ScoredPlaylistTrack] = []
        var deferred: [ScoredPlaylistTrack] = []
        var recentArtists: [String] = []
        let window = 3

        for item in ranked {
            let artist = normalize(item.track.artist)
            let repeats = recentArtists.suffix(window).filter { $0 == artist }.count
            if repeats >= 1, result.count < target {
                deferred.append(item)
            } else {
                result.append(item)
                recentArtists.append(artist)
                if result.count >= target { break }
            }
        }
        for item in deferred where result.count < target {
            result.append(item)
        }
        return result
    }

    private static func prependSeeds(
        seedTracks: [Track],
        ranked: [ScoredPlaylistTrack],
        target: Int
    ) -> [ScoredPlaylistTrack] {
        guard !seedTracks.isEmpty else { return Array(ranked.prefix(target)) }
        var seen = Set<UUID>()
        var out: [ScoredPlaylistTrack] = []
        for track in seedTracks {
            guard seen.insert(track.id).inserted else { continue }
            out.append(ScoredPlaylistTrack(track: track, score: 100, reasons: ["Your pick"]))
        }
        for item in ranked {
            guard seen.insert(item.track.id).inserted else { continue }
            out.append(item)
            if out.count >= target { break }
        }
        return out
    }

    // MARK: - Helpers

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    static func splitTags(_ raw: String) -> Set<String> {
        let parts = raw
            .split { $0 == "/" || $0 == "," || $0 == ";" || $0 == "|" }
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty && $0 != "unknown" && $0 != "other" }
        return Set(parts)
    }

    private static func jitter(for id: UUID, salt: UInt64) -> Double {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(salt)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        return Double(h % 1000) / 1000.0
    }
}
