import SwiftUI

// MARK: - Vinyl Soft PASS

/// Commercial LP Soft PASS: spinning disc, tonearm/needle, label uses album art.
struct VinylVisualizer: View {
    let track: Track
    let isPlaying: Bool
    let size: CGFloat

    /// Frozen angle when paused Soft PASS so the disc doesn’t jump on resume.
    @State private var pausedAngle: Double = 0
    @State private var playStartedAt: Date?
    @State private var angleAtPlayStart: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            let rotation = currentRotation(at: timeline.date)
            ZStack {
                // Plinth Soft PASS
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.12, blue: 0.11),
                        ChibiTheme.canvasDeep
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft felt mat
                Circle()
                    .fill(Color(red: 0.08, green: 0.1, blue: 0.1))
                    .frame(width: size * 0.88, height: size * 0.88)
                    .overlay(Circle().strokeBorder(ChibiTheme.hairline, lineWidth: 1))

                // Disc Soft PASS
                ZStack {
                    // Grooves
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.05, blue: 0.055),
                                    Color(red: 0.12, green: 0.12, blue: 0.13),
                                    Color(red: 0.04, green: 0.04, blue: 0.045)
                                ],
                                center: .center,
                                startRadius: size * 0.12,
                                endRadius: size * 0.4
                            )
                        )
                        .frame(width: size * 0.78, height: size * 0.78)
                        .overlay {
                            ForEach(0..<14, id: \.self) { i in
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.035), lineWidth: 1)
                                    .padding(CGFloat(i) * (size * 0.022))
                            }
                        }

                    // Label = album art Soft PASS
                    ArtworkView(
                        trackURL: track.url,
                        hasArtwork: track.hasArtwork,
                        pointSize: size * 0.32,
                        fullResolution: true,
                        placeholderIcon: "music.note"
                    )
                    .frame(width: size * 0.32, height: size * 0.32)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(ChibiTheme.amber.opacity(0.35), lineWidth: 2))

                    // Spindle
                    Circle()
                        .fill(ChibiTheme.textSecondary)
                        .frame(width: 8, height: 8)
                }
                .rotationEffect(.degrees(rotation))

                // Tonearm Soft PASS
                TonearmView(isPlaying: isPlaying, size: size)
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                playStartedAt = Date()
                angleAtPlayStart = pausedAngle
            } else {
                if let start = playStartedAt {
                    pausedAngle = angleAtPlayStart + Date().timeIntervalSince(start) * 120
                }
                playStartedAt = nil
            }
        }
        .onAppear {
            if isPlaying {
                playStartedAt = Date()
                angleAtPlayStart = pausedAngle
            }
        }
    }

    private func currentRotation(at date: Date) -> Double {
        guard isPlaying, let start = playStartedAt else { return pausedAngle }
        return angleAtPlayStart + date.timeIntervalSince(start) * 120
    }
}

private struct TonearmView: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        let restAngle: Double = -28
        let playAngle: Double = 12

        ZStack(alignment: .topTrailing) {
            // Pivot base
            Circle()
                .fill(ChibiTheme.canvasMid)
                .frame(width: size * 0.08, height: size * 0.08)
                .overlay(Circle().strokeBorder(ChibiTheme.hairline, lineWidth: 1))
                .overlay(
                    Circle()
                        .fill(ChibiTheme.teal.opacity(0.7))
                        .frame(width: 6, height: 6)
                )
                .offset(x: -size * 0.06, y: size * 0.08)

            // Arm + headshell
            ZStack(alignment: .top) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.75), Color(white: 0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: size * 0.42)

                // Cartridge / needle Soft PASS
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ChibiTheme.amber)
                    .frame(width: 12, height: 16)
                    .overlay(
                        Rectangle()
                            .fill(ChibiTheme.textPrimary)
                            .frame(width: 1.5, height: 10)
                            .offset(y: 8)
                    )
                    .offset(y: size * 0.40)
            }
            .rotationEffect(
                .degrees(isPlaying ? playAngle : restAngle),
                anchor: .top
            )
            .offset(x: -size * 0.06, y: size * 0.1)
            .animation(.spring(response: 0.55, dampingFraction: 0.75), value: isPlaying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(size * 0.06)
    }
}

// MARK: - Cassette / Mixtape Soft PASS

struct CassetteVisualizer: View {
    let track: Track
    let isPlaying: Bool
    let size: CGFloat

    @State private var pausedReel: Double = 0
    @State private var playStartedAt: Date?
    @State private var reelAtPlayStart: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            let reelRotation = currentReel(at: timeline.date)
            ZStack {
                ChibiTheme.canvasDeep

                // Shell Soft PASS
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.15, blue: 0.14),
                                Color(red: 0.09, green: 0.09, blue: 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.58)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                            .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

                VStack(spacing: size * 0.04) {
                    // Hand-written spine label Soft PASS
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.93, green: 0.9, blue: 0.82))
                            .frame(width: size * 0.78, height: size * 0.16)

                        VStack(spacing: 2) {
                            Text(track.title)
                                .font(.system(size: size * 0.045, weight: .medium, design: .serif))
                                .italic()
                                .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.28))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: size * 0.032, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.4))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                    }

                    // Window + reels Soft PASS
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: size * 0.72, height: size * 0.22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(ChibiTheme.teal.opacity(0.25), lineWidth: 1)
                            )

                        HStack(spacing: size * 0.18) {
                            CassetteReel(rotation: reelRotation, size: size * 0.16)
                            CassetteReel(rotation: -reelRotation * 0.92, size: size * 0.16)
                        }
                    }
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                playStartedAt = Date()
                reelAtPlayStart = pausedReel
            } else {
                if let start = playStartedAt {
                    pausedReel = reelAtPlayStart + Date().timeIntervalSince(start) * 270
                }
                playStartedAt = nil
            }
        }
        .onAppear {
            if isPlaying {
                playStartedAt = Date()
                reelAtPlayStart = pausedReel
            }
        }
    }

    private func currentReel(at date: Date) -> Double {
        guard isPlaying, let start = playStartedAt else { return pausedReel }
        return reelAtPlayStart + date.timeIntervalSince(start) * 270
    }
}

private struct CassetteReel: View {
    let rotation: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.25, green: 0.12, blue: 0.08),
                            Color(red: 0.08, green: 0.05, blue: 0.04)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size, height: size)

            // Spokes Soft PASS
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(ChibiTheme.amber.opacity(0.55))
                    .frame(width: 2, height: size * 0.42)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            Circle()
                .fill(ChibiTheme.canvasMid)
                .frame(width: size * 0.28, height: size * 0.28)
                .overlay(Circle().strokeBorder(ChibiTheme.hairline, lineWidth: 1))
        }
        .rotationEffect(.degrees(rotation))
    }
}
