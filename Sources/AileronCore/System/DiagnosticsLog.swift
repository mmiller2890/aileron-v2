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

    public func record(category: String, message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)"
        logger.info("\(line, privacy: .public)")
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
            lines.append("- Last Speech Error: \(err)")
        }
        lines.append("")
        lines.append("Audio Output Devices (\(outputDevices.count)):")
        for dev in outputDevices {
            lines.append("- \(dev.name)\(dev.isDefault ? " [default]" : "")")
        }
        lines.append("Audio Input Devices (\(inputDevices.count)):")
        for dev in inputDevices {
            lines.append("- \(dev.name)\(dev.isDefault ? " [default]" : "")")
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
