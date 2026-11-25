import XCTest
@testable import AileronCore

final class AileronCoreTests: XCTestCase {
    func testRingBufferWriteDrainAndWrap() {
        let rb = AudioRingBuffer(capacity: 1024)
        let first = [Float](repeating: 0.25, count: 600)
        first.withUnsafeBufferPointer { rb.write($0) }

        var drained: [Float] = []
        let dropped1 = rb.drain(into: &drained)
        XCTAssertEqual(dropped1, 0)
        XCTAssertEqual(drained.count, 600)
        XCTAssertEqual(drained.first, 0.25)

        let second = [Float](repeating: 0.5, count: 900)
        second.withUnsafeBufferPointer { rb.write($0) }
        let overflow = [Float](repeating: 0.75, count: 300)
        overflow.withUnsafeBufferPointer { rb.write($0) }

        let dropped2 = rb.drain(into: &drained)
        XCTAssertEqual(drained.count, 1024)
        XCTAssertEqual(dropped2, 176)
        XCTAssertEqual(drained[0], 0.5)
        XCTAssertEqual(drained[899], 0.5)
        XCTAssertEqual(drained[900], 0.75)
    }

    func testRingBufferStereoDownmix() {
        let rb = AudioRingBuffer(capacity: 1024)
        let stereo: [Float] = [0.2, 0.6, -0.4, 0.4, 1.0, 0.0]
        stereo.withUnsafeBufferPointer { rb.writeMonoDownmix(interleaved: $0, channels: 2) }
        var out: [Float] = []
        _ = rb.drain(into: &out)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0], 0.4, accuracy: 1e-5)
        XCTAssertEqual(out[1], 0.0, accuracy: 1e-5)
        XCTAssertEqual(out[2], 0.5, accuracy: 1e-5)
    }

    func testSoftClipContinuityAndBounds() {
        XCTAssertEqual(AudioPreprocessor.softClip(0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(AudioPreprocessor.softClip(-0.5), -0.5, accuracy: 1e-6)
        XCTAssertEqual(AudioPreprocessor.softClip(0.7), 0.7, accuracy: 1e-6)

        let justAbove = AudioPreprocessor.softClip(0.7001)
        XCTAssertGreaterThan(justAbove, 0.7)
        XCTAssertLessThan(justAbove, 0.701)

        let huge = AudioPreprocessor.softClip(10.0)
        XCTAssertLessThanOrEqual(huge, 1.0)
        XCTAssertGreaterThan(huge, 0.99)

        let hugeNeg = AudioPreprocessor.softClip(-10.0)
        XCTAssertGreaterThanOrEqual(hugeNeg, -1.0)
        XCTAssertLessThan(hugeNeg, -0.99)
    }

    func testPreprocessorResampleAndNoiseGate() {
        let prep = AudioPreprocessor(targetRMS: 0.14, maxGain: 4.0, noiseGateThreshold: 0.01)
        let silent = [Float](repeating: 0.001, count: 4800)
        let resampledSilent = prep.resampleTo16k(silent, inputSampleRate: 48_000)
        XCTAssertEqual(resampledSilent.count, 1600, accuracy: 2)

        let (gated, _) = prep.process(resampledSilent)
        XCTAssertTrue(gated.allSatisfy { $0 == 0 })

        let signal = (0..<1600).map { i in Float(sin(Double(i) * 0.1)) * 0.05 }
        let (boosted, levels) = prep.process(signal)
        XCTAssertGreaterThan(levels.rms, 0.03)
        let boostedLevels = AudioPreprocessor.measureLevels(boosted)
        XCTAssertGreaterThan(boostedLevels.rms, levels.rms)
    }

    func testSpeechSegmenterTurnLifecycle() {
        let settings = VADSettings(sensitivity: 0.6, silenceEndMs: 500, minSpeechMs: 250, maxTurnSeconds: 20)
        let segmenter = SpeechSegmenter(settings: settings)

        let silenceChunk = [Float](repeating: 0, count: 4096)
        let voiceChunk = [Float](repeating: 0.2, count: 4096)

        XCTAssertTrue(segmenter.process(samples16k: silenceChunk, neuralProbability: 0.05).isEmpty)
        XCTAssertFalse(segmenter.isInSpeech)

        let startEvents = segmenter.process(samples16k: voiceChunk, neuralProbability: 0.85)
        XCTAssertTrue(segmenter.isInSpeech)
        XCTAssertTrue(startEvents.contains { if case .speechStarted = $0 { return true }; return false })

        _ = segmenter.process(samples16k: voiceChunk, neuralProbability: 0.80)
        _ = segmenter.process(samples16k: silenceChunk, neuralProbability: 0.05)
        let endEvents = segmenter.process(samples16k: silenceChunk, neuralProbability: 0.02)

        XCTAssertFalse(segmenter.isInSpeech)
        let completed = endEvents.compactMap { event -> (UInt64, [Float], Double)? in
            if case .turnCompleted(let id, let samples, let duration) = event {
                return (id, samples, duration)
            }
            return nil
        }
        XCTAssertEqual(completed.count, 1)
        XCTAssertGreaterThan(completed[0].2, 0.5)
    }

    func testSpeechSegmenterDiscardsTinyBursts() {
        let settings = VADSettings(sensitivity: 0.6, silenceEndMs: 250, minSpeechMs: 600, maxTurnSeconds: 20)
        let segmenter = SpeechSegmenter(settings: settings)
        let shortVoice = [Float](repeating: 0.2, count: 2048)
        let silence = [Float](repeating: 0, count: 4096)

        _ = segmenter.process(samples16k: shortVoice, neuralProbability: 0.9)
        let events = segmenter.process(samples16k: silence, neuralProbability: 0.02)
        XCTAssertTrue(events.contains { if case .turnDiscarded = $0 { return true }; return false })
    }

    func testBackchannelAndQuestionHeuristics() {
        XCTAssertTrue(BackchannelFilter.isBackchannel("Yeah."))
        XCTAssertTrue(BackchannelFilter.isBackchannel("I see, okay."))
        XCTAssertTrue(BackchannelFilter.isBackchannel("Okay. Awesome."))
        XCTAssertTrue(BackchannelFilter.isBackchannel("Oh no."))
        XCTAssertTrue(BackchannelFilter.isBackchannel("..."))
        XCTAssertFalse(BackchannelFilter.isBackchannel("Why?"))
        XCTAssertFalse(BackchannelFilter.isBackchannel("Yeah, that makes sense, can you explain Raft?"))

        XCTAssertTrue(QuestionGate.isLikelyQuestion("How do you design a distributed rate limiter?"))
        XCTAssertTrue(QuestionGate.isLikelyQuestion("So walk me through your caching layer"))
        XCTAssertTrue(QuestionGate.isLikelyQuestion("Okay, can you describe an outage you owned"))
        XCTAssertTrue(QuestionGate.isLikelyQuestion("Have you ever handled an irate customer"))
        XCTAssertFalse(QuestionGate.isLikelyQuestion("Have a brilliant day."))
        XCTAssertFalse(QuestionGate.isLikelyQuestion("Have it within your inbox within two minutes."))
        XCTAssertFalse(QuestionGate.isLikelyQuestion("Sounds good, let's move on to the next slide."))
        XCTAssertFalse(QuestionGate.isLikelyQuestion("We deployed that service last Tuesday."))

        XCTAssertNil(DominantSpeakerSelector.selectSpeaker(from: [2, 1, 0, 0]))
        XCTAssertEqual(DominantSpeakerSelector.selectSpeaker(from: [2, 6, 4, 0]), "Speaker 2")
        XCTAssertEqual(DominantSpeakerSelector.selectSpeaker(from: [5, 5, 0, 0]), "Speaker 1")
    }

    func testDatabaseStorePersistenceFTS5AndMarkdownExport() async throws {
        let store = try DatabaseStore(path: ":memory:")

        let profiles = try await store.loadProfiles()
        XCTAssertEqual(profiles.count, 3)

        var session = SessionRecord(
            title: "Staff Architecture Loop",
            summary: "Discussed Kafka partitioning and multi-region failover.",
            speakerAliases: ["Speaker 1": "Interviewer"],
            turns: [
                TranscriptTurn(sequence: 1, text: "How would you handle backpressure in a streaming pipeline?", speaker: "Speaker 1", isQuestion: true),
                TranscriptTurn(sequence: 2, text: "I use bounded queues with adaptive shed load.", speaker: "You", isQuestion: false, source: .microphone)
            ],
            exchanges: [
                AIExchange(
                    prompt: "How would you handle backpressure in a streaming pipeline?",
                    response: "Start with bounded queues, explicit watermarks, and graceful load shedding.",
                    providerName: "Ollama (Local)",
                    modelName: "llama3.2",
                    triggeredAutomatically: true,
                    latencyMs: 410
                )
            ]
        )

        try await store.saveSession(session)

        let loaded = try await store.loadSession(id: session.id)
        XCTAssertEqual(loaded?.title, "Staff Architecture Loop")
        XCTAssertEqual(loaded?.turns.count, 2)
        XCTAssertEqual(loaded?.exchanges.count, 1)
        XCTAssertEqual(loaded?.displaySpeaker(for: "Speaker 1"), "Interviewer")

        let hits = try await store.listSessions(searchQuery: "backpressure")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].id, session.id)

        let summaryHits = try await store.listSessions(searchQuery: "Kafka")
        XCTAssertEqual(summaryHits.count, 1)

        let misses = try await store.listSessions(searchQuery: "nonexistenttermxyz")
        XCTAssertTrue(misses.isEmpty)

        let markdown = DatabaseStore.exportMarkdown(session: session)
        XCTAssertTrue(markdown.contains("# Staff Architecture Loop"))
        XCTAssertTrue(markdown.contains("## Executive Summary"))
        XCTAssertTrue(markdown.contains("Interviewer"))
        XCTAssertTrue(markdown.contains("backpressure"))

        session.title = "Updated Loop"
        try await store.saveSession(session)
        let renamed = try await store.loadSession(id: session.id)
        XCTAssertEqual(renamed?.title, "Updated Loop")

        try await store.deleteSession(id: session.id)
        let deleted = try await store.loadSession(id: session.id)
        XCTAssertNil(deleted)
    }

    func testPromptComposerVoiceRulesAndContext() {
        let profile = PrepProfile(
            name: "Principal Eng",
            roleContext: "Cloud infra interview",
            systemPrompt: "Keep answers under 45 seconds.",
            backgroundNotes: "Led 40-region edge proxy migration cutting p99 by 38%."
        )
        let system = PromptComposer.composeSystemPrompt(profile: profile, forCapturedSpeech: true)
        XCTAssertTrue(system.contains("Cloud infra interview"))
        XCTAssertTrue(system.contains("cutting p99 by 38%"))
        XCTAssertTrue(system.contains("Never say or imply that you are an AI"))

        let messages = PromptComposer.composeMessages(
            userPrompt: "Tell me about your p99 work.",
            forCapturedSpeech: true,
            recentTurns: [
                TranscriptTurn(sequence: 1, text: "Let's dive into latency.", speaker: "Speaker 1")
            ],
            recentExchanges: [
                AIExchange(prompt: "Hi", response: "Got it", providerName: "Ollama", modelName: "test")
            ],
            speakerAliases: ["Speaker 1": "Alex"]
        )
        XCTAssertEqual(messages.count, 3)
        XCTAssertTrue(messages[0].text.contains("[Alex]: Let's dive into latency."))
        XCTAssertTrue(messages.last?.text.contains("Tell me about your p99 work.") == true)
        XCTAssertTrue(messages.last?.text.contains("first-person spoken answer") == true)
    }

    func testAIClientStreamParsers() {
        let ollamaLine = #"{"model":"llama3.2","message":{"role":"assistant","content":"Hello "},"done":false}"#
        XCTAssertEqual(AIClient.parseStreamLine(ollamaLine, provider: .ollama), "Hello ")

        let openAILine = #"data: {"choices":[{"delta":{"content":"world"}}]}"#
        XCTAssertEqual(AIClient.parseStreamLine(openAILine, provider: .openAI), "world")
        XCTAssertNil(AIClient.parseStreamLine("data: [DONE]", provider: .openAI))

        let anthropicLine = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Claude!"}}"#
        XCTAssertEqual(AIClient.parseStreamLine(anthropicLine, provider: .anthropic), "Claude!")
        XCTAssertNil(AIClient.parseStreamLine(#"data: {"type":"message_start"}"#, provider: .anthropic))

        let geminiLine = #"data: {"candidates":[{"content":{"parts":[{"text":"Gemini"}]}}]}"#
        XCTAssertEqual(AIClient.parseStreamLine(geminiLine, provider: .gemini), "Gemini")
    }

    func testSlackAndCustomThemeStringParsing() throws {
        let shortParsed = CustomThemeColors.parse(themeString: "#3f0e40, c084fc, #34c78a")
        XCTAssertEqual(shortParsed?.sidebarHex, "#3F0E40")
        XCTAssertEqual(shortParsed?.accentHex, "#C084FC")
        XCTAssertEqual(shortParsed?.presenceHex, "#34C78A")

        let slackTheme = "#3F0E40,#350D36,#1164A3,#FFFFFF,#350D36,#FFFFFF,#2BAC76,#CD2553"
        let slackParsed = CustomThemeColors.parse(themeString: slackTheme)
        XCTAssertEqual(slackParsed?.sidebarHex, "#3F0E40")
        XCTAssertEqual(slackParsed?.accentHex, "#1164A3")
        XCTAssertEqual(slackParsed?.presenceHex, "#2BAC76")

        XCTAssertNil(CustomThemeColors.parse(themeString: "not-a-theme"))

        let legacyJson = Data(#"{"activeProvider":"ollama","autoAnswerQuestions":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJson)
        XCTAssertEqual(decoded.autoAnswerQuestions, false)
        XCTAssertEqual(decoded.appearance.preset, .graphite)
        XCTAssertEqual(decoded.appearance.colorMode, .dark)
        XCTAssertEqual(decoded.streamingLatency, .ms320)
        XCTAssertEqual(decoded.hasCompletedOnboarding, false)
        XCTAssertEqual(StreamingLatencyPreset.ms160.batchSamples16k, 2_560)
        XCTAssertEqual(StreamingLatencyPreset.ms320.batchSamples16k, 5_120)
        XCTAssertEqual(StreamingLatencyPreset.ms1280.batchSamples16k, 20_480)
    }

    func testDiagnosticsLogBoundedRingAndReport() {
        let log = DiagnosticsLog(maxEntries: 25)
        for i in 1...40 {
            log.record(category: "test", message: "event \(i)")
        }
        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, 25)
        XCTAssertTrue(entries.first?.contains("event 16") == true)
        XCTAssertTrue(entries.last?.contains("event 40") == true)

        let report = log.buildReport(
            settings: AppSettings(),
            speechStatus: SpeechModelStatus(),
            outputDevices: [AudioDeviceInfo(id: "out-1", name: "Studio Speakers", isDefault: true, isInput: false)],
            inputDevices: [AudioDeviceInfo(id: "in-1", name: "MacBook Pro Mic", isDefault: true, isInput: true)],
            hotkeySummary: ["⌘\\: active"]
        )
        XCTAssertTrue(report.contains("Aileron Diagnostic Report"))
        XCTAssertTrue(report.contains("Studio Speakers"))
        XCTAssertTrue(report.contains("MacBook Pro Mic"))
        XCTAssertTrue(report.contains("event 40"))

        let notice = EngineNotice(level: .error, message: "No mic", permissionAction: .microphone)
        XCTAssertEqual(notice.permissionAction, .microphone)
    }
}
