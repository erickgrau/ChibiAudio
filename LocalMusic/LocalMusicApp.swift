import SwiftUI

@main
struct LocalMusicApp: App {
    @State private var player = AudioPlayerManager()
    @State private var library = LibraryStore()
    @State private var recents = RecentsStore()
    @State private var tabs = TabRouter()
    @State private var plus = PlusStore()
    @State private var appearance = AppearanceStore()
    @State private var showWhatsNew = false

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.ui.info("App launched")
        let enabled = UserDefaults.standard.bool(forKey: "crashReportingEnabled")
        CrashDiagnosticsService.shared.setEnabled(enabled)
        AdMobConfig.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: Binding(
                get: { tabs.selected },
                set: { tabs.selected = $0 }
            )) {
                HomeView()
                    .adAwareMiniPlayer { tabs.selected = .nowPlaying }
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(ChibiTab.home)

                LibraryView()
                    .adAwareMiniPlayer { tabs.selected = .nowPlaying }
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(ChibiTab.library)

                NowPlayingView()
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(ChibiTab.nowPlaying)

                PlaylistsView()
                    .adAwareMiniPlayer { tabs.selected = .nowPlaying }
                    .tabItem {
                        Label("Playlists", systemImage: "rectangle.stack.fill")
                    }
                    .tag(ChibiTab.playlists)

                RadioView()
                    .adAwareMiniPlayer { tabs.selected = .nowPlaying }
                    .tabItem {
                        Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tag(ChibiTab.radio)
            }
            .tint(ChibiTheme.amber)
            .toolbarBackground(ChibiTheme.softGlass, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .chibiCanvas()
            .environment(player)
            .environment(library)
            .environment(recents)
            .environment(tabs)
            .environment(plus)
            .environment(appearance)
            .preferredColorScheme(appearance.preferredColorScheme)
            .sheet(isPresented: $showWhatsNew, onDismiss: { WhatsNew.markSeen() }) {
                WhatsNewView(releases: Array(WhatsNew.unseen.prefix(1))) {
                    showWhatsNew = false
                }
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
                await plus.refreshEntitlements()
                if WhatsNew.hasUnseen {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    showWhatsNew = true
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
                    Task {
                        await library.checkForExternalChanges()
                        await plus.refreshEntitlements()
                    }
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
