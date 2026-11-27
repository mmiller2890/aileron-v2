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
    public let permissionAction: PermissionKind?

    public init(level: Level, message: String, permissionAction: PermissionKind? = nil) {
        self.level = level
        self.message = message
        self.permissionAction = permissionAction
    }
}

@MainActor
@Observable
public final class AileronEngine {
    public typealias AIStreamHandler = @Sendable (
        AIProviderKind,
        ProviderSettings,
        String?,
        String,
        [AIChatMessage]
    ) -> AsyncThrowingStream<String, Error>

    internal struct CompletedTurnJob: Sendable {
        let samples16k: [Float]
        let duration: Double
        let trailingSpeakerSamples: [Float]
    }

    public var settings: AppSettings
    public var profiles: [PrepProfile] = []
    public var quickActions: [QuickAction] = QuickAction.defaults
    public var currentSession: SessionRecord
    public var sessionList: [SessionSummaryItem] = []
    public var searchQuery: String = ""

    public var speechStatus = SpeechModelStatus()
    public var telemetry = CaptureTelemetry()
    public var permissions = PermissionsSnapshot()
    public var showOnboarding: Bool = false
    public var hotkeyStatuses: [UInt32: Bool] = [:]
    public var outputDevices: [AudioDeviceInfo] = []
    public var inputDevices: [AudioDeviceInfo] = []
    public var discoveredOllamaModels: [String] = []

    public var livePartialText: String = ""
    public var livePartialSpeaker: String?
    public var liveMicText: String = ""
    public var micRmsLevel: Float = 0
    public var isTranscribing: Bool = false
    public var isStreamingAI: Bool = false
    public var streamingExchangeId: UUID?
    public var pendingScreenshot: CapturedScreenshot?
    public var isRecordingMic: Bool = false
    public var isGeneratingSummary: Bool = false
    public var bannerNotice: EngineNotice?

    public let keychain: any SecretStore
    internal let speechEngine: SpeechEngine
    internal let aiStreamHandler: AIStreamHandler
    internal let micCapture = MicCapture()
    internal var database: DatabaseStore?
    internal var captureTask: Task<Void, Never>?
    internal var transcriptionTask: Task<Void, Never>?
    internal var transcriptionContinuation: AsyncStream<CompletedTurnJob>.Continuation?
    internal var pendingTranscriptionCount: Int = 0
    internal var liveTextBusy: Bool = false
    internal var liveSpeakerBusy: Bool = false
    internal var micStreamTask: Task<Void, Never>?
    internal var accumulatedMicSamples16k: [Float] = []
    internal var micPreprocessor = AudioPreprocessor()
    internal var aiTask: Task<Void, Never>?
    internal var queuedAutoPrompt: String?
    internal var cachedAPIKeys: [AIProviderKind: String] = [:]
    internal var loadedKeyProviders: Set<AIProviderKind> = []
    internal var saveTask: Task<Void, Never>?
    internal var activeTap: SystemAudioTap?

    public var onStealthSettingChanged: ((Bool) -> Void)?
    public var onHUDOpacityChanged: ((Double) -> Void)?
    public var onAppearanceChanged: ((AppearanceSettings) -> Void)?
    public var onReregisterHotKeys: (() -> Void)?

