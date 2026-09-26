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

/// Detailed, realistic cassette render Soft PASS: smoked shell with screws and
/// ridges, a clear window showing tape pack on both reels, hubs with teeth,
/// capstan/pressure-roller holes, and a hand-labeled spine — all drawn in code
/// (no image assets, no licensing) and tinted by the active ChibiTheme so it
/// sits naturally in both Light and Dark modes.
struct CassetteVisualizer: View {
    let track: Track
    let isPlaying: Bool
    let size: CGFloat

    @State private var pausedReel: Double = 0
    @State private var playStartedAt: Date?
    @State private var reelAtPlayStart: Double = 0

    // Tape pack grows on one side, shrinks on the other Soft PASS.
    @State private var tapeRatio: CGFloat = 0.5

    private var shellWidth: CGFloat { size * 0.92 }
    private var shellHeight: CGFloat { size * 0.58 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { timeline in
            let reelRotation = currentReel(at: timeline.date)
            ZStack {
                ChibiTheme.canvasDeep

                CassetteShell(size: size)

                VStack(spacing: size * 0.045) {
                    // Hand-written spine label Soft PASS
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.92, blue: 0.83),
                                        Color(red: 0.9, green: 0.86, blue: 0.76)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: shellWidth * 0.84, height: size * 0.15)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color(red: 0.75, green: 0.7, blue: 0.58).opacity(0.6), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                        VStack(spacing: 2) {
                            Text(track.title)
                                .font(.system(size: size * 0.045, weight: .medium, design: .serif))
                                .italic()
                                .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.28))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(track.artist)
                                .font(.system(size: size * 0.032, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(Color(red: 0.28, green: 0.32, blue: 0.4))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .padding(.horizontal, 10)
                    }

                    // Window + tape reels Soft PASS
                    CassetteWindow(
                        rotation: reelRotation,
                        tapeRatio: tapeRatio,
                        size: size
                    )
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
        // Slow tape transfer between reels while playing.
        .onChange(of: isPlaying) { _, playing in
            withAnimation(.linear(duration: playing ? 45 : 0)) {
                tapeRatio = playing ? 0.82 : tapeRatio
            }
        }
    }

    private func currentReel(at date: Date) -> Double {
        guard isPlaying, let start = playStartedAt else { return pausedReel }
        return reelAtPlayStart + date.timeIntervalSince(start) * 270
    }
}

// MARK: Shell Soft PASS

/// Smoked outer casing: soft gradient body, top ridge, four screws,
/// and the bottom trapezoid section with capstan + pressure roller holes.
private struct CassetteShell: View {
    let size: CGFloat

    private var shellWidth: CGFloat { size * 0.92 }
    private var shellHeight: CGFloat { size * 0.58 }

    var body: some View {
        ZStack {
            // Body Soft PASS
            RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.21, blue: 0.2),
                            Color(red: 0.13, green: 0.13, blue: 0.14),
                            Color(red: 0.09, green: 0.09, blue: 0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                        .strokeBorder(ChibiTheme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 9)

            // Top ridge with label notch Soft PASS
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: shellWidth * 0.55, height: size * 0.022)
                .offset(y: -shellHeight * 0.42)

            // Screws Soft PASS
            ForEach(0..<4, id: \.self) { i in
                let x: CGFloat = i % 2 == 0 ? -1 : 1
                let y: CGFloat = i < 2 ? -1 : 1
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.55), Color(white: 0.25)],
                            center: .center,
                            startRadius: 0.5,
                            endRadius: size * 0.014
                        )
                    )
                    .frame(width: size * 0.018, height: size * 0.018)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                    .offset(x: x * shellWidth * 0.43, y: y * shellHeight * 0.4)
            }

            // Bottom trapezoid Soft PASS
            CassetteBottomSection(size: size)
                .offset(y: shellHeight * 0.36)
        }
    }
}

/// Trapezoid bottom with the two capstan holes and pressure roller wells.
private struct CassetteBottomSection: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Trapezoid cut Soft PASS
            CustomShapeCassetteTrapezoid()
                .fill(Color.black.opacity(0.35))
                .frame(width: size * 0.62, height: size * 0.09)

            // Capstan holes Soft PASS
            HStack(spacing: size * 0.26) {
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: size * 0.045, height: size * 0.045)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: size * 0.045, height: size * 0.045)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }
}

/// Trapezoid silhouette for the cassette's bottom access section.
struct CustomShapeCassetteTrapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Window + reels Soft PASS

/// Clear window: glazed reflection, tape packs sized by `tapeRatio`
/// (how much tape sits on the left hub), and toothed hubs.
private struct CassetteWindow: View {
    let rotation: Double
    let tapeRatio: CGFloat
    let size: CGFloat

    private var windowWidth: CGFloat { size * 0.74 }
    private var windowHeight: CGFloat { size * 0.24 }
    private var hubSize: CGFloat { size * 0.135 }

    var body: some View {
        ZStack {
            // Window frame Soft PASS
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .frame(width: windowWidth, height: windowHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ChibiTheme.teal.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: windowWidth * 0.24) {
                CassetteReel(
                    rotation: rotation,
                    tapeRadius: hubSize * (0.85 + tapeRatio * 0.85),
                    hubSize: hubSize
                )
                CassetteReel(
                    rotation: -rotation * 0.92,
                    tapeRadius: hubSize * (0.85 + (1 - tapeRatio) * 0.85),
                    hubSize: hubSize
                )
            }

            // Glare streak Soft PASS
            LinearGradient(
                colors: [Color.white.opacity(0.13), .clear, .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .frame(width: windowWidth, height: windowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// Wound tape pack + toothed hub. `tapeRadius` is the outer tape radius.
private struct CassetteReel: View {
    let rotation: Double
    let tapeRadius: CGFloat
    let hubSize: CGFloat

    var body: some View {
        ZStack {
            // Tape pack Soft PASS: dark brown ribbon wound on the reel
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.3, green: 0.16, blue: 0.09),
                            Color(red: 0.17, green: 0.1, blue: 0.06),
                            Color(red: 0.1, green: 0.06, blue: 0.04)
                        ],
                        center: .center,
                        startRadius: hubSize * 0.4,
                        endRadius: tapeRadius
                    )
                )
                .frame(width: tapeRadius * 2, height: tapeRadius * 2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                        .frame(width: tapeRadius * 2, height: tapeRadius * 2)
                )

            // Ribbon sheen Soft PASS
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: tapeRadius * 1.92, height: tapeRadius * 1.92)

            // Hub with teeth Soft PASS
            ZStack {
                Circle()
                    .fill(ChibiTheme.canvasMid)
                    .frame(width: hubSize, height: hubSize)
                    .overlay(Circle().strokeBorder(ChibiTheme.hairline, lineWidth: 1))

                ForEach(0..<6, id: \.self) { i in
                    // Teeth Soft PASS: wedges around the hub
                    CassetteHubTooth(index: i, hubSize: hubSize)
                }
            }
            .frame(width: hubSize, height: hubSize)
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct CassetteHubTooth: View {
    let index: Int
    let hubSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(ChibiTheme.amber.opacity(0.55))
            .frame(width: 2.5, height: hubSize * 0.2)
            .offset(y: -hubSize * 0.36)
            .rotationEffect(.degrees(Double(index) * 60))
    }
}
