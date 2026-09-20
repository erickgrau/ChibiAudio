import SwiftUI

/// Shows artwork for a track URL, loading from `ArtworkCache` asynchronously.
/// Soft PASS: embedded/cache first, then folder.jpg/cover.* discovery, then placeholder.
struct ArtworkView: View {
    let trackURL: URL?
    let hasArtwork: Bool
    let pointSize: CGFloat
    var fullResolution: Bool = false
    var placeholderIcon: String = "music.note"

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    ChibiTheme.canvasElevated
                    Image(systemName: placeholderIcon)
                        .font(pointSize > 80 ? .largeTitle : .body)
                        .foregroundStyle(ChibiTheme.textTertiary)
                }
            }
        }
        .task(id: identityKey) {
            await load()
        }
    }

    private var identityKey: String {
        let path = trackURL?.absoluteString ?? "_"
        return "\(path)|\(Int(pointSize))|\(fullResolution ? 1 : 0)|\(hasArtwork ? 1 : 0)"
    }

    private func load() async {
        guard let url = trackURL else {
            image = nil
            return
        }

        // Soft PASS: ensure folder art is cached even when scan-time hasArtwork was false.
        let available = hasArtwork || ArtworkCache.ensureArtworkAvailable(for: url)
        guard available else {
            image = nil
            return
        }

        let scale = displayScale > 0 ? displayScale : 2.0
        let maxPixel = max(pointSize * scale, 1)
        if fullResolution {
            if let cached = ArtworkCache.cachedFullImage(for: url, maxPixel: maxPixel) {
                image = cached
                return
            }
            let loaded = await ArtworkCache.fullImage(for: url, pointSize: pointSize, scale: scale)
            guard !Task.isCancelled else { return }
            image = loaded
        } else {
            if let cached = ArtworkCache.cachedThumbnail(for: url, maxPixel: maxPixel) {
                image = cached
                return
            }
            let loaded = await ArtworkCache.thumbnail(for: url, pointSize: pointSize, scale: scale)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
