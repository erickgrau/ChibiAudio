import CryptoKit
import Foundation

/// Slim representation of a single audio file. Heavy payloads (artwork bytes,
/// lyrics) are stored out-of-band in `ArtworkCache` / `LyricsCache` and looked
/// up on demand. The `id` is derived from the file URL so it stays stable
/// across rescans, which lets SwiftUI Lists preserve identity (no flicker /
/// scroll jump) when the library is re-loaded.
struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var hasArtwork: Bool
    var hasLyrics: Bool
    /// Embedded genre / style tag when present (empty if unknown).
    var genre: String
    /// Release year from embedded metadata when present.
    var year: Int?

    init(
        id: UUID,
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        hasArtwork: Bool,
        hasLyrics: Bool,
        genre: String = "",
        year: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasArtwork = hasArtwork
        self.hasLyrics = hasLyrics
        self.genre = genre
        self.year = year
    }

    /// Stable UUID derived from the file path: a SHA-256 truncated to 16
    /// bytes with RFC 4122 variant + version-5 nibbles set so the value is
    /// a syntactically valid UUID. (It is not a strict v5 UUID — there's no
    /// namespace input — but Foundation only cares about the layout.)
    ///
    /// Remote URLs hash host + path + query, because Subsonic / Bandcamp
    /// streams share one path and differ only by `id=`. Credential query
    /// items are dropped so a password change doesn't re-key every track.
    static func stableID(for url: URL) -> UUID {
        let digest = SHA256.hash(data: Data(identityKey(for: url).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0],  bytes[1],  bytes[2],  bytes[3],
                           bytes[4],  bytes[5],  bytes[6],  bytes[7],
                           bytes[8],  bytes[9],  bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static let credentialQueryItems: Set<String> = ["u", "p", "t", "s", "x-plex-token"]

    static func identityKey(for url: URL) -> String {
        guard !url.isFileURL,
              var components = URLComponents(url: url.standardized, resolvingAgainstBaseURL: false)
        else { return url.standardized.path }
        components.queryItems = components.queryItems?
            .filter { !credentialQueryItems.contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        components.fragment = nil
        return components.string ?? url.standardized.path
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
