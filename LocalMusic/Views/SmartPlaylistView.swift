import SwiftUI

/// Multi-seed playlist builder Soft PASS — pick up to 5 songs or artists from
/// music you already have, generate a blended playlist, preview, save, regenerate.
struct SmartPlaylistView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RecentsStore.self) private var recents
    @Environment(\.dismiss) private var dismiss

    @State private var generator = PlaylistGenerationService()
    @State private var seeds: [PlaylistSeed] = []
    @State private var preview: [ScoredPlaylistTrack] = []
    @State private var showSeedPicker = false
    @State private var showSaveAlert = false
    @State private var playlistName = ""
    @State private var useOnlineEnrichment = true
    @State private var savedPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCopy
                    seedsSection
                    actionsSection
                    if !preview.isEmpty {
                        previewSection
                    } else if let status = generator.statusMessage, !generator.isGenerating {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(ChibiTheme.textSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .chibiListChrome()
            .navigationTitle("Make a Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .tint(ChibiTheme.amber)
            .sheet(isPresented: $showSeedPicker) {
                SeedPickerSheet(seeds: $seeds)
            }
            .alert("Save Playlist", isPresented: $showSaveAlert) {
                TextField("Playlist name", text: $playlistName)
                Button("Save") { savePlaylist() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves an app playlist from the preview — only tracks you already own.")
            }
            .overlay {
                if generator.isGenerating {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(ChibiTheme.amber)
                            Text(generator.statusMessage ?? "Working…")
                                .font(.footnote)
                                .foregroundStyle(ChibiTheme.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .chibiGlassCard(cornerRadius: 18)
                        .padding(40)
                    }
                }
            }
        }
        .chibiCanvas()
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blend songs & artists you already own")
                .font(ChibiTheme.titleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Pick up to \(PlaylistSeed.maxSeeds) seeds. ChibiAudio builds a playlist from your library, Plex, and Bandcamp — never from Spotify or Apple Music catalogs.")
                .font(.footnote)
                .foregroundStyle(ChibiTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chibiGlassCard(cornerRadius: 18)
    }

    private var seedsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seeds")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChibiTheme.textPrimary)
                Spacer()
                Text("\(seeds.count)/\(PlaylistSeed.maxSeeds)")
                    .font(ChibiTheme.sampleRateFont())
                    .foregroundStyle(ChibiTheme.textTertiary)
            }

            if seeds.isEmpty {
                Text("Add a song or artist to get started.")
                    .font(.footnote)
                    .foregroundStyle(ChibiTheme.textSecondary)
            } else {
                ForEach(seeds) { seed in
                    HStack(spacing: 12) {
                        Image(systemName: seed.systemImage)
                            .foregroundStyle(ChibiTheme.amber)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seed.displayTitle)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(ChibiTheme.textPrimary)
                            Text(seed.displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(ChibiTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            seeds.removeAll { $0.id == seed.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ChibiTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(seed.displayTitle)")
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                showSeedPicker = true
            } label: {
                Label(
                    seeds.count >= PlaylistSeed.maxSeeds ? "Seed limit reached" : "Add song or artist",
                    systemImage: "plus.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ChibiTheme.amber)
            .disabled(seeds.count >= PlaylistSeed.maxSeeds)
        }
        .padding(16)
        .chibiGlassCard(cornerRadius: 18)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $useOnlineEnrichment) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Improve with online tags")
                        .foregroundStyle(ChibiTheme.textPrimary)
                    Text("Uses free MusicBrainz / ListenBrainz when online. Still works offline without this.")
                        .font(.caption2)
                        .foregroundStyle(ChibiTheme.textTertiary)
                }
            }
            .tint(ChibiTheme.teal)

            HStack(spacing: 12) {
                Button {
                    Task { await runGenerate() }
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(ChibiTheme.amber)
                .disabled(seeds.isEmpty || generator.isGenerating)

                Button {
                    Task { await runRegenerate() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(preview.isEmpty || generator.isGenerating)
            }

            if generator.usedOnlineEnrichment {
                Text("Included related artists from free online catalogs.")
                    .font(.caption2)
                    .foregroundStyle(ChibiTheme.textTertiary)
            }
        }
        .padding(16)
        .chibiGlassCard(cornerRadius: 18)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChibiTheme.textPrimary)
                Spacer()
                Text("\(preview.count) tracks")
                    .font(.caption)
                    .foregroundStyle(ChibiTheme.textTertiary)
            }

            ForEach(preview) { item in
                HStack(spacing: 12) {
                    ArtworkView(
                        trackURL: item.track.url,
                        hasArtwork: item.track.hasArtwork,
                        pointSize: 44
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.track.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(ChibiTheme.textPrimary)
                            .lineLimit(1)
                        Text(item.track.artist)
                            .font(.caption)
                            .foregroundStyle(ChibiTheme.textSecondary)
                            .lineLimit(1)
                        if !item.reasons.isEmpty {
                            Text(item.reasons.prefix(2).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(ChibiTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    SourceChip(kind: MediaSourceKind.infer(from: item.track.url))
                        .scaleEffect(0.85, anchor: .trailing)
                }
                .padding(.vertical, 2)
            }

            Button {
                playlistName = suggestedName
                showSaveAlert = true
            } label: {
                Label("Save playlist", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ChibiTheme.teal)
        }
        .padding(16)
        .chibiGlassCard(cornerRadius: 18)
    }

    private var suggestedName: String {
        let parts = seeds.prefix(2).map(\.displayTitle)
        if parts.isEmpty { return "Mixed playlist" }
        return "Mix · " + parts.joined(separator: " + ")
    }

    private func runGenerate() async {
        let result = await generator.generate(
            seeds: seeds,
            library: library,
            recents: recents,
            allowOnlineEnrichment: useOnlineEnrichment
        )
        preview = result
    }

    private func runRegenerate() async {
        let result = await generator.regenerate(
            library: library,
            recents: recents,
            allowOnlineEnrichment: useOnlineEnrichment
        )
        preview = result
    }

    private func savePlaylist() {
        let tracks = preview.map(\.track)
        if let saved = generator.savePreview(named: playlistName, tracks: tracks, library: library) {
            savedPlaylist = saved
            dismiss()
        }
    }
}

// MARK: - Seed picker

private struct SeedPickerSheet: View {
    @Binding var seeds: [PlaylistSeed]
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var mode: Mode = .songs

    private enum Mode: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case artists = "Artists"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    if mode == .songs {
                        ForEach(songResults) { track in
                            seedSongRow(track)
                        }
                    } else {
                        ForEach(artistResults, id: \.self) { name in
                            seedArtistRow(name)
                        }
                    }
                }
                .chibiListChrome()
            }
            .searchable(text: $query, prompt: mode == .songs ? "Search songs" : "Search artists")
            .navigationTitle("Add a seed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(ChibiTheme.amber)
            .chibiCanvas()
        }
        .presentationDetents([.large])
    }

    private var songResults: [Track] {
        let limit = 80
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(library.tracks.prefix(limit))
        }
        return library.searchTracks(query: query, limit: limit)
    }

    private var artistResults: [String] {
        var seen = Set<String>()
        var names: [String] = []
        let q = PlaylistScoringEngine.normalize(query)
        for track in library.tracks {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "Unknown Artist" else { continue }
            let key = PlaylistScoringEngine.normalize(name)
            guard seen.insert(key).inserted else { continue }
            if q.isEmpty || key.contains(q) {
                names.append(name)
            }
            if names.count >= 80 { break }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func seedSongRow(_ track: Track) -> some View {
        let seed = PlaylistSeed.song(from: track)
        let selected = seeds.contains(seed)
        return Button {
            toggle(seed)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(trackURL: track.url, hasArtwork: track.hasArtwork, pointSize: 40)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .foregroundStyle(ChibiTheme.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? ChibiTheme.teal : ChibiTheme.amber)
            }
        }
        .disabled(!selected && seeds.count >= PlaylistSeed.maxSeeds)
    }

    private func seedArtistRow(_ name: String) -> some View {
        let seed = PlaylistSeed.artist(name: name)
        let selected = seeds.contains(where: {
            if case .artist(let n) = $0 {
                return PlaylistScoringEngine.normalize(n) == PlaylistScoringEngine.normalize(name)
            }
            return false
        })
        return Button {
            toggle(seed)
        } label: {
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ChibiTheme.amber)
                Text(name)
                    .foregroundStyle(ChibiTheme.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? ChibiTheme.teal : ChibiTheme.amber)
            }
        }
        .disabled(!selected && seeds.count >= PlaylistSeed.maxSeeds)
    }

    private func toggle(_ seed: PlaylistSeed) {
        if let idx = seeds.firstIndex(of: seed) {
            seeds.remove(at: idx)
            return
        }
        // Artist equality by normalized name
        if case .artist(let name) = seed {
            if let idx = seeds.firstIndex(where: {
                if case .artist(let n) = $0 {
                    return PlaylistScoringEngine.normalize(n) == PlaylistScoringEngine.normalize(name)
                }
                return false
            }) {
                seeds.remove(at: idx)
                return
            }
        }
        guard seeds.count < PlaylistSeed.maxSeeds else { return }
        seeds.append(seed)
    }
}
