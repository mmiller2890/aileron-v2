import Foundation

public struct AudioDeviceInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let isInput: Bool

    public init(id: String, name: String, isDefault: Bool, isInput: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.isInput = isInput
    }
}

public struct TranscriptTurn: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var sequence: Int
    public var text: String
    public var speaker: String?
    public var isQuestion: Bool
    public var confidence: Float
    public var durationSeconds: Double
    public var timestamp: Date
    public var source: AudioSourceKind

    public init(
        id: UUID = UUID(),
        sequence: Int,
        text: String,
        speaker: String? = nil,
        isQuestion: Bool = false,
        confidence: Float = 1.0,
        durationSeconds: Double = 0,
        timestamp: Date = Date(),
        source: AudioSourceKind = .system
    ) {
        self.id = id
        self.sequence = sequence
        self.text = text
        self.speaker = speaker
        self.isQuestion = isQuestion
        self.confidence = confidence
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
        self.source = source
    }
}

public enum AudioSourceKind: String, Codable, Sendable, CaseIterable {
    case system
    case microphone
}

public struct AIExchange: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var prompt: String
    public var response: String
    public var providerName: String
    public var modelName: String
    public var hasScreenshot: Bool
    public var triggeredAutomatically: Bool
    public var latencyMs: Int?
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        prompt: String,
        response: String = "",
        providerName: String,
        modelName: String,
        hasScreenshot: Bool = false,
        triggeredAutomatically: Bool = false,
        latencyMs: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.response = response
        self.providerName = providerName
        self.modelName = modelName
        self.hasScreenshot = hasScreenshot
        self.triggeredAutomatically = triggeredAutomatically
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }
}

public struct SessionRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var profileId: UUID?
    public var summary: String?
    public var speakerAliases: [String: String]
    public var turns: [TranscriptTurn]
    public var exchanges: [AIExchange]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        profileId: UUID? = nil,
        summary: String? = nil,
        speakerAliases: [String: String] = [:],
        turns: [TranscriptTurn] = [],
        exchanges: [AIExchange] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.profileId = profileId
        self.summary = summary
        self.speakerAliases = speakerAliases
        self.turns = turns
        self.exchanges = exchanges
    }

    public func displaySpeaker(for rawSpeaker: String?) -> String? {
        guard let raw = rawSpeaker, !raw.isEmpty else { return nil }
        if let alias = speakerAliases[raw], !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        return raw
    }
}

public struct SessionSummaryItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let turnCount: Int
    public let exchangeCount: Int
    public let preview: String
    public let hasSummary: Bool

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        turnCount: Int,
        exchangeCount: Int,
        preview: String,
        hasSummary: Bool
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turnCount = turnCount
        self.exchangeCount = exchangeCount
        self.preview = preview
        self.hasSummary = hasSummary
    }
}

public struct PrepProfile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var roleContext: String
    public var systemPrompt: String
    public var backgroundNotes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        roleContext: String = "",
        systemPrompt: String,
        backgroundNotes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.roleContext = roleContext
        self.systemPrompt = systemPrompt
        self.backgroundNotes = backgroundNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let defaultProfiles: [PrepProfile] = [
        PrepProfile(
            id: UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!,
            name: "Technical Interview",
            roleContext: "Software engineering & system design interview",
            systemPrompt: "Give crisp, structured, confident answers the user can speak naturally in 30-60 seconds. Lead with the direct conclusion, follow with 2-3 concrete technical points or trade-offs, and keep prose conversational rather than overly formal.",
            backgroundNotes: ""
        ),
        PrepProfile(
            id: UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!,
            name: "Behavioral & Leadership",
            roleContext: "STAR-format behavioral interview",
            systemPrompt: "Frame responses concisely using Situation, Action, and measurable Result. Highlight ownership, clear trade-offs, and collaboration without sounding scripted.",
            backgroundNotes: ""
        ),
        PrepProfile(
            id: UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!,
            name: "Executive Meeting Copilot",
            roleContext: "Live client, product, or architecture meeting",
            systemPrompt: "Provide sharp, high-signal talking points, clarifying questions, or risk callouts tailored to the conversation context. Favor brevity and clarity.",
            backgroundNotes: ""
        )
    ]
}

public struct QuickAction: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public var instruction: String
    public var iconName: String

    public init(id: UUID = UUID(), label: String, instruction: String, iconName: String) {
        self.id = id
        self.label = label
        self.instruction = instruction
        self.iconName = iconName
    }

    public static let defaults: [QuickAction] = [
        QuickAction(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000001")!,
            label: "Summarize",
            instruction: "Give a crisp 3-bullet summary of the conversation so far and the current question or topic on the table.",
            iconName: "text.alignleft"
        ),
        QuickAction(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000002")!,
            label: "Follow-ups",
            instruction: "Suggest 3 sharp, insightful follow-up questions I can ask right now based on what was just discussed.",
            iconName: "sparkles"
        ),
        QuickAction(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000003")!,
            label: "Sharper Answer",
            instruction: "Tighten my last answer into a punchier 20-second spoken version with stronger concrete detail.",
            iconName: "bolt.fill"
        ),
        QuickAction(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000004")!,
            label: "Trade-offs",
            instruction: "List the key architectural trade-offs, edge cases, and failure modes relevant to what is being discussed.",
            iconName: "scale.3d"
        )
    ]
}
