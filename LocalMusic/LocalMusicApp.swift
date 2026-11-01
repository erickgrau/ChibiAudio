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
        #else
        MacPlaybackKeyMonitor.install()
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
            .chibiSheet(isPresented: $showWhatsNew, size: .large, onDismiss: { WhatsNew.markSeen() }) {
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
                #if os(macOS)
                // Mac UI tests host the app; never scan or restore the
                // user's library, or show release notes, under XCTest.
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
                #endif
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
        .commands { macCommands }
        #endif

        #if os(macOS)
        // ChibiAudio > Settings… (Command-comma). Same stores as the main
        // window, so changes show up there immediately.
        Settings {
            MacSettingsView()
                .environment(player)
                .environment(library)
                .environment(recents)
                .environment(tabs)
                .environment(plus)
        }
        .windowResizability(.contentMinSize)
        #endif
    }

    #if os(macOS)
    /// Mac menus. Space and Command-Left/Right are menu key equivalents;
    /// MacPlaybackKeyMonitor hands them to a text field while one is being
    /// edited, so typing never toggles playback or skips tracks. Media
    /// keys go through MPRemoteCommandCenter.
    @CommandsBuilder
    private var macCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Music Folder…") {
                MacFolderAccess.chooseFolder(library: library)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Reload Music") {
                Task { await library.rescan() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(library.folderURL == nil || library.isScanning)
        }

        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(player.currentTrack == nil)

            Button("Next Track") {
                player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(player.currentTrack == nil)

            Button("Previous Track") {
                player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(player.currentTrack == nil)

            Divider()

            Toggle("Shuffle", isOn: Binding(
                get: { player.shuffleEnabled },
                set: { _ in player.toggleShuffle() }
            ))

            Picker("Repeat", selection: Binding(
                get: { player.repeatMode },
                set: { mode in
                    // cycleRepeatMode keeps the queue state machine in step.
                    while player.repeatMode != mode { player.cycleRepeatMode() }
                }
            )) {
                Text("Off").tag(RepeatMode.off)
                Text("All").tag(RepeatMode.all)
                Text("One").tag(RepeatMode.one)
            }

            Divider()

            Button(tabs.showsQueue ? "Hide Up Next" : "Show Up Next") {
                tabs.showsQueue.toggle()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Button("Go to Now Playing") {
                tabs.selected = .nowPlaying
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Self.sidebarShortcuts, id: \.tab) { item in
                Button(item.title) { tabs.selected = item.tab }
                    .keyboardShortcut(item.key, modifiers: .command)
            }
            Divider()
        }
    }

    private static let sidebarShortcuts: [(tab: ChibiTab, title: String, key: KeyEquivalent)] = [
        (.home, "Home", "1"),
        (.library, "Songs", "2"),
        (.albums, "Albums", "3"),
        (.artists, "Artists", "4"),
        (.playlists, "Playlists", "5"),
        (.radio, "Radio", "6"),
        (.plex, "Plex", "7"),
        (.bandcamp, "Bandcamp", "8"),
    ]
    #endif

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
