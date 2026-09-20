import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Environment(AudioPlayerManager.self) private var player

    @State private var showLyrics = false
    @State private var showAddToPlaylist = false
    @State private var lyrics: TrackLyrics?
    @State private var lyricsTrackID: UUID?
    @State private var artworkColor: UIColor = .systemGray
    @State private var artworkColorTrackID: UUID?
    @State private var isSeeking = false
    @State private var seekTarget = 0.0

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.currentTrack {
                    nowPlayingContent(track: track)
                        .task(id: track.id) {
                            await loadAuxiliary(for: track)
                        }
                } else {
                    emptyNowPlaying
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if player.currentTrack != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showLyrics = true
                        } label: {
                            Image(systemName: "quote.opening")
                        }
                        .accessibilityLabel("Lyrics")

                        Button {
                            showAddToPlaylist = true
                        } label: {
                            Image(systemName: "text.badge.plus")
                        }
                        .accessibilityLabel("Add to Playlist")
                    }
                }
            }
            .onChange(of: player.currentTrack?.id) { _, _ in
                showLyrics = false
            }
        }
        .sheet(isPresented: $showLyrics) {
            if let track = player.currentTrack {
                LyricsSheet(
                    track: track,
                    lyrics: lyrics
                )
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = player.currentTrack {
                AddToPlaylistSheet(payload: .local(track))
            }
        }
        .chibiCanvas()
    }

    private var emptyNowPlaying: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ChibiTheme.softGlass)
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                    )
                Image(systemName: "play.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(ChibiTheme.amber)
            }
            Text("Nothing Playing")
                .font(ChibiTheme.heroTitleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Select a track from the Library to start playing.")
                .font(.body)
                .foregroundStyle(ChibiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var displayedTime: Double {
        isSeeking ? seekTarget : player.currentTime
    }

    private var routeInfo: DACSession.RouteInfo {
        DACSession.currentRouteInfo()
    }

    private var showBitPerfectPill: Bool {
        DACSession.isDACModeEnabled && routeInfo.isUSBAudio
    }

    private func nowPlayingContent(track: Track) -> some View {
        let color = Color(artworkColor)
        let source = MediaSourceKind.infer(from: track.url)

        return GeometryReader { geo in
            // Huge art: dominate the first viewport
            let artworkSize = min(max(geo.size.width - 24, 0), geo.size.height * 0.52)

            ZStack {
                ChibiTheme.canvasDeep.ignoresSafeArea()

                // Soft ambient wash from artwork (kept subdued on Onyx)
                LinearGradient(
                    colors: [
                        color.opacity(0.28),
                        ChibiTheme.canvasDeep.opacity(0.9),
                        ChibiTheme.canvasDeep
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: track.id)

                VStack(spacing: 0) {
                    Spacer(minLength: 8)

                    artworkView(track: track, size: artworkSize)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 16)
                        .animation(.spring(response: 0.5), value: track.id)
                        .onTapGesture {
                            showLyrics = true
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "quote.opening")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(ChibiTheme.textPrimary)
                                .padding(8)
                                .background(ChibiTheme.softGlass, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                                )
                                .padding(12)
                        }

                    Spacer().frame(height: 20)

                    // Minimal chrome: title + chips
                    VStack(spacing: 8) {
                        Text(track.title)
                            .font(ChibiTheme.heroTitleFont())
                            .foregroundStyle(ChibiTheme.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.body)
                            .foregroundStyle(ChibiTheme.textSecondary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            SourceChip(kind: source)
                            SampleRateChip(sampleRateHz: max(routeInfo.currentSampleRate, 44_100))
                        }

                        if showBitPerfectPill {
                            BitPerfectOnyxPill()
                                .padding(.top, 2)
                        } else {
                            DACRouteIndicator(summary: routeInfo.summary, isUSB: routeInfo.isUSBAudio)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 18)

                    // Transport glass strip
                    VStack(spacing: 14) {
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { displayedTime },
                                    set: { seekTarget = $0 }
                                ),
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
                            .tint(ChibiTheme.amber)

                            HStack {
                                Text(formatTime(displayedTime))
                                    .font(ChibiTheme.sampleRateFont())
                                    .foregroundStyle(ChibiTheme.textSecondary)
                                Spacer()
                                Text("-\(formatTime(max(0, player.duration - displayedTime)))")
                                    .font(ChibiTheme.sampleRateFont())
                                    .foregroundStyle(ChibiTheme.textSecondary)
                            }
                        }

                        HStack(spacing: 44) {
                            Button { player.previous() } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 26))
                            }

                            Button { player.togglePlayPause() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 42))
                                    .contentTransition(.symbolEffect(.replace))
                            }

                            Button { player.next() } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 26))
                            }
                        }
                        .foregroundStyle(ChibiTheme.textPrimary)

                        HStack(spacing: 36) {
                            Button { player.toggleShuffle() } label: {
                                Image(systemName: "shuffle")
                                    .font(.body)
                                    .foregroundStyle(player.shuffleEnabled ? ChibiTheme.amber : ChibiTheme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(player.shuffleEnabled ? ChibiTheme.amber.opacity(0.15) : .clear)
                                    )
                                    .contentShape(Circle())
                            }

                            // AirPlay Soft PASS — system route picker; USB DAC stays bit-perfect when selected.
                            RoutePickerButton()
                                .frame(width: 40, height: 40)
                                .accessibilityLabel("Audio Output")

                            Button { player.cycleRepeatMode() } label: {
                                Image(systemName: repeatIcon)
                                    .font(.body)
                                    .foregroundStyle(player.repeatMode != .off ? ChibiTheme.amber : ChibiTheme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(player.repeatMode != .off ? ChibiTheme.amber.opacity(0.15) : .clear)
                                    )
                                    .contentShape(Circle())
                            }

                            Button {
                                showAddToPlaylist = true
                            } label: {
                                Image(systemName: "text.badge.plus")
                                    .font(.body)
                                    .foregroundStyle(ChibiTheme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                            }
                            .accessibilityLabel("Add to Playlist")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .chibiGlassCard(cornerRadius: 22)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 12)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(track: Track, size: CGFloat) -> some View {
        ArtworkView(
            trackURL: track.url,
            hasArtwork: track.hasArtwork,
            pointSize: size,
            fullResolution: true,
            placeholderIcon: "music.note"
        )
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Auxiliary loads (lyrics + dominant color)

    private func loadAuxiliary(for track: Track) async {
        // Lyrics Soft PASS: cache + sidecar discovery even when hasLyrics was false at scan.
        if lyricsTrackID != track.id {
            lyrics = nil
            lyricsTrackID = track.id
            let loaded = await LyricsCache.loadOrDiscover(for: track.url)
            if lyricsTrackID == track.id {
                lyrics = loaded
            }
        }

        // Dominant color — compute once per track and cache.
        if artworkColorTrackID != track.id {
            artworkColorTrackID = track.id
            let artAvailable = track.hasArtwork || ArtworkCache.ensureArtworkAvailable(for: track.url)
            if artAvailable,
               let cached = ArtworkColorCache.color(for: track.url) {
                artworkColor = cached
            } else if artAvailable {
                let scale = UIScreen.main.scale
                let image = await ArtworkCache.thumbnail(for: track.url,
                                                          pointSize: 80,
                                                          scale: scale)
                // CIAreaAverage is 50–150 ms; hop off the main actor.
                let color = await Task.detached {
                    image?.dominantColor
                }.value
                if let color {
                    ArtworkColorCache.set(color, for: track.url)
                    if artworkColorTrackID == track.id {
                        artworkColor = color
                    }
                } else if artworkColorTrackID == track.id {
                    artworkColor = .systemGray
                }
            } else {
                artworkColor = .systemGray
            }
        }
    }
}

// MARK: - Lyrics Soft PASS sheet

struct LyricsSheet: View {
    let track: Track
    let lyrics: TrackLyrics?
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ChibiTheme.canvasDeep.ignoresSafeArea()

                Group {
                    if let synced = lyrics?.synced, !synced.isEmpty {
                        SyncedLyricsView(lines: synced, currentTime: player.currentTime)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    } else if let unsynced = lyrics?.unsynced, !unsynced.isEmpty {
                        ScrollView {
                            Text(unsynced)
                                .font(.body)
                                .lineSpacing(8)
                                .foregroundStyle(ChibiTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(24)
                        }
                    } else {
                        lyricsEmptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ChibiTheme.softGlass)
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(ChibiTheme.titleFont())
                        .foregroundStyle(ChibiTheme.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(ChibiTheme.softGlass)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ChibiTheme.hairline)
                        .frame(height: 1)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var lyricsEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ChibiTheme.canvasElevated)
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                    )
                Image(systemName: "quote.opening")
                    .font(.system(size: 30))
                    .foregroundStyle(ChibiTheme.amber)
            }
            Text("No Lyrics")
                .font(ChibiTheme.titleFont())
                .foregroundStyle(ChibiTheme.textPrimary)
            Text("Embed lyrics in the file or add a matching .lrc sidecar beside the track.")
                .font(.body)
                .foregroundStyle(ChibiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Synced Lyrics View

struct SyncedLyricsView: View {
    let lines: [SyncedLyricLine]
    let currentTime: Double

    /// Binary-searches for the largest index whose timestamp is `<= currentTime`.
    /// Replaces a per-tick linear scan over potentially hundreds of lines.
    /// Exposed as a static helper so tests can verify it without a `View`.
    static func activeIndex(in lines: [SyncedLyricLine], at currentTime: Double) -> Int {
        guard !lines.isEmpty else { return 0 }
        var lo = 0
        var hi = lines.count - 1
        var best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].timestamp <= currentTime {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }

    private var activeIndex: Int {
        Self.activeIndex(in: lines, at: currentTime)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text)
                            .font(.body)
                            .fontWeight(index == activeIndex ? .semibold : .regular)
                            .foregroundStyle(index == activeIndex ? ChibiTheme.amber : ChibiTheme.textSecondary)
                            .opacity(index == activeIndex ? 1.0 : 0.55)
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: activeIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(activeIndex, anchor: .center)
            }
        }
    }
}

