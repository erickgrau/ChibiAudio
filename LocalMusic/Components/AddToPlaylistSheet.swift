import SwiftUI

/// Payload for Soft PASS “Add to Playlist” (Library / Now Playing / Radio / Plex).
enum AddToPlaylistPayload: Equatable, Identifiable {
    case local(Track)
    case stream(url: URL, title: String, artist: String)
    case plex(
        serverURL: String,
        ratingKey: String,
        title: String,
        artist: String,
        album: String,
        duration: Double
    )

    var id: String {
        switch self {
        case .local(let track):
            return "local:\(track.id.uuidString)"
        case .stream(let url, let title, _):
            return "stream:\(url.absoluteString):\(title)"
        case .plex(_, let ratingKey, let title, _, _, _):
            return "plex:\(ratingKey):\(title)"
        }
    }
}

/// Glass sheet: pick an existing playlist or create a new app-owned one.
struct AddToPlaylistSheet: View {
    let payload: AddToPlaylistPayload
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.playlists.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(library.playlists) { playlist in
                                Button {
                                    add(to: playlist)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "music.note.list")
                                            .foregroundStyle(ChibiTheme.amber)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.name)
                                                .foregroundStyle(ChibiTheme.textPrimary)
                                            Text(playlist.isAppOwned ? "App playlist" : "Folder playlist")
                                                .font(.caption)
                                                .foregroundStyle(ChibiTheme.textTertiary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        } header: {
                            Text("Choose a playlist")
                        }
                    }
                    .chibiListChrome()
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newPlaylistName = ""
                        showCreateAlert = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    createAndAdd()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Creates an app playlist that can mix files, radio, and Plex.")
            }
            .tint(ChibiTheme.amber)
            .chibiCanvas()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ChibiTheme.softGlass)
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                    )
                Image(systemName: "music.note.list")
                    .font(.system(size: 32))
                    .foregroundStyle(ChibiTheme.amber)
            }
            Text("No Playlists Yet")
                .font(ChibiTheme.titleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Create a playlist to save this track.")
                .font(.body)
                .foregroundStyle(ChibiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                newPlaylistName = ""
                showCreateAlert = true
            } label: {
                Text("New Playlist")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(ChibiTheme.amber)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createAndAdd() {
        guard let playlist = library.createPlaylist(name: newPlaylistName) else { return }
        add(to: playlist)
    }

    private func add(to playlist: Playlist) {
        guard let idx = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var updated = library.playlists[idx]
        switch payload {
        case .local(let track):
            let baseDir = updated.fileURL.deletingLastPathComponent()
            let display = MetadataLoader.relativePath(for: track.url, relativeTo: baseDir)
            updated.appendLocal(url: track.url, displayPath: display)
        case .stream(let url, let title, let artist):
            updated.appendStream(url: url, title: title, artist: artist)
        case .plex(let serverURL, let ratingKey, let title, let artist, let album, let duration):
            updated.appendPlex(
                serverURL: serverURL,
                ratingKey: ratingKey,
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
        }
        library.savePlaylist(updated)
        dismiss()
    }
}
