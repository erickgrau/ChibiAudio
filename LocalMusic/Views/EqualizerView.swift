import SwiftUI

struct EqualizerView: View {
    @Bindable private var eq = EqualizerController.shared

    var body: some View {
        List {
            Section {
                Toggle("Enable EQ", isOn: $eq.isEnabled)
                    .disabled(eq.isForcedOffForBitPerfect)
                    .tint(ChibiTheme.amber)
                if eq.isForcedOffForBitPerfect {
                    Label {
                        Text("EQ is dimmed while Hi-res / DAC bit-perfect mode (or USB DAC like THX Onyx) is active — cleaner PCM path preferred.")
                            .font(.footnote)
                            .foregroundStyle(ChibiTheme.textSecondary)
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(ChibiTheme.teal)
                    }
                    .listRowBackground(ChibiTheme.canvasMid.opacity(0.6))
                } else {
                    Text("EQ processes audio in float PCM when engaged. For bit-perfect USB DAC listening, leave this off or enable Hi-res / DAC mode.")
                        .font(.footnote)
                        .foregroundStyle(ChibiTheme.textSecondary)
                }
            }

            Section("Presets") {
                ForEach(EqualizerController.presets) { preset in
                    Button {
                        eq.applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.name)
                                .foregroundStyle(
                                    eq.isForcedOffForBitPerfect
                                        ? ChibiTheme.textTertiary
                                        : ChibiTheme.textPrimary
                                )
                            Spacer()
                            if eq.activePresetID == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(ChibiTheme.amber)
                            }
                        }
                    }
                    .disabled(eq.isForcedOffForBitPerfect)
                }
            }

            Section("Bands") {
                ForEach(Array(EqualizerController.bandFrequencies.enumerated()), id: \.offset) { index, freq in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(freqLabel(freq))
                                .foregroundStyle(ChibiTheme.textPrimary)
                            Spacer()
                            Text(String(format: "%+.1f dB", eq.gains[index]))
                                .font(ChibiTheme.sampleRateFont())
                                .foregroundStyle(ChibiTheme.textSecondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(eq.gains[index]) },
                                set: { newValue in
                                    var g = eq.gains
                                    g[index] = Float(newValue)
                                    eq.gains = g
                                    eq.activePresetID = "custom"
                                }
                            ),
                            in: -12...12,
                            step: 0.5
                        )
                        .tint(ChibiTheme.amber)
                        .disabled(eq.isForcedOffForBitPerfect || !eq.isEnabled)
                        .opacity(eq.isForcedOffForBitPerfect || !eq.isEnabled ? 0.4 : 1)
                    }
                }
            }
        }
        .navigationTitle("Equalizer")
        .chibiListChrome()
        .toolbarBackground(ChibiTheme.softGlass, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func freqLabel(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.0f kHz", freq / 1000)
        }
        return String(format: "%.0f Hz", freq)
    }
}
