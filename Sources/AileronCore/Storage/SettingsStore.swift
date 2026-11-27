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

    private static var settingsURL: URL {
        appSupportDirectory().appendingPathComponent("settings.json")
    }

    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    public static func save(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        let url = settingsURL
        try? data.write(to: url, options: .atomic)
        enforcePrivatePermissions(at: url, isDirectory: false)
    }
}
