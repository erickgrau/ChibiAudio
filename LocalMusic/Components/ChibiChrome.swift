import SwiftUI

/// Subtle glass capsule labeling the media source.
struct SourceChip: View {
    let kind: MediaSourceKind

    var body: some View {
        Text(kind.label)
            .font(ChibiTheme.chipFont())
            .foregroundStyle(ChibiTheme.textPrimary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ChibiTheme.softGlass, in: Capsule())
            .overlay(Capsule().strokeBorder(ChibiTheme.hairline, lineWidth: 1))
    }
}

/// Monospace sample-rate / PCM chip near transport.
struct SampleRateChip: View {
    var sampleRateHz: Double
    var bitDepthLabel: String = "PCM"

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ChibiTheme.amber)
                .frame(width: 6, height: 6)
            Text(rateLabel)
                .font(ChibiTheme.sampleRateFont())
                .foregroundStyle(ChibiTheme.amber.opacity(0.95))
            Text("·")
                .font(ChibiTheme.sampleRateFont())
                .foregroundStyle(ChibiTheme.textTertiary)
            Text(bitDepthLabel)
                .font(ChibiTheme.sampleRateFont())
                .foregroundStyle(ChibiTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ChibiTheme.softGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(ChibiTheme.amber.opacity(0.25), lineWidth: 1))
        .accessibilityLabel("\(bitDepthLabel) \(rateLabel)")
    }

    private var rateLabel: String {
        if sampleRateHz >= 1000 {
            let k = sampleRateHz / 1000
            if abs(k.rounded() - k) < 0.05 {
                return "\(Int(k)) kHz"
            }
            return String(format: "%.1f kHz", k)
        }
        return "\(Int(sampleRateHz)) Hz"
    }
}

/// Shown when Hi-res/DAC mode is on and USB DAC (THX Onyx) is the route.
struct BitPerfectOnyxPill: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ChibiTheme.teal)
                .frame(width: 7, height: 7)
                .shadow(color: ChibiTheme.teal.opacity(0.6), radius: 4)
            Text("Bit-perfect → THX Onyx")
                .font(ChibiTheme.chipFont())
                .foregroundStyle(ChibiTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(ChibiTheme.softGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(ChibiTheme.teal.opacity(0.45), lineWidth: 1))
    }
}

/// USB/DAC connected indicator (teal).
struct DACRouteIndicator: View {
    let summary: String
    var isUSB: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isUSB ? ChibiTheme.teal : ChibiTheme.textTertiary)
                .frame(width: 6, height: 6)
            Text(summary)
                .font(.caption2)
                .foregroundStyle(ChibiTheme.textSecondary)
                .lineLimit(1)
        }
    }
}
