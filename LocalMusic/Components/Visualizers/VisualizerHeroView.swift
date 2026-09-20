import SwiftUI

/// Soft PASS Now Playing hero: swipeable / picker visualizer modes.
/// Transport stays below; this only replaces the big art plane.
struct VisualizerHeroView: View {
    @Binding var mode: VisualizerMode
    let track: Track
    let size: CGFloat
    let isPlaying: Bool
    let onLyricsTap: () -> Void

    @Environment(AudioPlayerManager.self) private var player
    private var analyzer: VisualizerAudioAnalyzer { VisualizerAudioAnalyzer.shared }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                TabView(selection: $mode) {
                    ForEach(VisualizerMode.allCases) { m in
                        modeContent(m)
                            .tag(m)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 16)

                lyricsChip
            }

            modeChrome
        }
        .onAppear { applyMode(mode) }
        .onChange(of: mode) { _, newValue in
            newValue.persist()
            applyMode(newValue)
        }
        .onChange(of: player.isPlaying) { _, _ in syncAnalyzer() }
        .onChange(of: player.currentTrack?.id) { _, _ in syncAnalyzer() }
        .onChange(of: player.currentTime) { _, _ in
            // Lightweight seek sync — analyzer throttles internally.
            if mode.needsAudioMetering {
                analyzer.sync(
                    trackURL: track.url,
                    isPlaying: isPlaying,
                    currentTime: player.currentTime
                )
            }
        }
        .onDisappear {
            analyzer.setMeteringEnabled(false)
        }
        .animation(.spring(response: 0.45), value: mode)
    }

    // MARK: - Mode bodies

    @ViewBuilder
    private func modeContent(_ m: VisualizerMode) -> some View {
        switch m {
        case .albumArt:
            AlbumArtVisualizer(track: track, size: size)
        case .trackArt:
            TrackArtVisualizer(track: track, size: size)
        case .vuMeters:
            VUMeterVisualizer(
                left: analyzer.leftLevel,
                right: analyzer.rightLevel,
                isPlaying: isPlaying
            )
        case .ledBar:
            LEDBarVisualizer(spectrum: analyzer.spectrum, beat: analyzer.beatEnergy)
        case .eqSpectrum:
            EQSpectrumVisualizer(spectrum: analyzer.spectrum, beat: analyzer.beatEnergy)
        case .kaleidoscope:
            KaleidoscopeVisualizer(spectrum: analyzer.spectrum, beat: analyzer.beatEnergy)
        case .vectors:
            VectorsVisualizer(waveform: analyzer.waveform, beat: analyzer.beatEnergy)
        case .vinyl:
            VinylVisualizer(track: track, isPlaying: isPlaying, size: size)
        case .cassette:
            CassetteVisualizer(track: track, isPlaying: isPlaying, size: size)
        }
    }

    private var lyricsChip: some View {
        Button(action: onLyricsTap) {
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
        }
        .padding(12)
        .accessibilityLabel("Lyrics")
    }

    private var modeChrome: some View {
        HStack(spacing: 10) {
            // Soft glass mode picker Soft PASS
            Menu {
                ForEach(VisualizerMode.allCases) { m in
                    Button {
                        mode = m
                    } label: {
                        Label(m.title, systemImage: m.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: mode.systemImage)
                        .font(.caption)
                    Text(mode.title)
                        .font(ChibiTheme.chipFont())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(ChibiTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ChibiTheme.softGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(ChibiTheme.hairline, lineWidth: 1))
            }
            .accessibilityLabel("Visualizer mode")

            // Page dots Soft PASS
            HStack(spacing: 5) {
                ForEach(VisualizerMode.allCases) { m in
                    Circle()
                        .fill(m == mode ? ChibiTheme.amber : ChibiTheme.textTertiary)
                        .frame(width: m == mode ? 6 : 4, height: m == mode ? 6 : 4)
                        .animation(.easeInOut(duration: 0.2), value: mode)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func applyMode(_ m: VisualizerMode) {
        analyzer.setMeteringEnabled(m.needsAudioMetering)
        syncAnalyzer()
    }

    private func syncAnalyzer() {
        guard mode.needsAudioMetering else { return }
        analyzer.sync(
            trackURL: track.url,
            isPlaying: isPlaying,
            currentTime: player.currentTime
        )
    }
}
