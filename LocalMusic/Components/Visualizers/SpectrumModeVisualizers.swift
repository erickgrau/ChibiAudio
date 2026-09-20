import SwiftUI

// MARK: - VU Meters Soft PASS

struct VUMeterVisualizer: View {
    let left: Float
    let right: Float
    let isPlaying: Bool

    var body: some View {
        ZStack {
            ChibiTheme.canvasElevated
            // Soft vignette
            RadialGradient(
                colors: [ChibiTheme.canvasMid, ChibiTheme.canvasDeep],
                center: .center,
                startRadius: 20,
                endRadius: 220
            )

            HStack(spacing: 28) {
                VUNeedleGauge(level: left, label: "L")
                VUNeedleGauge(level: right, label: "R")
            }
            .padding(20)

            // Soft glass bezel label
            VStack {
                Spacer()
                Text(isPlaying ? "VU" : "VU · IDLE")
                    .font(ChibiTheme.sampleRateFont())
                    .foregroundStyle(ChibiTheme.amber.opacity(0.85))
                    .padding(.bottom, 14)
            }
        }
    }
}

private struct VUNeedleGauge: View {
    let level: Float
    let label: String

    /// Needle angle Soft PASS: −50° (rest) → +50° (peak).
    private var angle: Double {
        let clamped = Double(max(0, min(1, level)))
        return -50 + clamped * 100
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Face
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.12, blue: 0.13),
                                Color(red: 0.07, green: 0.07, blue: 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().strokeBorder(ChibiTheme.hairline, lineWidth: 1))

                // Scale arc Soft PASS (amber → red)
                Circle()
                    .trim(from: 0.12, to: 0.38)
                    .stroke(
                        AngularGradient(
                            colors: [ChibiTheme.amber, ChibiTheme.amber, Color.red.opacity(0.9)],
                            center: .center,
                            startAngle: .degrees(-50),
                            endAngle: .degrees(50)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(180))
                    .padding(s * 0.12)

                // Needle
                Capsule()
                    .fill(ChibiTheme.amber)
                    .frame(width: 2.5, height: s * 0.38)
                    .offset(y: -s * 0.16)
                    .rotationEffect(.degrees(angle))
                    .shadow(color: ChibiTheme.amber.opacity(0.45), radius: 2)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.55), value: level)

                // Hub
                Circle()
                    .fill(ChibiTheme.teal)
                    .frame(width: 8, height: 8)

                VStack {
                    Spacer()
                    Text(label)
                        .font(ChibiTheme.sampleRateFont())
                        .foregroundStyle(ChibiTheme.textSecondary)
                        .padding(.bottom, s * 0.12)
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 1980s LED Bar Soft PASS

struct LEDBarVisualizer: View {
    let spectrum: [Float]
    let beat: Float

    private let barCount = 16

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.025)

            // Subtle CRT Soft PASS wash
            LinearGradient(
                colors: [
                    ChibiTheme.amber.opacity(0.06 + Double(beat) * 0.08),
                    .clear,
                    ChibiTheme.teal.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    LEDColumn(level: band(at: i))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)

            VStack {
                HStack {
                    Text("SPECTRUM")
                        .font(ChibiTheme.sampleRateFont())
                        .foregroundStyle(ChibiTheme.amber.opacity(0.7))
                    Spacer()
                    Text("1980")
                        .font(ChibiTheme.sampleRateFont())
                        .foregroundStyle(ChibiTheme.textTertiary)
                }
                .padding(14)
                Spacer()
            }
        }
    }

    private func band(at index: Int) -> Float {
        guard !spectrum.isEmpty else { return 0 }
        let mapped = Int(Float(index) / Float(barCount) * Float(spectrum.count))
        return spectrum[min(spectrum.count - 1, mapped)]
    }
}

private struct LEDColumn: View {
    let level: Float
    private let segments = 12

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { seg in
                let threshold = Float(segments - 1 - seg) / Float(segments)
                let on = level > threshold
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(ledColor(segment: seg, on: on))
                    .frame(maxWidth: .infinity)
                    .frame(height: 7)
                    .opacity(on ? 1 : 0.18)
            }
        }
    }

    private func ledColor(segment: Int, on: Bool) -> Color {
        guard on else { return Color.white.opacity(0.15) }
        // Top = red, mid = amber, low = amber-dim Soft PASS
        if segment < 2 { return Color.red }
        if segment < 5 { return Color(red: 1.0, green: 0.45, blue: 0.1) }
        return ChibiTheme.amber
    }
}

