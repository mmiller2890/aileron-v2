import Foundation
import Observation

public struct EngineNotice: Identifiable, Equatable, Sendable {
    public enum Level: Sendable {
        case info
        case warning
        case error
    }

    public let id = UUID()
    public let level: Level
    public let message: String

    public init(level: Level, message: String) {
        self.level = level
        self.message = message
    }
}

@MainActor
@Observable
public final class AileronEngine {
    public var settings: AppSettings
    public var profiles: [PrepProfile] = []
    public var quickActions: [QuickAction] = QuickAction.defaults
    public var currentSession: SessionRecord
    public var sessionList: [SessionSummaryItem] = []
    public var searchQuery: String = ""

    public var speechStatus = SpeechModelStatus()
    public var telemetry = CaptureTelemetry()
    public var outputDevices: [AudioDeviceInfo] = []
    public var inputDevices: [AudioDeviceInfo] = []
    public var discoveredOllamaModels: [String] = []

    public var livePartialText: String = ""
    public var livePartialSpeaker: String?
    public var liveMicText: String = ""
    public var micRmsLevel: Float = 0
    public var isStreamingAI: Bool = false
    public var streamingExchangeId: UUID?
    public var pendingScreenshot: CapturedScreenshot?
    public var isRecordingMic: Bool = false
    public var isGeneratingSummary: Bool = false
    public var bannerNotice: EngineNotice?

    public let keychain: KeychainStore
    private let speechEngine: SpeechEngine
    private let micCapture = MicCapture()
    private var database: DatabaseStore?
    private var captureTask: Task<Void, Never>?
    private var micStreamTask: Task<Void, Never>?
    private var accumulatedMicSamples16k: [Float] = []
    private var micPreprocessor = AudioPreprocessor()
    private var aiTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var activeTap: SystemAudioTap?

    public var onStealthSettingChanged: ((Bool) -> Void)?
    public var onHUDOpacityChanged: ((Double) -> Void)?
    public var onAppearanceChanged: ((AppearanceSettings) -> Void)?

    public init(
        keychain: KeychainStore = KeychainStore(),
        speechEngine: SpeechEngine = SpeechEngine(),
        databasePath: String? = nil
    ) {
        self.keychain = keychain
        self.speechEngine = speechEngine
        let loadedSettings = SettingsStore.load()
        self.settings = loadedSettings
        self.currentSession = SessionRecord(
            title: Self.defaultSessionTitle(),
            profileId: loadedSettings.activeProfileId
        )

        do {
            self.database = try DatabaseStore(path: databasePath)
        } catch {
            self.bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }

        refreshAudioDevices()
        Task {
            await bootstrapAsync()
        }
    }

