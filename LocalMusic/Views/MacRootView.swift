#if os(macOS)
import SwiftUI

/// Mac window chrome: a task-based sidebar (Listen, Library, Sources) over
/// the shared section views, a persistent player bar, and Up Next in an
/// inspector column that stays open while browsing. iOS keeps the TabView
/// in LocalMusicApp.
struct MacRootView: View {
    @Environment(TabRouter.self) private var tabs
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var tabs = tabs
        NavigationSplitView {
            List(selection: selectionBinding) {
                Section {
                    Label("Home", systemImage: "house.fill").tag(ChibiTab.home)
                    Label("Now Playing", systemImage: "play.circle.fill").tag(ChibiTab.nowPlaying)
                }
                Section("Library") {
                    Label("Songs", systemImage: "music.note.list").tag(ChibiTab.library)
                    Label("Albums", systemImage: "square.stack").tag(ChibiTab.albums)
                    Label("Artists", systemImage: "music.mic").tag(ChibiTab.artists)
                    Label("Playlists", systemImage: "rectangle.stack.fill").tag(ChibiTab.playlists)
                }
                Section("Sources") {
                    Label("Radio", systemImage: "dot.radiowaves.left.and.right").tag(ChibiTab.radio)
                    Label("Plex", systemImage: "play.rectangle.fill").tag(ChibiTab.plex)
                    Label("Bandcamp", systemImage: "bag.fill").tag(ChibiTab.bandcamp)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom, spacing: 0) { folderFooter }
            .navigationTitle("ChibiAudio")
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Now Playing shows the full transport itself.
                    if tabs.selected != .nowPlaying {
                        MacTransportBar()
                    }
                }
                .inspector(isPresented: $tabs.showsQueue) {
                    MacQueueInspector()
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
                }
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    private var selectionBinding: Binding<ChibiTab> {
        Binding(
            get: { tabs.selected },
            set: { tabs.selected = $0 }
        )
    }

    /// The local folder source, always visible under the sidebar.
    private var folderFooter: some View {
        Button {
            MacFolderAccess.chooseFolder(library: library)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Music Folder")
                        .font(.caption.weight(.semibold))
                    Text(library.folderURL?.lastPathComponent ?? "Choose…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if library.isScanning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose Music Folder…")
        .accessibilityLabel("Music folder: \(library.folderURL?.lastPathComponent ?? "none chosen")")
        .accessibilityHint("Choose a different music folder")
    }

    @ViewBuilder
    private var detail: some View {
        switch tabs.selected {
        case .home:
            HomeView()
        case .library:
            LibraryView()
        case .albums:
            MacAlbumsView()
        case .artists:
            MacArtistsView()
        case .nowPlaying:
            NowPlayingView()
        case .playlists:
            PlaylistsView()
        case .radio:
            RadioView()
        case .plex:
            NavigationStack { PlexBrowserView() }
        case .bandcamp:
            NavigationStack { BandcampBrowserView() }
        }
    }
}

/// The Mac Settings window (ChibiAudio > Settings…, Command-comma, or the
/// gear on Home and Songs). One tab per pane of the shared SettingsView.
struct MacSettingsView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsView(panes: [pane], isSettingsWindow: true)
                    .tabItem { Label(pane.title, systemImage: pane.systemImage) }
                    .tag(pane)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 560)
        .chibiCanvas()
    }
}
#endif
