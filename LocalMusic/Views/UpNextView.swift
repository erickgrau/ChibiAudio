import SwiftUI

/// The playing queue as a sheet (iOS, and Mac callers that present it):
/// current track pinned on top, Up Next below with drag to reorder, swipe
/// to remove, and a confirmed Clear. Tapping an Up Next row jumps to it.
struct UpNextView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            UpNextList(confirmClear: $confirmClear)
                .navigationTitle("Up Next")
                .chibiInlineNavTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                            .disabled(player.upNext.isEmpty)
                    }
                }
        }
    }
}

/// Queue list shared by the Up Next sheet and the Mac queue inspector.
/// Owns the cancelable Clear confirmation; callers own the Clear button.
struct UpNextList: View {
    @Environment(AudioPlayerManager.self) private var player
    @Binding var confirmClear: Bool

    var body: some View {
        List {
            if let current = player.currentTrack {
                Section("Now Playing") {
                    TrackRow(track: current,
                             isCurrent: true,
                             isActivelyPlaying: player.isPlaying)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                if player.upNext.isEmpty {
                    Text("Nothing up next. Use Play Next or Add to Queue on any track.")
                        .font(.callout)
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .listRowSeparator(.hidden)
                } else {
                    // Offsets, not ids: the same track can be queued twice.
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, track in
                        Button {
                            player.skip(toUpNextOffset: offset)
                        } label: {
                            TrackRow(track: track)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        #if os(macOS)
                        // No swipe on the Mac: the same actions live in a context menu.
                        .contextMenu {
                            Button("Play Now") { player.skip(toUpNextOffset: offset) }
                            Button("Remove from Up Next", role: .destructive) {
                                player.removeUpNext(atOffsets: IndexSet(integer: offset))
                            }
                        }
                        #endif
                    }
                    .onMove { player.moveUpNext(fromOffsets: $0, toOffset: $1) }
                    .onDelete { player.removeUpNext(atOffsets: $0) }
                }
            } header: {
                Text("Up Next")
            }
        }
        .listStyle(.plain)
        .chibiListChrome()
        .confirmationDialog("Clear Up Next?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Up Next", role: .destructive) { player.clearUpNext() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current track keeps playing.")
        }
    }
}
