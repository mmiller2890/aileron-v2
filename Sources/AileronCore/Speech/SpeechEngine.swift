import AVFoundation
import FluidAudio
import Foundation

public struct TranscriptionOutcome: Sendable {
    public let text: String
    public let confidence: Float
    public let durationSeconds: Double
    public let processingSeconds: Double
    public let rtfx: Float
}

public enum SpeechEngineError: LocalizedError {
    case asrNotInitialized
    case audioBufferCreationFailed

    public var errorDescription: String? {
        switch self {
        case .asrNotInitialized:
            return "On-device Parakeet speech model is not loaded yet."
        case .audioBufferCreationFailed:
            return "Could not allocate PCM buffer for streaming transcription."
        }
    }
}

private actor VadSession {
    private var vadManager: VadManager?
    private var vadStreamState: VadStreamState?

    var isReady: Bool { vadManager != nil }

    func initialize(threshold: Float) async throws {
        if vadManager != nil { return }
        let config = VadConfig(defaultThreshold: threshold)
        let manager = try await VadManager(config: config)
        self.vadManager = manager
        self.vadStreamState = await manager.makeStreamState()
    }

    func probability(samples4096: [Float]) async -> Float? {
        guard let manager = vadManager, let state = vadStreamState else { return nil }
        do {
            let result = try await manager.processStreamingChunk(samples4096, state: state)
            self.vadStreamState = result.state
            return result.probability
        } catch {
            return nil
        }
    }

    func reset() async {
        guard let manager = vadManager else { return }
        vadStreamState = await manager.makeStreamState()
    }
}

