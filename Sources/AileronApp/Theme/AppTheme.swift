import AileronCore
import AppKit
import SwiftUI

public struct ResolvedTheme: Equatable, Sendable {
    public let isDark: Bool
    public let windowGradient: Bool

    public let canvas: Color
    public let surface: Color
    public let surfaceHover: Color
    public let surfaceElevated: Color
    public let inputBackground: Color

    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color

    public let borderSubtle: Color
    public let borderMedium: Color

    public let sidebarBase: Color
    public let sidebarTop: Color
    public let sidebarBottom: Color
    public let sidebarTextPrimary: Color
    public let sidebarTextSecondary: Color
    public let sidebarTextTertiary: Color
    public let sidebarSelectionFill: Color
    public let sidebarSelectionText: Color
    public let sidebarDivider: Color

    public let accent: Color
    public let accentForeground: Color
    public let accentTint: Color

    public let live: Color
    public let liveTint: Color
    public let warn: Color
    public let danger: Color
    public let dangerTint: Color

    public let hudSurface: Color
    public let cardPadding: CGFloat
    public let sectionSpacing: CGFloat
    public let bodyFontSize: CGFloat

    public init(appearance: AppearanceSettings, systemScheme: ColorScheme) {
        let dark: Bool
        switch appearance.colorMode {
        case .dark: dark = true
        case .light: dark = false
        case .system: dark = (systemScheme == .dark)
        }
        self.isDark = dark
        self.windowGradient = appearance.windowGradient

        let palette = appearance.effectiveColors
        let rawSidebarRGB = CustomThemeColors.rgbComponents(from: palette.sidebarHex) ?? (0.10, 0.11, 0.12)
        let accentRGB = CustomThemeColors.rgbComponents(from: palette.accentHex) ?? (0.38, 0.65, 0.98)
        let liveRGB = CustomThemeColors.rgbComponents(from: palette.presenceHex) ?? (0.20, 0.78, 0.54)

        let effectiveSidebarRGB: (r: Double, g: Double, b: Double)
        if !dark && appearance.preset.usesNeutralLightSidebar {
            effectiveSidebarRGB = (0.945, 0.953, 0.965)
        } else {
            effectiveSidebarRGB = rawSidebarRGB
        }

        let sidebarColor = Color(.sRGB, red: effectiveSidebarRGB.r, green: effectiveSidebarRGB.g, blue: effectiveSidebarRGB.b, opacity: 1)
        self.sidebarBase = sidebarColor
        let sidebarIsLight = Self.luminance(effectiveSidebarRGB) > 0.52

        if appearance.windowGradient {
            let delta = sidebarIsLight ? -0.04 : 0.055
            self.sidebarTop = Self.shiftedColor(effectiveSidebarRGB, delta: delta)
            self.sidebarBottom = Self.shiftedColor(effectiveSidebarRGB, delta: -delta * 0.85)
        } else {
            self.sidebarTop = sidebarColor
            self.sidebarBottom = sidebarColor
        }

        let accentColor = Color(.sRGB, red: accentRGB.r, green: accentRGB.g, blue: accentRGB.b, opacity: 1)
        let accentIsLight = Self.luminance(accentRGB) > 0.56
        self.accent = accentColor
        self.accentForeground = accentIsLight ? Color(hex: 0x111317) : Color.white
        self.accentTint = accentColor.opacity(dark ? 0.18 : 0.13)

        let liveColor = Color(.sRGB, red: liveRGB.r, green: liveRGB.g, blue: liveRGB.b, opacity: 1)
        self.live = liveColor
        self.liveTint = liveColor.opacity(dark ? 0.16 : 0.14)
        self.warn = Color(hex: 0xEAB308)
        self.danger = Color(hex: 0xEF4444)
        self.dangerTint = Color(hex: 0xEF4444).opacity(dark ? 0.16 : 0.12)

        if sidebarIsLight {
            self.sidebarTextPrimary = Color(hex: 0x111827)
            self.sidebarTextSecondary = Color(hex: 0x4B5563)
            self.sidebarTextTertiary = Color(hex: 0x6B7280)
            self.sidebarSelectionFill = accentColor.opacity(0.16)
            self.sidebarSelectionText = Color(hex: 0x111827)
            self.sidebarDivider = Color.black.opacity(0.08)
        } else {
            self.sidebarTextPrimary = Color.white.opacity(0.95)
            self.sidebarTextSecondary = Color.white.opacity(0.72)
            self.sidebarTextTertiary = Color.white.opacity(0.48)
            self.sidebarSelectionFill = Color.white.opacity(0.14)
            self.sidebarSelectionText = Color.white
            self.sidebarDivider = Color.white.opacity(0.10)
        }

        if dark {
            self.canvas = Color(hex: 0x131416)
            self.surface = Color(hex: 0x1B1D20)
            self.surfaceHover = Color(hex: 0x24272C)
            self.surfaceElevated = Color(hex: 0x212328)
            self.inputBackground = Color(hex: 0x17181B)
            self.textPrimary = Color(hex: 0xF3F4F6)
            self.textSecondary = Color(hex: 0x9CA3AF)
            self.textTertiary = Color(hex: 0x6B7280)
            self.borderSubtle = Color.white.opacity(0.08)
            self.borderMedium = Color.white.opacity(0.15)
            self.hudSurface = appearance.windowGradient
                ? sidebarColor.opacity(0.78)
                : Color(hex: 0x131416).opacity(0.76)
        } else {
            self.canvas = Color(hex: 0xFFFFFF)
            self.surface = Color(hex: 0xF6F7F9)
            self.surfaceHover = Color(hex: 0xEAEDF2)
            self.surfaceElevated = Color(hex: 0xEEF0F4)
            self.inputBackground = Color(hex: 0xFFFFFF)
            self.textPrimary = Color(hex: 0x111827)
            self.textSecondary = Color(hex: 0x4B5563)
            self.textTertiary = Color(hex: 0x6B7280)
            self.borderSubtle = Color.black.opacity(0.08)
            self.borderMedium = Color.black.opacity(0.15)
            self.hudSurface = Color.white.opacity(0.82)
        }

        switch appearance.density {
        case .compact:
            self.cardPadding = 12
            self.sectionSpacing = 12
        case .comfortable:
            self.cardPadding = 16
            self.sectionSpacing = 18
        case .spacious:
            self.cardPadding = 22
            self.sectionSpacing = 24
        }

        switch appearance.textSize {
        case .small:
            self.bodyFontSize = 12.5
        case .medium:
            self.bodyFontSize = 13.5
        case .large:
            self.bodyFontSize = 15.0
        }
    }

