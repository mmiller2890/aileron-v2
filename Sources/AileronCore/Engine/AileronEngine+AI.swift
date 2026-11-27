import Foundation

extension AileronEngine {
    public func captureScreen(analyzeImmediately: Bool = false) {
        Task {
            do {
                let shot = try await ScreenCaptureService.captureActiveDisplay()
                permissions.screenRecording = .granted
                pendingScreenshot = shot
                DiagnosticsLog.shared.record(category: "screen", message: "Captured display \(shot.width)x\(shot.height)")
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
                permissions.screenRecording = .denied
                DiagnosticsLog.shared.record(category: "screen", message: "Screen capture failed: \(error.localizedDescription)")
                bannerNotice = EngineNotice(
                    level: .error,
                    message: error.localizedDescription,
                    permissionAction: .screenRecording
                )
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
        queuedAutoPrompt = nil
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

        if !triggeredAutomatically {
            queuedAutoPrompt = nil
        }
        aiTask?.cancel()
        bannerNotice = nil

        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        let apiKey = resolvedAPIKey(for: provider)
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
            forCapturedSpeech: isCapturedSpeech,
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
        let streamer = aiStreamHandler

        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = streamer(provider, config, apiKey, systemPrompt, messages)
                for try await chunk in stream {
                    if Task.isCancelled || self.streamingExchangeId != exchangeId { break }
                    if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }) {
                        self.currentSession.exchanges[idx].response += chunk
                    }
                }
                if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }) {
                    self.currentSession.exchanges[idx].latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.currentSession.updatedAt = Date()
                    self.persistExchangeIncrementally(self.currentSession.exchanges[idx])
                }

                guard !Task.isCancelled, self.streamingExchangeId == exchangeId else { return }
                self.isStreamingAI = false
                self.streamingExchangeId = nil

                if let nextPrompt = self.queuedAutoPrompt {
                    self.queuedAutoPrompt = nil
                    self.ask(nextPrompt, usePendingScreenshot: false, isCapturedSpeech: true, triggeredAutomatically: true)
                }
            } catch {
                guard self.streamingExchangeId == exchangeId else { return }
                self.isStreamingAI = false
                self.streamingExchangeId = nil
                self.queuedAutoPrompt = nil
                if let idx = self.currentSession.exchanges.firstIndex(where: { $0.id == exchangeId }) {
                    if self.currentSession.exchanges[idx].response.isEmpty {
                        self.currentSession.exchanges[idx].response = "_Error: \(error.localizedDescription)_"
                    }
                    self.persistExchangeIncrementally(self.currentSession.exchanges[idx])
                }
                let logDetail = (error as? AIClientError)?.safeLogSummary ?? "stream_error"
                DiagnosticsLog.shared.record(category: "ai", message: "AI stream failed: \(logDetail)")
                self.bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
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
        let apiKey = resolvedAPIKey(for: provider)
        let (system, user) = PromptComposer.composeSummaryPrompt(session: currentSession)
        let streamer = aiStreamHandler

        Task {
            var accumulated = ""
            do {
                let stream = streamer(provider, config, apiKey, system, [AIChatMessage(role: .user, text: user)])
                for try await chunk in stream {
                    accumulated += chunk
                    currentSession.summary = accumulated
                }
                currentSession.updatedAt = Date()
                persistSessionMetadataIncrementally()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: "Summary failed: \(error.localizedDescription)")
            }
            isGeneratingSummary = false
        }
    }
}
