#if os(macOS)
import SwiftUI

/// Persistent player bar along the bottom of the Mac window. It stays put
/// while the sidebar changes sections, so browsing never resets transport.
/// Every control has an explicit accessibility label; the same actions are
/// in the Playback menu with keyboard shortcuts.
struct MacTransportBar: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(TabRouter.self) private var tabs
    @State private var isSeeking = false
    @State private var seekTarget = 0.0

    private var hasTrack: Bool { player.currentTrack != nil }
    private var isLive: Bool { player.duration.isNaN || player.duration <= 0 }
    private var displayedTime: Double { isSeeking ? seekTarget : player.currentTime }

    var body: some View {
        HStack(spacing: 16) {
            nowPlayingSummary
                .frame(minWidth: 200, maxWidth: 300, alignment: .leading)

            VStack(spacing: 4) {
                controls
                scrubber
            }
            .frame(maxWidth: 520)

            trailingControls
                .frame(minWidth: 120, maxWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Sections

    private var nowPlayingSummary: some View {
        Button {
            if hasTrack { tabs.selected = .nowPlaying }
        } label: {
            HStack(spacing: 10) {
                ArtworkView(
                    trackURL: player.currentTrack?.url,
                    hasArtwork: player.currentTrack?.hasArtwork ?? false,
                    pointSize: 44
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "Not Playing")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(ChibiTheme.textPrimary)
                        .lineLimit(1)
                    if let track = player.currentTrack {
                        HStack(spacing: 6) {
                            Text(track.artist)
                                .lineLimit(1)
                            SourceChip(kind: MediaSourceKind.infer(from: track.url))
                                .scaleEffect(0.85, anchor: .leading)
                        }
                        .font(.caption)
                        .foregroundStyle(ChibiTheme.textSecondary)
                    } else {
                        Text("Choose a song to start playing.")
                            .font(.caption)
                            .foregroundStyle(ChibiTheme.textSecondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasTrack)
        .help("Show Now Playing")
        .accessibilityLabel(player.currentTrack.map { "Now playing: \($0.title) by \($0.artist)" } ?? "Not playing")
        .accessibilityHint(hasTrack ? "Shows Now Playing" : "")
    }

    private var controls: some View {
        HStack(spacing: 22) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffleEnabled ? ChibiTheme.amber : ChibiTheme.textSecondary)
            }
            .help("Shuffle")
            .accessibilityLabel("Shuffle")
            .accessibilityValue(player.shuffleEnabled ? "On" : "Off")

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .help("Previous Track")
            .accessibilityLabel("Previous Track")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
            .help("Next Track")
            .accessibilityLabel("Next Track")

            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode != .off ? ChibiTheme.amber : ChibiTheme.textSecondary)
            }
            .help("Repeat")
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatValue)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(ChibiTheme.textPrimary)
        .disabled(!hasTrack)
    }

    @ViewBuilder
    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(hasTrack && !isLive ? formatTime(displayedTime) : "")
                .frame(width: 44, alignment: .trailing)
            if hasTrack && isLive {
                HStack(spacing: 6) {
                    Circle().fill(ChibiTheme.amber).frame(width: 6, height: 6)
                    Text("LIVE").fontWeight(.semibold).foregroundStyle(ChibiTheme.amber)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Live stream")
            } else {
                Slider(
                    value: Binding(get: { displayedTime }, set: { seekTarget = $0 }),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            isSeeking = true
                            seekTarget = player.currentTime
                        } else {
                            player.seek(to: seekTarget)
                            isSeeking = false
                        }
                    }
                )
                .controlSize(.mini)
                .tint(ChibiTheme.amber)
                .disabled(!hasTrack)
                .accessibilityLabel("Playback position")
                .accessibilityValue(hasTrack ? "\(formatTime(displayedTime)) of \(formatTime(player.duration))" : "")
            }
            Text(hasTrack && !isLive ? "-\(formatTime(max(0, player.duration - displayedTime)))" : "")
                .frame(width: 44, alignment: .leading)
        }
        .font(ChibiTheme.sampleRateFont())
        .foregroundStyle(ChibiTheme.textSecondary)
    }

    private var trailingControls: some View {
        HStack(spacing: 14) {
            RoutePickerButton(player: player.routingPlayer)
                .frame(width: 24, height: 24)
                .help("Audio Output (AirPlay)")

            Button {
                tabs.showsQueue.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(tabs.showsQueue ? ChibiTheme.amber : ChibiTheme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help(tabs.showsQueue ? "Hide Up Next" : "Show Up Next")
            .accessibilityLabel("Up Next")
            .accessibilityValue(tabs.showsQueue ? "Shown" : "Hidden")
        }
    }

    private var repeatValue: String {
        switch player.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Up Next in the Mac inspector column, beside any section.
struct MacQueueInspector: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(TabRouter.self) private var tabs
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(player.upNext.isEmpty)
                    .help("Clear Up Next")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            UpNextList(confirmClear: $confirmClear)
        }
        .background(ChibiTheme.canvasDeep)
    }
}
#endif
