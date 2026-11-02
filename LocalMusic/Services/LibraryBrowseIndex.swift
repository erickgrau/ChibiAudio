import Foundation

/// An album built from the tags of the tracks in the library.
struct AlbumSummary: Identifiable, Hashable, Sendable {
    /// Case-folded album title plus the album's folder. Tracks have no
    /// album-artist tag, so the folder keeps same-titled albums (two
    /// "Greatest Hits") apart while a compilation's folder stays together.
    let id: String
    let title: String
    /// The single artist on every track, or "Various Artists".
    let artist: String
    let year: Int?
    /// File-name order, which follows track numbering for most rips.
    let tracks: [Track]

    var artworkTrack: Track? { tracks.first(where: \.hasArtwork) ?? tracks.first }
}

/// An artist built from the artist tags of the tracks in the library.
struct ArtistSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let albumCount: Int
    let tracks: [Track]
}

/// Groups library tracks into albums and artists for the Mac browse views.
/// Uses only real tags; untagged tracks keep the loader's "Unknown Album" /
/// "Unknown Artist" values rather than invented ones.
enum LibraryBrowseIndex {
    static let variousArtists = "Various Artists"

    static func albums(from tracks: [Track]) -> [AlbumSummary] {
        let groups = Dictionary(grouping: tracks) { key(for: $0.album) + "|" + albumFolder(of: $0.url) }
        return groups.compactMap { id, members -> AlbumSummary? in
            guard let first = members.first else { return nil }
            let ordered = members.sorted(by: fileOrder)
            let artists = Set(members.map { key(for: $0.artist) })
            return AlbumSummary(
                id: id,
                title: displayName(first.album, fallback: "Unknown Album"),
                artist: artists.count == 1 ? displayName(first.artist, fallback: "Unknown Artist") : variousArtists,
                year: members.compactMap(\.year).min(),
                tracks: ordered
            )
        }
        .sorted {
            let byTitle = $0.title.localizedStandardCompare($1.title)
            return byTitle == .orderedSame
                ? $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
                : byTitle == .orderedAscending
        }
    }

    static func artists(from tracks: [Track]) -> [ArtistSummary] {
        let groups = Dictionary(grouping: tracks) { key(for: $0.artist) }
        return groups.compactMap { id, members -> ArtistSummary? in
            guard let first = members.first else { return nil }
            let ordered = members.sorted {
                let byAlbum = $0.album.localizedStandardCompare($1.album)
                return byAlbum == .orderedSame ? fileOrder($0, $1) : byAlbum == .orderedAscending
            }
            return ArtistSummary(
                id: id,
                name: displayName(first.artist, fallback: "Unknown Artist"),
                albumCount: Set(members.map { key(for: $0.album) }).count,
                tracks: ordered
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The folder holding an album's files. Disc subfolders ("CD1",
    /// "Disc 2") count as their parent so multi-disc sets stay one album.
    static func albumFolder(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardized
        let name = folder.lastPathComponent.lowercased()
        let isDiscFolder = name.range(of: #"^(cd|disc|disk)\s*\d+$"#, options: .regularExpression) != nil
        return (isDiscFolder ? folder.deletingLastPathComponent() : folder).path
    }

    private static func key(for value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func displayName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func fileOrder(_ a: Track, _ b: Track) -> Bool {
        a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
    }
}