// MARK: - EQ Spectrum Soft PASS

struct EQSpectrumVisualizer: View {
    let spectrum: [Float]
    let beat: Float

    var body: some View {
        ZStack {
            ChibiTheme.canvasElevated
            LinearGradient(
                colors: [
                    ChibiTheme.teal.opacity(0.12 + Double(beat) * 0.1),
                    ChibiTheme.canvasDeep,
                    ChibiTheme.amber.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geo in
                let count = max(spectrum.count, 1)
                let spacing: CGFloat = 3
                let barWidth = max(2, (geo.size.width - CGFloat(count + 1) * spacing) / CGFloat(count))

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let h = max(4, CGFloat(spectrum[i]) * geo.size.height * 0.85)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ChibiTheme.teal, ChibiTheme.amber],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: barWidth, height: h)
                            .shadow(color: ChibiTheme.teal.opacity(0.25 * Double(spectrum[i])), radius: 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, spacing)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.08), value: spectrum)
            }
        }
    }
}

// MARK: - Kaleidoscope Soft PASS

struct KaleidoscopeVisualizer: View {
    let spectrum: [Float]
    let beat: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.42
                let wedges = 8
                let bands = max(spectrum.count, 1)

                for w in 0..<wedges {
                    let base = (Double(w) / Double(wedges)) * .pi * 2 + t * (0.35 + Double(beat) * 0.8)
                    for i in 0..<min(bands, 24) {
                        let level = CGFloat(spectrum[i])
                        guard level > 0.02 else { continue }
                        let a0 = base + Double(i) * 0.04
                        let a1 = a0 + (.pi * 2 / Double(wedges)) * 0.85
                        var path = Path()
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius * (0.25 + level * 0.75),
                            startAngle: .radians(a0),
                            endAngle: .radians(a1),
                            clockwise: false
                        )
                        path.closeSubpath()
                        let color: Color = (i % 2 == 0) ? ChibiTheme.amber : ChibiTheme.teal
                        context.fill(
                            path,
                            with: .color(color.opacity(0.15 + Double(level) * 0.55))
                        )
                    }
                }

                // Mirrored ring Soft PASS
                let ring = Path(ellipseIn: CGRect(
                    x: center.x - radius * 0.2,
                    y: center.y - radius * 0.2,
                    width: radius * 0.4,
                    height: radius * 0.4
                ))
                context.stroke(ring, with: .color(ChibiTheme.amber.opacity(0.35 + Double(beat) * 0.4)), lineWidth: 2)
            }
            .background(ChibiTheme.canvasDeep)
        }
    }
}

// MARK: - Vectors / Oscilloscope Soft PASS

struct VectorsVisualizer: View {
    let waveform: [Float]
    let beat: Float

    var body: some View {
        ZStack {
            Color.black
            // Grid Soft PASS
            Canvas { context, size in
                let cols = 6
                let rows = 4
                for c in 0...cols {
                    let x = size.width * CGFloat(c) / CGFloat(cols)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(p, with: .color(ChibiTheme.teal.opacity(0.12)), lineWidth: 1)
                }
                for r in 0...rows {
                    let y = size.height * CGFloat(r) / CGFloat(rows)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(p, with: .color(ChibiTheme.teal.opacity(0.12)), lineWidth: 1)
                }

                guard waveform.count > 1 else { return }
                var path = Path()
                for (i, sample) in waveform.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(waveform.count - 1)
                    let y = size.height * 0.5 - CGFloat(sample) * size.height * 0.42
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .color(ChibiTheme.amber.opacity(0.55 + Double(beat) * 0.4)),
                    style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                )

                // Vector Lissajous-ish secondary Soft PASS from delayed samples
                if waveform.count > 8 {
                    var liss = Path()
                    let mid = waveform.count / 2
                    for i in 0..<mid {
                        let x = size.width * 0.5 + CGFloat(waveform[i]) * size.width * 0.28
                        let y = size.height * 0.5 + CGFloat(waveform[i + mid / 2]) * size.height * 0.28
                        if i == 0 {
                            liss.move(to: CGPoint(x: x, y: y))
                        } else {
                            liss.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    context.stroke(
                        liss,
                        with: .color(ChibiTheme.teal.opacity(0.35 + Double(beat) * 0.3)),
                        style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
                    )
                }
            }
        }
    }
}
