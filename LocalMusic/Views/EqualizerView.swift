import SwiftUI

struct EqualizerView: View {
    @Bindable private var eq = EqualizerController.shared

    var body: some View {
        List {
            Section {
                Toggle("Enable EQ", isOn: $eq.isEnabled)
                    .disabled(eq.isForcedOffForBitPerfect)
                if eq.isForcedOffForBitPerfect {
                    Text("EQ is off while Hi-res / DAC mode (or USB DAC like THX Onyx) is active — bit-perfect path preferred. Turn off DAC mode in Settings to use EQ.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("EQ processes audio in float PCM and may resample in the engine graph. For bit-perfect USB DAC listening, leave this off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Presets") {
                ForEach(EqualizerController.presets) { preset in
                    Button {
                        eq.applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if eq.activePresetID == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section("Bands") {
                ForEach(Array(EqualizerController.bandFrequencies.enumerated()), id: \.offset) { index, freq in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(freqLabel(freq))
                            Spacer()
                            Text(String(format: "%+.1f dB", eq.gains[index]))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
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
                        .disabled(eq.isForcedOffForBitPerfect || !eq.isEnabled)
                    }
                }
            }
        }
        .navigationTitle("Equalizer")
    }

    private func freqLabel(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.0f kHz", freq / 1000)
        }
        return String(format: "%.0f Hz", freq)
    }
}
