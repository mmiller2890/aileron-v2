import AileronCore
import SwiftUI

public struct ProvidersAndSpeechView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState

    @State private var apiKeyDraft: String = ""
    @State private var testingProvider: Bool = false
    @State private var testStatusMessage: String?
    @State private var testSucceeded: Bool = false

    private var activeKind: AIProviderKind {
        engine.settings.activeProvider
    }

    private var activeConfig: ProviderSettings {
        engine.settings.config(for: activeKind)
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(theme.borderSubtle).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    aiProviderCard
                    speechModelsCard
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: engine.settings.activeProvider) { _, _ in
            apiKeyDraft = ""
            testStatusMessage = nil
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !layout.showNavSidebar {
                Button {
                    layout.toggleNavSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13.5))
                }
                .buttonStyle(QuietIconButtonStyle())
                .padding(.leading, 68)
            }

            Text("Models & Speech")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var aiProviderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Model")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                SoftPill(
                    activeKind.isLocal ? "Local" : "Keychain Secured",
                    color: activeKind.isLocal ? theme.live : theme.textSecondary,
                    fill: activeKind.isLocal ? theme.liveTint : theme.surfaceElevated
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Provider")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { engine.settings.activeProvider },
                        set: { newValue in
                            engine.settings.activeProvider = newValue
                            engine.saveSettings()
                        }
                    )) {
                        ForEach(AIProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    Spacer()
                }

                Divider().overlay(theme.borderSubtle)

                HStack {
                    Text("Endpoint")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    TextField(activeKind.defaultBaseURL, text: Binding(
                        get: { activeConfig.baseURL },
                        set: { newValue in
                            var cfg = activeConfig
                            cfg.baseURL = newValue
                            engine.settings.setConfig(cfg, for: activeKind)
                            engine.saveSettings()
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .padding(8)
                    .softCard(background: theme.inputBackground, radius: 8)
                }

                HStack(alignment: .top) {
                    Text("Model")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField(activeKind.defaultModel, text: Binding(
                                get: { activeConfig.model },
                                set: { newValue in
                                    var cfg = activeConfig
                                    cfg.model = newValue
                                    engine.settings.setConfig(cfg, for: activeKind)
                                    engine.saveSettings()
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .padding(8)
                            .softCard(background: theme.inputBackground, radius: 8)

                            if activeKind == .ollama {
                                Button("Refresh") {
                                    Task { await engine.refreshOllamaModels(silent: false) }
                                }
                                .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                            }
                        }

                        let choices = activeKind == .ollama && !engine.discoveredOllamaModels.isEmpty
                            ? engine.discoveredOllamaModels
                            : activeKind.suggestedModels

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(choices, id: \.self) { modelName in
                                    Button(modelName) {
                                        var cfg = activeConfig
                                        cfg.model = modelName
                                        engine.settings.setConfig(cfg, for: activeKind)
                                        engine.saveSettings()
                                    }
                                    .buttonStyle(SoftButtonStyle(activeConfig.model == modelName ? .live : .subtle, compact: true))
                                }
                            }
                        }
                    }
                }

                if activeKind.requiresAPIKey {
                    Divider().overlay(theme.borderSubtle)

                    HStack {
                        Text("API Key")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 110, alignment: .leading)

                        SecureField(
                            engine.hasAPIKey(for: activeKind) ? "Saved in Keychain — enter new key to replace" : "Paste API key…",
                            text: $apiKeyDraft
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .padding(8)
                        .softCard(background: theme.inputBackground, radius: 8)

                        Button("Save") {
                            engine.saveAPIKey(apiKeyDraft, for: activeKind)
                            apiKeyDraft = ""
                        }
                        .buttonStyle(SoftButtonStyle(.primary, compact: true))
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if engine.hasAPIKey(for: activeKind) {
                            Button("Clear") {
                                engine.saveAPIKey("", for: activeKind)
                            }
                            .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                        }
                    }
                }

                Divider().overlay(theme.borderSubtle)

                HStack {
                    Text("Temperature")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(
                        get: { activeConfig.temperature },
                        set: { newValue in
                            var cfg = activeConfig
                            cfg.temperature = newValue
                            engine.settings.setConfig(cfg, for: activeKind)
                            engine.saveSettings()
                        }
                    ), in: 0.0...1.0, step: 0.05)
                    .frame(width: 160)
                    Text(String(format: "%.2f", activeConfig.temperature))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(theme.textSecondary)

                    Spacer()

                    if activeKind == .ollama {
                        Toggle("Thinking", isOn: Binding(
                            get: { activeConfig.enableThinking },
                            set: { newValue in
                                var cfg = activeConfig
                                cfg.enableThinking = newValue
                                engine.settings.setConfig(cfg, for: activeKind)
                                engine.saveSettings()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Button {
                        runConnectionTest()
                    } label: {
                        HStack(spacing: 6) {
                            if testingProvider { ProgressView().controlSize(.mini) }
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                    .disabled(testingProvider)

                    if let testStatusMessage {
                        Text(testStatusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(testSucceeded ? theme.live : theme.danger)
                    }
                    Spacer()
                }
            }
            .padding(18)
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private var speechModelsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-Device Speech (FluidAudio)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Runs locally on Apple Silicon with CoreML.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button("Load Models") {
                    engine.preloadSpeechModels()
                }
                .buttonStyle(SoftButtonStyle(.subtle, compact: true))
            }

            if engine.speechStatus.asrPhase != .idle && engine.speechStatus.asrPhase != .ready {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(engine.speechStatus.asrDetail ?? "Preparing models…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(Int(engine.speechStatus.asrProgress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.textPrimary)
                    }
                    ProgressView(value: engine.speechStatus.asrProgress)
                        .tint(theme.live)
                }
                .padding(14)
                .softCard(background: theme.surface, radius: 12)
            }

            VStack(spacing: 0) {
                speechRow("Parakeet TDT v3", detail: "Final speech transcription", ready: engine.speechStatus.isAsrReady)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                speechRow("Silero Voice Activity", detail: "Speech boundary detection", ready: engine.speechStatus.vadReady)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                speechRow("Streaming Live Text", detail: "Real-time captions while speaking", ready: engine.speechStatus.liveTextReady)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                speechRow("Sortformer Speakers", detail: "Multi-speaker diarization", ready: engine.speechStatus.speakerLabelsReady)
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private func speechRow(_ title: String, detail: String, ready: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            SoftPill(
                ready ? "Ready" : "On demand",
                color: ready ? theme.live : theme.textTertiary,
                fill: ready ? theme.liveTint : theme.surfaceElevated
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func runConnectionTest() {
        testingProvider = true
        testStatusMessage = nil
        Task {
            let result = await engine.testActiveProvider()
            testingProvider = false
            switch result {
            case .success(let latencyMs):
                testSucceeded = true
                testStatusMessage = "Connected (\(latencyMs) ms)"
            case .failure(let error):
                testSucceeded = false
                testStatusMessage = error.localizedDescription
            }
        }
    }
}
