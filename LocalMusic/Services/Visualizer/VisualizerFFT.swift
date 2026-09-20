import Accelerate
import Foundation

/// Pure Soft PASS FFT / metering helpers (testable without AVPlayer).
enum VisualizerFFT {

    static let bandCount = 32
    static let waveformSampleCount = 128

    /// Collapse a magnitude spectrum (linear bins) into log-spaced display bands in 0…1.
    static func logBands(from magnitudes: [Float], bandCount: Int = bandCount) -> [Float] {
        guard !magnitudes.isEmpty, bandCount > 0 else {
            return Array(repeating: 0, count: max(bandCount, 0))
        }
        let n = magnitudes.count
        var bands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let lower = exp(log(Float(max(n - 1, 1))) * Float(i) / Float(bandCount))
            let upper = exp(log(Float(max(n - 1, 1))) * Float(i + 1) / Float(bandCount))
            let start = min(n - 1, max(0, Int(lower)))
            let end = min(n, max(start + 1, Int(ceil(upper))))
            var sum: Float = 0
            var peak: Float = 0
            for j in start..<end {
                let v = magnitudes[j]
                sum += v
                if v > peak { peak = v }
            }
            let avg = sum / Float(end - start)
            // Blend peak + average so sparse highs still light LEDs.
            bands[i] = min(1, (peak * 0.65 + avg * 0.35) * 2.2)
        }
        return bands
    }

    /// RMS level 0…1 from interleaved or mono samples.
    static func rmsLevel(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var meanSquares: Float = 0
        vDSP_measqv(samples, 1, &meanSquares, vDSP_Length(count))
        let rms = sqrtf(meanSquares)
        // Soft compressor into display range.
        return min(1, rms * 3.5)
    }

    /// Peak absolute sample 0…1.
    static func peakLevel(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        return min(1, peak)
    }

    /// Downsample a mono buffer into a fixed waveform strip (−1…1).
    static func waveform(from samples: [Float], count: Int = waveformSampleCount) -> [Float] {
        guard !samples.isEmpty, count > 0 else {
            return Array(repeating: 0, count: max(count, 0))
        }
        if samples.count <= count { return samples }
        var out = [Float](repeating: 0, count: count)
        let step = Float(samples.count) / Float(count)
        for i in 0..<count {
            let idx = min(samples.count - 1, Int(Float(i) * step))
            out[i] = max(-1, min(1, samples[idx]))
        }
        return out
    }

    /// Apply a light peak-hold decay for LED Soft PASS feel.
    static func decay(_ current: [Float], toward target: [Float], rise: Float = 0.55, fall: Float = 0.18) -> [Float] {
        zip(current, target).map { c, t in
            if t >= c {
                return c + (t - c) * rise
            } else {
                return max(0, c - (c - t) * fall)
            }
        }
    }

    /// Simple beat / energy pulse from spectrum (low+mid emphasis).
    static func beatEnergy(from bands: [Float]) -> Float {
        guard !bands.isEmpty else { return 0 }
        let lowEnd = bands.prefix(min(8, bands.count))
        let sum = lowEnd.reduce(0, +)
        return min(1, sum / Float(lowEnd.count) * 1.4)
    }
}
