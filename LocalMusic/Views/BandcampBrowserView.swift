import SwiftUI

/// Browse purchased Bandcamp collection via Subsonic (Fan Settings credentials).
struct BandcampBrowserView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Bindable private var client = BandcampSubsonicClient.shared
    @State private var tracks: [BandcampSubsonicClient.BandcampTrack] = []
    @State private var selectedAlbum: BandcampSubsonicClient.BandcampAlbum?
    @State private var addPayload: AddToPlaylistPayload?

    var body: some View {
        List {
            if !client.isConfigured {
                Section {
                    Text("Add your Bandcamp Subsonic username and password under Settings → Bandcamp. Generate them in Bandcamp Fan Settings → Subsonic. Only your purchased collection is available — no web scraping.")
                        .font(.footnote)
                        .foregroundStyle(ChibiTheme.textSecondary)
                    SourceChip(kind: .bandcamp)
                }
            } else {
                Section {
                    LabeledContent("Server", value: client.serverURLString)
                        .font(.caption)
                    Button("Refresh Collection") {
                        Task { await client.refreshCollection() }
                    }
                    .disabled(client.isLoading)
                    if client.isLoading {
                        ProgressView("Loading purchased albums…")
                    }
                } header: {
                    Text("Collection")
                } footer: {
                    Text("Purchased Bandcamp albums only, via \(BandcampSubsonicClient.defaultServerURL).")
                }

                if let err = client.lastError {
                    Section("Status") {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }

                if !client.albums.isEmpty {
                    Section("Albums") {
                        ForEach(client.albums) { album in
                            Button {
                                selectedAlbum = album
                                Task { tracks = await client.fetchAlbumTracks(albumID: album.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name)
                                        .foregroundStyle(ChibiTheme.textPrimary)
                                    Text(album.artist)
                                        .font(.caption)
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                }
                            }
                        }
                    }
                }

                if !tracks.isEmpty {
                    Section(selectedAlbum?.name ?? "Tracks") {
                        ForEach(tracks) { track in
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
                                    if let url = client.streamURL(forSongID: track.id) {
                                        addPayload = .stream(
                                            url: url,
                                            title: track.title,
                                            artist: track.artist
                                        )
                                    }
                                } label: {
                                    Label("Add to Playlist", systemImage: "text.badge.plus")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bandcamp")
        .chibiListChrome()
        .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ChibiTheme.amber)
        .sheet(item: $addPayload) { payload in
            AddToPlaylistSheet(payload: payload)
        }
        .task {
            if client.isConfigured {
                await client.refreshCollection()
            }
        }
    }

    private func play(_ track: BandcampSubsonicClient.BandcampTrack) {
        guard let url = client.streamURL(forSongID: track.id) else { return }
        let t = Track(
            id: Track.stableID(for: url),
            url: url,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.durationSeconds,
            hasArtwork: track.coverArtID != nil,
            hasLyrics: false
        )
        player.play(track: t, queue: [t], startIndex: 0)
    }
}
