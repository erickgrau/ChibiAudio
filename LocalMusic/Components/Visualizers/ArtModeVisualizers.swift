import SwiftUI

/// Soft PASS: current big cover (embedded → folder → placeholder).
struct AlbumArtVisualizer: View {
    let track: Track
    let size: CGFloat

    var body: some View {
        ArtworkView(
            trackURL: track.url,
            hasArtwork: track.hasArtwork,
            pointSize: size,
            fullResolution: true,
            placeholderIcon: "music.note"
        )
    }
}

/// Soft PASS: alternate track-named sidecar art when available; else album art.
struct TrackArtVisualizer: View {
    let track: Track
    let size: CGFloat

    @State private var image: UIImage?
    @State private var usedTrackSidecar = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ArtworkView(
                    trackURL: track.url,
                    hasArtwork: track.hasArtwork,
                    pointSize: size,
                    fullResolution: true,
                    placeholderIcon: "photo"
                )
            }

            if usedTrackSidecar {
                VStack {
                    HStack {
                        Text("TRACK")
                            .font(ChibiTheme.chipFont())
                            .foregroundStyle(ChibiTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ChibiTheme.softGlass, in: Capsule())
                            .overlay(Capsule().strokeBorder(ChibiTheme.hairline, lineWidth: 1))
                            .padding(12)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .task(id: track.id) {
            await loadTrackArt()
        }
    }

    private func loadTrackArt() async {
        usedTrackSidecar = false
        image = nil
        guard let data = ArtworkCache.discoverTrackArtwork(beside: track.url),
              let ui = UIImage(data: data) else {
            return
        }
        image = ui
        usedTrackSidecar = true
    }
}
