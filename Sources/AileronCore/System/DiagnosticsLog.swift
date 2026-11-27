import Foundation
import os

public final class DiagnosticsLog: @unchecked Sendable {
    public static let shared = DiagnosticsLog()

    private struct State {
        var entries: [String] = []
    }

    private let maxEntries: Int
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let logger = Logger(subsystem: "com.aileron.macos", category: "runtime")
    private let formatter: ISO8601DateFormatter

    public init(maxEntries: Int = 300) {
        self.maxEntries = max(20, maxEntries)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = fmt
    }

    private static let secretPatterns: [(NSRegularExpression, String)] = {
        let specs: [(String, String)] = [
            (#"(?i)bearer\s+[A-Za-z0-9._\-+/=]{8,}"#, "Bearer [REDACTED]"),
            (#"\b(?:sk-[A-Za-z0-9_\-]{12,}|AIza[A-Za-z0-9_\-]{16,}|gsk_[A-Za-z0-9_\-]{12,}|xai-[A-Za-z0-9_\-]{12,})\b"#, "[REDACTED_KEY]"),
            (#"(?i)([?&](?:key|api_key|apikey|token|secret)=)[^&\s]+"#, "$1[REDACTED]")
        ]
        return specs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, replacement)
        }
    }()

    private static let possessivePrefixRegex = try? NSRegularExpression(
        pattern: #"^[^\s']{1,32}['’]s\s+"#,
        options: []
    )

    public static func sanitize(_ text: String) -> String {
        var result = text
        for (regex, replacement) in secretPatterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    public static func sanitizeDeviceName(_ name: String) -> String {
        guard let regex = possessivePrefixRegex else { return name }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        let stripped = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? name : stripped
    }

    public func record(category: String, message: String) {
        let timestamp = formatter.string(from: Date())
        let safeMessage = Self.sanitize(message)
        let line = "[\(timestamp)] [\(category)] \(safeMessage)"
        logger.info("\(line, privacy: .private)")
        lock.withLock { state in
            state.entries.append(line)
            if state.entries.count > maxEntries {
                state.entries.removeFirst(state.entries.count - maxEntries)
            }
        }
    }

    public func recentEntries() -> [String] {
        lock.withLock { $0.entries }
    }

    public func buildReport(
        settings: AppSettings,
        speechStatus: SpeechModelStatus,
        outputDevices: [AudioDeviceInfo],
        inputDevices: [AudioDeviceInfo],
        hotkeySummary: [String]
    ) -> String {
        let info = ProcessInfo.processInfo
        var lines: [String] = []
        lines.append("Aileron Diagnostic Report")
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append("macOS: \(info.operatingSystemVersionString)")
        lines.append("CPU Count: \(info.processorCount)")
        lines.append("Physical Memory: \(info.physicalMemory / (1024 * 1024 * 1024)) GB")
        lines.append("")
        lines.append("Configuration (Secrets Redacted):")
        lines.append("- Active Provider: \(settings.activeProvider.displayName)")
        lines.append("- Model: \(settings.config(for: settings.activeProvider).model)")
        lines.append("- Streaming Latency: \(settings.streamingLatency.displayName)")
        lines.append("- Output Device Pref: \(settings.outputDeviceId)")
        lines.append("- Input Device Pref: \(settings.inputDeviceId)")
        lines.append("- Stealth Protection: \(settings.stealthScreenShareProtection)")
        lines.append("")
        lines.append("Speech Engine:")
        lines.append("- ASR Phase: \(speechStatus.asrPhase.rawValue)")
        lines.append("- VAD Ready: \(speechStatus.vadReady)")
        lines.append("- Live Text Ready: \(speechStatus.liveTextReady)")
        lines.append("- Speaker Labels Ready: \(speechStatus.speakerLabelsReady)")
        if let err = speechStatus.lastError {
            lines.append("- Last Speech Error: \(Self.sanitize(err))")
        }
        lines.append("")
        lines.append("Audio Output Devices (\(outputDevices.count)):")
        for dev in outputDevices {
            lines.append("- \(Self.sanitizeDeviceName(dev.name))\(dev.isDefault ? " [default]" : "")")
        }
        lines.append("Audio Input Devices (\(inputDevices.count)):")
        for dev in inputDevices {
            lines.append("- \(Self.sanitizeDeviceName(dev.name))\(dev.isDefault ? " [default]" : "")")
        }
        if !hotkeySummary.isEmpty {
            lines.append("")
            lines.append("Global Hotkeys:")
            for item in hotkeySummary {
                lines.append("- \(item)")
            }
        }
        lines.append("")
        lines.append("Recent Operational Log:")
        let entries = recentEntries()
        if entries.isEmpty {
            lines.append("(no events recorded)")
        } else {
            lines.append(contentsOf: entries)
        }
        return lines.joined(separator: "\n")
    }
}
