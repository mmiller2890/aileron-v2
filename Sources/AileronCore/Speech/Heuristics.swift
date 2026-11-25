import Foundation

public enum BackchannelFilter {
    private static let maxLength = 80
    private static let tokenRegex = try! NSRegularExpression(
        pattern: "^(?:oh\\s+)?(?:yeah|yes|yep|yup|mm+[-\\s]?hm+|mmm+|hmm+|okay|ok|sure|right|uh[-\\s]?huh|oh|wow|ha|no|nope|cool|awesome|got it|i see|makes sense)$",
        options: [.caseInsensitive]
    )
    private static let wordCharRegex = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{N}]",
        options: []
    )
    private static let separators = CharacterSet(charactersIn: ".,!;")

    public static func isBackchannel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("?") { return false }

        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        if wordCharRegex.firstMatch(in: trimmed, range: fullRange) == nil {
            return true
        }
        if trimmed.count > maxLength {
            return false
        }

        let pieces = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !pieces.isEmpty else { return true }
        return pieces.allSatisfy { piece in
            let range = NSRange(piece.startIndex..., in: piece)
            return tokenRegex.firstMatch(in: piece, range: range) != nil
        }
    }
}

public enum QuestionGate {
    private static let trailingQuestion = try! NSRegularExpression(
        pattern: "\\?\\s*$",
        options: []
    )
    private static let leadingPattern = try! NSRegularExpression(
        pattern: "^(?:so[,\\s]+|and[,\\s]+|now[,\\s]+|okay[,\\s]+|ok[,\\s]+|well[,\\s]+)*(?:what|why|how|when|where|who|whom|whose|which|can|could|would|will|should|shall|do|does|did|is|are|was|were|am|have|has|had|may|might|must|tell me|explain|describe|walk me through|talk me through|talk about|give me|define|compare|name|list|share|elaborate)\\b",
        options: [.caseInsensitive]
    )
    private static let embeddedPattern = try! NSRegularExpression(
        pattern: "\\b(?:can you|could you|would you|will you|do you|did you|have you|are you|tell me|explain|describe|walk me through|what is|what are|what's|what was|what were|how do|how does|how did|how would|how was|why is|why do|why did|why would|when do|when did|where do|where did|give me an example|give an example)\\b",
        options: [.caseInsensitive]
    )

    public static func isLikelyQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if trailingQuestion.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        if leadingPattern.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        return embeddedPattern.firstMatch(in: trimmed, range: range) != nil
    }
}

public enum DominantSpeakerSelector {
    public static let minActiveFrames: Int32 = 3

    public static func selectSpeaker(from counts: [Int32]) -> String? {
        var bestSlot: Int?
        var bestCount: Int32 = 0
        for (slot, count) in counts.enumerated() {
            if count >= minActiveFrames && count > bestCount {
                bestSlot = slot
                bestCount = count
            }
        }
        guard let slot = bestSlot else { return nil }
        return "Speaker \(slot + 1)"
    }
}
