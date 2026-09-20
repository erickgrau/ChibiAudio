import SwiftUI

struct PlexBrowserView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Bindable private var client = PlexClient.shared
    @State private var tracks: [PlexClient.PlexTrack] = []
    @State private var selectedSection: PlexClient.PlexDirectory?
    @State private var addPayload: AddToPlaylistPayload?

    var body: some View {
        List {
            if !client.isConfigured {
                Section {
                    Text("Add your Plex Media Server URL and X-Plex-Token under Settings → Plex. Basic LAN streaming of your own library does not require Plex Pass.")
                        .font(.footnote)
                        .foregroundStyle(ChibiTheme.textSecondary)
                    SourceChip(kind: .plex)
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
                                    Text(track.title)
                                        .foregroundStyle(ChibiTheme.textPrimary)
                                    Text("\(track.artist) — \(track.album)")
                                        .font(.caption)
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                }
                            }
                            .contextMenu {
                                Button {
                                    addPayload = .plex(
                                        serverURL: client.serverURLString,
                                        ratingKey: track.ratingKey,
                                        title: track.title,
                                        artist: track.artist,
                                        album: track.album,
                                        duration: track.durationMs / 1000
                                    )
                                } label: {
                                    Label("Add to Playlist", systemImage: "text.badge.plus")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Plex")
        .chibiListChrome()
        .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ChibiTheme.amber)
        .sheet(item: $addPayload) { payload in
            AddToPlaylistSheet(payload: payload)
        }
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
}
