#if os(macOS)
import SwiftUI

/// Mac window chrome: sidebar navigation over the same tab content.
/// iOS keeps the TabView in LocalMusicApp; the Mac follows NavigationSplitView
/// conventions. Up Next stays a sheet from Now Playing, as on iOS.
struct MacRootView: View {
    @Environment(TabRouter.self) private var tabs

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                Label("Home", systemImage: "house.fill").tag(ChibiTab.home)
                Label("Library", systemImage: "music.note.list").tag(ChibiTab.library)
                Label("Now Playing", systemImage: "play.circle.fill").tag(ChibiTab.nowPlaying)
                Label("Playlists", systemImage: "rectangle.stack.fill").tag(ChibiTab.playlists)
                Label("Radio", systemImage: "dot.radiowaves.left.and.right").tag(ChibiTab.radio)
            }
            .listStyle(.sidebar)
            .navigationTitle("ChibiAudio")
        } detail: {
            detail
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    private var selectionBinding: Binding<ChibiTab> {
        Binding(
            get: { tabs.selected },
            set: { tabs.selected = $0 }
        )
    }

    /// The mini player (no ads on the Mac) sits under every sidebar section
    /// except Now Playing, which already shows the full transport.
    @ViewBuilder
    private var detail: some View {
        switch tabs.selected {
        case .home:
            HomeView().miniPlayer { tabs.selected = .nowPlaying }
        case .library:
            LibraryView().miniPlayer { tabs.selected = .nowPlaying }
        case .nowPlaying:
            NowPlayingView()
        case .playlists:
            PlaylistsView().miniPlayer { tabs.selected = .nowPlaying }
        case .radio:
            RadioView().miniPlayer { tabs.selected = .nowPlaying }
        }
    }
}
#endif