    public static let defaultDark = ResolvedTheme(appearance: AppearanceSettings(), systemScheme: .dark)

    private static func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    }

    private static func shiftedColor(_ rgb: (r: Double, g: Double, b: Double), delta: Double) -> Color {
        Color(
            .sRGB,
            red: max(0, min(1, rgb.r + delta)),
            green: max(0, min(1, rgb.g + delta)),
            blue: max(0, min(1, rgb.b + delta)),
            opacity: 1
        )
    }
}

private struct AileronThemeKey: EnvironmentKey {
    static let defaultValue: ResolvedTheme = .defaultDark
}

public extension EnvironmentValues {
    var aileronTheme: ResolvedTheme {
        get { self[AileronThemeKey.self] }
        set { self[AileronThemeKey.self] = newValue }
    }
}

public struct AileronThemeProvider: ViewModifier {
    public let appearance: AppearanceSettings
    @Environment(\.colorScheme) private var systemScheme

    public func body(content: Content) -> some View {
        let resolved = ResolvedTheme(appearance: appearance, systemScheme: systemScheme)
        content
            .environment(\.aileronTheme, resolved)
            .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch appearance.colorMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public extension View {
    func aileronTheme(_ appearance: AppearanceSettings) -> some View {
        modifier(AileronThemeProvider(appearance: appearance))
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    init(hexString: String, fallback: Color = .gray) {
        if let rgb = CustomThemeColors.rgbComponents(from: hexString) {
            self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
        } else {
            self = fallback
        }
    }

    func toHexString() -> String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return CustomThemeColors.hexString(
            r: Double(nsColor.redComponent),
            g: Double(nsColor.greenComponent),
            b: Double(nsColor.blueComponent)
        )
    }
}

public struct VisualEffectBlur: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

public struct SoftCardModifier: ViewModifier {
    @Environment(\.aileronTheme) private var theme
    public let background: Color?
    public let radius: CGFloat
    public let border: Color?

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background ?? theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border ?? theme.borderSubtle, lineWidth: 1)
            )
    }
}

public struct SectionCaptionModifier: ViewModifier {
    @Environment(\.aileronTheme) private var theme

