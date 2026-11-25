import Accelerate
import Foundation

public struct AudioLevelMetrics: Equatable, Sendable {
    public let rms: Float
    public let peak: Float

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }
}

public final class AudioPreprocessor {
    public var targetRMS: Float
    public var maxGain: Float
    public var noiseGateThreshold: Float
    private var smoothedGain: Float = 1.0
    private var fractionalPosition: Double = 0
    private var previousSample: Float = 0
    private var hasPreviousSample: Bool = false

    public init(
        targetRMS: Float = 0.14,
        maxGain: Float = 6.0,
        noiseGateThreshold: Float = 0.0025
    ) {
        self.targetRMS = targetRMS
        self.maxGain = maxGain
        self.noiseGateThreshold = noiseGateThreshold
    }

    public func reset() {
        smoothedGain = 1.0
        fractionalPosition = 0
        previousSample = 0
        hasPreviousSample = false
    }

    public static func measureLevels(_ samples: [Float]) -> AudioLevelMetrics {
        guard !samples.isEmpty else { return AudioLevelMetrics(rms: 0, peak: 0) }
        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        if !rms.isFinite { rms = 0 }
        if !peak.isFinite { peak = 0 }
        return AudioLevelMetrics(rms: rms, peak: peak)
    }

    public static func softClip(_ value: Float, knee: Float = 0.7) -> Float {
        let absVal = abs(value)
        if absVal <= knee {
            return value
        }
        let headroom = max(1e-5, 1.0 - knee)
        let excess = (absVal - knee) / headroom
        let compressed = knee + headroom * Foundation.tanh(excess)
        return value >= 0 ? compressed : -compressed
    }

    public func resampleTo16k(_ input: [Float], inputSampleRate: Double) -> [Float] {
        guard !input.isEmpty, inputSampleRate > 0 else { return [] }
        let targetRate: Double = 16_000.0
        if abs(inputSampleRate - targetRate) < 1.0 {
            previousSample = input.last ?? 0
            hasPreviousSample = true
            return input
        }

        let ratio = inputSampleRate / targetRate
        var extended: [Float]
        if hasPreviousSample {
            extended = [previousSample]
            extended.append(contentsOf: input)
        } else {
            extended = [input[0]]
            extended.append(contentsOf: input)
            fractionalPosition = 1.0
        }

        var output: [Float] = []
        let estimatedCount = max(1, Int(Double(input.count) / ratio) + 2)
        output.reserveCapacity(estimatedCount)

        let maxIndex = Double(extended.count - 1)
        var pos = fractionalPosition
        while pos < maxIndex {
            let idx = Int(pos)
            let frac = Float(pos - Double(idx))
            let s0 = extended[idx]
            let s1 = extended[idx + 1]
            output.append(s0 + (s1 - s0) * frac)
            pos += ratio
        }

        fractionalPosition = pos - Double(input.count)
        if fractionalPosition < 0 {
            fractionalPosition = 0
        }
        previousSample = input.last ?? 0
        hasPreviousSample = true
        return output
    }

    public func process(_ samples: [Float]) -> (samples: [Float], levels: AudioLevelMetrics) {
        guard !samples.isEmpty else {
            return ([], AudioLevelMetrics(rms: 0, peak: 0))
        }
        let rawLevels = Self.measureLevels(samples)
        if rawLevels.rms < noiseGateThreshold {
            smoothedGain = smoothedGain * 0.9 + 1.0 * 0.1
            return ([Float](repeating: 0, count: samples.count), rawLevels)
        }

        let desiredGain = min(maxGain, max(0.5, targetRMS / max(rawLevels.rms, 1e-5)))
        let alpha: Float = desiredGain < smoothedGain ? 0.35 : 0.12
        smoothedGain += (desiredGain - smoothedGain) * alpha

        var processed = [Float](repeating: 0, count: samples.count)
        let gain = smoothedGain
        for i in 0..<samples.count {
            let v = samples[i]
            let finite = v.isFinite ? v : 0
            processed[i] = Self.softClip(finite * gain)
        }
        return (processed, rawLevels)
    }
}
