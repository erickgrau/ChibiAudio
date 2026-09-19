import SwiftUI

struct RadioView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var stations: [RadioStation] = RadioCatalog.allStations()
    @State private var customURL = ""
    @State private var customName = ""
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Free Icecast / Shoutcast-style streams. Paste any http(s) stream URL. Not a paid catalog.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Stations") {
                    ForEach(stations) { station in
                        Button {
                            play(station)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.name)
                                    .foregroundStyle(.primary)
                                Text(station.genre)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Add to Playlist") {
                                addToFirstPlaylist(station)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Radio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add URL", systemImage: "plus")
                    }
                }
            }
            .alert("Add Stream URL", isPresented: $showAdd) {
                TextField("Name", text: $customName)
                TextField("https://…", text: $customURL)
                Button("Add") { addCustom() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func play(_ station: RadioStation) {
        let track = Track(
            id: Track.stableID(for: station.streamURL),
            url: station.streamURL,
            title: station.name,
            artist: station.genre,
            album: "Radio",
            duration: 0,
            hasArtwork: false,
            hasLyrics: false
        )
        player.play(track: track, queue: [track], startIndex: 0)
    }

    private func addCustom() {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.host ?? "Stream")
            : customName
        var user = RadioCatalog.loadUserStations()
        let station = RadioStation(name: name, genre: "Custom", streamURL: url, isUserAdded: true)
        user.append(station)
        RadioCatalog.saveUserStations(user)
        stations = RadioCatalog.allStations()
        customURL = ""
        customName = ""
    }

    private func addToFirstPlaylist(_ station: RadioStation) {
        guard var playlist = library.playlists.first else { return }
        playlist.appendStream(url: station.streamURL, title: station.name, artist: station.genre)
        library.savePlaylist(playlist)
    }
}
