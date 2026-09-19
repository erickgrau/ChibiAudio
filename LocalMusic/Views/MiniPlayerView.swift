import SwiftUI

struct MiniPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    let onTap: () -> Void

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Capsule()
                    .fill(ChibiTheme.amber)
                    .frame(width: geo.size.width * progress, height: 2)
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .frame(height: 2)
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                ArtworkView(
                    trackURL: player.currentTrack?.url,
                    hasArtwork: player.currentTrack?.hasArtwork ?? false,
                    pointSize: 48
                )
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(ChibiTheme.textPrimary)
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if let url = player.currentTrack?.url {
                    SourceChip(kind: MediaSourceKind.infer(from: url))
                }

                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 4)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
            }
            .foregroundStyle(ChibiTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ChibiTheme.softGlass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
