import AVFoundation
import UIKit

/// Progress payload published while a folder scan is in flight.
struct ScanProgress: Sendable, Equatable {
    var completed: Int
    var total: Int
}

/// Distinguishes a successful scan that found nothing from a failed
/// root listing. An empty folder is a real result (the library should
/// clear); an inaccessible folder should keep the cached library.
struct FolderScanResult: Sendable {
    enum Outcome: Sendable {
        case success([Track])
        case inaccessible
    }
    var outcome: Outcome
}

struct MetadataLoader {

    /// Audio extensions accepted into the library. Playability is decided by
    /// `CodecRouter` (native vs needs-decode vs DSD) at playback time.
    static let supportedExtensions: Set<String> = CodecRouter.libraryExtensions

    static let playlistExtensions: Set<String> = [
        "m3u", "m3u8", "pls"
    ]

    /// Maximum number of concurrent metadata loads. AVFoundation hits the file
    /// system aggressively, so we cap concurrency to avoid descriptor pressure.
    private static let scanConcurrency = 8

    // MARK: - Folder Scanning

    /// Caller must ensure security-scoped access is already active on `url`.
    /// Reports progress periodically via `onProgress`. Collection runs off
    /// the caller's actor so a large tree walk does not hitch the main thread.
    static func scanFolder(at url: URL,
                           onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> FolderScanResult {
        // Detached so `collectAudioFiles` is not the first synchronous work
        // on whoever called us (typically `@MainActor` LibraryStore).
        let collectTask = Task.detached(priority: .userInitiated) {
            collectAudioFiles(in: url)
        }
        let listing = await withTaskCancellationHandler {
            await collectTask.value
        } onCancel: {
            collectTask.cancel()
        }

        guard let audioURLs = listing else {
            Log.scan.warning("Scan folder: \(url.lastPathComponent) — root listing failed")
            return FolderScanResult(outcome: .inaccessible)
        }
        if Task.isCancelled {
            return FolderScanResult(outcome: .success([]))
        }

        let total = audioURLs.count
        Log.scan.info("Scan folder: \(url.lastPathComponent) — found \(total) audio files")
        guard total > 0 else {
            onProgress?(ScanProgress(completed: 0, total: 0))
            return FolderScanResult(outcome: .success([]))
        }

        var tracks: [Track] = []
        tracks.reserveCapacity(total)

        // The order tracks land in is determined by the TaskGroup; LibraryStore
        // re-sorts according to the active sort option in `ingest`, so we
        // skip an extra `sorted` here.
        await withTaskGroup(of: Track.self) { group in
            var iterator = audioURLs.makeIterator()
            let seed = min(scanConcurrency, total)
            for _ in 0..<seed {
                guard let next = iterator.next() else { break }
                group.addTask { await loadTrack(from: next) }
            }
            var completed = 0
            for await track in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                tracks.append(track)
                completed += 1
                if completed % 25 == 0 || completed == total {
                    onProgress?(ScanProgress(completed: completed, total: total))
                }
                if let next = iterator.next() {
                    group.addTask { await loadTrack(from: next) }
                }
            }
        }

        return FolderScanResult(outcome: .success(tracks))
    }

