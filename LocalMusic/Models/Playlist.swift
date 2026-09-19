import Foundation

/// Typed source for one row in an app-owned (or extended) playlist.
/// Mix freely: local/cloud files, Plex, free radio URLs, optional Apple Music IDs.
enum PlaylistSourceRef: Codable, Equatable, Hashable, Sendable {
    /// On-device or Files-provider file (On My iPhone, iCloud Drive, Google Drive, …).
    case localFile(urlString: String, displayPath: String)
    /// Direct HTTP(S) stream — Icecast / Shoutcast / free radio URL.
    case stream(urlString: String, title: String, artist: String)
    /// Track on the user's Plex Media Server (resolved to a play URL at queue time).
    case plex(
        serverURL: String,
        ratingKey: String,
        title: String,
        artist: String,
        album: String,
        duration: Double
    )
    /// Apple Music catalog ID — playback requires an active Apple Music subscription.
    case appleMusic(songID: String, title: String, artist: String)

    var displayTitle: String {
        switch self {
        case .localFile(_, let displayPath):
            return URL(fileURLWithPath: displayPath).deletingPathExtension().lastPathComponent
        case .stream(_, let title, _): return title
        case .plex(_, _, let title, _, _, _): return title
        case .appleMusic(_, let title, _): return title
        }
    }

    var displayArtist: String {
        switch self {
        case .localFile: return ""
        case .stream(_, _, let artist): return artist
        case .plex(_, _, _, let artist, _, _): return artist
        case .appleMusic(_, _, let artist): return artist
        }
    }

    var sourceBadge: String {
        switch self {
        case .localFile: return "File"
        case .stream: return "Radio"
        case .plex: return "Plex"
        case .appleMusic: return "Apple Music"
        }
    }
}

/// One ordered playlist row.
struct PlaylistEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var source: PlaylistSourceRef

    init(id: UUID = UUID(), source: PlaylistSourceRef) {
        self.id = id
        self.source = source
    }
}

/// Playlist discovered from `.m3u` / `.m3u8` / `.pls` **or** app-owned JSON.
///
/// `entries` is the multi-source source of truth. `trackURLs` / `rawPaths` remain
/// for local-file UI and m3u round-trips; helpers keep them aligned with
/// `.localFile` entries when you mutate through `Playlist` methods.
struct Playlist: Identifiable, Sendable {
    var id: URL { fileURL }
    let fileURL: URL
    let name: String
    var entries: [PlaylistEntry]
    /// Parallel local-file mirrors (legacy + mosaic / missing-file UI).
    var trackURLs: [URL]
    var rawPaths: [String]

    /// App-owned unified playlists live under Documents as `.json`.
    var isAppOwned: Bool {
        fileURL.pathExtension.lowercased() == "json"
    }

    init(
        fileURL: URL,
        name: String,
        entries: [PlaylistEntry] = [],
        trackURLs: [URL] = [],
        rawPaths: [String] = []
    ) {
        self.fileURL = fileURL
        self.name = name
        self.entries = entries
        self.trackURLs = trackURLs
        self.rawPaths = rawPaths
        if self.entries.isEmpty && !self.trackURLs.isEmpty {
            self.rebuildEntriesFromLegacyLocals()
        } else if self.trackURLs.isEmpty && !self.entries.isEmpty {
            self.rebuildLegacyLocalsFromEntries()
        }
    }

    mutating func appendLocal(url: URL, displayPath: String) {
        trackURLs.append(url)
        rawPaths.append(displayPath)
        entries.append(PlaylistEntry(source: .localFile(
            urlString: url.absoluteString,
            displayPath: displayPath
        )))
    }

    mutating func appendStream(url: URL, title: String, artist: String = "Internet Radio") {
        entries.append(PlaylistEntry(source: .stream(
            urlString: url.absoluteString,
            title: title,
            artist: artist
        )))
    }

    mutating func appendPlex(
        serverURL: String,
        ratingKey: String,
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) {
        entries.append(PlaylistEntry(source: .plex(
            serverURL: serverURL,
            ratingKey: ratingKey,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )))
    }

    mutating func appendAppleMusic(songID: String, title: String, artist: String) {
        entries.append(PlaylistEntry(source: .appleMusic(
            songID: songID,
            title: title,
            artist: artist
        )))
    }

    mutating func moveEntries(from offsets: IndexSet, to offset: Int) {
        entries.move(fromOffsets: offsets, toOffset: offset)
        rebuildLegacyLocalsFromEntries()
    }

    mutating func removeEntries(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        rebuildLegacyLocalsFromEntries()
    }

    mutating func rebuildEntriesFromLegacyLocals() {
        entries = zip(trackURLs, rawPaths).map { url, path in
            PlaylistEntry(source: .localFile(urlString: url.absoluteString, displayPath: path))
        }
        // If rawPaths shorter, pad from URLs.
        if rawPaths.count < trackURLs.count {
            for url in trackURLs.dropFirst(rawPaths.count) {
                entries.append(PlaylistEntry(source: .localFile(
                    urlString: url.absoluteString,
                    displayPath: url.path
                )))
            }
        }
    }

    mutating func rebuildLegacyLocalsFromEntries() {
        var urls: [URL] = []
        var paths: [String] = []
        for entry in entries {
            if case .localFile(let urlString, let displayPath) = entry.source {
                if let url = URL(string: urlString) {
                    urls.append(url)
                    paths.append(displayPath)
                }
            }
        }
        trackURLs = urls
        rawPaths = paths
    }
}

// MARK: - Codable app-owned persistence

struct PlaylistDocument: Codable, Sendable {
    var name: String
    var entries: [PlaylistEntry]
}

enum PlaylistPlaybackGate: Equatable, Sendable {
    case playable
    case needsAppleMusicSubscription
    case needsPlexServer
    case unsupported
}

enum PlaylistResolver {
    /// Map a playlist entry to a `Track` the existing AVPlayer queue can load,
    /// or a gate explaining why it cannot play yet.
    static func resolve(
        _ entry: PlaylistEntry,
        plexStreamURL: ((String, String) -> URL?)? = nil
    ) -> Result<Track, PlaylistPlaybackGate> {
        switch entry.source {
        case .localFile(let urlString, let displayPath):
            guard let url = URL(string: urlString) else { return .failure(.unsupported) }
            let title = URL(fileURLWithPath: displayPath)
                .deletingPathExtension().lastPathComponent
            return .success(Track(
                id: Track.stableID(for: url),
                url: url,
                title: title,
                artist: "Unknown Artist",
                album: "Unknown Album",
                duration: 0,
                hasArtwork: false,
                hasLyrics: false
            ))

        case .stream(let urlString, let title, let artist):
            guard let url = URL(string: urlString) else { return .failure(.unsupported) }
            return .success(Track(
                id: Track.stableID(for: url),
                url: url,
                title: title,
                artist: artist,
                album: "Radio",
                duration: 0,
                hasArtwork: false,
                hasLyrics: false
            ))

        case .plex(let serverURL, let ratingKey, let title, let artist, let album, let duration):
            guard let url = plexStreamURL?(serverURL, ratingKey) else {
                return .failure(.needsPlexServer)
            }
            return .success(Track(
                id: Track.stableID(for: url),
                url: url,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                hasArtwork: false,
                hasLyrics: false
            ))

        case .appleMusic:
            return .failure(.needsAppleMusicSubscription)
        }
    }
}