    public var activeProfile: PrepProfile? {
        if let id = settings.activeProfileId, let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    public var latestExchange: AIExchange? {
        currentSession.exchanges.last
    }

    public var latestTurn: TranscriptTurn? {
        currentSession.turns.last
    }

    private func bootstrapAsync() async {
        if let database {
            do {
                self.profiles = try await database.loadProfiles()
                if settings.activeProfileId == nil || !profiles.contains(where: { $0.id == settings.activeProfileId }) {
                    settings.activeProfileId = profiles.first?.id
                    currentSession.profileId = settings.activeProfileId
                }
                self.sessionList = try await database.listSessions()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
        await refreshOllamaModels(silent: true)
    }

    public func saveSettings() {
        SettingsStore.save(settings)
        onStealthSettingChanged?(settings.stealthScreenShareProtection)
        onHUDOpacityChanged?(settings.hudOpacity)
        onAppearanceChanged?(settings.appearance)
    }

    public func refreshAudioDevices() {
        outputDevices = AudioDeviceManager.outputDevices()
        inputDevices = AudioDeviceManager.inputDevices()
    }

    public func dismissNotice() {
        bannerNotice = nil
    }

    public func preloadSpeechModels() {
        Task {
            await ensureSpeechModelsLoaded(includeOptional: true)
        }
    }

    public func ensureSpeechModelsLoaded(includeOptional: Bool) async -> Bool {
        if await !speechEngine.isAsrReady {
            speechStatus.asrPhase = .listing
            speechStatus.asrProgress = 0
            speechStatus.asrDetail = "Initializing Parakeet TDT v3"
            speechStatus.lastError = nil

            do {
                try await speechEngine.initializeAsr { [weak self] phase, progress, detail in
                    Task { @MainActor [weak self] in
                        self?.speechStatus.asrPhase = phase
                        self?.speechStatus.asrProgress = progress
                        self?.speechStatus.asrDetail = detail
                    }
                }
                speechStatus.asrPhase = .ready
                speechStatus.asrProgress = 1.0
                speechStatus.asrDetail = "Parakeet TDT v3 Ready"
            } catch {
                speechStatus.asrPhase = .failed
                speechStatus.lastError = error.localizedDescription
                bannerNotice = EngineNotice(level: .error, message: "Speech model load failed: \(error.localizedDescription)")
                return false
            }
        }

        if await !speechEngine.isVadReady {
            do {
                try await speechEngine.initializeVad(threshold: max(0.25, 1.0 - settings.vad.sensitivity + 0.1))
                speechStatus.vadReady = true
            } catch {
                speechStatus.vadReady = false
            }
        }

        if includeOptional {
            let liveTextAlreadyReady = await speechEngine.isLiveTextReady
            if settings.enableLiveText && !liveTextAlreadyReady {
                do {
                    try await speechEngine.initializeLiveText(latency: settings.streamingLatency) { [weak self] _, _, detail in
                        Task { @MainActor [weak self] in
                            self?.speechStatus.asrDetail = detail
                        }
                    }
                    speechStatus.liveTextReady = true
                    speechStatus.asrDetail = "All Speech Models Ready"
                } catch {
                    speechStatus.liveTextReady = false
                }
            }

            let speakersAlreadyReady = await speechEngine.isLiveSpeakersReady
            if settings.enableSpeakerLabels && !speakersAlreadyReady {
                do {
                    try await speechEngine.initializeLiveSpeakers { [weak self] _, _, detail in
                        Task { @MainActor [weak self] in
                            self?.speechStatus.asrDetail = detail
                        }
                    }
                    speechStatus.speakerLabelsReady = true
                    speechStatus.asrDetail = "All Speech Models Ready"
                } catch {
                    speechStatus.speakerLabelsReady = false
                }
            }
        }

        return true
    }

    public func toggleListening() {
        if telemetry.isCapturing {
            stopListening()
        } else {
            startListening()
        }
    }

    public func startListening() {
        guard !telemetry.isCapturing else { return }
        bannerNotice = nil
        telemetry.isCapturing = true
        telemetry.lastAudibleAt = Date()

        captureTask = Task { [weak self] in
            guard let self else { return }
            let ready = await self.ensureSpeechModelsLoaded(includeOptional: true)
            guard ready, !Task.isCancelled else {
                await MainActor.run {
                    self.telemetry.isCapturing = false
                }
                return
            }

            if self.settings.activeProvider == .ollama {
                let ollamaCfg = self.settings.config(for: .ollama)
                Task.detached {
                    await AIClient.warmupOllamaModel(baseURL: ollamaCfg.baseURL, model: ollamaCfg.model)
                }
            }

            await self.runCaptureLoop()
        }
    }

    public func stopListening(reason: EngineNotice? = nil) {
        captureTask?.cancel()
        captureTask = nil
        activeTap?.stop()
        activeTap = nil
        telemetry.isCapturing = false
        telemetry.isSpeechActive = false
        telemetry.rmsLevel = 0
        telemetry.peakLevel = 0
        livePartialText = ""
        livePartialSpeaker = nil
        if let reason {
            bannerNotice = reason
        }
    }

    private func runCaptureLoop() async {
        let preferredUID = settings.outputDeviceId == "default" ? nil : settings.outputDeviceId
        let tap: SystemAudioTap
        do {
            tap = try SystemAudioTap(preferredOutputUID: preferredUID)
        } catch {
            stopListening(reason: EngineNotice(level: .error, message: error.localizedDescription))
            return
        }

        activeTap = tap
        telemetry.activeDeviceName = tap.boundDeviceName
        telemetry.sampleRate = tap.currentSampleRate
        telemetry.droppedSamples = 0
        telemetry.lastAudibleAt = Date()

        await speechEngine.resetVad()
        await speechEngine.resetLiveText()
        await speechEngine.resetLiveSpeakers()

        let preprocessor = AudioPreprocessor(noiseGateThreshold: settings.vad.noiseGateThreshold)
        let segmenter = SpeechSegmenter(settings: settings.vad)
        var rawScratch: [Float] = []
        var vadBuffer: [Float] = []
        var liveTextBatch: [Float] = []
        var liveSpeakerBatch: [Float] = []
        var lastDeviceCheck = Date()
        var currentTap = tap

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { break }

            segmenter.settings = settings.vad
            preprocessor.noiseGateThreshold = settings.vad.noiseGateThreshold

            if settings.outputDeviceId == "default",
               Date().timeIntervalSince(lastDeviceCheck) >= 1.2 {
                lastDeviceCheck = Date()
                if let liveDefault = AudioDeviceManager.defaultOutputUID(),
                   liveDefault != currentTap.boundOutputUID {
                    currentTap.stop()
                    do {
                        let rebound = try SystemAudioTap(preferredOutputUID: nil)
                        currentTap = rebound
                        activeTap = rebound
                        preprocessor.reset()
                        telemetry.activeDeviceName = rebound.boundDeviceName
                        telemetry.sampleRate = rebound.currentSampleRate
                        bannerNotice = EngineNotice(level: .info, message: "Switched capture to \(rebound.boundDeviceName)")
                    } catch {
                        stopListening(reason: EngineNotice(level: .error, message: error.localizedDescription))
                        return
                    }
                }
            }

            let dropped = currentTap.drain(into: &rawScratch)
            if dropped > 0 {
                telemetry.droppedSamples &+= dropped
            }

            let rate = currentTap.currentSampleRate
            telemetry.sampleRate = rate

            if !rawScratch.isEmpty {
                let resampled = preprocessor.resampleTo16k(rawScratch, inputSampleRate: rate)
                let (cleaned, levels) = preprocessor.process(resampled)
                telemetry.rmsLevel = levels.rms
                telemetry.peakLevel = levels.peak
                if levels.rms > 0.002 {
                    telemetry.lastAudibleAt = Date()
                }

                vadBuffer.append(contentsOf: cleaned)
                while vadBuffer.count >= 4096 {
                    let chunk = Array(vadBuffer.prefix(4096))
                    vadBuffer.removeFirst(4096)
                    let prob = await speechEngine.vadProbability(samples4096: chunk)
                    let events = segmenter.process(samples16k: chunk, neuralProbability: prob)
                    telemetry.isSpeechActive = segmenter.isInSpeech

                    for event in events {
                        await handleSegmentEvent(
                            event,
                            liveTextBatch: &liveTextBatch,
                            liveSpeakerBatch: &liveSpeakerBatch
                        )
                    }
                }
            } else {
                telemetry.rmsLevel *= 0.8
                telemetry.peakLevel *= 0.8
            }

            if settings.idleAutoStopMinutes > 0,
               let lastAudible = telemetry.lastAudibleAt,
               Date().timeIntervalSince(lastAudible) >= Double(settings.idleAutoStopMinutes * 60) {
                let flushed = segmenter.flush()
                for event in flushed {
                    await handleSegmentEvent(event, liveTextBatch: &liveTextBatch, liveSpeakerBatch: &liveSpeakerBatch)
                }
                stopListening(reason: EngineNotice(
                    level: .warning,
                    message: "Listening stopped after \(settings.idleAutoStopMinutes) minutes of silence."
                ))
                return
            }
        }

        let tailEvents = segmenter.flush()
        for event in tailEvents {
            await handleSegmentEvent(event, liveTextBatch: &liveTextBatch, liveSpeakerBatch: &liveSpeakerBatch)
        }
        currentTap.stop()
        activeTap = nil
    }

    private func handleSegmentEvent(
        _ event: SpeechSegmentEvent,
        liveTextBatch: inout [Float],
        liveSpeakerBatch: inout [Float]
    ) async {
        switch event {
        case .speechStarted:
            liveTextBatch.removeAll(keepingCapacity: true)
            liveSpeakerBatch.removeAll(keepingCapacity: true)
            livePartialText = ""
            livePartialSpeaker = nil
            await speechEngine.resetLiveText()

        case .speechAudio(_, let samples):
            if settings.enableLiveText && speechStatus.liveTextReady {
                liveTextBatch.append(contentsOf: samples)
                if liveTextBatch.count >= settings.streamingLatency.batchSamples16k {
                    let batch = liveTextBatch
                    liveTextBatch.removeAll(keepingCapacity: true)
                    if let partial = try? await speechEngine.feedLiveText(samples16k: batch), !partial.isEmpty {
                        livePartialText = partial
                    }
                }
            }
            if settings.enableSpeakerLabels && speechStatus.speakerLabelsReady {
                liveSpeakerBatch.append(contentsOf: samples)
                if liveSpeakerBatch.count >= 5_120 {
                    let batch = liveSpeakerBatch
                    liveSpeakerBatch.removeAll(keepingCapacity: true)
                    if let speaker = try? await speechEngine.feedLiveSpeakers(samples16k: batch) {
                        livePartialSpeaker = currentSession.displaySpeaker(for: speaker) ?? speaker
                    }
                }
            }

        case .turnDiscarded:
            livePartialText = ""
            livePartialSpeaker = nil
            liveTextBatch.removeAll(keepingCapacity: true)
            liveSpeakerBatch.removeAll(keepingCapacity: true)
            _ = try? await speechEngine.endLiveSpeakerTurn()

        case .turnCompleted(_, let samples, let duration):
            var finalSpeaker: String?
            if settings.enableSpeakerLabels && speechStatus.speakerLabelsReady {
                if !liveSpeakerBatch.isEmpty {
                    _ = try? await speechEngine.feedLiveSpeakers(samples16k: liveSpeakerBatch)
                    liveSpeakerBatch.removeAll(keepingCapacity: true)
                }
                finalSpeaker = try? await speechEngine.endLiveSpeakerTurn()
            }
            livePartialText = ""
            livePartialSpeaker = nil
            liveTextBatch.removeAll(keepingCapacity: true)

            do {
                let outcome = try await speechEngine.transcribe(samples16k: samples)
                telemetry.lastRtfx = outcome.rtfx
                telemetry.lastTranscribeMs = Int(outcome.processingSeconds * 1000)

                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                if settings.filterBackchannels && BackchannelFilter.isBackchannel(text) {
                    return
                }

                let isQuestion = QuestionGate.isLikelyQuestion(text)
                let turn = TranscriptTurn(
                    sequence: currentSession.turns.count + 1,
                    text: text,
                    speaker: finalSpeaker,
                    isQuestion: isQuestion,
                    confidence: outcome.confidence,
                    durationSeconds: duration,
                    source: .system
                )
                currentSession.turns.append(turn)
                currentSession.updatedAt = Date()
                if currentSession.turns.count == 1 && currentSession.title.hasPrefix("Session ") {
                    currentSession.title = Self.deriveTitle(from: text)
                }
                schedulePersistSession()

                if settings.autoAnswerQuestions && isQuestion {
                    ask(text, usePendingScreenshot: false, isCapturedSpeech: true, triggeredAutomatically: true)
                }
            } catch {
                bannerNotice = EngineNotice(level: .error, message: "Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    public func updateStreamingLatency(_ latency: StreamingLatencyPreset) {
        guard settings.streamingLatency != latency else { return }
        settings.streamingLatency = latency
        saveSettings()
        speechStatus.liveTextReady = false
        Task {
            await speechEngine.setStreamingLatency(latency)
        }
    }

    public func cancelMicDictation() {
        micStreamTask?.cancel()
        micStreamTask = nil
        micCapture.cancel()
        isRecordingMic = false
        liveMicText = ""
        micRmsLevel = 0
        accumulatedMicSamples16k.removeAll(keepingCapacity: false)
    }

    public func toggleMicDictation() {
        if isRecordingMic {
            isRecordingMic = false
            micStreamTask?.cancel()
            micStreamTask = nil

            let tail = micCapture.stopAndDrainRaw()
            if !tail.samples.isEmpty {
                let tail16k = micPreprocessor.resampleTo16k(tail.samples, inputSampleRate: tail.sampleRate)
                accumulatedMicSamples16k.append(contentsOf: tail16k)
            }
            let recordedSamples = accumulatedMicSamples16k
            accumulatedMicSamples16k.removeAll(keepingCapacity: false)
            let fallbackText = liveMicText.trimmingCharacters(in: .whitespacesAndNewlines)
            liveMicText = ""
            micRmsLevel = 0

            guard recordedSamples.count > 2_400 || !fallbackText.isEmpty else { return }
            Task {
                var finalSpoken = fallbackText
                var finalConfidence: Float = 1.0
                var finalDuration = Double(recordedSamples.count) / 16_000.0

                if recordedSamples.count > 2_400 {
                    let ready = await ensureSpeechModelsLoaded(includeOptional: false)
                    if ready, let outcome = try? await speechEngine.transcribe(samples16k: recordedSamples) {
                        let refined = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !refined.isEmpty {
                            finalSpoken = refined
                            finalConfidence = outcome.confidence
                            finalDuration = outcome.durationSeconds
                        }
                    }
                }

                guard !finalSpoken.isEmpty else { return }
                let turn = TranscriptTurn(
                    sequence: currentSession.turns.count + 1,
                    text: finalSpoken,
                    speaker: "You",
                    isQuestion: true,
                    confidence: finalConfidence,
                    durationSeconds: finalDuration,
                    source: .microphone
                )
                currentSession.turns.append(turn)
                currentSession.updatedAt = Date()
                schedulePersistSession()
                ask(finalSpoken, usePendingScreenshot: true, isCapturedSpeech: false)
            }
        } else {
            bannerNotice = nil
            liveMicText = ""
            micRmsLevel = 0
            accumulatedMicSamples16k.removeAll(keepingCapacity: true)
            micPreprocessor.reset()

            micStreamTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.micCapture.start()
                    self.isRecordingMic = true
                } catch {
                    self.bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
                    return
                }

                let latency = self.settings.streamingLatency
                if await !self.speechEngine.isMicLiveTextReady {
                    do {
                        try await self.speechEngine.initializeMicLiveText(latency: latency) { [weak self] phase, progress, detail in
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                if !self.speechStatus.isAsrReady {
                                    self.speechStatus.asrPhase = phase
                                    self.speechStatus.asrProgress = progress
                                }
                                self.speechStatus.asrDetail = detail
                            }
                        }
                        self.speechStatus.liveTextReady = true
                        self.speechStatus.asrDetail = "Streaming ASR Ready"
                    } catch {
                        self.bannerNotice = EngineNotice(level: .warning, message: "Live mic preview unavailable — final transcript will appear on stop.")
                    }
                }

                await self.speechEngine.resetMicLiveText()
                var rawScratch: [Float] = []
                var streamBatch: [Float] = []

                while !Task.isCancelled && self.isRecordingMic {
                    try? await Task.sleep(for: .milliseconds(40))
                    if Task.isCancelled || !self.isRecordingMic { break }

                    _ = self.micCapture.drainRaw(into: &rawScratch)
                    guard !rawScratch.isEmpty else {
                        self.micRmsLevel *= 0.75
                        continue
                    }

                    let resampled = self.micPreprocessor.resampleTo16k(rawScratch, inputSampleRate: self.micCapture.sampleRate)
                    let levels = AudioPreprocessor.measureLevels(resampled)
                    self.micRmsLevel = levels.rms
                    self.accumulatedMicSamples16k.append(contentsOf: resampled)
                    streamBatch.append(contentsOf: resampled)

                    let batchTarget = self.settings.streamingLatency.batchSamples16k
                    if streamBatch.count >= batchTarget {
                        let chunk = streamBatch
                        streamBatch.removeAll(keepingCapacity: true)
                        if let partial = try? await self.speechEngine.feedMicLiveText(samples16k: chunk) {
                            let cleaned = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty {
                                self.liveMicText = cleaned
                            }
                        }
                    }
                }
            }
        }
    }

    public func captureScreen(analyzeImmediately: Bool = false) {
        Task {
            do {
                let shot = try await ScreenCaptureService.captureActiveDisplay()
                pendingScreenshot = shot
                if analyzeImmediately {
                    ask(
                        "Analyze what is on my screen right now and give me the clearest, highest-value answer or next step.",
                        usePendingScreenshot: true,
                        isCapturedSpeech: false
                    )
                } else {
                    bannerNotice = EngineNotice(level: .info, message: "Screen captured (\(shot.width)x\(shot.height)) — attached to your next question.")
                }
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func clearPendingScreenshot() {
        pendingScreenshot = nil
    }

    public func answerLastUtterance() {
        guard let last = currentSession.turns.last else {
            bannerNotice = EngineNotice(level: .warning, message: "No captured speech yet to answer.")
            return
        }
        ask(last.text, usePendingScreenshot: true, isCapturedSpeech: true)
    }

    public func answerTurn(_ turn: TranscriptTurn) {
        ask(turn.text, usePendingScreenshot: true, isCapturedSpeech: true)
    }

    public func runQuickAction(_ action: QuickAction) {
        ask(action.instruction, usePendingScreenshot: true, isCapturedSpeech: false)
    }

    public func cancelAIResponse() {
        aiTask?.cancel()
        aiTask = nil
        isStreamingAI = false
        streamingExchangeId = nil
    }

    public func ask(
        _ prompt: String,
        usePendingScreenshot: Bool = true,
        isCapturedSpeech: Bool = false,
        triggeredAutomatically: Bool = false
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        aiTask?.cancel()
        bannerNotice = nil

        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        let apiKey = keychain.secret(for: provider.rawValue)
        let screenshot = usePendingScreenshot ? pendingScreenshot : nil
        if usePendingScreenshot {
            pendingScreenshot = nil
        }

        let systemPrompt = PromptComposer.composeSystemPrompt(
            profile: activeProfile,
            forCapturedSpeech: isCapturedSpeech
        )
        let messages = PromptComposer.composeMessages(
            userPrompt: trimmed,
            screenshotJPEG: screenshot?.jpegData,
            recentTurns: currentSession.turns,
            recentExchanges: currentSession.exchanges,
            speakerAliases: currentSession.speakerAliases
        )

        let exchange = AIExchange(
            prompt: trimmed,
            response: "",
            providerName: provider.displayName,
            modelName: config.model,
            hasScreenshot: screenshot != nil,
            triggeredAutomatically: triggeredAutomatically
        )
        currentSession.exchanges.append(exchange)
        currentSession.updatedAt = Date()
        if currentSession.exchanges.count == 1 && currentSession.turns.isEmpty && currentSession.title.hasPrefix("Session ") {
            currentSession.title = Self.deriveTitle(from: trimmed)
        }

        let exchangeId = exchange.id
        isStreamingAI = true
        streamingExchangeId = exchangeId
        let startedAt = Date()

        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = AIClient.streamCompletion(
                    provider: provider,
                    config: config,
                    apiKey: apiKey,
                    systemPrompt: systemPrompt,
                    messages: messages
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }) {
                        self.currentSession.exchanges[idx].response += chunk
                    }
                }
                if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }) {
                    self.currentSession.exchanges[idx].latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                }
                self.isStreamingAI = false
                self.streamingExchangeId = nil
                self.currentSession.updatedAt = Date()
                self.schedulePersistSession()
            } catch {
                self.isStreamingAI = false
                self.streamingExchangeId = nil
                if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }),
                   self.currentSession.exchanges[idx].response.isEmpty {
                    self.currentSession.exchanges[idx].response = "_Error: \(error.localizedDescription)_"
                }
                self.bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
                self.schedulePersistSession()
            }
        }
    }

    public func generateSummaryForCurrentSession() {
        guard !isGeneratingSummary else { return }
        guard !currentSession.turns.isEmpty || !currentSession.exchanges.isEmpty else {
            bannerNotice = EngineNotice(level: .warning, message: "Capture speech or ask a question before summarizing.")
            return
        }
        isGeneratingSummary = true
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        let apiKey = keychain.secret(for: provider.rawValue)
        let (system, user) = PromptComposer.composeSummaryPrompt(session: currentSession)

        Task {
            var accumulated = ""
            do {
                let stream = AIClient.streamCompletion(
                    provider: provider,
                    config: config,
                    apiKey: apiKey,
                    systemPrompt: system,
                    messages: [AIChatMessage(role: .user, text: user)]
                )
                for try await chunk in stream {
                    accumulated += chunk
                    currentSession.summary = accumulated
                }
                currentSession.updatedAt = Date()
                schedulePersistSession()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: "Summary failed: \(error.localizedDescription)")
            }
            isGeneratingSummary = false
        }
    }

    public func startNewSession() {
        cancelAIResponse()
        let hadContent = !currentSession.turns.isEmpty || !currentSession.exchanges.isEmpty
        if hadContent {
            persistSessionNow()
        }
        currentSession = SessionRecord(
            title: Self.defaultSessionTitle(),
            profileId: settings.activeProfileId
        )
        livePartialText = ""
        livePartialSpeaker = nil
        pendingScreenshot = nil
    }

    public func loadSession(id: UUID) {
        Task {
            guard let database else { return }
            do {
                if let loaded = try await database.loadSession(id: id) {
                    cancelAIResponse()
                    currentSession = loaded
                }
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func deleteSession(id: UUID) {
        Task {
            guard let database else { return }
            do {
                try await database.deleteSession(id: id)
                if currentSession.id == id {
                    currentSession = SessionRecord(
                        title: Self.defaultSessionTitle(),
                        profileId: settings.activeProfileId
                    )
                }
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func renameCurrentSession(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentSession.title = trimmed
        currentSession.updatedAt = Date()
        schedulePersistSession()
    }

    public func renameSpeaker(rawSpeaker: String, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentSession.speakerAliases.removeValue(forKey: rawSpeaker)
        } else {
            currentSession.speakerAliases[rawSpeaker] = trimmed
        }
        currentSession.updatedAt = Date()
        schedulePersistSession()
    }

    public func searchSessions(_ query: String) {
        searchQuery = query
        Task {
            await reloadSessionList()
        }
    }

    public func reloadSessionList() async {
        guard let database else { return }
        do {
            sessionList = try await database.listSessions(searchQuery: searchQuery)
        } catch {
            bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }
    }

    public func exportCurrentSessionMarkdown() -> String {
        DatabaseStore.exportMarkdown(session: currentSession)
    }

    public func saveProfile(_ profile: PrepProfile) {
        var updated = profile
        updated.updatedAt = Date()
        if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[idx] = updated
        } else {
            profiles.insert(updated, at: 0)
        }
        Task {
            try? await database?.saveProfile(updated)
        }
    }

    public func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if settings.activeProfileId == id {
            settings.activeProfileId = profiles.first?.id
            saveSettings()
        }
        Task {
            try? await database?.deleteProfile(id: id)
        }
    }

    public func selectProfile(id: UUID) {
        settings.activeProfileId = id
        currentSession.profileId = id
        saveSettings()
    }

    public func refreshOllamaModels(silent: Bool = false) async {
        let cfg = settings.config(for: .ollama)
        do {
            let models = try await AIClient.discoverOllamaModels(baseURL: cfg.baseURL)
            discoveredOllamaModels = models
            if !models.isEmpty && !models.contains(cfg.model) {
                var updated = cfg
                updated.model = models[0]
                settings.setConfig(updated, for: .ollama)
                saveSettings()
            }
        } catch {
            if !silent {
                bannerNotice = EngineNotice(level: .warning, message: "Could not reach Ollama at \(cfg.baseURL).")
            }
        }
    }

    public func saveAPIKey(_ key: String, for provider: AIProviderKind) {
        do {
            try keychain.setSecret(key, for: provider.rawValue)
            bannerNotice = EngineNotice(
                level: .info,
                message: key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Removed API key for \(provider.displayName) from Keychain."
                    : "Saved API key for \(provider.displayName) in macOS Keychain."
            )
        } catch {
            bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }
    }

    public func hasAPIKey(for provider: AIProviderKind) -> Bool {
        keychain.hasSecret(for: provider.rawValue)
    }

    public func testActiveProvider() async -> Result<Int, Error> {
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        let key = keychain.secret(for: provider.rawValue)
        do {
            let latency = try await AIClient.testConnection(provider: provider, config: config, apiKey: key)
            return .success(latency)
        } catch {
            return .failure(error)
        }
    }

    private func schedulePersistSession() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistSessionNow()
        }
    }

    public func persistSessionNow() {
        let snapshot = currentSession
        guard !snapshot.turns.isEmpty || !snapshot.exchanges.isEmpty || snapshot.summary != nil else { return }
        Task {
            guard let database else { return }
            do {
                try await database.saveSession(snapshot)
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    private static func defaultSessionTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return "Session \(formatter.string(from: Date()))"
    }

    private static func deriveTitle(from text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 48 { return cleaned }
        return String(cleaned.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
