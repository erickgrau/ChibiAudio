#if os(macOS)
import SwiftUI

/// Album grid built from the library's own tags (see `LibraryBrowseIndex`).
struct MacAlbumsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)]

    var body: some View {
        NavigationStack {
            let albums = filtered(LibraryBrowseIndex.albums(from: library.tracks))
            Group {
                if library.tracks.isEmpty {
                    MacLibraryEmptyState()
                } else if albums.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(albums) { album in
                                NavigationLink(value: album) {
                                    AlbumTile(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(for: AlbumSummary.self) { album in
                MacTrackCollectionView(
                    title: album.title,
                    subtitle: [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                    tracks: album.tracks
                )
            }
            .searchable(text: $query, prompt: "Search albums or artists")
            .chibiCanvas()
        }
    }

    private func filtered(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }
}

private struct AlbumTile: View {
    let album: AlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(
                trackURL: album.artworkTrack?.url,
                hasArtwork: album.artworkTrack?.hasArtwork ?? false,
                pointSize: 200
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(album.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(ChibiTheme.textPrimary)
                .lineLimit(1)
            Text(album.artist)
                .font(.caption)
                .foregroundStyle(ChibiTheme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(album.artist), \(album.tracks.count) songs")
    }
}

/// Artist list built from the library's own tags.
struct MacArtistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let artists = filtered(LibraryBrowseIndex.artists(from: library.tracks))
            Group {
                if library.tracks.isEmpty {
                    MacLibraryEmptyState()
                } else if artists.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(artists) { artist in
                        NavigationLink(value: artist) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                    .foregroundStyle(ChibiTheme.textPrimary)
                                Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s") · \(artist.tracks.count) song\(artist.tracks.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(ChibiTheme.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .chibiListChrome()
                }
            }
            .navigationTitle("Artists")
            .navigationDestination(for: ArtistSummary.self) { artist in
                MacTrackCollectionView(
                    title: artist.name,
                    subtitle: "\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")",
                    tracks: artist.tracks
                )
            }
            .searchable(text: $query, prompt: "Search artists")
            .chibiCanvas()
        }
    }

    private func filtered(_ artists: [ArtistSummary]) -> [ArtistSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}

/// Album or artist detail: Play / Shuffle header and the shared track rows
/// (context menu: Play Next, Add to Queue, Add to Playlist, Rename, Share).
private struct MacTrackCollectionView: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        guard let first = tracks.first else { return }
                        player.play(track: first, queue: tracks, startIndex: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ChibiTheme.amber)

                    Button {
                        // Shuffled order for this play only; the Shuffle
                        // setting in the player bar is left as the user set it.
                        let order = tracks.shuffled()
                        guard let first = order.first else { return }
                        player.play(track: first, queue: order, startIndex: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(ChibiTheme.textSecondary)
                }
                .disabled(tracks.isEmpty)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(tracks) { track in
                    TrackRowButton(track: track, queue: tracks)
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .chibiListChrome()
        .navigationTitle(title)
    }
}

/// Shown by Albums and Artists before any music folder is scanned.
private struct MacLibraryEmptyState: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label(library.isScanning ? "Scanning…" : "No Music Yet", systemImage: "music.note.house")
        } description: {
            Text(library.isScanning
                 ? "Albums and artists appear as the folder scan finds tagged files."
                 : "Choose a music folder to browse albums and artists from your files' tags.")
        } actions: {
            if !library.isScanning {
                Button("Choose Music Folder…") { MacFolderAccess.chooseFolder(library: library) }
                    .buttonStyle(.borderedProminent)
                    .tint(ChibiTheme.amber)
            }
        }
    }
}
#endif