public actor SpeechEngine {
    private static let liveTurnFlushSamples = 16_640

    private let vadSession = VadSession()
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private var streamingAsrManager: StreamingEouAsrManager?
    private var micStreamingAsrManager: StreamingEouAsrManager?
    private var loadedStreamingLatency: StreamingLatencyPreset?
    private var liveDiarizer: SortformerDiarizer?
    private var liveTurnFinalized = [Int32](repeating: 0, count: 4)
    private var liveTurnTentative = [Int32](repeating: 0, count: 4)

    public init() {}

    public var isAsrReady: Bool { asrManager != nil }
    public var isVadReady: Bool {
        get async { await vadSession.isReady }
    }
    public var isLiveTextReady: Bool { streamingAsrManager != nil }
    public var isMicLiveTextReady: Bool { micStreamingAsrManager != nil }
    public var isLiveSpeakersReady: Bool { liveDiarizer != nil }

    private static func fluidChunkSize(for preset: StreamingLatencyPreset) -> StreamingChunkSize {
        switch preset {
        case .ms160: return .ms160
        case .ms320: return .ms320
        case .ms1280: return .ms1280
        }
    }

    public func initializeAsr(
        onProgress: (@Sendable (ModelLoadPhase, Double, String?) -> Void)? = nil
    ) async throws {
        if asrManager != nil {
            onProgress?(.ready, 1.0, nil)
            return
        }
        let handler: ProgressHandler? = onProgress.map { callback in
            let sendableHandler: ProgressHandler = { @Sendable progress in
                switch progress.phase {
                case .listing:
                    callback(.listing, progress.fractionCompleted, "Preparing model manifest")
                case .downloading:
                    callback(.downloading, progress.fractionCompleted, "Downloading Parakeet TDT v3")
                case .compiling(let name):
                    callback(.compiling, progress.fractionCompleted, "Compiling \(name)")
                }
            }
            return sendableHandler
        }
        let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: handler)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.asrModels = models
        self.asrManager = manager
        onProgress?(.ready, 1.0, nil)
    }

    public nonisolated func initializeVad(threshold: Float = 0.5) async throws {
        try await vadSession.initialize(threshold: threshold)
    }

    public func initializeLiveText(
        latency: StreamingLatencyPreset = .ms320,
        onProgress: (@Sendable (ModelLoadPhase, Double, String?) -> Void)? = nil
    ) async throws {
        if streamingAsrManager != nil && loadedStreamingLatency == latency { return }
        let handler: ProgressHandler? = onProgress.map { callback in
            let sendableHandler: ProgressHandler = { @Sendable progress in
                switch progress.phase {
                case .listing:
                    callback(.listing, progress.fractionCompleted, "Preparing live text model (\(latency.displayName))")
                case .downloading:
                    callback(.downloading, progress.fractionCompleted, "Downloading streaming ASR (\(latency.displayName))")
                case .compiling(let name):
                    callback(.compiling, progress.fractionCompleted, "Compiling \(name)")
                }
            }
            return sendableHandler
        }
        let manager = StreamingEouAsrManager(chunkSize: Self.fluidChunkSize(for: latency))
        try await manager.loadModels(to: nil, configuration: nil, progressHandler: handler)
        self.streamingAsrManager = manager
        if loadedStreamingLatency != latency {
            self.micStreamingAsrManager = nil
        }
        self.loadedStreamingLatency = latency
    }

    public func initializeMicLiveText(
        latency: StreamingLatencyPreset = .ms320,
        onProgress: (@Sendable (ModelLoadPhase, Double, String?) -> Void)? = nil
    ) async throws {
        if micStreamingAsrManager != nil && loadedStreamingLatency == latency { return }
        let handler: ProgressHandler? = onProgress.map { callback in
            let sendableHandler: ProgressHandler = { @Sendable progress in
                switch progress.phase {
                case .listing:
                    callback(.listing, progress.fractionCompleted, "Preparing mic streaming (\(latency.displayName))")
                case .downloading:
                    callback(.downloading, progress.fractionCompleted, "Downloading streaming ASR (\(latency.displayName))")
                case .compiling(let name):
                    callback(.compiling, progress.fractionCompleted, "Compiling \(name)")
                }
            }
            return sendableHandler
        }
        let manager = StreamingEouAsrManager(chunkSize: Self.fluidChunkSize(for: latency))
        try await manager.loadModels(to: nil, configuration: nil, progressHandler: handler)
        self.micStreamingAsrManager = manager
        if loadedStreamingLatency != latency {
            self.streamingAsrManager = nil
        }
        self.loadedStreamingLatency = latency
    }

    public func setStreamingLatency(_ latency: StreamingLatencyPreset) {
        guard loadedStreamingLatency != latency else { return }
        streamingAsrManager = nil
        micStreamingAsrManager = nil
        loadedStreamingLatency = nil
    }

    public func initializeLiveSpeakers(
        onProgress: (@Sendable (ModelLoadPhase, Double, String?) -> Void)? = nil
    ) async throws {
        if liveDiarizer != nil { return }
        let handler: ProgressHandler? = onProgress.map { callback in
            let sendableHandler: ProgressHandler = { @Sendable progress in
                switch progress.phase {
                case .listing:
                    callback(.listing, progress.fractionCompleted, "Preparing speaker model")
                case .downloading:
                    callback(.downloading, progress.fractionCompleted, "Downloading Sortformer")
                case .compiling(let name):
                    callback(.compiling, progress.fractionCompleted, "Compiling \(name)")
                }
            }
            return sendableHandler
        }
        let models = try await SortformerModels.loadFromHuggingFace(config: .default, progressHandler: handler)
        let diarizer = SortformerDiarizer(config: .default)
        diarizer.initialize(models: models)
        self.liveDiarizer = diarizer
    }

    public func transcribe(samples16k: [Float]) async throws -> TranscriptionOutcome {
        guard let manager = asrManager else {
            throw SpeechEngineError.asrNotInitialized
        }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(
            samples16k,
            decoderState: &decoderState,
            language: .english
        )
        return TranscriptionOutcome(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: result.confidence,
            durationSeconds: result.duration,
            processingSeconds: result.processingTime,
            rtfx: result.rtfx
        )
    }

    public nonisolated func vadProbability(samples4096: [Float]) async -> Float? {
        await vadSession.probability(samples4096: samples4096)
    }

    public nonisolated func resetVad() async {
        await vadSession.reset()
    }

    public func feedLiveText(samples16k: [Float]) async throws -> String {
        guard let manager = streamingAsrManager else { return "" }
        return try await feedStreamingManager(manager, samples16k: samples16k)
    }

    public func resetLiveText() async {
        guard let manager = streamingAsrManager else { return }
        await manager.reset()
    }

    public func feedMicLiveText(samples16k: [Float]) async throws -> String {
        guard let manager = micStreamingAsrManager else { return "" }
        return try await feedStreamingManager(manager, samples16k: samples16k)
    }

    public func resetMicLiveText() async {
        guard let manager = micStreamingAsrManager else { return }
        await manager.reset()
    }

    private func feedStreamingManager(_ manager: StreamingEouAsrManager, samples16k: [Float]) async throws -> String {
        if !samples16k.isEmpty {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples16k.count)
            ),
            let channel = buffer.floatChannelData else {
                throw SpeechEngineError.audioBufferCreationFailed
            }
            buffer.frameLength = AVAudioFrameCount(samples16k.count)
            samples16k.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel[0].update(from: base, count: samples16k.count)
                }
            }
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        }
        return await manager.getPartialTranscript()
    }

    public func resetLiveSpeakers() {
        liveDiarizer?.reset()
        liveTurnFinalized = [Int32](repeating: 0, count: 4)
        liveTurnTentative = [Int32](repeating: 0, count: 4)
    }

    public func feedLiveSpeakers(samples16k: [Float]) throws -> String? {
        guard !samples16k.isEmpty else { return nil }
        try ingestSpeakers(samples16k)
        let combined = zip(liveTurnFinalized, liveTurnTentative).map { $0 + $1 }
        return DominantSpeakerSelector.selectSpeaker(from: combined)
    }

    public func endLiveSpeakerTurn() throws -> String? {
        guard liveDiarizer != nil else { return nil }
        try ingestSpeakers([Float](repeating: 0, count: Self.liveTurnFlushSamples))
        let counts = liveTurnFinalized
        liveTurnFinalized = [Int32](repeating: 0, count: 4)
        liveTurnTentative = [Int32](repeating: 0, count: 4)
        return DominantSpeakerSelector.selectSpeaker(from: counts)
    }

    private func ingestSpeakers(_ samples: [Float]) throws {
        guard let diarizer = liveDiarizer else { return }
        let speakers = min(diarizer.numSpeakers ?? 4, 4)
        let stride = diarizer.numSpeakers ?? 4
        diarizer.addAudio(samples)
        var iterations = 0
        while iterations < 64, let update = try diarizer.process() {
            iterations += 1
            let chunk = update.chunkResult
            if chunk.finalizedFrameCount == 0 && chunk.tentativeFrameCount == 0 {
                break
            }
            for frame in 0..<chunk.finalizedFrameCount {
                for speaker in 0..<speakers where chunk.finalizedPredictions[frame * stride + speaker] >= 0.5 {
                    liveTurnFinalized[speaker] += 1
                }
            }
            var tentative = [Int32](repeating: 0, count: 4)
            for frame in 0..<chunk.tentativeFrameCount {
                for speaker in 0..<speakers where chunk.tentativePredictions[frame * stride + speaker] >= 0.5 {
                    tentative[speaker] += 1
                }
            }
            liveTurnTentative = tentative
        }
    }

    public func unloadOptionalModels() {
        streamingAsrManager = nil
        micStreamingAsrManager = nil
        loadedStreamingLatency = nil
        liveDiarizer = nil
        liveTurnFinalized = [Int32](repeating: 0, count: 4)
        liveTurnTentative = [Int32](repeating: 0, count: 4)
    }
}