// MARK: - Dominant Color Cache

/// Caches the result of `UIImage.dominantColor` per track URL so we don't
/// re-run the (50–150 ms) CIAreaAverage filter on every Now Playing render.
enum ArtworkColorCache {
    /// `nonisolated(unsafe)` because `NSCache` is internally thread-safe but
    /// not `Sendable`-marked in the iOS SDK.
    nonisolated(unsafe) private static let storage: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        cache.countLimit = 64
        return cache
    }()

    static func color(for trackURL: URL) -> UIColor? {
        storage.object(forKey: ArtworkCache.key(for: trackURL) as NSString)
    }

    static func set(_ color: UIColor, for trackURL: URL) {
        storage.setObject(color, forKey: ArtworkCache.key(for: trackURL) as NSString)
    }
}

// MARK: - Dominant Color Extraction

extension UIImage {
    /// Reused across dominant-color extractions. Creating a `CIContext` is
    /// the expensive part; the 1×1 CIAreaAverage render is cheap by comparison.
    private static let dominantColorContext: CIContext = {
        CIContext(options: [.workingColorSpace: kCFNull as Any])
    }()

    nonisolated var dominantColor: UIColor? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let extent = ciImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y,
                                     z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: extentVector]),
              let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = UIImage.dominantColorContext
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255,
                       green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255,
                       alpha: 1)
    }
}
