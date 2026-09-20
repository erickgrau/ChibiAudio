import SwiftUI

/// Soft PASS Home — Continue, Recent, Playlists shortcuts, Library entry points.
struct HomeView: View {
    // Avoid observing the player at the root (0.5s ticks). Continue card
    // reads player state in a nested view.
    @Environment(LibraryStore.self) private var library
    @Environment(RecentsStore.self) private var recents
    @Environment(\.chibiSelectTab) private var selectTab

    @State private var showSettings = false
    @State private var showFolderPicker = false
    @AppStorage("crashReportingEnabled") private var crashReportingEnabled = false
    private let crashService = CrashDiagnosticsService.shared

    private var hasLibrary: Bool {
        library.folderURL != nil || !library.tracks.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !hasLibrary {
                        emptyLibraryBanner
                    }

                    ContinueCard(
                        onOpenNowPlaying: { selectTab(.nowPlaying) },
                        onChooseFolder: { showFolderPicker = true }
                    )

                    RecentSection(
                        onChooseFolder: { showFolderPicker = true }
                    )

                    PlaylistsShortcutSection()

                    LibraryShortcutsSection(
                        onFolders: { showFolderPicker = true },
                        onAllTracks: { selectTab(.library) },
                        onRadio: { selectTab(.radio) }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .contentMargins(.bottom, 80, for: .scrollContent)
            .navigationTitle("Home")
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(ChibiTheme.textPrimary)
                            .overlay(alignment: .topTrailing) {
                                if crashReportingEnabled, crashService.hasPendingCrash {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showFolderPicker) {
                DocumentPicker { pickerURL in
                    _ = pickerURL.startAccessingSecurityScopedResource()
                    PersistenceManager.shared.saveFolderBookmark(pickerURL)
                    pickerURL.stopAccessingSecurityScopedResource()
                    Task {
                        await library.adoptSavedFolder()
                    }
                }
            }
            .chibiCanvas()
            .tint(ChibiTheme.amber)
        }
    }

    private var emptyLibraryBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No library yet")
                .font(ChibiTheme.titleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Add a folder on this iPhone, iCloud Drive, or another Files provider to start listening.")
                .font(.subheadline)
                .foregroundStyle(ChibiTheme.textSecondary)
            Button {
                showFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ChibiTheme.amber)
            .controlSize(.large)
        }
        .padding(18)
        .chibiGlassCard(cornerRadius: 18)
    }
}

// MARK: - Continue / Now Playing

