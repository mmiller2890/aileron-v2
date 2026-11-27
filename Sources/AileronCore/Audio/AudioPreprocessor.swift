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
    private static let polyphasePhases = 64

    public var targetRMS: Float
    public var maxGain: Float
    public var noiseGateThreshold: Float
    private var smoothedGain: Float = 1.0
    private var configuredInputRate: Double = 0
    private var halfTaps: Int = 0
    private var tapsPerPhase: Int = 0
    private var polyphaseTable: [Float] = []
    private var resampleBuffer: [Float] = []
    private var resamplePos: Double = 0

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
        configuredInputRate = 0
        halfTaps = 0
        tapsPerPhase = 0
        polyphaseTable.removeAll(keepingCapacity: true)
        resampleBuffer.removeAll(keepingCapacity: true)
        resamplePos = 0
    }

    private func configureResampler(inputSampleRate: Double) {
        let ratio = inputSampleRate / 16_000.0
        let cutoff = 0.45 * min(1.0, 1.0 / ratio)
        let half = max(8, min(24, Int(ceil(4.0 * max(1.0, ratio)))))
        let taps = half * 2
        let phases = Self.polyphasePhases

        var table = [Float](repeating: 0, count: phases * taps)
        let halfDouble = Double(half)
        for p in 0..<phases {
            let frac = Double(p) / Double(phases)
            var sum = 0.0
            let rowOffset = p * taps
            for k in 0..<taps {
                let x = Double(k - half + 1) - frac
                let sincArg = 2.0 * cutoff * x
                let sincVal: Double
                if abs(sincArg) < 1e-9 {
                    sincVal = 2.0 * cutoff
                } else {
                    sincVal = sin(.pi * sincArg) / (.pi * x)
                }
                let u = x / halfDouble
                let window: Double
                if abs(u) >= 1.0 {
                    window = 0.0
                } else {
                    let c1 = cos(.pi * (u + 1.0))
                    let c2 = cos(2.0 * .pi * (u + 1.0))
                    window = 0.42 - 0.5 * c1 + 0.08 * c2
                }
                let coeff = sincVal * window
                table[rowOffset + k] = Float(coeff)
                sum += coeff
            }
            if abs(sum) > 1e-9 {
                let inv = Float(1.0 / sum)
                for k in 0..<taps {
                    table[rowOffset + k] *= inv
                }
            }
        }

        self.configuredInputRate = inputSampleRate
        self.halfTaps = half
        self.tapsPerPhase = taps
        self.polyphaseTable = table
        self.resampleBuffer = [Float](repeating: 0, count: half)
        self.resamplePos = Double(half)
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
            return input
        }

        if abs(configuredInputRate - inputSampleRate) >= 1.0 || polyphaseTable.isEmpty {
            configureResampler(inputSampleRate: inputSampleRate)
        }

        resampleBuffer.append(contentsOf: input)
        let ratio = inputSampleRate / targetRate
        let half = halfTaps
        let taps = tapsPerPhase
        let phases = Self.polyphasePhases
        let limit = Double(resampleBuffer.count - half)
        guard resamplePos < limit else { return [] }

        var output: [Float] = []
        output.reserveCapacity(max(1, Int((limit - resamplePos) / ratio) + 2))

        var pos = resamplePos
        resampleBuffer.withUnsafeBufferPointer { srcBuf in
            polyphaseTable.withUnsafeBufferPointer { tblBuf in
                guard let srcBase = srcBuf.baseAddress, let tblBase = tblBuf.baseAddress else { return }
                while pos < limit {
                    let center = Int(pos)
                    let frac = pos - Double(center)
                    let phaseIdx = min(phases - 1, Int(frac * Double(phases)))
                    let startIdx = center - half + 1
                    var dot: Float = 0
                    vDSP_dotpr(
                        srcBase.advanced(by: startIdx),
                        1,
                        tblBase.advanced(by: phaseIdx * taps),
                        1,
                        &dot,
                        vDSP_Length(taps)
                    )
                    output.append(dot)
                    pos += ratio
                }
            }
        }

        let keepFrom = max(0, Int(pos) - half)
        if keepFrom > 0 {
            resampleBuffer.removeFirst(keepFrom)
            pos -= Double(keepFrom)
        }
        resamplePos = pos
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

    public static func prepareForTranscription(
        _ samples: [Float],
        noiseGateThreshold: Float = 0.0015,
        targetRMS: Float = 0.10,
        maxGain: Float = 6.0
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let threshold = max(0, noiseGateThreshold)
        var gated = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let s = samples[i].isFinite ? samples[i] : 0
            let a = abs(s)
            if threshold > 0 && a < threshold {
                gated[i] = s * powf(a / threshold, 1.0 / 3.0)
            } else {
                gated[i] = s
            }
        }
        let rms = measureLevels(gated).rms
        guard rms >= 0.001 else { return gated }
        let gain = min(maxGain, max(0.5, targetRMS / rms))
        var out = [Float](repeating: 0, count: gated.count)
        for i in 0..<gated.count {
            out[i] = softClip(gated[i] * gain, knee: 0.9)
        }
        return out
    }
}
