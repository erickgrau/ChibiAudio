import SwiftUI

// MARK: - Playlist Item (resolved track or missing file)

private enum PlaylistItem: Identifiable {
    /// `queueIndex` is this item's offset among resolved tracks (missing
    /// rows skipped) — the play-queue `startIndex`, not `firstIndex` by id.
    case resolved(index: Int, track: Track, queueIndex: Int)
    case missing(index: Int, rawPath: String)

    var id: String {
        switch self {
        case .resolved(let index, _, _): return "r-\(index)"
        case .missing(let index, _):  return "m-\(index)"
        }
    }
}

struct PlaylistDetailView: View {
    @Binding var playlist: Playlist
    @Environment(LibraryStore.self) private var library
    // Intentionally does NOT observe `AudioPlayerManager`: that would force
    // a body re-render on every 0.5 s playback tick. Per-row playback state
    // is read inside `PlaylistTrackRowButton`; Play All lives in its own
    // inner view so this list is not subscribed to the player.
    @State private var showAddTracks = false

    /// Resolves URLs to tracks via the store's O(1) lookup. Memoizing this
    /// across body re-renders happens via the `@State` cache below.
    @State private var cachedItems: [PlaylistItem] = []
    @State private var cachedResolvedTracks: [Track] = []

    var body: some View {
        Group {
            if playlist.entries.isEmpty && playlist.trackURLs.isEmpty {
                emptyState
            } else {
                listBody
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTracks = true
                } label: {
                    Label("Add Tracks", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddTracks) {
            AddTracksSheet(playlist: $playlist)
        }
        .onAppear { rebuildCaches() }
        .onChange(of: playlist.entries) { _, _ in rebuildCaches() }
        .onChange(of: playlist.trackURLs) { _, _ in rebuildCaches() }
        .onChange(of: library.tracks.count) { _, _ in rebuildCaches() }
        // Track == is id-only, so a rescan that replaces files in place
        // (same count, same ids) does not fire `onChange(of: library.tracks)`.
        // Rebuild when the scan finishes so retags / replacements resolve.
        .onChange(of: library.isScanning) { _, scanning in
            if !scanning { rebuildCaches() }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(Color.accentColor)
            }
            Text("Empty Playlist")
                .font(.title3)
                .fontWeight(.medium)
            Text("Tap + to add tracks from your library. App-owned playlists can also hold Plex and radio items.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var listBody: some View {
        let resolved = cachedResolvedTracks
        let items = cachedItems
        let missingCount = items.reduce(0) { acc, item in
            if case .missing = item { return acc + 1 }
            return acc
        }

        List {
            if !resolved.isEmpty {
                Section {
                    PlaylistPlayAllButton(resolved: resolved)
                }
            }

            Section {
                ForEach(items) { item in
                    switch item {
                    case .resolved(_, let track, let queueIndex):
                        PlaylistTrackRowButton(
                            track: track,
                            resolvedQueue: resolved,
                            startIndex: queueIndex
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    case .missing(_, let rawPath):
                        MissingTrackRow(rawPath: rawPath)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
                .onMove { from, to in
                    playlist.moveEntries(from: from, to: to)
                    library.savePlaylist(playlist)
                }
                .onDelete { offsets in
                    playlist.removeEntries(at: offsets)
                    library.savePlaylist(playlist)
                }
            } header: {
                if missingCount > 0 {
                    Text("\(resolved.count) track\(resolved.count == 1 ? "" : "s"), \(missingCount) missing")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                } else if !resolved.isEmpty {
                    Text("\(resolved.count) track\(resolved.count == 1 ? "" : "s")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    // MARK: - Caching

    private func rebuildCaches() {
        var items: [PlaylistItem] = []
        var resolved: [Track] = []
        let plex = PlexClient.shared

        let sourceEntries: [PlaylistEntry] = playlist.entries.isEmpty
            ? zip(playlist.trackURLs, playlist.rawPaths).map { url, path in
                PlaylistEntry(source: .localFile(urlString: url.absoluteString, displayPath: path))
            }
            : playlist.entries

        items.reserveCapacity(sourceEntries.count)
        for (index, entry) in sourceEntries.enumerated() {
            switch PlaylistResolver.resolve(entry, plexStreamURL: { server, key in
                plex.directPlayURL(serverURL: server, ratingKey: key)
            }) {
            case .success(var track):
                if case .localFile = entry.source,
                   let libraryTrack = library.track(forURL: track.url) {
                    track = libraryTrack
                }
                items.append(.resolved(index: index, track: track, queueIndex: resolved.count))
                resolved.append(track)
            case .failure(let gate):
                let label: String
                switch gate {
                case .needsAppleMusicSubscription:
                    label = "\(entry.source.displayTitle) — needs Apple Music"
                case .needsPlexServer:
                    label = "\(entry.source.displayTitle) — sign in with Plex"
                case .unsupported:
                    label = entry.source.displayTitle
                case .playable:
                    label = entry.source.displayTitle
                }
                items.append(.missing(index: index, rawPath: label))
            }
        }
        self.cachedItems = items
        self.cachedResolvedTracks = resolved
    }
}

// MARK: - Play All (isolated player access)

private struct PlaylistPlayAllButton: View {
    let resolved: [Track]
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        Button {
            if let first = resolved.first {
                player.play(track: first, queue: resolved, startIndex: 0)
            }
        } label: {
            HStack {
                Spacer()
                Label("Play All", systemImage: "play.fill")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
    }
}

// MARK: - Playlist Track Row

/// Wraps a `TrackRow` with the play action. Pulled out so SwiftUI doesn't
/// re-evaluate the entire `PlaylistDetailView` body each time the player
/// ticks. `startIndex` is the offset in `resolvedQueue`, not `firstIndex`
/// by `Track.id` — duplicate files in the playlist play the tapped copy.
private struct PlaylistTrackRowButton: View {
    let track: Track
    let resolvedQueue: [Track]
    let startIndex: Int
    @Environment(AudioPlayerManager.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        Button {
            player.play(track: track, queue: resolvedQueue, startIndex: startIndex)
        } label: {
            TrackRow(track: track,
                     isCurrent: player.currentTrack?.id == track.id,
                     isActivelyPlaying: player.isPlaying
                         && player.currentTrack?.id == track.id)
        }
        .contextMenu {
            Button {
                renameText = track.title
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                ShareSheet.present(items: [track.url])
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .alert("Rename Track", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { library.renameTrack(track, to: renameText) }
        }
    }
}

// MARK: - Missing Track Row

struct MissingTrackRow: View {
    let rawPath: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rawPath)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("File not found")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Tracks Sheet

struct AddTracksSheet: View {
    @Binding var playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var searchDraft = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    /// Local mutable snapshot. Toggles edit this copy only; we call
    /// `library.savePlaylist` once on dismiss so adding a hundred tracks
    /// no longer rewrites the .m3u file a hundred times.
    @State private var workingPlaylist: Playlist?
    @State private var includedURLs: Set<URL> = []
    @State private var dirty = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredLibrary, id: \.id) { track in
                    let key = track.url.standardized
                    let included = includedURLs.contains(key)
                    Button {
                        toggle(track)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(included ? Color.accentColor : .secondary)

                            TrackRow(track: track)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchDraft, prompt: "Search library")
            .onChange(of: searchDraft) { _, newValue in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        debouncedQuery = newValue
                    }
                }
            }
            .navigationTitle("Add Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        commitIfNeeded()
                        dismiss()
                    }
                }
            }
            .onAppear {
                workingPlaylist = playlist
                includedURLs = Set(playlist.trackURLs.map { $0.standardized })
            }
            .onDisappear {
                commitIfNeeded()
            }
        }
    }

    private var filteredLibrary: [Track] {
        // `List` is lazy; no empty-query ceiling. The store's pre-lowercased
        // index does the actual matching.
        library.searchTracks(query: debouncedQuery)
    }

    private func toggle(_ track: Track) {
        guard var working = workingPlaylist else { return }
        if working.entries.isEmpty, !working.trackURLs.isEmpty {
            working.rebuildEntriesFromLegacyLocals()
        }
        let key = track.url.standardized
        if includedURLs.contains(key) {
            includedURLs.remove(key)
            let indices = working.entries.enumerated().compactMap { idx, entry -> Int? in
                if case .localFile(let urlString, _) = entry.source,
                   URL(string: urlString)?.standardized == key {
                    return idx
                }
                return nil
            }
            working.removeEntries(at: IndexSet(indices))
        } else {
            includedURLs.insert(key)
            let baseDir = working.fileURL.deletingLastPathComponent()
            working.appendLocal(
                url: track.url,
                displayPath: MetadataLoader.relativePath(for: track.url, relativeTo: baseDir)
            )
        }
        workingPlaylist = working
        dirty = true
    }

    private func commitIfNeeded() {
        guard dirty, let working = workingPlaylist else { return }
        // `library.savePlaylist` is the single source of truth: it updates
        // the shared `playlists` array and writes the file once. The parent
        // binding reads through that array, so it'll observe the change on
        // its next render. No second write via `playlist = working`.
        library.savePlaylist(working)
        dirty = false
    }
}
