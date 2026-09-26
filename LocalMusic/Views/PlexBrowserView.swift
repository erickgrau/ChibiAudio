import SwiftUI

struct PlexBrowserView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Bindable private var client = PlexClient.shared
    @State private var showSignIn = false
    @State private var albums: [PlexClient.PlexAlbum] = []
    @State private var selectedSection: PlexClient.PlexDirectory?
    @State private var addPayload: AddToPlaylistPayload?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if !client.isSignedIn {
                ContentUnavailableView {
                    Label("Plex", systemImage: "play.rectangle.fill")
                } description: {
                    Text("Sign in with Plex to browse your music. We never see your password.")
                } actions: {
                    Button("Continue with Plex") { showSignIn = true }
                        .buttonStyle(.borderedProminent)
                        .tint(ChibiTheme.amber)
                }
            } else {
                signedInBody
            }
        }
        .navigationTitle("Plex")
        .chibiCanvas()
        .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ChibiTheme.amber)
        .sheet(isPresented: $showSignIn) {
            PlexSignInView()
        }
        .sheet(item: $addPayload) { payload in
            AddToPlaylistSheet(payload: payload)
        }
        .task {
            if client.isSignedIn {
                if client.discoveredServers.isEmpty {
                    await client.refreshAccountAndServers()
                }
                await client.refreshMusicLibraries()
                if selectedSection == nil, let first = client.musicSections.first {
                    selectedSection = first
                    albums = await client.fetchAlbums(sectionKey: first.key)
                }
            }
        }
    }

    private var signedInBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let err = client.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
                libraries
                albumGrid
            }
            .padding(16)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceChip(kind: .plex)
            Text(client.username.isEmpty ? "Signed in" : client.username)
                .font(ChibiTheme.heroTitleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            HStack(spacing: 8) {
                Circle().fill(ChibiTheme.teal).frame(width: 7, height: 7)
                Text(serverSubtitle)
                    .font(.caption)
                    .foregroundStyle(ChibiTheme.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chibiGlassCard(cornerRadius: 18)
    }

    private var serverSubtitle: String {
        let name = client.discoveredServers.first(where: { $0.machineIdentifier == client.machineIdentifier })?.name
            ?? "Plex"
        return "\(name) · \(client.connectionKindLabel)"
    }

    private var libraries: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(client.musicSections) { section in
                    Button {
                        selectedSection = section
                        Task { albums = await client.fetchAlbums(sectionKey: section.key) }
                    } label: {
                        Text(section.title)
                            .font(ChibiTheme.chipFont())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                ChibiTheme.softGlass,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selectedSection?.id == section.id ? ChibiTheme.amber : ChibiTheme.hairline,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChibiTheme.textPrimary)
                }
            }
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(albums.prefix(50)) { album in
                NavigationLink {
                    PlexAlbumDetailView(album: album)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        PlexThumbView(thumb: album.thumb)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(album.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChibiTheme.textPrimary)
                            .lineLimit(2)
                        Text(album.artist)
                            .font(.caption)
                            .foregroundStyle(ChibiTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PlexAlbumDetailView: View {
    let album: PlexClient.PlexAlbum
    @Environment(AudioPlayerManager.self) private var player
    @Bindable private var client = PlexClient.shared
    @State private var tracks: [PlexClient.PlexTrack] = []
    @State private var addPayload: AddToPlaylistPayload?

    var body: some View {
        List {
            Section {
                PlexThumbView(thumb: album.thumb)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Text(album.title)
                    .font(ChibiTheme.heroTitleFont())
                Text(album.artist)
                    .foregroundStyle(ChibiTheme.textSecondary)
                HStack {
                    Button("Play all") { playAll(shuffle: false) }
                    Button("Shuffle") { playAll(shuffle: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(ChibiTheme.amber)
            }

            Section(album.title) {
                ForEach(tracks) { track in
                    Button {
                        play(tracks: tracks, start: track)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).foregroundStyle(ChibiTheme.textPrimary)
                            Text(track.artist)
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
        .chibiListChrome()
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addPayload) { payload in
            AddToPlaylistSheet(payload: payload)
        }
        .task {
            tracks = await client.fetchAlbumTracks(ratingKey: album.ratingKey)
        }
    }

    private func playAll(shuffle: Bool) {
        var list = tracks
        if shuffle { list.shuffle() }
        guard let first = list.first else { return }
        play(tracks: list, start: first)
    }

    private func play(tracks: [PlexClient.PlexTrack], start: PlexClient.PlexTrack) {
        let mapped = tracks.compactMap { t -> Track? in
            guard let url = client.directPlayURL(serverURL: client.serverURLString, ratingKey: t.ratingKey) else {
                return nil
            }
            return Track(
                id: Track.stableID(for: url),
                url: url,
                title: t.title,
                artist: t.artist,
                album: t.album,
                duration: t.durationMs / 1000,
                hasArtwork: t.thumb != nil,
                hasLyrics: false
            )
        }
        guard let current = mapped.first(where: { track in
            guard let url = client.directPlayURL(serverURL: client.serverURLString, ratingKey: start.ratingKey) else {
                return false
            }
            return track.id == Track.stableID(for: url)
        }) ?? mapped.first else { return }
        let index = mapped.firstIndex(where: { $0.id == current.id }) ?? 0
        player.play(track: current, queue: mapped, startIndex: index)
    }
}

struct PlexThumbView: View {
    let thumb: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            ChibiTheme.canvasElevated
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "opticaldisc")
                    .foregroundStyle(ChibiTheme.textTertiary)
            }
        }
        .task(id: thumb) { await load() }
    }

    private func load() async {
        guard let url = PlexClient.shared.artworkURL(thumb: thumb) else { return }
        var request = URLRequest(url: url)
        let client = PlexClient.shared
        for (k, v) in PlexAuthService.plexHeaders(clientID: client.clientID, token: client.authToken) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let ui = UIImage(data: data) {
            image = ui
        }
    }
}
