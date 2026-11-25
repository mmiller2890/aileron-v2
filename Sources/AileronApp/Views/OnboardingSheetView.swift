import AileronCore
import SwiftUI

public struct OnboardingSheetView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    public let onOpenModels: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                AileronLogo(size: 52, framed: true)
                VStack(alignment: .leading, spacing: 5) {
                    AileronWordmark(height: 15, color: theme.textPrimary)
                    Text("Quick setup for on-device audio, permissions, and AI.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("1. macOS Permissions")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("Refresh") {
                        engine.refreshPermissions()
                    }
                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                }

                VStack(spacing: 0) {
                    permissionRow(.systemAudio, state: engine.permissions.systemAudio)
                    Divider().overlay(theme.borderSubtle).padding(.leading, 14)
                    permissionRow(.microphone, state: engine.permissions.microphone)
                    Divider().overlay(theme.borderSubtle).padding(.leading, 14)
                    permissionRow(.screenRecording, state: engine.permissions.screenRecording)
                }
                .softCard(background: theme.surface, radius: 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("2. AI & On-Device Speech")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Provider: \(engine.settings.activeProvider.displayName)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(aiStatusSubtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Button("Configure") {
                            engine.completeOnboarding()
                            onOpenModels()
                        }
                        .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    Divider().overlay(theme.borderSubtle).padding(.leading, 14)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FluidAudio Speech Models")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(speechSubtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        if engine.speechStatus.isAsrReady {
                            SoftPill("Ready", color: theme.live, fill: theme.liveTint)
                        } else if engine.speechStatus.asrPhase != .idle && engine.speechStatus.asrPhase != .failed {
                            SoftPill("\(Int(engine.speechStatus.asrProgress * 100))%", color: theme.accent, fill: theme.accentTint)
                        } else {
                            Button("Preload") {
                                engine.preloadSpeechModels()
                            }
                            .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .softCard(background: theme.surface, radius: 12)
            }

            HStack {
                Text("You can revisit this checklist anytime in Settings.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button("Start Using Aileron") {
                    engine.completeOnboarding()
                }
                .buttonStyle(SoftButtonStyle(.primary))
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(theme.canvas)
        .onAppear {
            engine.refreshPermissions()
        }
    }

    private var aiStatusSubtitle: String {
        if engine.settings.activeProvider == .ollama {
            if engine.discoveredOllamaModels.isEmpty {
                return "Ollama not detected yet — start Ollama or pick a cloud provider."
            }
            return "Ready with \(engine.settings.config(for: .ollama).model) (\(engine.discoveredOllamaModels.count) local models found)."
        }
        if engine.settings.activeProvider.requiresAPIKey {
            return engine.hasAPIKey(for: engine.settings.activeProvider)
                ? "API key stored in macOS Keychain."
                : "Add your API key in Models (stored in macOS Keychain)."
        }
        return "Configured for \(engine.settings.config(for: engine.settings.activeProvider).model)."
    }

    private var speechSubtitle: String {
        if engine.speechStatus.isAsrReady {
            return "Parakeet TDT v3 and streaming models are ready on-device."
        }
        if let detail = engine.speechStatus.asrDetail, engine.speechStatus.asrPhase != .idle {
            return detail
        }
        return "Downloads locally on Apple Silicon (or loads automatically when you click Listen)."
    }

    private func permissionRow(_ kind: PermissionKind, state: PermissionState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(kind.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            switch state {
            case .granted:
                SoftPill("Granted", color: theme.live, fill: theme.liveTint)
            case .denied:
                Button("Open Settings") {
                    engine.openPermissionSettings(kind)
                }
                .buttonStyle(SoftButtonStyle(.danger, compact: true))
            case .notDetermined:
                Button("Grant") {
                    engine.requestPermission(kind)
                }
                .buttonStyle(SoftButtonStyle(.subtle, compact: true))
            case .needsVerification:
                HStack(spacing: 6) {
                    Button("Test") {
                        engine.requestPermission(kind)
                    }
                    .buttonStyle(SoftButtonStyle(.subtle, compact: true))
                    Button("Settings") {
                        engine.openPermissionSettings(kind)
                    }
                    .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