    public init(
        keychain: any SecretStore = KeychainStore(),
        speechEngine: SpeechEngine = SpeechEngine(),
        databasePath: String? = nil,
        initialSettings: AppSettings? = nil,
        aiStreamHandler: @escaping AIStreamHandler = AIClient.streamCompletion,
        autoBootstrap: Bool = true
    ) {
        self.keychain = keychain
        self.speechEngine = speechEngine
        self.aiStreamHandler = aiStreamHandler
        let loadedSettings = initialSettings ?? SettingsStore.load()
        self.settings = loadedSettings
        self.showOnboarding = !loadedSettings.hasCompletedOnboarding
        self.currentSession = SessionRecord(
            title: Self.defaultSessionTitle(),
            profileId: loadedSettings.activeProfileId
        )

        do {
            self.database = try DatabaseStore(path: databasePath)
        } catch {
            self.bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }

        if autoBootstrap {
            refreshAudioDevices()
            refreshPermissions()
            DiagnosticsLog.shared.record(category: "app", message: "AileronEngine initialized")
            Task {
                await bootstrapAsync()
            }
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
        do {
            try SettingsStore.save(settings)
        } catch {
            DiagnosticsLog.shared.record(category: "storage", message: "Failed to save settings")
            bannerNotice = EngineNotice(level: .error, message: "Could not save settings: \(error.localizedDescription)")
        }
        onStealthSettingChanged?(settings.stealthScreenShareProtection)
        onHUDOpacityChanged?(settings.hudOpacity)
        onAppearanceChanged?(settings.appearance)
    }

    public func refreshAudioDevices() {
        outputDevices = AudioDeviceManager.outputDevices()
        inputDevices = AudioDeviceManager.inputDevices()
    }

    public func refreshPermissions() {
        permissions.microphone = PermissionsService.currentMicrophoneState()
        permissions.screenRecording = PermissionsService.currentScreenRecordingState()
    }

    public func requestPermission(_ kind: PermissionKind) {
        Task {
            switch kind {
            case .microphone:
                permissions.microphone = await PermissionsService.requestMicrophone()
                DiagnosticsLog.shared.record(category: "permissions", message: "Microphone status: \(permissions.microphone.rawValue)")
                if permissions.microphone == .denied {
                    PermissionsService.openSystemSettings(for: .microphone)
                }
            case .screenRecording:
                let granted = PermissionsService.requestScreenRecording()
                permissions.screenRecording = granted ? .granted : .denied
                DiagnosticsLog.shared.record(category: "permissions", message: "Screen recording status: \(permissions.screenRecording.rawValue)")
                if !granted {
                    PermissionsService.openSystemSettings(for: .screenRecording)
                }
            case .systemAudio:
                let result = PermissionsService.probeSystemAudioTap()
                permissions.systemAudio = result
                DiagnosticsLog.shared.record(category: "permissions", message: "System audio probe: \(result.rawValue)")
                if result != .granted {
                    PermissionsService.openSystemSettings(for: .systemAudio)
                }
            }
        }
    }

    public func openPermissionSettings(_ kind: PermissionKind) {
        PermissionsService.openSystemSettings(for: kind)
    }

    public func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        showOnboarding = false
        saveSettings()
    }

    public func reopenOnboarding() {
        refreshPermissions()
        refreshAudioDevices()
        showOnboarding = true
    }

    public func updateHotKeyStatuses(_ statuses: [UInt32: Bool], conflictedShortcuts: [String]) {
        hotkeyStatuses = statuses
        if !conflictedShortcuts.isEmpty {
            let joined = conflictedShortcuts.joined(separator: ", ")
            DiagnosticsLog.shared.record(category: "hotkeys", message: "Shortcut conflict: \(joined)")
            bannerNotice = EngineNotice(
                level: .warning,
                message: "Shortcut already in use by another app: \(joined). Check Settings > Shortcuts."
            )
        } else {
            DiagnosticsLog.shared.record(category: "hotkeys", message: "All global shortcuts registered")
        }
    }

    public func exportDiagnosticReport(hotkeySummary: [String]) -> String {
        DiagnosticsLog.shared.buildReport(
            settings: settings,
            speechStatus: speechStatus,
            outputDevices: outputDevices,
            inputDevices: inputDevices,
            hotkeySummary: hotkeySummary
        )
    }

    public func dismissNotice() {
        bannerNotice = nil
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

    internal func resolvedAPIKey(for provider: AIProviderKind) -> String? {
        guard provider.requiresAPIKey else { return nil }
        if loadedKeyProviders.contains(provider) {
            return cachedAPIKeys[provider]
        }
        let secret = keychain.secret(for: provider.rawValue)
        loadedKeyProviders.insert(provider)
        cachedAPIKeys[provider] = secret
        return secret
    }

    public func saveAPIKey(_ key: String, for provider: AIProviderKind) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try keychain.setSecret(trimmed, for: provider.rawValue)
            loadedKeyProviders.insert(provider)
            cachedAPIKeys[provider] = trimmed.isEmpty ? nil : trimmed
            bannerNotice = EngineNotice(
                level: .info,
                message: trimmed.isEmpty
                    ? "Removed API key for \(provider.displayName) from Keychain."
                    : "Saved API key for \(provider.displayName) in macOS Keychain."
            )
        } catch {
            bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }
    }

    public func hasAPIKey(for provider: AIProviderKind) -> Bool {
        guard provider.requiresAPIKey else { return false }
        if loadedKeyProviders.contains(provider) {
            return cachedAPIKeys[provider] != nil
        }
        return keychain.hasSecret(for: provider.rawValue)
    }

    public func testActiveProvider() async -> Result<Int, Error> {
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        let key = resolvedAPIKey(for: provider)
        do {
            let latency = try await AIClient.testConnection(provider: provider, config: config, apiKey: key)
            return .success(latency)
        } catch {
            return .failure(error)
        }
    }

    internal static func defaultSessionTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return "Session \(formatter.string(from: Date()))"
    }

    internal static func deriveTitle(from text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 48 { return cleaned }
        return String(cleaned.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
