import AileronCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct LiveStudioView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState
    public let onToggleHUD: () -> Void

    @State private var promptDraft: String = ""
    @State private var editingTitle: Bool = false
    @State private var titleDraft: String = ""
    @State private var speakerRenameTarget: String?
    @State private var speakerAliasDraft: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Rectangle().fill(theme.borderSubtle).frame(height: 1)

            HStack(spacing: 0) {
                mainConversationCanvas

                if layout.showTranscriptDrawer {
                    Rectangle().fill(theme.borderSubtle).frame(width: 1)
                    transcriptDrawer
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { speakerRenameTarget != nil },
            set: { if !$0 { speakerRenameTarget = nil } }
        )) {
            speakerRenameSheet
                .aileronTheme(engine.settings.appearance)
        }
    }

    private var topToolbar: some View {
        HStack(spacing: 10) {
            if !layout.showNavSidebar {
                Button {
                    layout.toggleNavSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13.5))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Show Sidebar (⌘⌥S)")
                .padding(.leading, 68)
            }

            if editingTitle {
                TextField("Session title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .softCard(background: theme.surface, radius: 7, border: theme.borderMedium)
                    .frame(maxWidth: 280)
                    .onSubmit { commitTitle() }
                Button("Done") { commitTitle() }
                    .buttonStyle(SoftButtonStyle(.subtle, compact: true))
            } else {
                Button {
                    titleDraft = engine.currentSession.title
                    editingTitle = true
                } label: {
                    Text(engine.currentSession.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Click to rename session")
            }

            Spacer()

            Button {
                engine.toggleListening()
            } label: {
                HStack(spacing: 6) {
                    if engine.telemetry.isCapturing {
                        SubtleAudioWave(
                            level: engine.telemetry.rmsLevel,
                            active: true,
                            speechDetected: engine.telemetry.isSpeechActive
                        )
                        Text("Listening")
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                        Text("Listen")
                    }
                }
            }
            .buttonStyle(SoftButtonStyle(engine.telemetry.isCapturing ? .live : .primary, compact: true))
            .help("Start or stop system audio capture (⌘⇧A)")

            Button {
                onToggleHUD()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.system(size: 13))
            }
            .buttonStyle(QuietIconButtonStyle())
            .help("Toggle Floating Bar (⌘\\)")

            Button {
                layout.toggleTranscriptDrawer()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                    if !engine.currentSession.turns.isEmpty {
                        Text("\(engine.currentSession.turns.count)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .foregroundStyle(layout.showTranscriptDrawer ? theme.textPrimary : theme.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(layout.showTranscriptDrawer ? theme.surfaceHover : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("Toggle Live Transcript panel (⌘⌥T)")

            Menu {
                Menu("Prep Profile: \(engine.activeProfile?.name ?? "Default")") {
                    ForEach(engine.profiles) { profile in
                        Button {
                            engine.selectProfile(id: profile.id)
                        } label: {
                            HStack {
                                Text(profile.name)
                                if engine.activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Answer Last Utterance (⌘⇧L)") {
                    engine.answerLastUtterance()
                }
                Button(engine.isGeneratingSummary ? "Summarizing…" : "Generate Session Brief") {
                    engine.generateSummaryForCurrentSession()
                }
                .disabled(engine.isGeneratingSummary)
                Button("Export Markdown…") {
                    exportMarkdownFile()
                }
                Divider()
                Button("New Session") {
                    engine.startNewSession()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Session actions")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var mainConversationCanvas: some View {
        VStack(spacing: 0) {
            if engine.speechStatus.asrPhase != .idle && engine.speechStatus.asrPhase != .ready {
                HStack(spacing: 12) {
                    Text(engine.speechStatus.asrDetail ?? "Loading speech models…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    ProgressView(value: engine.speechStatus.asrProgress)
                        .tint(theme.live)
                        .frame(maxWidth: 180)
                    Text("\(Int(engine.speechStatus.asrProgress * 100))%")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.borderSubtle).frame(height: 1)
                }
            }

            if !engine.livePartialText.isEmpty && !layout.showTranscriptDrawer {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.live)
                        .frame(width: 6, height: 6)
                    if let speaker = engine.livePartialSpeaker {
                        Text(speaker)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.live)
                    }
                    Text(engine.livePartialText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Transcript") {
                        layout.toggleTranscriptDrawer()
                    }
                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(theme.surface.opacity(0.85))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.borderSubtle).frame(height: 1)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                        if let summary = engine.currentSession.summary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Session Brief", systemImage: "doc.plaintext")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.live)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(summary, forType: .string)
                                    }
                                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                                }
                                MarkdownTextView(summary)
                            }
                            .padding(theme.cardPadding)
                            .softCard(background: theme.surface, radius: 14, border: theme.live.opacity(0.32))
                        }

                        if engine.currentSession.exchanges.isEmpty && (engine.currentSession.summary ?? "").isEmpty {
                            emptyFocusState
                        } else {
                            ForEach(engine.currentSession.exchanges) { exchange in
                                exchangeView(exchange)
                                    .id(exchange.id)
                            }
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: engine.currentSession.exchanges.last?.response.count) { _, _ in
                    if let lastId = engine.currentSession.exchanges.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            composerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFocusState: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(spacing: 12) {
                AileronLogo(size: 76, framed: true)
                AileronWordmark(height: 15, color: theme.textPrimary)
            }
            Text("Ready for your conversation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Start listening to transcribe system audio locally on your Mac, or ask a question below. Detected questions will appear here in your own voice.")
                .font(.system(size: theme.bodyFontSize))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3.5)
                .frame(maxWidth: 430)

            HStack(spacing: 10) {
                Button {
                    engine.toggleListening()
                } label: {
                    Label(engine.telemetry.isCapturing ? "Stop Listening" : "Start Listening", systemImage: "waveform")
                }
                .buttonStyle(SoftButtonStyle(engine.telemetry.isCapturing ? .live : .primary))

                Button {
                    engine.captureScreen(analyzeImmediately: true)
                } label: {
                    Label("Analyze Screen", systemImage: "camera.viewfinder")
                }
                .buttonStyle(SoftButtonStyle(.subtle))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
    }

    private func exchangeView(_ exchange: AIExchange) -> some View {
        let isActive = engine.streamingExchangeId == exchange.id && engine.isStreamingAI
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exchange.prompt)
                    .font(.system(size: theme.bodyFontSize + 0.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                Spacer()
                if exchange.hasScreenshot {
                    SoftPill("Screen", color: theme.live, fill: theme.liveTint)
                }
                if !isActive && !exchange.response.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exchange.response, forType: .string)
                    }
                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                }
            }

            if exchange.response.isEmpty && isActive {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                MarkdownTextView(exchange.response)
            }

            HStack(spacing: 8) {
                Text(exchange.modelName)
                if let ms = exchange.latencyMs {
                    Text("·")
                    Text("\(String(format: "%.1fs", Double(ms) / 1000.0))")
                }
                if exchange.triggeredAutomatically {
                    Text("·")
                    Text("Auto")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
        }
        .padding(theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(
            background: theme.surface,
            radius: 14,
            border: isActive ? theme.accent.opacity(0.55) : theme.borderSubtle
        )
    }

    private var composerBar: some View {
        VStack(spacing: 10) {
            if !engine.currentSession.turns.isEmpty || !engine.currentSession.exchanges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(engine.quickActions) { action in
                        Button(action.label) {
                            engine.runQuickAction(action)
                        }
                        .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                    }
                    Spacer()
                }
                .frame(maxWidth: 720)
            }

            if engine.isRecordingMic {
                HStack(spacing: 10) {
                    SubtleAudioWave(
                        level: engine.micRmsLevel,
                        active: true,
                        speechDetected: engine.micRmsLevel > 0.012
                    )
                    Text(engine.liveMicText.isEmpty ? "Listening to microphone…" : engine.liveMicText)
                        .font(.system(size: theme.bodyFontSize))
                        .foregroundStyle(engine.liveMicText.isEmpty ? theme.textSecondary : theme.textPrimary)
                        .lineLimit(3)
                    Spacer()
                    Button("Cancel") {
                        engine.cancelMicDictation()
                    }
                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                    Button("Send") {
                        engine.toggleMicDictation()
                    }
                    .buttonStyle(SoftButtonStyle(.primary, compact: true))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .softCard(background: theme.surface, radius: 12, border: theme.danger.opacity(0.45))
                .frame(maxWidth: 720)
            }

            HStack(spacing: 8) {
                if let shot = engine.pendingScreenshot {
                    HStack(spacing: 5) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                        Text("\(shot.width)×\(shot.height)")
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            engine.clearPendingScreenshot()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(theme.live)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.liveTint))
                }

                TextField("Ask anything or follow up…", text: $promptDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: theme.bodyFontSize))
                    .foregroundStyle(theme.textPrimary)
                    .onSubmit { sendDraft() }

                Button {
                    engine.captureScreen(analyzeImmediately: false)
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13.5))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Attach screenshot")

                Button {
                    engine.toggleMicDictation()
                } label: {
                    Image(systemName: engine.isRecordingMic ? "mic.fill" : "mic")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle(active: engine.isRecordingMic, tint: theme.danger))
                .help("Voice ask (⌘⇧M)")

                if engine.isStreamingAI {
                    Button {
                        engine.cancelAIResponse()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(SoftButtonStyle(.danger, compact: true))
                } else {
                    Button {
                        sendDraft()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(SoftButtonStyle(.primary, compact: true))
                    .disabled(promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .softCard(background: theme.surface, radius: 13, border: theme.borderMedium)
            .frame(maxWidth: 720)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 8)
    }

    private var transcriptDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    layout.toggleTranscriptDrawer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Close Transcript")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.borderSubtle).frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if engine.currentSession.turns.isEmpty && engine.livePartialText.isEmpty {
                            Text("Captured speech will appear here with speaker labels. Click any line to answer it.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(3)
                                .padding(8)
                        }

                        ForEach(engine.currentSession.turns) { turn in
                            transcriptRow(turn)
                                .id(turn.id)
                        }

                        if !engine.livePartialText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle().fill(theme.live).frame(width: 6, height: 6)
                                    Text(engine.livePartialSpeaker ?? "Speaking…")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(theme.live)
                                }
                                Text(engine.livePartialText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                                    .lineSpacing(3)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .softCard(background: theme.surfaceElevated, radius: 10, border: theme.live.opacity(0.35))
                            .id("partial")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: engine.currentSession.turns.count) { _, _ in
                    if let last = engine.currentSession.turns.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(width: 310)
        .background(theme.surface.opacity(0.5))
    }

    private func transcriptRow(_ turn: TranscriptTurn) -> some View {
        let rawSpeaker = turn.speaker ?? (turn.source == .microphone ? "You" : "Speaker")
        let label = engine.currentSession.displaySpeaker(for: turn.speaker) ?? rawSpeaker

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    speakerRenameTarget = rawSpeaker
                    speakerAliasDraft = engine.currentSession.speakerAliases[rawSpeaker] ?? ""
                } label: {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(turn.source == .microphone ? theme.accent : theme.live)
                }
                .buttonStyle(.plain)
                .help("Click to rename speaker")

                Text(turn.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                Button("Answer") {
                    engine.answerTurn(turn)
                }
                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
            }

            Text(turn.text)
                .font(.system(size: max(12, theme.bodyFontSize - 1)))
                .foregroundStyle(theme.textPrimary.opacity(0.92))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(background: theme.surface, radius: 10)
    }

    private var speakerRenameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Speaker")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Set a display name for \(speakerRenameTarget ?? "Speaker") in this session.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
            TextField("e.g. Interviewer, Sarah", text: $speakerAliasDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .padding(10)
                .softCard(background: theme.surface, radius: 9, border: theme.borderMedium)
            HStack {
                Spacer()
                Button("Cancel") { speakerRenameTarget = nil }
                    .buttonStyle(SoftButtonStyle(.subtle))
                Button("Save") {
                    if let target = speakerRenameTarget {
                        engine.renameSpeaker(rawSpeaker: target, alias: speakerAliasDraft)
                    }
                    speakerRenameTarget = nil
                }
                .buttonStyle(SoftButtonStyle(.primary))
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(theme.canvas)
    }

    private func sendDraft() {
        let trimmed = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptDraft = ""
        engine.ask(trimmed, usePendingScreenshot: true, isCapturedSpeech: false)
    }

    private func commitTitle() {
        engine.renameCurrentSession(titleDraft)
        editingTitle = false
    }

    private func exportMarkdownFile() {
        let markdown = engine.exportCurrentSessionMarkdown()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(engine.currentSession.title.replacingOccurrences(of: "/", with: "-")).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
