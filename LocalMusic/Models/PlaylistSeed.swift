import Foundation

/// One input for multi-seed playlist generation — a song or an artist from
/// music the user already owns (local library, Plex, Bandcamp, …).
enum PlaylistSeed: Identifiable, Hashable, Sendable, Codable {
    case song(trackID: UUID, title: String, artist: String, album: String, url: URL)
    case artist(name: String)

    var id: String {
        switch self {
        case .song(let trackID, _, _, _, _):
            return "song:\(trackID.uuidString)"
        case .artist(let name):
            return "artist:\(name.lowercased())"
        }
    }

    var displayTitle: String {
        switch self {
        case .song(_, let title, _, _, _): return title
        case .artist(let name): return name
        }
    }

    var displaySubtitle: String {
        switch self {
        case .song(_, _, let artist, let album, _):
            if album.isEmpty || album == "Unknown Album" { return artist }
            return "\(artist) · \(album)"
        case .artist:
            return "Artist"
        }
    }

    var systemImage: String {
        switch self {
        case .song: return "music.note"
        case .artist: return "person"
        }
    }

    static func song(from track: Track) -> PlaylistSeed {
        .song(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            url: track.url
        )
    }

    static let maxSeeds = 5
}

/// Ranked candidate returned by the playlist scorer (owned-library only).
struct ScoredPlaylistTrack: Identifiable, Hashable, Sendable {
    var id: UUID { track.id }
    var track: Track
    var score: Double
    /// Optional reason chips for debug / preview (plain English).
    var reasons: [String]
}

/// Optional house-LLM hook for a later wave. v1 never requires a paid key.
protocol PlaylistLLMEnriching: Sendable {
    /// Return related artist names for the given seeds, or `nil` to skip.
    func relatedArtists(for seeds: [PlaylistSeed]) async -> [String]?
}

/// No-op enricher so call sites can inject Stiki / house LLM later.
struct NullPlaylistLLMEnricher: PlaylistLLMEnriching {
    func relatedArtists(for seeds: [PlaylistSeed]) async -> [String]? { nil }
}
