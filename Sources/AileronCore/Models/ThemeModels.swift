import Foundation

public enum ThemeColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum ThemeDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case spacious

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .spacious: return "Spacious"
        }
    }
}

public enum ThemeTextSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Default"
        case .large: return "Large"
        }
    }
}

public enum ThemePresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case graphite
    case pierrePeron
    case mostraNoir
    case villaAmore
    case aubergine
    case midnight
    case forest
    case espresso
    case rosewood
    case monochrome
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .pierrePeron: return "Pierre Péron"
        case .mostraNoir: return "Mostra Noir"
        case .villaAmore: return "Villa Amore"
        case .aubergine: return "Aubergine"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        case .espresso: return "Espresso"
        case .rosewood: return "Rosewood"
        case .monochrome: return "Monochrome"
        case .custom: return "Custom"
        }
    }

    public static var curatedPresets: [ThemePresetID] {
        [.graphite, .pierrePeron, .mostraNoir, .villaAmore, .aubergine, .midnight, .forest, .espresso, .rosewood, .monochrome]
    }

    public var palette: CustomThemeColors {
        switch self {
        case .graphite:
            return CustomThemeColors(sidebarHex: "#1A1B1E", accentHex: "#60A5FA", presenceHex: "#34C78A")
        case .pierrePeron:
            return CustomThemeColors(sidebarHex: "#243456", accentHex: "#D1493B", presenceHex: "#6CB6D9")
        case .mostraNoir:
            return CustomThemeColors(sidebarHex: "#11181F", accentHex: "#7FC5D6", presenceHex: "#E8934A")
        case .villaAmore:
            return CustomThemeColors(sidebarHex: "#2F3E46", accentHex: "#D49B54", presenceHex: "#52B7A8")
        case .aubergine:
            return CustomThemeColors(sidebarHex: "#3F0E40", accentHex: "#C084FC", presenceHex: "#2BAC76")
        case .midnight:
            return CustomThemeColors(sidebarHex: "#14213D", accentHex: "#38BDF8", presenceHex: "#34D399")
        case .forest:
            return CustomThemeColors(sidebarHex: "#132A22", accentHex: "#34C78A", presenceHex: "#5EEAD4")
        case .espresso:
            return CustomThemeColors(sidebarHex: "#281D18", accentHex: "#E0A458", presenceHex: "#6EE7B7")
        case .rosewood:
            return CustomThemeColors(sidebarHex: "#311623", accentHex: "#F472B6", presenceHex: "#4ADE80")
        case .monochrome:
            return CustomThemeColors(sidebarHex: "#141414", accentHex: "#E5E7EB", presenceHex: "#22C55E")
        case .custom:
            return CustomThemeColors(sidebarHex: "#243456", accentHex: "#D1493B", presenceHex: "#6CB6D9")
        }
    }

    public var usesNeutralLightSidebar: Bool {
        self == .graphite || self == .monochrome
    }
}

public struct CustomThemeColors: Codable, Equatable, Sendable {
    public var sidebarHex: String
    public var accentHex: String
    public var presenceHex: String

    public init(
        sidebarHex: String = "#3F0E40",
        accentHex: String = "#C084FC",
        presenceHex: String = "#34C78A"
    ) {
        self.sidebarHex = Self.normalizeHex(sidebarHex) ?? "#3F0E40"
        self.accentHex = Self.normalizeHex(accentHex) ?? "#C084FC"
        self.presenceHex = Self.normalizeHex(presenceHex) ?? "#34C78A"
    }

    public var themeString: String {
        "\(sidebarHex),\(accentHex),\(presenceHex)"
    }

    public static func normalizeHex(_ input: String) -> String? {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6,
              cleaned.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(cleaned.uppercased())"
    }

    public static func parse(themeString: String) -> CustomThemeColors? {
        let tokens = themeString
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { normalizeHex($0) }

        if tokens.count >= 7 {
            return CustomThemeColors(
                sidebarHex: tokens[0],
                accentHex: tokens[2],
                presenceHex: tokens[6]
            )
        }
        if tokens.count >= 3 {
            return CustomThemeColors(
                sidebarHex: tokens[0],
                accentHex: tokens[1],
                presenceHex: tokens[2]
            )
        }
        return nil
    }

    public static func rgbComponents(from hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let normalized = normalizeHex(hex) else { return nil }
        let digits = String(normalized.dropFirst())
        guard let value = UInt32(digits, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    public static func hexString(r: Double, g: Double, b: Double) -> String {
        let ri = max(0, min(255, Int((r * 255.0).rounded())))
        let gi = max(0, min(255, Int((g * 255.0).rounded())))
        let bi = max(0, min(255, Int((b * 255.0).rounded())))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var colorMode: ThemeColorMode
    public var preset: ThemePresetID
    public var customColors: CustomThemeColors
    public var windowGradient: Bool
    public var density: ThemeDensity
    public var textSize: ThemeTextSize

    public init(
        colorMode: ThemeColorMode = .dark,
        preset: ThemePresetID = .graphite,
        customColors: CustomThemeColors = CustomThemeColors(),
        windowGradient: Bool = true,
        density: ThemeDensity = .comfortable,
        textSize: ThemeTextSize = .medium
    ) {
        self.colorMode = colorMode
        self.preset = preset
        self.customColors = customColors
        self.windowGradient = windowGradient
        self.density = density
        self.textSize = textSize
    }

    public var effectiveColors: CustomThemeColors {
        preset == .custom ? customColors : preset.palette
    }
}
