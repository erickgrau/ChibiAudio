import SwiftUI

struct RadioView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case search = "Search"
        case favorites = "Favorites"
        var id: String { rawValue }
    }

    @Environment(AudioPlayerManager.self) private var player
    @Bindable private var browser = RadioBrowserClient.shared
    @State private var segment: Segment = .browse
    @State private var browseMode: BrowseMode = .countries

    @State private var countries: [RadioCountry] = []
    @State private var tags: [RadioTag] = []
    @State private var browseStations: [RadioStation] = []
    @State private var browseTitle = ""
    @State private var showingStations = false

    @State private var searchText = ""
    @State private var searchResults: [RadioStation] = []
    @State private var searchTask: Task<Void, Never>?

    @State private var favorites: [RadioStation] = RadioCatalog.favoriteStations()
    @State private var customURL = ""
    @State private var customName = ""
    @State private var showAdd = false
    @State private var addPayload: AddToPlaylistPayload?
    @State private var didLoadBrowseLists = false

    private enum BrowseMode: String, CaseIterable, Identifiable {
        case countries = "By Country"
        case genres = "By Genre"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Radio", selection: $segment) {
                    ForEach(Segment.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Group {
                    switch segment {
                    case .browse:
                        browseRoot
                    case .search:
                        searchRoot
                    case .favorites:
                        favoritesRoot
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Radio")
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == .favorites {
                        Button {
                            showAdd = true
                        } label: {
                            Label("Add URL", systemImage: "plus")
                        }
                    }
                }
            }
            .alert("Add Stream URL", isPresented: $showAdd) {
                TextField("Name", text: $customName)
                TextField("https://…", text: $customURL)
                Button("Add") { addCustom() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paste any free Icecast / Shoutcast http(s) stream URL.")
            }
            .sheet(item: $addPayload) { payload in
                AddToPlaylistSheet(payload: payload)
            }
            .navigationDestination(isPresented: $showingStations) {
                stationList(
                    title: browseTitle,
                    stations: browseStations,
                    emptyMessage: "No stations in this category right now."
                )
            }
            .task {
                guard !didLoadBrowseLists else { return }
                didLoadBrowseLists = true
                await reloadBrowseLists(force: false)
            }
            .chibiCanvas()
            .tint(ChibiTheme.amber)
        }
    }

    // MARK: - Browse

    private var browseRoot: some View {
        List {
            Section {
                Text("Free global directory via Radio Browser — no IAP. Browse by country or genre/tag.")
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
                SourceChip(kind: .radio)
            }

            if browser.isOffline {
                offlineSection(retry: { await reloadBrowseLists(force: true) })
            }

            Section {
                Picker("Browse", selection: $browseMode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if browseMode == .countries {
                Section("Countries") {
                    if countries.isEmpty && browser.isLoading {
                        ProgressView()
                            .tint(ChibiTheme.amber)
                            .frame(maxWidth: .infinity)
                    } else if countries.isEmpty {
                        emptyInline("No countries loaded.")
                    } else {
                        ForEach(countries) { country in
                            Button {
                                Task { await openCountry(country) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(country.displayName)
                                            .foregroundStyle(ChibiTheme.textPrimary)
                                        Text(country.code)
                                            .font(.caption)
                                            .foregroundStyle(ChibiTheme.textTertiary)
                                    }
                                    Spacer()
                                    Text("\(country.stationCount)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(ChibiTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            } else {
                Section("Genres / Tags") {
                    if tags.isEmpty && browser.isLoading {
                        ProgressView()
                            .tint(ChibiTheme.amber)
                            .frame(maxWidth: .infinity)
                    } else if tags.isEmpty {
                        emptyInline("No genres loaded.")
                    } else {
                        ForEach(tags) { tag in
                            Button {
                                Task { await openTag(tag) }
                            } label: {
                                HStack {
                                    Text(tag.name.capitalized)
                                        .foregroundStyle(ChibiTheme.textPrimary)
                                    Spacer()
                                    Text("\(tag.stationCount)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(ChibiTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .chibiListChrome()
        .refreshable {
            await reloadBrowseLists(force: true)
        }
    }

    // MARK: - Search

    private var searchRoot: some View {
        List {
            Section {
                Text("Search free stations by name worldwide.")
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
            }

            if browser.isOffline && searchResults.isEmpty {
                offlineSection(retry: {
                    await runSearch(searchText, force: true)
                })
            }

            Section {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    emptyInline("Type at least 2 characters to search.")
                } else if browser.isLoading && searchResults.isEmpty {
                    ProgressView()
                        .tint(ChibiTheme.amber)
                        .frame(maxWidth: .infinity)
                } else if searchResults.isEmpty {
                    emptyInline("No stations match “\(searchText)”.")
                } else {
                    ForEach(searchResults) { station in
                        RadioStationRow(
                            station: station,
                            isFavorite: RadioCatalog.isFavorite(station),
                            onPlay: { play(station) },
                            onFavorite: { toggleFavorite(station) },
                            onAddToPlaylist: {
                                addPayload = .stream(
                                    url: station.streamURL,
                                    title: station.name,
                                    artist: station.tagsDisplay
                                )
                            }
                        )
                    }
                }
            }
        }
        .chibiListChrome()
        .searchable(text: $searchText, prompt: "Station name")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await runSearch(newValue, force: false)
            }
        }
    }

    // MARK: - Favorites

    private var favoritesRoot: some View {
        List {
            Section {
                Text("Saved Radio Browser stations and custom stream URLs. Curated seeds appear when empty.")
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
                SourceChip(kind: .radio)
            }

            Section("Favorites") {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Favorite stations from Browse or Search, or paste a custom stream URL.")
                    )
                    .foregroundStyle(ChibiTheme.textSecondary)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(favorites) { station in
                        RadioStationRow(
                            station: station,
                            isFavorite: true,
                            onPlay: { play(station) },
                            onFavorite: { removeFromFavorites(station) },
                            onAddToPlaylist: {
                                addPayload = .stream(
                                    url: station.streamURL,
                                    title: station.name,
                                    artist: station.tagsDisplay
                                )
                            }
                        )
                    }
                    .onDelete(perform: deleteFavorites)
                }
            }
        }
        .chibiListChrome()
        .onAppear { favorites = RadioCatalog.favoriteStations() }
    }

    // MARK: - Shared pieces

    private func stationList(title: String, stations: [RadioStation], emptyMessage: String) -> some View {
        List {
            if browser.isOffline && stations.isEmpty {
                offlineSection(retry: {
                    showingStations = false
                    await reloadBrowseLists(force: true)
                })
            }

            Section {
                if stations.isEmpty {
                    emptyInline(emptyMessage)
                } else {
                    ForEach(stations) { station in
                        RadioStationRow(
                            station: station,
                            isFavorite: RadioCatalog.isFavorite(station),
                            onPlay: { play(station) },
                            onFavorite: { toggleFavorite(station) },
                            onAddToPlaylist: {
                                addPayload = .stream(
                                    url: station.streamURL,
                                    title: station.name,
                                    artist: station.tagsDisplay
                                )
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .chibiListChrome()
    }

    private func offlineSection(retry: @escaping @MainActor () async -> Void) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Offline or unreachable", systemImage: "wifi.slash")
                    .font(.headline)
                    .foregroundStyle(ChibiTheme.textPrimary)
                Text(browser.lastError ?? "Couldn’t reach Radio Browser mirrors. Check your connection and try again.")
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
                Button {
                    Task { await retry() }
                } label: {
                    Text("Retry")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(ChibiTheme.amber)
            }
            .padding(.vertical, 4)
        }
    }

    private func emptyInline(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(ChibiTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func reloadBrowseLists(force: Bool) async {
        async let c = browser.countries(forceRefresh: force)
        async let t = browser.tags(forceRefresh: force)
        countries = await c
        tags = await t
    }

    private func openCountry(_ country: RadioCountry) async {
        browseTitle = country.displayName
        browseStations = await browser.stationsByCountryCode(country.code)
        showingStations = true
    }

    private func openTag(_ tag: RadioTag) async {
        browseTitle = tag.name.capitalized
        browseStations = await browser.stationsByTag(tag.name)
        showingStations = true
    }

    private func runSearch(_ text: String, force: Bool) async {
        searchResults = await browser.searchStations(name: text, forceRefresh: force)
    }

    private func play(_ station: RadioStation) {
        let track = Track(
            id: Track.stableID(for: station.streamURL),
            url: station.streamURL,
            title: station.name,
            artist: station.tagsDisplay,
            album: station.countryDisplay.map { "Radio · \($0)" } ?? "Radio",
            duration: 0,
            hasArtwork: false,
            hasLyrics: false
        )
        player.play(track: track, queue: [track], startIndex: 0)
        if let uuid = station.stationUUID {
            browser.reportClick(stationUUID: uuid)
        }
    }

    private func toggleFavorite(_ station: RadioStation) {
        RadioCatalog.toggleFavorite(station)
        favorites = RadioCatalog.favoriteStations()
    }

    private func removeFromFavorites(_ station: RadioStation) {
        if RadioCatalog.loadFavorites().contains(where: { $0.id == station.id }) {
            RadioCatalog.toggleFavorite(station)
        }
        if station.isUserAdded {
            RadioCatalog.removeUserStation(id: station.id)
        }
        favorites = RadioCatalog.favoriteStations()
    }

    private func deleteFavorites(at offsets: IndexSet) {
        let snapshot = favorites
        for index in offsets {
            removeFromFavorites(snapshot[index])
        }
    }

    private func addCustom() {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.host ?? "Stream")
            : customName
        let station = RadioStation(
            name: name,
            genre: "Custom",
            streamURL: url,
            isUserAdded: true,
            tags: ["custom"]
        )
        RadioCatalog.addUserStation(station)
        favorites = RadioCatalog.favoriteStations()
        customURL = ""
        customName = ""
        segment = .favorites
    }
}

// MARK: - Station row

private struct RadioStationRow: View {
    let station: RadioStation
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(ChibiTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    metaLine
                    Text(station.tagsDisplay)
                        .font(.caption)
                        .foregroundStyle(ChibiTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ChibiTheme.amber)
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button(action: onAddToPlaylist) {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            Button(action: onFavorite) {
                Label(
                    isFavorite ? "Remove Favorite" : "Add Favorite",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onAddToPlaylist) {
                Label("Playlist", systemImage: "text.badge.plus")
            }
            .tint(ChibiTheme.teal)
            Button(action: onFavorite) {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: "heart")
            }
            .tint(ChibiTheme.amber)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if let country = station.countryDisplay {
                Text(country)
            }
            if station.countryDisplay != nil, station.bitrateDisplay != nil {
                Text("·")
            }
            if let bitrate = station.bitrateDisplay {
                Text(bitrate)
                    .font(.caption.monospacedDigit())
            }
            if let codec = station.codec, !codec.isEmpty {
                Text("·")
                Text(codec.uppercased())
                    .font(.caption.monospaced())
            }
        }
        .font(.caption)
        .foregroundStyle(ChibiTheme.textSecondary)
    }
}
