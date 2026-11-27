import Darwin
import Foundation

public enum SettingsStore {
    public static func enforcePrivatePermissions(at url: URL, isDirectory: Bool = false) {
        let mode: mode_t = isDirectory ? 0o700 : 0o600
        _ = chmod(url.path, mode)
    }

    public static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Aileron", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        enforcePrivatePermissions(at: dir, isDirectory: true)
        return dir
    }

    public static var defaultSettingsURL: URL {
        appSupportDirectory().appendingPathComponent("settings.json")
    }

    public static func load(from url: URL? = nil) -> AppSettings {
        let target = url ?? defaultSettingsURL
        guard FileManager.default.fileExists(atPath: target.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: target)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            DiagnosticsLog.shared.record(
                category: "storage",
                message: "Settings load failed; falling back to defaults"
            )
            return AppSettings()
        }
    }

    public static func save(_ settings: AppSettings, to url: URL? = nil) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        let target = url ?? defaultSettingsURL
        try data.write(to: target, options: .atomic)
        enforcePrivatePermissions(at: target, isDirectory: false)
    }
}
