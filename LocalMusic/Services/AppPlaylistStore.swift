import Foundation

/// Persistence for app-owned multi-source playlists (Documents/ChibiPlaylists/*.json).
/// These are free to mix local files, Plex, and radio — no subscription.
enum AppPlaylistStore {

    #if DEBUG
    /// Test-only override. When non-nil, playlists are written here instead
    /// of `Documents/ChibiPlaylists/`. Set sequentially in `setUp` / `tearDown`;
    /// not safe for parallel test plans.
    nonisolated(unsafe) static var directoryOverride: URL?
    #endif

    private static var directory: URL {
        let dir: URL = {
            #if DEBUG
            if let override = directoryOverride { return override }
            #endif
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docs.appendingPathComponent("ChibiPlaylists", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAll() -> [Playlist] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> Playlist? in
                guard let data = try? Data(contentsOf: url),
                      let doc = try? JSONDecoder().decode(PlaylistDocument.self, from: data)
                else { return nil }
                var playlist = Playlist(
                    fileURL: url,
                    name: doc.name,
                    entries: doc.entries,
                    trackURLs: [],
                    rawPaths: []
                )
                playlist.rebuildLegacyLocalsFromEntries()
                return playlist
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func save(_ playlist: Playlist) {
        let doc = PlaylistDocument(name: playlist.name, entries: playlist.entries)
        do {
            let data = try JSONEncoder().encode(doc)
            try data.write(to: playlist.fileURL, options: .atomic)
        } catch {
            Log.persistence.error("Failed to save app playlist: \(error.localizedDescription)")
        }
    }

    static func create(name: String) -> Playlist {
        let base = MetadataLoader.sanitizedPlaylistBaseName(name)
        var fileURL = directory.appendingPathComponent("\(base).json")
        var n = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = directory.appendingPathComponent("\(base) \(n).json")
            n += 1
        }
        let playlist = Playlist(
            fileURL: fileURL,
            name: fileURL.deletingPathExtension().lastPathComponent,
            entries: [],
            trackURLs: [],
            rawPaths: []
        )
        save(playlist)
        return playlist
    }

    static func delete(_ playlist: Playlist) {
        try? FileManager.default.removeItem(at: playlist.fileURL)
    }
}
