import Foundation

public struct AIChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let text: String
    public let imageJPEGData: Data?

    public init(role: Role, text: String, imageJPEGData: Data? = nil) {
        self.role = role
        self.text = text
        self.imageJPEGData = imageJPEGData
    }
}

public enum PromptComposer {
    public static let captureAnswerRules =
        "You are writing what the user will say aloud, in their own voice, to the person they are talking with. " +
        "Write in the first person as the user. Never say or imply that you are an AI, an assistant, or a language model. " +
        "Never write bracketed placeholders such as [X] or [company]: if a fact about the user is not known, answer naturally without it. " +
        "If what was said is small talk or not a question, reply with a brief natural line the user could say."

    public static func composeSystemPrompt(
        profile: PrepProfile?,
        forCapturedSpeech: Bool
    ) -> String {
        var sections: [String] = []
        if let profile {
            let role = profile.roleContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !role.isEmpty {
                sections.append("Session Context: \(role)")
            }
            let prompt = profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                sections.append(prompt)
            }
            let notes = profile.backgroundNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                sections.append("User Background & Prep Notes (draw on these naturally when relevant):\n\(notes)")
            }
        }
        if forCapturedSpeech {
            sections.append(captureAnswerRules)
        } else if sections.isEmpty {
            sections.append("You are Aileron, a concise, high-signal real-time assistant. Give clear, direct, actionable answers formatted cleanly in Markdown.")
        }
        return sections.joined(separator: "\n\n")
    }

    public static func composeMessages(
        userPrompt: String,
        screenshotJPEG: Data? = nil,
        recentTurns: [TranscriptTurn],
        recentExchanges: [AIExchange],
        speakerAliases: [String: String] = [:],
        maxTurns: Int = 18,
        maxExchanges: Int = 5
    ) -> [AIChatMessage] {
        var messages: [AIChatMessage] = []

        let tailTurns = recentTurns.suffix(maxTurns)
        if !tailTurns.isEmpty {
            let formattedTranscript = tailTurns.map { turn in
                let raw = turn.speaker ?? (turn.source == .microphone ? "You" : "Speaker")
                let label = speakerAliases[raw].flatMap { $0.isEmpty ? nil : $0 } ?? raw
                return "[\(label)]: \(turn.text)"
            }.joined(separator: "\n")
            messages.append(AIChatMessage(
                role: .user,
                text: "Recent live conversation transcript:\n\(formattedTranscript)"
            ))
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Understood. I have the live conversation context."
            ))
        }

        for exchange in recentExchanges.suffix(maxExchanges) {
            let promptText = exchange.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let responseText = exchange.response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !promptText.isEmpty, !responseText.isEmpty else { continue }
            messages.append(AIChatMessage(role: .user, text: promptText))
            messages.append(AIChatMessage(role: .assistant, text: responseText))
        }

        messages.append(AIChatMessage(role: .user, text: userPrompt, imageJPEGData: screenshotJPEG))
        return messages
    }

    public static func composeSummaryPrompt(session: SessionRecord) -> (system: String, user: String) {
        let system =
            "You create concise, executive-grade session briefs in Markdown. " +
            "Include four compact sections: **Overview**, **Key Topics & Questions**, **Decisions & Takeaways**, and **Recommended Follow-Ups**."

        var parts: [String] = []
        if !session.turns.isEmpty {
            let transcript = session.turns.map { turn in
                let label = session.displaySpeaker(for: turn.speaker) ?? (turn.source == .microphone ? "You" : "Speaker")
                return "- \(label): \(turn.text)"
            }.joined(separator: "\n")
            parts.append("Transcript:\n\(transcript)")
        }
        if !session.exchanges.isEmpty {
            let qa = session.exchanges.map { ex in
                "Q: \(ex.prompt)\nA: \(ex.response)"
            }.joined(separator: "\n\n")
            parts.append("Coaching Exchanges:\n\(qa)")
        }

        let body = parts.isEmpty ? "No transcript recorded." : parts.joined(separator: "\n\n---\n\n")
        return (system, "Summarize the following session:\n\n\(body)")
    }
}