private struct ContinueCard: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(RecentsStore.self) private var recents
    @Environment(LibraryStore.self) private var library

    let onOpenNowPlaying: () -> Void
    let onChooseFolder: () -> Void

    private var continueTrack: Track? {
        if let current = player.currentTrack { return current }
        if let first = recents.entries.first {
            return library.track(forURL: first.url) ?? first.asTrack()
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Continue")

            if let track = continueTrack {
                Button {
                    if player.currentTrack?.id == track.id {
                        onOpenNowPlaying()
                    } else {
                        play(track)
                        onOpenNowPlaying()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        ArtworkView(
                            trackURL: track.url,
                            hasArtwork: track.hasArtwork,
                            pointSize: 112
                        )
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(player.currentTrack?.id == track.id && player.isPlaying
                                 ? "Now Playing"
                                 : "Continue Listening")
                                .font(ChibiTheme.chipFont())
                                .foregroundStyle(ChibiTheme.amber)
                                .textCase(.uppercase)

                            Text(track.title)
                                .font(ChibiTheme.heroTitleFont())
                                .foregroundStyle(ChibiTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(ChibiTheme.textSecondary)
                                .lineLimit(1)

                            SourceChip(kind: MediaSourceKind.infer(from: track.url))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: player.currentTrack?.id == track.id && player.isPlaying
                              ? "pause.circle.fill"
                              : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(ChibiTheme.amber)
                    }
                    .padding(16)
                    .chibiGlassCard(cornerRadius: 20)
                }
                .buttonStyle(.plain)
            } else {
                emptyContinue
            }
        }
    }

    private var emptyContinue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing playing")
                .font(.headline)
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Pick a track from your library, or add a folder to get started.")
                .font(.subheadline)
                .foregroundStyle(ChibiTheme.textSecondary)
            Button(action: onChooseFolder) {
                Label("Add Folder", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(ChibiTheme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .chibiGlassCard(cornerRadius: 18)
    }

    private func play(_ track: Track) {
        if let libraryTrack = library.track(forURL: track.url),
           let idx = library.displayTracks.firstIndex(where: { $0.id == libraryTrack.id }) {
            player.play(track: libraryTrack, queue: library.displayTracks, startIndex: idx)
        } else {
            player.play(track: track, queue: [track], startIndex: 0)
        }
    }
}

// MARK: - Recent

private struct RecentSection: View {
    @Environment(RecentsStore.self) private var recents
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayerManager.self) private var player

    let onChooseFolder: () -> Void

    private var recentTracks: [Track] {
        recents.resolvedTracks(using: library)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent")

            if recentTracks.isEmpty {
                emptyRecent
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentTracks) { track in
                            Button {
                                play(track)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkView(
                                        trackURL: track.url,
                                        hasArtwork: track.hasArtwork,
                                        pointSize: 96
                                    )
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Text(track.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(
                                            player.currentTrack?.id == track.id
                                            ? ChibiTheme.amber
                                            : ChibiTheme.textPrimary
                                        )
                                        .lineLimit(2)
                                        .frame(width: 96, alignment: .leading)

                                    Text(track.artist)
                                        .font(.caption2)
                                        .foregroundStyle(ChibiTheme.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 96, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptyRecent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No recent plays")
                .font(.headline)
                .foregroundStyle(ChibiTheme.textPrimary)
            Text(library.tracks.isEmpty
                 ? "Play something after you add a folder — it’ll show up here."
                 : "Tracks you play will land here for quick resume.")
                .font(.subheadline)
                .foregroundStyle(ChibiTheme.textSecondary)
            if library.tracks.isEmpty {
                Button(action: onChooseFolder) {
                    Label("Add Folder", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(ChibiTheme.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .chibiGlassCard(cornerRadius: 16)
    }

    private func play(_ track: Track) {
        if let libraryTrack = library.track(forURL: track.url),
           let idx = library.displayTracks.firstIndex(where: { $0.id == libraryTrack.id }) {
            player.play(track: libraryTrack, queue: library.displayTracks, startIndex: idx)
        } else {
            let queue = recentTracks
            let idx = queue.firstIndex(where: { $0.id == track.id }) ?? 0
            player.play(track: track, queue: queue, startIndex: idx)
        }
    }
}

// MARK: - Playlists shortcuts

private struct PlaylistsShortcutSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.chibiSelectTab) private var selectTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Playlists")
                Spacer()
                Button("See All") {
                    selectTab(.playlists)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChibiTheme.amber)
            }

            if library.playlists.isEmpty {
                Text("No playlists yet — create one on the Playlists tab.")
                    .font(.subheadline)
                    .foregroundStyle(ChibiTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .chibiGlassCard(cornerRadius: 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(library.playlists.prefix(12)) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlist: Binding(
                                        get: {
                                            library.playlists.first(where: { $0.id == playlist.id })
                                                ?? playlist
                                        },
                                        set: { library.savePlaylist($0) }
                                    )
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    PlaylistMosaicView(trackURLs: playlist.trackURLs)
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(ChibiTheme.textPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .chibiGlassCard(cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Library shortcuts

private struct LibraryShortcutsSection: View {
    let onFolders: () -> Void
    let onAllTracks: () -> Void
    let onRadio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Library")

            VStack(spacing: 8) {
                shortcutRow(
                    title: "Folders",
                    subtitle: "Choose or change your music folder",
                    systemImage: "folder.fill",
                    action: onFolders
                )
                shortcutRow(
                    title: "All tracks",
                    subtitle: "Browse your full library",
                    systemImage: "music.note.list",
                    action: onAllTracks
                )
                shortcutRow(
                    title: "Radio",
                    subtitle: "Free Icecast / Shoutcast streams",
                    systemImage: "dot.radiowaves.left.and.right",
                    action: onRadio
                )
            }
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(ChibiTheme.amber)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(ChibiTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ChibiTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ChibiTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .chibiGlassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared chrome

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(ChibiTheme.textPrimary)
}

// MARK: - Tab selection environment

enum ChibiTab: Int, Hashable, Sendable {
    case home = 0
    case library = 1
    case nowPlaying = 2
    case playlists = 3
    case radio = 4
}

private struct ChibiSelectTabKey: EnvironmentKey {
    static let defaultValue: (ChibiTab) -> Void = { _ in }
}

extension EnvironmentValues {
    var chibiSelectTab: (ChibiTab) -> Void {
        get { self[ChibiSelectTabKey.self] }
        set { self[ChibiSelectTabKey.self] = newValue }
    }
}
