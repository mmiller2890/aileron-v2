import Accelerate
import Foundation

public enum SpeechSegmentEvent: Sendable {
    case speechStarted(turnId: UInt64)
    case speechAudio(turnId: UInt64, samples: [Float])
    case turnCompleted(turnId: UInt64, samples: [Float], durationSeconds: Double)
    case turnDiscarded(turnId: UInt64)
}

public final class SpeechSegmenter {
    public static let sampleRate: Int = 16_000
    public static let frameSamples: Int = 512
    public static let preSpeechSamples: Int = 10_240

    public var settings: VADSettings
    private var nextTurnId: UInt64 = 1
    private var activeTurnId: UInt64?
    private var preBuffer: [Float] = []
    private var speechBuffer: [Float] = []
    private var silenceSampleCount: Int = 0
    private var activeSpeechSampleCount: Int = 0
    private var noiseFloorRMS: Float = 0.001

    public var isInSpeech: Bool { activeTurnId != nil }

    public init(settings: VADSettings = VADSettings()) {
        self.settings = settings
        self.preBuffer.reserveCapacity(Self.preSpeechSamples * 2)
    }

    public func reset() {
        activeTurnId = nil
        preBuffer.removeAll(keepingCapacity: true)
        speechBuffer.removeAll(keepingCapacity: true)
        silenceSampleCount = 0
        activeSpeechSampleCount = 0
        noiseFloorRMS = 0.001
    }

    public func process(samples16k: [Float], neuralProbability: Float?) -> [SpeechSegmentEvent] {
        guard !samples16k.isEmpty else { return [] }
        var events: [SpeechSegmentEvent] = []

        let startThreshold = max(0.15, min(0.90, 1.0 - settings.sensitivity + 0.15))
        let sustainThreshold = startThreshold * 0.65
        let energy = AudioPreprocessor.measureLevels(samples16k).rms
        let energyStart = max(0.008, settings.noiseGateThreshold * 3.5)
        let silenceFloor = max(settings.noiseGateThreshold * 2.0, noiseFloorRMS * 2.2)

        if activeTurnId == nil && energy < energyStart {
            noiseFloorRMS = noiseFloorRMS * 0.92 + energy * 0.08
        }

        let isVoice: Bool
        if let prob = neuralProbability {
            if activeTurnId == nil {
                isVoice = prob >= startThreshold && energy >= silenceFloor
            } else {
                isVoice = prob >= sustainThreshold && energy >= silenceFloor
            }
        } else {
            isVoice = activeTurnId == nil ? (energy >= energyStart) : (energy >= silenceFloor)
        }

        if let currentId = activeTurnId {
            speechBuffer.append(contentsOf: samples16k)
            events.append(.speechAudio(turnId: currentId, samples: samples16k))

            if isVoice {
                silenceSampleCount = 0
                activeSpeechSampleCount += samples16k.count
            } else {
                silenceSampleCount += samples16k.count
            }

            let silenceThresholdSamples = max(1_600, (settings.silenceEndMs * Self.sampleRate) / 1000)
            let hardSplitSamples = max(20 * Self.sampleRate, Int(settings.maxTurnSeconds * Double(Self.sampleRate)))

            if silenceSampleCount >= silenceThresholdSamples {
                events.append(contentsOf: finishCurrentTurn(trimTrailingSilence: true))
            } else if speechBuffer.count >= hardSplitSamples {
                events.append(contentsOf: splitCurrentTurnAtQuietestHop())
            }
        } else {
            if isVoice {
                let turnId = nextTurnId
                nextTurnId += 1
                activeTurnId = turnId
                speechBuffer.removeAll(keepingCapacity: true)
                speechBuffer.append(contentsOf: preBuffer)
                speechBuffer.append(contentsOf: samples16k)
                preBuffer.removeAll(keepingCapacity: true)
                silenceSampleCount = 0
                activeSpeechSampleCount = samples16k.count
                events.append(.speechStarted(turnId: turnId))
                events.append(.speechAudio(turnId: turnId, samples: speechBuffer))
            } else {
                preBuffer.append(contentsOf: samples16k)
                if preBuffer.count > Self.preSpeechSamples {
                    preBuffer.removeFirst(preBuffer.count - Self.preSpeechSamples)
                }
            }
        }

        return events
    }

    public func flush() -> [SpeechSegmentEvent] {
        guard activeTurnId != nil else { return [] }
        return finishCurrentTurn(trimTrailingSilence: false)
    }

    private func finishCurrentTurn(trimTrailingSilence: Bool) -> [SpeechSegmentEvent] {
        guard let turnId = activeTurnId else { return [] }
        activeTurnId = nil
        let minSamples = max(1_600, (settings.minSpeechMs * Self.sampleRate) / 1000)

        var segment = speechBuffer
        speechBuffer.removeAll(keepingCapacity: true)
        let spokenCount = activeSpeechSampleCount
        let trailingSilence = silenceSampleCount
        activeSpeechSampleCount = 0
        silenceSampleCount = 0

        if trimTrailingSilence && trailingSilence > 3_200 && segment.count > trailingSilence {
            let keepSilence = 2_400
            let trimCount = max(0, trailingSilence - keepSilence)
            if trimCount > 0 && trimCount < segment.count {
                segment.removeLast(trimCount)
            }
        }

        guard spokenCount >= minSamples, segment.count >= minSamples else {
            return [.turnDiscarded(turnId: turnId)]
        }
        let duration = Double(segment.count) / Double(Self.sampleRate)
        return [.turnCompleted(turnId: turnId, samples: segment, durationSeconds: duration)]
    }

    private func splitCurrentTurnAtQuietestHop() -> [SpeechSegmentEvent] {
        guard let turnId = activeTurnId else { return [] }
        let hopSize = 2_560
        let searchWindow = min(speechBuffer.count / 2, 48_000)
        let searchStart = max(0, speechBuffer.count - searchWindow)

        var bestSplitIndex = speechBuffer.count
        var lowestEnergy = Float.greatestFiniteMagnitude
        var cursor = searchStart
        while cursor + hopSize <= speechBuffer.count {
            var rms: Float = 0
            speechBuffer.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    vDSP_rmsqv(base.advanced(by: cursor), 1, &rms, vDSP_Length(hopSize))
                }
            }
            if rms < lowestEnergy {
                lowestEnergy = rms
                bestSplitIndex = cursor + hopSize / 2
            }
            cursor += hopSize / 2
        }

        let head = Array(speechBuffer[0..<bestSplitIndex])
        let tail = bestSplitIndex < speechBuffer.count ? Array(speechBuffer[bestSplitIndex...]) : []
        let headDuration = Double(head.count) / Double(Self.sampleRate)

        let newId = nextTurnId
        nextTurnId += 1
        activeTurnId = newId
        speechBuffer = tail
        activeSpeechSampleCount = tail.count
        silenceSampleCount = 0

        var events: [SpeechSegmentEvent] = [
            .turnCompleted(turnId: turnId, samples: head, durationSeconds: headDuration),
            .speechStarted(turnId: newId)
        ]
        if !tail.isEmpty {
            events.append(.speechAudio(turnId: newId, samples: tail))
        }
        return events
    }
}
