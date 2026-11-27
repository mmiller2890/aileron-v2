import Foundation

public enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case lmStudio
    case openAI
    case anthropic
    case gemini
    case groq
    case customOpenAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .lmStudio: return "LM Studio (Local)"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .groq: return "Groq"
        case .customOpenAI: return "Custom OpenAI-Compatible"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .lmStudio: return "http://127.0.0.1:1234/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .groq: return "https://api.groq.com/openai/v1"
        case .customOpenAI: return "http://127.0.0.1:8080/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .lmStudio: return "local-model"
        case .openAI: return "gpt-4.1-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .customOpenAI: return "default"
        }
    }

    public var suggestedModels: [String] {
        switch self {
        case .ollama: return ["llama3.2", "qwen2.5:14b", "gemma3:12b", "deepseek-r1:8b"]
        case .lmStudio: return ["local-model"]
        case .openAI: return ["gpt-4.1-mini", "gpt-4.1", "gpt-4o", "o4-mini"]
        case .anthropic: return ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022"]
        case .gemini: return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        case .groq: return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
        case .customOpenAI: return ["default"]
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmStudio:
            return false
        case .openAI, .anthropic, .gemini, .groq, .customOpenAI:
            return true
        }
    }

    public var isLocal: Bool {
        self == .ollama || self == .lmStudio
    }

    public var supportsVision: Bool {
        switch self {
        case .groq: return false
        default: return true
        }
    }
}

public struct ProviderSettings: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var enableThinking: Bool

    public init(
        baseURL: String,
        model: String,
        temperature: Double = 0.4,
        enableThinking: Bool = false
    ) {
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.enableThinking = enableThinking
    }

    public static func defaultFor(_ kind: AIProviderKind) -> ProviderSettings {
        ProviderSettings(baseURL: kind.defaultBaseURL, model: kind.defaultModel)
    }
}

public enum StreamingLatencyPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case ms160
    case ms320
    case ms1280

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ms160: return "160 ms"
        case .ms320: return "320 ms"
        case .ms1280: return "1280 ms"
        }
    }

    public var summary: String {
        switch self {
        case .ms160: return "Fastest response (~8-9% WER)"
        case .ms320: return "Best balance — recommended (~5.7% WER)"
        case .ms1280: return "Lowest CPU/battery, ~1.3s delay"
        }
    }

    public var batchSamples16k: Int {
        switch self {
        case .ms160: return 2_560
        case .ms320: return 5_120
        case .ms1280: return 20_480
        }
    }
}

public struct VADSettings: Codable, Equatable, Sendable {
    public var sensitivity: Float
    public var silenceEndMs: Int
    public var minSpeechMs: Int
    public var maxTurnSeconds: Double
    public var noiseGateThreshold: Float