    public func body(content: Content) -> some View {
        content
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
    }
}

public extension View {
    func softCard(
        background: Color? = nil,
        radius: CGFloat = 12,
        border: Color? = nil
    ) -> some View {
        modifier(SoftCardModifier(background: background, radius: radius, border: border))
    }

    func sectionCaption() -> some View {
        modifier(SectionCaptionModifier())
    }
}

public enum SoftButtonRole {
    case primary
    case live
    case subtle
    case quiet
    case danger
}

public struct SoftButtonStyle: ButtonStyle {
    public let role: SoftButtonRole
    public let compact: Bool

    public init(_ role: SoftButtonRole = .subtle, compact: Bool = false) {
        self.role = role
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration, role: role, compact: compact)
    }
}

private struct SoftButtonBody: View {
    @Environment(\.aileronTheme) private var theme
    let configuration: ButtonStyle.Configuration
    let role: SoftButtonRole
    let compact: Bool

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5.5 : 7.5)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .stroke(borderColor, lineWidth: role == .quiet || role == .primary ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous))
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: return theme.accentForeground
        case .live: return theme.live
        case .subtle: return theme.textPrimary
        case .quiet: return theme.textSecondary
        case .danger: return theme.danger
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch role {
        case .primary: return pressed ? theme.accent.opacity(0.82) : theme.accent
        case .live: return pressed ? theme.live.opacity(0.26) : theme.liveTint
        case .subtle: return pressed ? theme.surfaceHover : theme.surfaceElevated
        case .quiet: return pressed ? theme.surfaceHover : Color.clear
        case .danger: return pressed ? theme.danger.opacity(0.24) : theme.dangerTint
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary: return Color.clear
        case .live: return theme.live.opacity(0.38)
        case .subtle: return theme.borderSubtle
        case .quiet: return Color.clear
        case .danger: return theme.danger.opacity(0.32)
        }
    }
}

public struct QuietIconButtonStyle: ButtonStyle {
    public let active: Bool
    public let tint: Color?
    public let onSidebar: Bool

    public init(active: Bool = false, tint: Color? = nil, onSidebar: Bool = false) {
        self.active = active
        self.tint = tint
        self.onSidebar = onSidebar
    }

    public func makeBody(configuration: Configuration) -> some View {
        QuietIconButtonBody(
            configuration: configuration,
            active: active,
            tint: tint,
            onSidebar: onSidebar
        )
    }
}

private struct QuietIconButtonBody: View {
    @Environment(\.aileronTheme) private var theme
    let configuration: ButtonStyle.Configuration
    let active: Bool
    let tint: Color?
    let onSidebar: Bool

    var body: some View {
        let resolvedTint = tint ?? (onSidebar ? theme.sidebarTextPrimary : theme.accent)
        let inactiveColor = onSidebar ? theme.sidebarTextSecondary : theme.textSecondary
        let hoverFill = onSidebar ? theme.sidebarSelectionFill : theme.surfaceHover

        configuration.label
            .foregroundStyle(active ? resolvedTint : inactiveColor)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? hoverFill
                            : (active ? resolvedTint.opacity(0.16) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

public struct SoftPill: View {
    @Environment(\.aileronTheme) private var theme
    public let text: String
    public let color: Color?
    public let fill: Color?

    public init(_ text: String, color: Color? = nil, fill: Color? = nil) {
        self.text = text
        self.color = color
        self.fill = fill
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color ?? theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill ?? theme.surfaceElevated))
    }
}

public struct SubtleAudioWave: View {
    @Environment(\.aileronTheme) private var theme
    public let level: Float
    public let active: Bool
    public let speechDetected: Bool

    public init(level: Float, active: Bool, speechDetected: Bool) {
        self.level = level
        self.active = active
        self.speechDetected = speechDetected
    }

    public var body: some View {
        let energy = active ? min(1.0, max(0.15, Double(level) * 9.0)) : 0.15
        let weights: [Double] = [0.55, 1.0, 0.72, 0.42]
        HStack(spacing: 2.5) {
            ForEach(0..<weights.count, id: \.self) { idx in
                let h = active ? max(4, 14 * energy * weights[idx]) : 4
                Capsule()
                    .fill(speechDetected ? theme.live : theme.live.opacity(0.65))
                    .frame(width: 2.5, height: h)
                    .animation(.easeOut(duration: 0.1), value: h)
            }
        }
        .frame(height: 14)
    }
}
