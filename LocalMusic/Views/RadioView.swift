import SwiftUI

struct RadioView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var stations: [RadioStation] = RadioCatalog.allStations()
    @State private var customURL = ""
    @State private var customName = ""
    @State private var showAdd = false
    @State private var addPayload: AddToPlaylistPayload?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Free Icecast / Shoutcast-style streams. Paste any http(s) stream URL. Not a paid catalog.")
                        .font(.footnote)
                        .foregroundStyle(ChibiTheme.textSecondary)
                    SourceChip(kind: .radio)
                }

                Section("Stations") {
                    ForEach(stations) { station in
                        Button {
                            play(station)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .foregroundStyle(ChibiTheme.textPrimary)
                                    Text(station.genre)
                                        .font(.caption)
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(ChibiTheme.amber)
                            }
                        }
                        .contextMenu {
                            Button {
                                addPayload = .stream(
                                    url: station.streamURL,
                                    title: station.name,
                                    artist: station.genre
                                )
                            } label: {
                                Label("Add to Playlist", systemImage: "text.badge.plus")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Radio")
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            .sheet(item: $addPayload) { payload in
                AddToPlaylistSheet(payload: payload)
            }
            .chibiListChrome()
            .tint(ChibiTheme.amber)
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
}
