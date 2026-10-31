import SwiftUI

@main
struct LocalMusicApp: App {
    @State private var player = AudioPlayerManager()
    @State private var library = LibraryStore()
    @State private var recents = RecentsStore()
    @State private var tabs = TabRouter()
    @State private var plus = PlusStore()
    @State private var showWhatsNew = false

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.ui.info("App launched")
        let enabled = UserDefaults.standard.bool(forKey: "crashReportingEnabled")
        CrashDiagnosticsService.shared.setEnabled(enabled)
        #if os(iOS)
        AdMobConfig.configureIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .chibiCanvas()
            .environment(player)
            .environment(library)
            .environment(recents)
            .environment(tabs)
            .environment(plus)
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
        #if os(macOS)
        // Playback menu: space toggles play/pause, Cmd+arrow keys move
        // between tracks. Media keys go through MPRemoteCommandCenter.
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Next Track") {
                    player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Track") {
                    player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
        #endif
    }

    /// Tab bar on iOS, sidebar window on the Mac. Both route the same
    /// tab selection through TabRouter.
    private var rootContent: some View {
        #if os(iOS)
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
        #else
        MacRootView()
            .tint(ChibiTheme.amber)
        #endif
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

    /// Mini player with the optional free-tier ad banner above it (not for
    /// Now Playing). The Mac target has no ads, so it is the plain mini player there.
    func adAwareMiniPlayer(onTap: @escaping () -> Void) -> some View {
        modifier(AdAwareMiniPlayerModifier(onTap: onTap))
    }
}

private struct AdAwareMiniPlayerModifier: ViewModifier {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(PlusStore.self) private var plus
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                #if os(iOS)
                if AdMobConfig.shouldShowBanner(isPlusActive: plus.isPlusActive) {
                    AdBannerView()
                }
                #endif
                if player.currentTrack != nil {
                    MiniPlayerView(onTap: onTap)
                }
            }
        }
    }
}
