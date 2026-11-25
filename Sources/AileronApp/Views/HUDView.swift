import AileronCore
import AppKit
import SwiftUI

public struct HUDView: View {
    @Bindable public var engine: AileronEngine
    public let onExpandedChanged: (Bool) -> Void
    public let onOpenDashboard: () -> Void
    public let onReturnToApp: () -> Void
    public let onHideHUD: () -> Void

    public var body: some View {
        HUDContentView(
            engine: engine,
            onExpandedChanged: onExpandedChanged,
            onOpenDashboard: onOpenDashboard,
            onReturnToApp: onReturnToApp,
            onHideHUD: onHideHUD
        )
        .aileronTheme(engine.settings.appearance)
    }
}

private struct HUDContentView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable var engine: AileronEngine
    let onExpandedChanged: (Bool) -> Void
    let onOpenDashboard: () -> Void
    let onReturnToApp: () -> Void
    let onHideHUD: () -> Void

    @State private var promptInput: String = ""
    @State private var userExpanded: Bool = false
    @State private var copiedLatest: Bool = false

    private var shouldExpand: Bool {
        userExpanded
            || engine.isStreamingAI
            || engine.isRecordingMic
            || !engine.livePartialText.isEmpty
            || !engine.liveMicText.isEmpty
            || engine.bannerNotice != nil
            || (engine.speechStatus.asrPhase != .idle && engine.speechStatus.asrPhase != .ready)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if shouldExpand {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(height: 1)
                expandedContent
            }
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                theme.hudSurface
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.borderMedium, lineWidth: 1)
        )
        .onChange(of: shouldExpand) { _, newValue in
            onExpandedChanged(newValue)
        }
        .onAppear {
            onExpandedChanged(shouldExpand)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            AileronLogo(size: 24, framed: true)
                .padding(.leading, 2)

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
                        Text("Live")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .medium))
                        Text("Listen")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .buttonStyle(SoftButtonStyle(engine.telemetry.isCapturing ? .live : .subtle, compact: true))
            .help("Start or stop listening (⌘⇧A)")

            HStack(spacing: 6) {
                if engine.pendingScreenshot != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                        Text("Screen")
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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.liveTint))
                }

                TextField("Ask Aileron…", text: $promptInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: theme.bodyFontSize))
                    .foregroundStyle(theme.textPrimary)
                    .onSubmit {
                        submitPrompt()
                    }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                Button {
                    userExpanded = true
                    engine.answerLastUtterance()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Answer last utterance (⌘⇧L)")

                Button {
                    userExpanded = true
                    engine.captureScreen(analyzeImmediately: true)
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13.5))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Capture screen & analyze (⌘⇧S)")

                Button {
                    userExpanded = true
                    engine.toggleMicDictation()
                } label: {
                    Image(systemName: engine.isRecordingMic ? "mic.fill" : "mic")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle(active: engine.isRecordingMic, tint: theme.danger))
                .help("Voice ask (⌘⇧M)")

                Button {
                    userExpanded.toggle()
                } label: {
                    Image(systemName: shouldExpand ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help(shouldExpand ? "Collapse" : "Expand")

                Button {
                    onReturnToApp()
                } label: {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Return floating bar to app")

                Button {
                    onOpenDashboard()
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("Open Aileron window (keep floating bar)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = engine.bannerNotice {
                HStack(spacing: 8) {
                    Circle()
                        .fill(noticeColor(notice.level))
                        .frame(width: 6, height: 6)
                    Text(notice.message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        engine.dismissNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .softCard(radius: 10)
            }

            if engine.speechStatus.asrPhase != .idle && engine.speechStatus.asrPhase != .ready {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(engine.speechStatus.asrDetail ?? "Preparing speech model…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(Int(engine.speechStatus.asrProgress * 100))%")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.textPrimary)
                    }
                    ProgressView(value: engine.speechStatus.asrProgress)
                        .tint(theme.live)
                }
                .padding(.horizontal, 4)
            }

            if engine.isRecordingMic {
                HStack(spacing: 8) {
                    SubtleAudioWave(
                        level: engine.micRmsLevel,
                        active: true,
                        speechDetected: engine.micRmsLevel > 0.012
                    )
                    Text(engine.liveMicText.isEmpty ? "Listening to microphone…" : engine.liveMicText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(engine.liveMicText.isEmpty ? theme.textSecondary : theme.textPrimary)
                        .lineLimit(2)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .softCard(background: theme.surface.opacity(0.92), radius: 10, border: theme.danger.opacity(0.45))
            }

            if !engine.livePartialText.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.live)
                        .frame(width: 6, height: 6)
                    if let speaker = engine.livePartialSpeaker {
                        Text(speaker)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.live)
                    }
                    Text(engine.livePartialText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .softCard(background: theme.surface.opacity(0.85), radius: 10)
            }

            ScrollView {
                if let latest = engine.latestExchange {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(latest.prompt)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            if engine.isStreamingAI {
                                Button("Stop") {
                                    engine.cancelAIResponse()
                                }
                                .buttonStyle(SoftButtonStyle(.danger, compact: true))
                            } else {
                                Button(copiedLatest ? "Copied" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(latest.response, forType: .string)
                                    copiedLatest = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                        copiedLatest = false
                                    }
                                }
                                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                            }
                        }

                        if latest.response.isEmpty && engine.isStreamingAI {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            MarkdownTextView(latest.response)
                        }
                    }
                    .padding(4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready when you are")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("Click Listen to transcribe your call locally, or type a question above.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(engine.quickActions.prefix(3)) { action in
                    Button(action.label) {
                        engine.runQuickAction(action)
                    }
                    .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                }
                Spacer()
                Button {
                    onReturnToApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pip.exit")
                            .font(.system(size: 11))
                        Text("Return to App")
                    }
                }
                .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                .help("Dock floating bar back into main window")
                Button("Hide") {
                    onHideHUD()
                }
                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                .help("Hide floating bar (⌘\\)")
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity)
    }

    private func submitPrompt() {
        let trimmed = promptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptInput = ""
        userExpanded = true
        engine.ask(trimmed, usePendingScreenshot: true, isCapturedSpeech: false)
    }

    private func noticeColor(_ level: EngineNotice.Level) -> Color {
        switch level {
        case .info: return theme.live
        case .warning: return theme.warn
        case .error: return theme.danger
        }
    }
}
