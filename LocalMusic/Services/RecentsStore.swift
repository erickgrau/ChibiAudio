import Foundation
import Observation

/// One recently played item. Snapshot metadata so Home still renders if the
/// library entry is gone; resolve against `LibraryStore` when possible.
struct RecentPlay: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var hasArtwork: Bool
    var playedAt: Date

    init(track: Track, playedAt: Date = .now) {
        self.id = track.id
        self.url = track.url
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.duration = track.duration
        self.hasArtwork = track.hasArtwork
        self.playedAt = playedAt
    }

    func asTrack() -> Track {
        Track(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            hasArtwork: hasArtwork,
            hasLyrics: false
        )
    }
}

/// Minimal Soft PASS Recents: JSON under Documents, capped list, most-recent first.
@Observable
@MainActor
final class RecentsStore {

    private(set) var entries: [RecentPlay] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let maxCount: Int

    init(documentsURL: URL? = nil, maxCount: Int = 40) {
        let docs = documentsURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("recents.json")
        self.maxCount = max(1, maxCount)
        entries = Self.loadSync(from: fileURL)
    }

    /// Record a play. Dedupes by track `id`, moves to front, trims, persists.
    func record(_ track: Track) {
        var next = entries.filter { $0.id != track.id }
        next.insert(RecentPlay(track: track), at: 0)
        if next.count > maxCount {
            next = Array(next.prefix(maxCount))
        }
        entries = next
        persist(next)
    }

    /// Prefer live library metadata when the file is still indexed.
    func resolvedTracks(using library: LibraryStore) -> [Track] {
        entries.map { entry in
            library.track(forURL: entry.url) ?? entry.asTrack()
        }
    }

    func clear() {
        entries = []
        persist([])
    }

    // MARK: - Persistence

    private func persist(_ entries: [RecentPlay]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.persistence.error("Failed to save recents: \(error.localizedDescription)")
        }
    }

    private static func loadSync(from url: URL) -> [RecentPlay] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RecentPlay].self, from: data)
        } catch {
            Log.persistence.error("Failed to load recents: \(error.localizedDescription)")
            return []
        }
    }
}
