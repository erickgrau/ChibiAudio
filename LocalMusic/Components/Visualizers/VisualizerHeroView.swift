import SwiftUI

/// Now Playing hero: swipeable / picker visualizer modes.
/// Transport stays below; this only replaces the big art plane.
/// Plus gates spectrum / vinyl suite; album & track art stay free.
struct VisualizerHeroView: View {
    @Binding var mode: VisualizerMode
    let track: Track
    let size: CGFloat
    let isPlaying: Bool
    let onLyricsTap: () -> Void

    @Environment(AudioPlayerManager.self) private var player
    @Environment(PlusStore.self) private var plus
    @State private var showPaywall = false
    private var analyzer: VisualizerAudioAnalyzer { VisualizerAudioAnalyzer.shared }

    private var availableModes: [VisualizerMode] {
        VisualizerMode.availableModes(isPlusActive: plus.isPlusActive)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                TabView(selection: $mode) {
                    ForEach(availableModes) { m in
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
        .onAppear { clampAndApply() }
        .onChange(of: mode) { _, newValue in
            let clamped = VisualizerMode.clamped(newValue, isPlusActive: plus.isPlusActive)
            if clamped != newValue {
                mode = clamped
                return
            }
            newValue.persist()
            applyMode(newValue)
        }
        .onChange(of: plus.isPlusActive) { _, _ in clampAndApply() }
        .onChange(of: player.isPlaying) { _, _ in syncAnalyzer() }
        .onChange(of: player.currentTrack?.id) { _, _ in syncAnalyzer() }
        .onDisappear {
            analyzer.setMeteringEnabled(false)
        }
        .animation(.spring(response: 0.45), value: mode)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
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
            Menu {
                ForEach(VisualizerMode.freeModes) { m in
                    Button {
                        mode = m
                    } label: {
                        Label(m.title, systemImage: m.systemImage)
                    }
                }
                if plus.isPlusActive {
                    ForEach(VisualizerMode.plusModes) { m in
                        Button {
                            mode = m
                        } label: {
                            Label(m.title, systemImage: m.systemImage)
                        }
                    }
                } else {
                    Section("ChibiAudio Plus") {
                        ForEach(VisualizerMode.plusModes) { m in
                            Button {
                                showPaywall = true
                            } label: {
                                Label(m.title, systemImage: "lock.fill")
                            }
                        }
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

            HStack(spacing: 5) {
                ForEach(availableModes) { m in
                    Circle()
                        .fill(m == mode ? ChibiTheme.amber : ChibiTheme.textTertiary)
                        .frame(width: m == mode ? 6 : 4, height: m == mode ? 6 : 4)
                        .animation(.easeInOut(duration: 0.2), value: mode)
                }
            }
            .accessibilityHidden(true)

            if !plus.isPlusActive {
                Button {
                    showPaywall = true
                } label: {
                    Text("Plus")
                        .font(ChibiTheme.chipFont())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ChibiTheme.amber, in: Capsule())
                }
                .accessibilityLabel("Unlock visualizer modes with Plus")
            }
        }
    }

    private func clampAndApply() {
        let clamped = VisualizerMode.clamped(mode, isPlusActive: plus.isPlusActive)
        if clamped != mode {
            mode = clamped
        }
        clamped.persist()
        applyMode(clamped)
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