    public init(
        sensitivity: Float = 0.55,
        silenceEndMs: Int = 750,
        minSpeechMs: Int = 260,
        maxTurnSeconds: Double = 35.0,
        noiseGateThreshold: Float = 0.0025
    ) {
        self.sensitivity = sensitivity
        self.silenceEndMs = silenceEndMs
        self.minSpeechMs = minSpeechMs
        self.maxTurnSeconds = maxTurnSeconds
        self.noiseGateThreshold = noiseGateThreshold
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var activeProvider: AIProviderKind
    public var providerConfigs: [String: ProviderSettings]
    public var activeProfileId: UUID?
    public var outputDeviceId: String
    public var inputDeviceId: String
    public var autoAnswerQuestions: Bool
    public var filterBackchannels: Bool
    public var enableLiveText: Bool
    public var enableSpeakerLabels: Bool
    public var stealthScreenShareProtection: Bool
    public var hudOpacity: Double
    public var idleAutoStopMinutes: Int
    public var streamingLatency: StreamingLatencyPreset
    public var hasCompletedOnboarding: Bool
    public var vad: VADSettings
    public var appearance: AppearanceSettings

    public init(
        activeProvider: AIProviderKind = .ollama,
        providerConfigs: [String: ProviderSettings] = Dictionary(
            uniqueKeysWithValues: AIProviderKind.allCases.map { ($0.rawValue, ProviderSettings.defaultFor($0)) }
        ),
        activeProfileId: UUID? = PrepProfile.defaultProfiles.first?.id,
        outputDeviceId: String = "default",
        inputDeviceId: String = "default",
        autoAnswerQuestions: Bool = true,
        filterBackchannels: Bool = true,
        enableLiveText: Bool = true,
        enableSpeakerLabels: Bool = true,
        stealthScreenShareProtection: Bool = true,
        hudOpacity: Double = 0.96,
        idleAutoStopMinutes: Int = 20,
        streamingLatency: StreamingLatencyPreset = .ms320,
        hasCompletedOnboarding: Bool = false,
        vad: VADSettings = VADSettings(),
        appearance: AppearanceSettings = AppearanceSettings()
    ) {
        self.activeProvider = activeProvider
        self.providerConfigs = providerConfigs
        self.activeProfileId = activeProfileId
        self.outputDeviceId = outputDeviceId
        self.inputDeviceId = inputDeviceId
        self.autoAnswerQuestions = autoAnswerQuestions
        self.filterBackchannels = filterBackchannels
        self.enableLiveText = enableLiveText
        self.enableSpeakerLabels = enableSpeakerLabels
        self.stealthScreenShareProtection = stealthScreenShareProtection
        self.hudOpacity = hudOpacity
        self.idleAutoStopMinutes = idleAutoStopMinutes
        self.streamingLatency = streamingLatency
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.vad = vad
        self.appearance = appearance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.activeProvider = try container.decodeIfPresent(AIProviderKind.self, forKey: .activeProvider) ?? defaults.activeProvider
        self.providerConfigs = try container.decodeIfPresent([String: ProviderSettings].self, forKey: .providerConfigs) ?? defaults.providerConfigs
        self.activeProfileId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId)
        self.outputDeviceId = try container.decodeIfPresent(String.self, forKey: .outputDeviceId) ?? defaults.outputDeviceId
        self.inputDeviceId = try container.decodeIfPresent(String.self, forKey: .inputDeviceId) ?? defaults.inputDeviceId
        self.autoAnswerQuestions = try container.decodeIfPresent(Bool.self, forKey: .autoAnswerQuestions) ?? defaults.autoAnswerQuestions
        self.filterBackchannels = try container.decodeIfPresent(Bool.self, forKey: .filterBackchannels) ?? defaults.filterBackchannels
        self.enableLiveText = try container.decodeIfPresent(Bool.self, forKey: .enableLiveText) ?? defaults.enableLiveText
        self.enableSpeakerLabels = try container.decodeIfPresent(Bool.self, forKey: .enableSpeakerLabels) ?? defaults.enableSpeakerLabels
        self.stealthScreenShareProtection = try container.decodeIfPresent(Bool.self, forKey: .stealthScreenShareProtection) ?? defaults.stealthScreenShareProtection
        self.hudOpacity = try container.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? defaults.hudOpacity
        self.idleAutoStopMinutes = try container.decodeIfPresent(Int.self, forKey: .idleAutoStopMinutes) ?? defaults.idleAutoStopMinutes
        self.streamingLatency = try container.decodeIfPresent(StreamingLatencyPreset.self, forKey: .streamingLatency) ?? defaults.streamingLatency
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        self.vad = try container.decodeIfPresent(VADSettings.self, forKey: .vad) ?? defaults.vad
        self.appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? defaults.appearance
    }

    public func config(for kind: AIProviderKind) -> ProviderSettings {
        providerConfigs[kind.rawValue] ?? ProviderSettings.defaultFor(kind)
    }

    public mutating func setConfig(_ config: ProviderSettings, for kind: AIProviderKind) {
        providerConfigs[kind.rawValue] = config
    }
}

public enum ModelLoadPhase: String, Sendable, Equatable {
    case idle
    case listing
    case downloading
    case compiling
    case ready
    case failed
}

public struct SpeechModelStatus: Equatable, Sendable {
    public var asrPhase: ModelLoadPhase
    public var asrProgress: Double
    public var asrDetail: String?
    public var vadReady: Bool
    public var liveTextReady: Bool
    public var speakerLabelsReady: Bool
    public var lastError: String?

    public init(
        asrPhase: ModelLoadPhase = .idle,
        asrProgress: Double = 0,
        asrDetail: String? = nil,
        vadReady: Bool = false,
        liveTextReady: Bool = false,
        speakerLabelsReady: Bool = false,
        lastError: String? = nil
    ) {
        self.asrPhase = asrPhase
        self.asrProgress = asrProgress
        self.asrDetail = asrDetail
        self.vadReady = vadReady
        self.liveTextReady = liveTextReady
        self.speakerLabelsReady = speakerLabelsReady
        self.lastError = lastError
    }

    public var isAsrReady: Bool { asrPhase == .ready }
}

public struct CaptureTelemetry: Equatable, Sendable {
    public var isCapturing: Bool
    public var isSpeechActive: Bool
    public var rmsLevel: Float
    public var peakLevel: Float
    public var sampleRate: Double
    public var activeDeviceName: String
    public var droppedSamples: UInt64
    public var lastRtfx: Float?
    public var lastTranscribeMs: Int?
    public var lastAudibleAt: Date?

    public init(
        isCapturing: Bool = false,
        isSpeechActive: Bool = false,
        rmsLevel: Float = 0,
        peakLevel: Float = 0,
        sampleRate: Double = 0,
        activeDeviceName: String = "System Default",
        droppedSamples: UInt64 = 0,
        lastRtfx: Float? = nil,
        lastTranscribeMs: Int? = nil,
        lastAudibleAt: Date? = nil
    ) {
        self.isCapturing = isCapturing
        self.isSpeechActive = isSpeechActive
        self.rmsLevel = rmsLevel
        self.peakLevel = peakLevel
        self.sampleRate = sampleRate
        self.activeDeviceName = activeDeviceName
        self.droppedSamples = droppedSamples
        self.lastRtfx = lastRtfx
        self.lastTranscribeMs = lastTranscribeMs
        self.lastAudibleAt = lastAudibleAt
    }
}