    /// Iterative walk via `contentsOfDirectory(at:)`. Returns `nil` when the
    /// *root* listing fails; nested directories that cannot be listed are
    /// skipped. An explicit stack avoids overflowing on deep trees.
    ///
    /// `contentsOfDirectory` preserves the parent URL's path prefix (critical
    /// for security-scoped access), unlike `FileManager.enumerator` which
    /// resolves symlinks and can produce `/private/var/...` paths that fall
    /// outside the security scope.
    private static func collectAudioFiles(in directory: URL) -> [URL]? {
        let fm = FileManager.default
        guard let rootContents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var results: [URL] = []
        var stack: [URL] = []
        consumeListing(rootContents, files: &results, stack: &stack, matching: supportedExtensions)
        while let current = stack.popLast() {
            if Task.isCancelled { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            consumeListing(contents, files: &results, stack: &stack, matching: supportedExtensions)
        }
        return results
    }

    private static func consumeListing(_ contents: [URL],
                                       files: inout [URL],
                                       stack: inout [URL],
                                       matching extensions: Set<String>) {
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                stack.append(item)
            } else if extensions.contains(item.pathExtension.lowercased()) {
                files.append(item)
            }
        }
    }

    // MARK: - Single Track Metadata

    static func loadTrack(from url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        var title = fallbackTitle
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration: Double = 0
        var artworkData: Data?

        do {
            let durationTime = try await asset.load(.duration)
            duration = CMTimeGetSeconds(durationTime)
            if duration.isNaN || duration.isInfinite { duration = 0 }
        } catch { }

        do {
            let metadata = try await asset.load(.commonMetadata)

            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        album = value
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        artworkData = data
                    }
                default:
                    break
                }
            }
        } catch { }

        // Persist artwork to disk cache instead of the in-memory Track.
        var hasArtwork = false
        if let data = artworkData, !data.isEmpty {
            ArtworkCache.storeSync(data, for: url)
            hasArtwork = true
        } else {
            // Clean up stale artwork from a prior scan.
            if ArtworkCache.hasArtwork(for: url) {
                ArtworkCache.remove(for: url)
            }
        }

        // Persist lyrics to disk cache; only `hasLyrics` lives on the Track.
        let unsynced = await extractUnsyncedLyrics(from: asset)
        let synced = await extractSyncedLyrics(from: asset)
        let lyrics = TrackLyrics(unsynced: unsynced, synced: synced)
        var hasLyrics = false
        if !lyrics.isEmpty {
            LyricsCache.storeSync(lyrics, for: url)
            hasLyrics = true
        } else if LyricsCache.hasLyrics(for: url) {
            LyricsCache.remove(for: url)
        }

        return Track(
            id: Track.stableID(for: url),
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            hasArtwork: hasArtwork,
            hasLyrics: hasLyrics
        )
    }

    // MARK: - Lyrics Extraction

    private static func extractUnsyncedLyrics(from asset: AVAsset) async -> String? {
        // Try iTunes metadata (©lyr)
        let iTunesFormats: [AVMetadataFormat] = [.iTunesMetadata]
        for format in iTunesFormats {
            if let items = try? await asset.loadMetadata(for: format) {
                for item in items {
                    if let key = item.identifier,
                       key == .iTunesMetadataLyrics,
                       let value = try? await item.load(.stringValue),
                       !value.isEmpty {
                        return value
                    }
                }
            }
        }

        // Try ID3 metadata (USLT)
        if let items = try? await asset.loadMetadata(for: .id3Metadata) {
            for item in items {
                if let key = item.identifier,
                   key == .id3MetadataUnsynchronizedLyric,
                   let value = try? await item.load(.stringValue),
                   !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    private static func extractSyncedLyrics(from asset: AVAsset) async -> [SyncedLyricLine]? {
        guard let items = try? await asset.loadMetadata(for: .id3Metadata) else { return nil }

        for item in items {
            if let key = item.identifier,
               key == .id3MetadataSynchronizedLyric,
               let data = try? await item.load(.dataValue) {
                return parseSYLT(data: data)
            }
        }
        return nil
    }

    /// Parse ID3v2 SYLT frame payload.
    /// Format: encoding(1) language(3) timestampFormat(1) contentType(1)
    ///         contentDescriptor(null-terminated) then repeated [text\0][4-byte ms timestamp]
    static func parseSYLT(data: Data) -> [SyncedLyricLine]? {
        guard data.count > 6 else { return nil }

        let encoding = data[0]
        // bytes 1-3: language (skip)
        let timestampFormat = data[4]
        // byte 5: content type (skip)

        // Skip past content descriptor (null-terminated string after the 6-byte header)
        var offset = 6
        offset = skipNullTerminatedString(in: data, from: offset, encoding: encoding)
        guard offset < data.count else { return nil }

        var lines: [SyncedLyricLine] = []

        while offset < data.count {
            // Read null-terminated text
            guard let (text, nextOffset) = readNullTerminatedString(in: data, from: offset, encoding: encoding) else {
                break
            }
            offset = nextOffset

            // Read 4-byte big-endian timestamp
            guard offset + 4 <= data.count else { break }
            let rawTimestamp = UInt32(data[offset]) << 24
                | UInt32(data[offset + 1]) << 16
                | UInt32(data[offset + 2]) << 8
                | UInt32(data[offset + 3])
            offset += 4

            let seconds: Double
            if timestampFormat == 2 {
                // Milliseconds
                seconds = Double(rawTimestamp) / 1000.0
            } else {
                // MPEG frames — treat as ms as a fallback
                seconds = Double(rawTimestamp) / 1000.0
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(SyncedLyricLine(timestamp: seconds, text: trimmed))
            }
        }

        guard !lines.isEmpty else { return nil }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private static func skipNullTerminatedString(in data: Data, from offset: Int, encoding: UInt8) -> Int {
        let isUTF16 = encoding == 1 || encoding == 2
        var i = offset
        if isUTF16 {
            while i + 1 < data.count {
                if data[i] == 0 && data[i + 1] == 0 { return i + 2 }
                i += 2
            }
        } else {
            while i < data.count {
                if data[i] == 0 { return i + 1 }
                i += 1
            }
        }
        return data.count
    }

    private static func readNullTerminatedString(in data: Data, from offset: Int, encoding: UInt8) -> (String, Int)? {
        let isUTF16 = encoding == 1 || encoding == 2
        var end = offset

        if isUTF16 {
            while end + 1 < data.count {
                if data[end] == 0 && data[end + 1] == 0 { break }
                end += 2
            }
            let strData = data[offset..<end]
            let swiftEncoding: String.Encoding = encoding == 2 ? .utf16BigEndian : .utf16
            let text = String(data: strData, encoding: swiftEncoding) ?? ""
            return (text, end + 2)
        } else {
            while end < data.count && data[end] != 0 {
                end += 1
            }
            let strData = data[offset..<end]
            let swiftEncoding: String.Encoding = encoding == 3 ? .utf8 : .isoLatin1
            let text = String(data: strData, encoding: swiftEncoding) ?? ""
            return (text, end + 1)
        }
    }

    // MARK: - Playlist Discovery

    static func scanPlaylists(in directory: URL) async -> [Playlist] {
        let walk = Task.detached(priority: .userInitiated) { () -> [Playlist] in
            let files = collectPlaylistFiles(in: directory)
            return files.compactMap { parsePlaylist(at: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return await withTaskCancellationHandler {
            await walk.value
        } onCancel: {
            walk.cancel()
        }
    }

    /// Iterative walk; nested listing failures are skipped. Same
    /// `contentsOfDirectory` rationale as `collectAudioFiles`.
    private static func collectPlaylistFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let rootContents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        var stack: [URL] = []
        consumeListing(rootContents, files: &results, stack: &stack, matching: playlistExtensions)
        while let current = stack.popLast() {
            if Task.isCancelled { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            consumeListing(contents, files: &results, stack: &stack, matching: playlistExtensions)
        }
        return results
    }

    static func parsePlaylist(at url: URL) -> Playlist? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Try Latin-1 as fallback
            guard let content = try? String(contentsOf: url, encoding: .isoLatin1) else {
                Log.scan.warning("Failed to read playlist: \(url.lastPathComponent)")
                return nil
            }
            return parsePlaylistContent(content, url: url)
        }
        return parsePlaylistContent(content, url: url)
    }

    private static func parsePlaylistContent(_ content: String, url: URL) -> Playlist? {
        let ext = url.pathExtension.lowercased()
        let baseDir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent

        let pairs: [(rawPath: String, url: URL)]
        if ext == "pls" {
            pairs = parsePLS(content, baseDir: baseDir)
        } else {
            pairs = parseM3U(content, baseDir: baseDir)
        }

        var entries: [PlaylistEntry] = []
        var trackURLs: [URL] = []
        var rawPaths: [String] = []
        for pair in pairs {
            if pair.url.isFileURL {
                trackURLs.append(pair.url)
                rawPaths.append(pair.rawPath)
                entries.append(PlaylistEntry(source: .localFile(
                    urlString: pair.url.absoluteString,
                    displayPath: pair.rawPath
                )))
            } else {
                let title = pair.url.host ?? pair.rawPath
                entries.append(PlaylistEntry(source: .stream(
                    urlString: pair.url.absoluteString,
                    title: title,
                    artist: "Stream"
                )))
            }
        }

        return Playlist(
            fileURL: url,
            name: name,
            entries: entries,
            trackURLs: trackURLs,
            rawPaths: rawPaths
        )
    }

    private static func parseM3U(_ content: String, baseDir: URL) -> [(rawPath: String, url: URL)] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [(rawPath: String, url: URL)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let resolved = resolveTrackPath(trimmed, baseDir: baseDir) {
                entries.append((trimmed, resolved))
            }
        }
        return entries
    }

    private static func parsePLS(_ content: String, baseDir: URL) -> [(rawPath: String, url: URL)] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [(rawPath: String, url: URL)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match File1=..., File2=..., etc.
            guard trimmed.lowercased().hasPrefix("file") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let path = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if let resolved = resolveTrackPath(path, baseDir: baseDir) {
                entries.append((path, resolved))
            }
        }
        return entries
    }

    static func resolveTrackPath(_ path: String, baseDir: URL) -> URL? {
        guard !path.isEmpty else { return nil }
        let lower = path.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: path)
        }
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = baseDir.appendingPathComponent(path).standardized
        }
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }
        return url
    }

    // MARK: - Playlist Writing

    static func writePlaylist(_ playlist: Playlist) {
        // App-owned unified playlists persist as JSON (multi-source).
        if playlist.isAppOwned {
            AppPlaylistStore.save(playlist)
            return
        }

        let ext = playlist.fileURL.pathExtension.lowercased()
        let baseDir = playlist.fileURL.deletingLastPathComponent()
        let content: String

        if ext == "pls" {
            content = buildPLS(playlist: playlist, baseDir: baseDir)
        } else {
            content = buildM3U(playlist: playlist, baseDir: baseDir)
        }

        do {
            try content.write(to: playlist.fileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.persistence.error("Failed to write playlist \(playlist.fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func createPlaylist(name: String, in directory: URL) -> Playlist {
        let baseName = sanitizedPlaylistBaseName(name)
        let fileURL = uniquePlaylistFileURL(baseName: baseName, in: directory)
        let displayName = fileURL.deletingPathExtension().lastPathComponent
        let playlist = Playlist(
            fileURL: fileURL,
            name: displayName,
            entries: [],
            trackURLs: [],
            rawPaths: []
        )
        let content = "#EXTM3U\n"
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.persistence.error("Failed to create playlist \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        return playlist
    }

    /// App-owned multi-source playlist (Documents), not tied to the music folder.
    static func createAppOwnedPlaylist(name: String) -> Playlist {
        AppPlaylistStore.create(name: name)
    }

    /// Replaces `/` and `:` and strips `..` so `appendingPathComponent`
    /// cannot nest or escape `directory`.
    static func sanitizedPlaylistBaseName(_ name: String) -> String {
        var result = name
        result = result.replacingOccurrences(of: "/", with: "-")
        result = result.replacingOccurrences(of: ":", with: "-")
        while result.contains("..") {
            result = result.replacingOccurrences(of: "..", with: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Playlist" : result
    }

    private static func uniquePlaylistFileURL(baseName: String, in directory: URL) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).m3u")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(n).m3u")
            n += 1
        }
        return candidate
    }

    static func relativePath(for trackURL: URL, relativeTo baseDir: URL) -> String {
        let trackPath = trackURL.standardized.path
        let basePath = baseDir.standardized.path.hasSuffix("/")
            ? baseDir.standardized.path
            : baseDir.standardized.path + "/"
        if trackPath.hasPrefix(basePath) {
            return String(trackPath.dropFirst(basePath.count))
        }
        return trackPath
    }

    private static func buildM3U(playlist: Playlist, baseDir: URL) -> String {
        var lines = ["#EXTM3U"]
        if playlist.entries.isEmpty {
            for url in playlist.trackURLs {
                lines.append(relativePath(for: url, relativeTo: baseDir))
            }
        } else {
            for entry in playlist.entries {
                switch entry.source {
                case .localFile(let urlString, let displayPath):
                    if let url = URL(string: urlString), url.isFileURL {
                        lines.append(relativePath(for: url, relativeTo: baseDir))
                    } else {
                        lines.append(displayPath)
                    }
                case .stream(let urlString, let title, let artist):
                    lines.append("#EXTINF:-1,\(artist) - \(title)")
                    lines.append(urlString)
                case .plex(_, _, let title, let artist, _, _):
                    lines.append("#EXTINF:-1,\(artist) - \(title) (Plex — open in ChibiAudio)")
                case .appleMusic(_, let title, let artist):
                    lines.append("#EXTINF:-1,\(artist) - \(title) (Apple Music — needs subscription)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildPLS(playlist: Playlist, baseDir: URL) -> String {
        var lines = ["[playlist]"]
        var num = 0
        let exportables: [(String, String)] = {
            if !playlist.entries.isEmpty {
                return playlist.entries.compactMap { entry in
                    switch entry.source {
                    case .localFile(let urlString, _):
                        guard let url = URL(string: urlString) else { return nil }
                        return (relativePath(for: url, relativeTo: baseDir), entry.source.displayTitle)
                    case .stream(let urlString, let title, _):
                        return (urlString, title)
                    default:
                        return nil
                    }
                }
            }
            return playlist.trackURLs.map {
                (relativePath(for: $0, relativeTo: baseDir), $0.deletingPathExtension().lastPathComponent)
            }
        }()
        for (path, title) in exportables {
            num += 1
            lines.append("File\(num)=\(path)")
            lines.append("Title\(num)=\(title)")
        }
        lines.append("NumberOfEntries=\(num)")
        lines.append("Version=2")
        return lines.joined(separator: "\n") + "\n"
    }
}
