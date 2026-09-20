import SwiftUI

@main
struct LocalMusicApp: App {
    @State private var player = AudioPlayerManager()
    @State private var library = LibraryStore()
    @State private var recents = RecentsStore()
    /// Soft PASS: Home is the default landing tab.
    @State private var selectedTab = ChibiTab.home.rawValue

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.ui.info("App launched")
        let enabled = UserDefaults.standard.bool(forKey: "crashReportingEnabled")
        CrashDiagnosticsService.shared.setEnabled(enabled)
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                HomeView()
                    .miniPlayer { selectedTab = ChibiTab.nowPlaying.rawValue }
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(ChibiTab.home.rawValue)

                LibraryView()
                    .miniPlayer { selectedTab = ChibiTab.nowPlaying.rawValue }
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(ChibiTab.library.rawValue)

                NowPlayingView()
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(ChibiTab.nowPlaying.rawValue)

                PlaylistsView()
                    .miniPlayer { selectedTab = ChibiTab.nowPlaying.rawValue }
                    .tabItem {
                        Label("Playlists", systemImage: "rectangle.stack.fill")
                    }
                    .tag(ChibiTab.playlists.rawValue)

                RadioView()
                    .miniPlayer { selectedTab = ChibiTab.nowPlaying.rawValue }
                    .tabItem {
                        Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(ChibiTab.radio.rawValue)
            }
            .tint(ChibiTheme.amber)
            .toolbarBackground(ChibiTheme.softGlass, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .chibiCanvas()
            .environment(player)
            .environment(library)
            .environment(recents)
            .environment(\.chibiSelectTab) { tab in
                selectedTab = tab.rawValue
            }
            .onChange(of: library.tracks) { _, _ in
                player.refreshTrackMetadata { library.track(forURL: $0) }
            }
            .onChange(of: player.currentTrack?.id) { _, _ in
                if let track = player.currentTrack {
                    recents.record(track)
                }
            }
            .task {
                await library.bootstrap()
                if let url = library.folderURL {
                    player.startAccessingFolder(url)
                }
            }
            .onChange(of: library.folderURL) { _, newValue in
                if let url = newValue {
                    Log.ui.info("Folder URL changed: \(url.lastPathComponent)")
                    player.startAccessingFolder(url)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                Log.ui.debug("Scene phase: \(String(describing: phase))")
                if phase == .active {
                    Task { await library.checkForExternalChanges() }
                }
            }
        }
    }
}

// MARK: - Mini Player Modifier

private struct MiniPlayerModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var player
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if player.currentTrack != nil {
                MiniPlayerView(onTap: onTap)
            }
        }
    }
}

extension View {
    func miniPlayer(onTap: @escaping () -> Void) -> some View {
        modifier(MiniPlayerModifier(onTap: onTap))
    }
}
