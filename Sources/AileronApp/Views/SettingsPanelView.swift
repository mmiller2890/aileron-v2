import AileronCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case audio = "Audio & Capture"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }
}

public struct SettingsPanelView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState
    @State private var selectedCategory: SettingsCategory = .appearance

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(theme.borderSubtle).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedCategory {
                    case .appearance:
                        AppearanceSettingsSection(engine: engine)
                    case .audio:
                        audioSection
                        conversationSection
                        permissionsAndDiagnosticsSection
                    case .shortcuts:
                        shortcutsSection
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            engine.refreshPermissions()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
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

            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Picker("", selection: $selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 310)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Refresh Devices") {
                    engine.refreshAudioDevices()
                }
                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
            }

            VStack(spacing: 0) {
                HStack {
                    Text("System Output")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { engine.settings.outputDeviceId },
                        set: { engine.settings.outputDeviceId = $0; engine.saveSettings() }
                    )) {
                        Text("Follow System Default").tag("default")
                        ForEach(engine.outputDevices) { dev in
                            Text(dev.isDefault ? "\(dev.name) (Default)" : dev.name).tag(dev.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack {
                    Text("Microphone Input")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { engine.settings.inputDeviceId },
                        set: { engine.settings.inputDeviceId = $0; engine.saveSettings() }
                    )) {
                        Text("Follow System Default").tag("default")
                        ForEach(engine.inputDevices) { dev in
                            Text(dev.isDefault ? "\(dev.name) (Default)" : dev.name).tag(dev.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streaming Chunk Latency")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text(engine.settings.streamingLatency.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { engine.settings.streamingLatency },
                        set: { engine.updateStreamingLatency($0) }
                    )) {
                        ForEach(StreamingLatencyPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                sliderRow(
                    title: "Voice Sensitivity",
                    valueText: "\(Int(engine.settings.vad.sensitivity * 100))%",
                    value: Binding(
                        get: { Double(engine.settings.vad.sensitivity) },
                        set: { engine.settings.vad.sensitivity = Float($0); engine.saveSettings() }
                    ),
                    range: 0.25...0.90,
                    step: 0.05
                )

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                sliderRow(
                    title: "Pause Before Turn Ends",
                    valueText: "\(engine.settings.vad.silenceEndMs) ms",
                    value: Binding(
                        get: { Double(engine.settings.vad.silenceEndMs) },
                        set: { engine.settings.vad.silenceEndMs = Int($0); engine.saveSettings() }
                    ),
                    range: 400...2000,
                    step: 100
                )

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                sliderRow(
                    title: "Auto-Stop After Silence",
                    valueText: engine.settings.idleAutoStopMinutes == 0 ? "Off" : "\(engine.settings.idleAutoStopMinutes) min",
                    value: Binding(
                        get: { Double(engine.settings.idleAutoStopMinutes) },
                        set: { engine.settings.idleAutoStopMinutes = Int($0); engine.saveSettings() }
                    ),
                    range: 0...60,
                    step: 5
                )
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversation")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            VStack(spacing: 0) {
                toggleRow(
                    title: "Auto-Answer Questions",
                    subtitle: "Stream an answer automatically when a question is detected",
                    binding: Binding(
                        get: { engine.settings.autoAnswerQuestions },
                        set: { engine.settings.autoAnswerQuestions = $0; engine.saveSettings() }
                    )
                )
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                toggleRow(
                    title: "Filter Backchannels",
                    subtitle: "Ignore short acknowledgments like \"Yeah\" and \"Mm-hmm\"",
                    binding: Binding(
                        get: { engine.settings.filterBackchannels },
                        set: { engine.settings.filterBackchannels = $0; engine.saveSettings() }
                    )
                )
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                toggleRow(
                    title: "Live Partial Captions",
                    subtitle: "Show words as someone is still speaking",
                    binding: Binding(
                        get: { engine.settings.enableLiveText },
                        set: { engine.settings.enableLiveText = $0; engine.saveSettings() }
                    )
                )
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                toggleRow(
                    title: "Speaker Labels",
                    subtitle: "Distinguish speakers in the transcript",
                    binding: Binding(
                        get: { engine.settings.enableSpeakerLabels },
                        set: { engine.settings.enableSpeakerLabels = $0; engine.saveSettings() }
                    )
                )
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private var permissionsAndDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Permissions & Diagnostics")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Open Setup Guide") {
                    engine.reopenOnboarding()
                }
                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
            }

            VStack(spacing: 0) {
                permissionQuickRow(.systemAudio, state: engine.permissions.systemAudio)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                permissionQuickRow(.microphone, state: engine.permissions.microphone)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                permissionQuickRow(.screenRecording, state: engine.permissions.screenRecording)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostic Report")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("Exports system & audio status for troubleshooting (secrets and transcripts excluded)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Button("Export Report…") {
                        exportDiagnostics()
                    }
                    .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private func permissionQuickRow(_ kind: PermissionKind, state: PermissionState) -> some View {
        HStack(spacing: 12) {
            Text(kind.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if state == .granted {
                SoftPill("Granted", color: theme.live, fill: theme.liveTint)
            } else {
                Button(state == .denied ? "Open Settings" : "Grant / Test") {
                    engine.requestPermission(kind)
                }
                .buttonStyle(SoftButtonStyle(state == .denied ? .danger : .subtle, compact: true))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Re-register Global Shortcuts") {
                    engine.onReregisterHotKeys?()
                }
                .buttonStyle(SoftButtonStyle(.quiet, compact: true))
            }

            VStack(spacing: 0) {
                shortcutRow("Toggle Sidebar", shortcut: "⌘⌥S", registered: nil)
                Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                shortcutRow("Toggle Live Transcript", shortcut: "⌘⌥T", registered: nil)
                ForEach(AileronHotKey.allCases, id: \.rawValue) { key in
                    Divider().overlay(theme.borderSubtle).padding(.leading, 16)
                    shortcutRow(
                        key.label,
                        shortcut: key.displayShortcut,
                        registered: engine.hotkeyStatuses[key.rawValue]
                    )
                }
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private func shortcutRow(_ label: String, shortcut: String, registered: Bool?) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if let registered {
                SoftPill(
                    registered ? "Active" : "Conflict",
                    color: registered ? theme.live : theme.warn,
                    fill: registered ? theme.liveTint : theme.warn.opacity(0.16)
                )
                .help(registered ? "Registered globally with macOS" : "Another application currently owns this shortcut")
            }
            Text(shortcut)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.surfaceElevated)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func toggleRow(title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Slider(value: value, in: range, step: step)
                .frame(width: 150)
            Text(valueText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func exportDiagnostics() {
        let hotkeySummary = AileronHotKey.allCases.map { key -> String in
            let state = engine.hotkeyStatuses[key.rawValue] == true ? "active" : "conflict"
            return "\(key.displayShortcut) (\(key.label)): \(state)"
        }
        let report = engine.exportDiagnosticReport(hotkeySummary: hotkeySummary)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "aileron-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
