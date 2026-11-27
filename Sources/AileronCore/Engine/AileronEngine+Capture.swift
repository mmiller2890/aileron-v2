import Foundation

extension AileronEngine {
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
        transcriptionContinuation?.finish()
        transcriptionContinuation = nil
        activeTap?.stop()
        activeTap = nil
        telemetry.isCapturing = false
        telemetry.isSpeechActive = false
        telemetry.rmsLevel = 0
        telemetry.peakLevel = 0
        livePartialText = ""
        livePartialSpeaker = nil
        liveTextBusy = false
        liveSpeakerBusy = false
        if let reason {
            bannerNotice = reason
        }
    }

    private func runCaptureLoop() async {
        let preferredUID = settings.outputDeviceId == "default" ? nil : settings.outputDeviceId
        let tap: SystemAudioTap
        do {
            tap = try SystemAudioTap(preferredOutputUID: preferredUID)
            permissions.systemAudio = .granted
            DiagnosticsLog.shared.record(category: "audio", message: "Started system audio tap on \(tap.boundDeviceName) at \(Int(tap.currentSampleRate)) Hz")
        } catch {
            permissions.systemAudio = .denied
            DiagnosticsLog.shared.record(category: "audio", message: "System audio tap failed: \(error.localizedDescription)")
            stopListening(reason: EngineNotice(
                level: .error,
                message: error.localizedDescription,
                permissionAction: .systemAudio
            ))
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

        let (turnStream, turnContinuation) = AsyncStream.makeStream(of: CompletedTurnJob.self)
        transcriptionContinuation = turnContinuation
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            for await job in turnStream {
                guard let self else { break }
                await self.processCompletedTurnJob(job)
            }
        }

        let preprocessor = AudioPreprocessor(noiseGateThreshold: settings.vad.noiseGateThreshold)
        let segmenter = SpeechSegmenter(settings: settings.vad)
        var rawScratch: [Float] = []
        var vadBuffer: [Float] = []
        var vadCursor = 0
        var liveTextBatch: [Float] = []
        var liveSpeakerBatch: [Float] = []
        var lastDeviceCheck = Date()
        var currentTap = tap

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
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
                let raw16k = preprocessor.resampleTo16k(rawScratch, inputSampleRate: rate)
                let levels = AudioPreprocessor.measureLevels(raw16k)
                telemetry.rmsLevel = levels.rms
                telemetry.peakLevel = levels.peak
                if levels.rms > 0.002 {
                    telemetry.lastAudibleAt = Date()
                }

                vadBuffer.append(contentsOf: raw16k)
                while vadBuffer.count - vadCursor >= SpeechSegmenter.frameSamples {
                    let end = vadCursor + SpeechSegmenter.frameSamples
                    let frame = Array(vadBuffer[vadCursor..<end])
                    vadCursor = end

                    let prob = await speechEngine.vadProbability(samples512: frame)
                    let events = segmenter.process(samples16k: frame, neuralProbability: prob)
                    telemetry.isSpeechActive = segmenter.isInSpeech

                    for event in events {
                        handleSegmentEvent(
                            event,
                            liveTextBatch: &liveTextBatch,
                            liveSpeakerBatch: &liveSpeakerBatch
                        )
                    }
                }
                if vadCursor >= 8_192 || (vadCursor > 0 && vadCursor == vadBuffer.count) {
                    vadBuffer.removeFirst(vadCursor)
                    vadCursor = 0
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
                    handleSegmentEvent(event, liveTextBatch: &liveTextBatch, liveSpeakerBatch: &liveSpeakerBatch)
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
            handleSegmentEvent(event, liveTextBatch: &liveTextBatch, liveSpeakerBatch: &liveSpeakerBatch)
        }
        transcriptionContinuation?.finish()
        transcriptionContinuation = nil
        currentTap.stop()
        activeTap = nil
    }

    private func handleSegmentEvent(
        _ event: SpeechSegmentEvent,
        liveTextBatch: inout [Float],
        liveSpeakerBatch: inout [Float]
    ) {
        switch event {
        case .speechStarted:
            liveTextBatch.removeAll(keepingCapacity: true)
            liveSpeakerBatch.removeAll(keepingCapacity: true)
            livePartialText = ""
            livePartialSpeaker = nil
            let engine = speechEngine
            Task {
                await engine.resetLiveText()
            }

        case .speechAudio(_, let samples):
            if settings.enableLiveText && speechStatus.liveTextReady {
                liveTextBatch.append(contentsOf: samples)
                if liveTextBatch.count >= settings.streamingLatency.batchSamples16k && !liveTextBusy {
                    let batch = liveTextBatch
                    liveTextBatch.removeAll(keepingCapacity: true)
                    liveTextBusy = true
                    let engine = speechEngine
                    Task { [weak self] in
                        let partial = try? await engine.feedLiveText(samples16k: batch)
                        guard let self else { return }
                        self.liveTextBusy = false
                        if self.telemetry.isSpeechActive, let partial, !partial.isEmpty {
                            self.livePartialText = partial
                        }
                    }
                }
            }
            if settings.enableSpeakerLabels && speechStatus.speakerLabelsReady {
                liveSpeakerBatch.append(contentsOf: samples)
                if liveSpeakerBatch.count >= 5_120 && !liveSpeakerBusy {
                    let batch = liveSpeakerBatch
                    liveSpeakerBatch.removeAll(keepingCapacity: true)
                    liveSpeakerBusy = true
                    let engine = speechEngine
                    Task { [weak self] in
                        let speaker = try? await engine.feedLiveSpeakers(samples16k: batch)
                        guard let self else { return }
                        self.liveSpeakerBusy = false
                        if self.telemetry.isSpeechActive, let speaker {
                            self.livePartialSpeaker = self.currentSession.displaySpeaker(for: speaker) ?? speaker
                        }
                    }
                }
            }

        case .turnDiscarded:
            livePartialText = ""
            livePartialSpeaker = nil
            liveTextBatch.removeAll(keepingCapacity: true)
            liveSpeakerBatch.removeAll(keepingCapacity: true)
            let engine = speechEngine
            Task {
                _ = try? await engine.endLiveSpeakerTurn()
            }

        case .turnCompleted(_, let samples, let duration):
            let trailingSpeakers = liveSpeakerBatch
            livePartialText = ""
            livePartialSpeaker = nil
            liveTextBatch.removeAll(keepingCapacity: true)
            liveSpeakerBatch.removeAll(keepingCapacity: true)
            pendingTranscriptionCount += 1
            isTranscribing = true
            transcriptionContinuation?.yield(CompletedTurnJob(
                samples16k: samples,
                duration: duration,
                trailingSpeakerSamples: trailingSpeakers
            ))
        }
    }

    private func processCompletedTurnJob(_ job: CompletedTurnJob) async {
        defer {
            pendingTranscriptionCount = max(0, pendingTranscriptionCount - 1)
            isTranscribing = pendingTranscriptionCount > 0
        }

        var finalSpeaker: String?
        if settings.enableSpeakerLabels && speechStatus.speakerLabelsReady {
            if !job.trailingSpeakerSamples.isEmpty {
                _ = try? await speechEngine.feedLiveSpeakers(samples16k: job.trailingSpeakerSamples)
            }
            finalSpeaker = try? await speechEngine.endLiveSpeakerTurn()
        }

        do {
            let prepared = AudioPreprocessor.prepareForTranscription(
                job.samples16k,
                noiseGateThreshold: settings.vad.noiseGateThreshold
            )
            let outcome = try await speechEngine.transcribe(samples16k: prepared)
            telemetry.lastRtfx = outcome.rtfx
            telemetry.lastTranscribeMs = Int(outcome.processingSeconds * 1000)
            commitTranscribedTurn(
                text: outcome.text,
                confidence: outcome.confidence,
                duration: job.duration,
                speaker: finalSpeaker
            )
        } catch {
            DiagnosticsLog.shared.record(category: "speech", message: "Transcription failed: \(error.localizedDescription)")
            bannerNotice = EngineNotice(level: .error, message: "Transcription failed: \(error.localizedDescription)")
        }
    }

    internal func commitTranscribedTurn(
        text rawText: String,
        confidence: Float = 1.0,
        duration: Double = 1.0,
        speaker: String? = nil
    ) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if settings.filterBackchannels && BackchannelFilter.isBackchannel(text) {
            return
        }

        let isQuestion = QuestionGate.isLikelyQuestion(text)
        let turn = TranscriptTurn(
            sequence: currentSession.turns.count + 1,
            text: text,
            speaker: speaker,
            isQuestion: isQuestion,
            confidence: confidence,
            durationSeconds: duration,
            source: .system
        )
        currentSession.turns.append(turn)
        currentSession.updatedAt = Date()
        if currentSession.turns.count == 1 && currentSession.title.hasPrefix("Session ") {
            currentSession.title = Self.deriveTitle(from: text)
        }
        persistTurnIncrementally(turn)
        DiagnosticsLog.shared.record(
            category: "speech",
            message: "Turn #\(turn.sequence) committed (\(Int(duration * 1000)) ms, question=\(isQuestion))"
        )

        if settings.autoAnswerQuestions && isQuestion {
            if isStreamingAI {
                queuedAutoPrompt = text
            } else {
                ask(text, usePendingScreenshot: false, isCapturedSpeech: true, triggeredAutomatically: true)
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
                    let prepared = AudioPreprocessor.prepareForTranscription(
                        recordedSamples,
                        noiseGateThreshold: settings.vad.noiseGateThreshold
                    )
                    if ready, let outcome = try? await speechEngine.transcribe(samples16k: prepared) {
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
                persistTurnIncrementally(turn)
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
                let preferredMic = self.settings.inputDeviceId == "default" ? nil : self.settings.inputDeviceId
                do {
                    try await self.micCapture.start(preferredInputUID: preferredMic)
                    self.permissions.microphone = .granted
                    self.isRecordingMic = true
                    DiagnosticsLog.shared.record(category: "mic", message: "Started live streaming mic dictation at \(Int(self.micCapture.sampleRate)) Hz")
                } catch {
                    let isDenied = (error as? MicCaptureError).map {
                        if case .permissionDenied = $0 { return true }
                        return false
                    } ?? false
                    if isDenied {
                        self.permissions.microphone = .denied
                    }
                    DiagnosticsLog.shared.record(category: "mic", message: "Mic start failed: \(error.localizedDescription)")
                    self.bannerNotice = EngineNotice(
                        level: .error,
                        message: error.localizedDescription,
                        permissionAction: isDenied ? .microphone : nil
                    )
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
}
