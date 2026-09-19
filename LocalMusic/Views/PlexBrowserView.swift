import SwiftUI

struct PlexBrowserView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(LibraryStore.self) private var library
    @Bindable private var client = PlexClient.shared
    @State private var tracks: [PlexClient.PlexTrack] = []
    @State private var selectedSection: PlexClient.PlexDirectory?

    var body: some View {
        List {
            if !client.isConfigured {
                Section {
                    Text("Add your Plex Media Server URL and X-Plex-Token under Settings → Plex. Basic LAN streaming of your own library does not require Plex Pass.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Music Libraries") {
                    ForEach(client.musicSections) { section in
                        Button(section.title) {
                            selectedSection = section
                            Task { tracks = await client.fetchTracks(sectionKey: section.key) }
                        }
                    }
                    Button("Refresh") {
                        Task { await client.refreshMusicLibraries() }
                    }
                }

                if let err = client.lastError {
                    Section("Status") {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }

                if !tracks.isEmpty {
                    Section(selectedSection?.title ?? "Tracks") {
                        ForEach(tracks.prefix(200)) { track in
                            Button {
                                play(track)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).foregroundStyle(.primary)
                                    Text("\(track.artist) — \(track.album)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button("Add to Playlist") {
                                    addToPlaylist(track)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Plex")
        .task {
            if client.isConfigured {
                await client.refreshMusicLibraries()
            }
        }
    }

    private func play(_ track: PlexClient.PlexTrack) {
        guard let url = client.directPlayURL(
            serverURL: client.serverURLString,
            ratingKey: track.ratingKey
        ) else { return }
        let t = Track(
            id: Track.stableID(for: url),
            url: url,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.durationMs / 1000,
            hasArtwork: false,
            hasLyrics: false
        )
        player.play(track: t, queue: [t], startIndex: 0)
    }

    private func addToPlaylist(_ track: PlexClient.PlexTrack) {
        guard var playlist = library.playlists.first else { return }
        playlist.appendPlex(
            serverURL: client.serverURLString,
            ratingKey: track.ratingKey,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.durationMs / 1000
        )
        library.savePlaylist(playlist)
    }
}
