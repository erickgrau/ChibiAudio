import SwiftUI

/// "Play Next" and "Add to Queue" buttons for a track's context menu. Kept
/// free of UIKit so the macOS target can reuse it.
struct QueueMenuItems: View {
    let track: Track
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        Button {
            player.playNext([track])
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
        Button {
            player.addToQueue([track])
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }
    }
}

private struct QueueSwipeActions: ViewModifier {
    let track: Track
    @Environment(AudioPlayerManager.self) private var player

    func body(content: Content) -> some View {
        content.swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                player.playNext([track])
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .tint(ChibiTheme.amber)
            Button {
                player.addToQueue([track])
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            .tint(ChibiTheme.teal)
        }
    }
}

extension View {
    /// Leading-edge swipe for Play Next / Add to Queue. Leading so it never
    /// collides with a list's trailing delete.
    func queueSwipeActions(for track: Track) -> some View {
        modifier(QueueSwipeActions(track: track))
    }
}
