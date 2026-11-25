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

public struct AileronLogo: View {
    public let size: CGFloat
    public let framed: Bool
    @Environment(\.aileronTheme) private var theme

    public init(size: CGFloat = 24, framed: Bool = false) {
        self.size = size
        self.framed = framed
    }

    public var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let sx = w / 100.0
            let sy = h / 100.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }

            let inkBlack = Color(hex: 0x121417)
            let slateBlue = Color(hex: 0x263B63)
            let skyBlue = Color(hex: 0x72B2D4)
            let creamPaper = Color(hex: 0xF2EAD9)
            let vermilion = Color(hex: 0xCF4636)
            let warmOchre = Color(hex: 0xD9A74A)

            if framed {
                var steppedOuter = Path()
                let s1: CGFloat = 10
                let s2: CGFloat = 18
                steppedOuter.move(to: pt(s2, 2))
                steppedOuter.addLine(to: pt(100 - s2, 2))
                steppedOuter.addLine(to: pt(100 - s2, s1))
                steppedOuter.addLine(to: pt(100 - s1, s1))
                steppedOuter.addLine(to: pt(100 - s1, s2))
                steppedOuter.addLine(to: pt(98, s2))
                steppedOuter.addLine(to: pt(98, 100 - s2))
                steppedOuter.addLine(to: pt(100 - s1, 100 - s2))
                steppedOuter.addLine(to: pt(100 - s1, 100 - s1))
                steppedOuter.addLine(to: pt(100 - s2, 100 - s1))
                steppedOuter.addLine(to: pt(100 - s2, 98))
                steppedOuter.addLine(to: pt(s2, 98))
                steppedOuter.addLine(to: pt(s2, 100 - s1))
                steppedOuter.addLine(to: pt(s1, 100 - s1))
                steppedOuter.addLine(to: pt(s1, 100 - s2))
                steppedOuter.addLine(to: pt(2, 100 - s2))
                steppedOuter.addLine(to: pt(2, s2))
                steppedOuter.addLine(to: pt(s1, s2))
                steppedOuter.addLine(to: pt(s1, s1))
                steppedOuter.addLine(to: pt(s2, s1))
                steppedOuter.closeSubpath()

                ctx.drawLayer { layer in
                    layer.clip(to: steppedOuter)
                    layer.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(inkBlack))

                    var diagPlane = Path()
                    diagPlane.move(to: pt(0, 0))
                    diagPlane.addLine(to: pt(64, 0))
                    diagPlane.addLine(to: pt(34, 100))
                    diagPlane.addLine(to: pt(0, 100))
                    diagPlane.closeSubpath()
                    layer.fill(diagPlane, with: .color(slateBlue))

                    var creamBand = Path()
                    creamBand.move(to: pt(76, 0))
                    creamBand.addLine(to: pt(100, 0))
                    creamBand.addLine(to: pt(100, 100))
                    creamBand.addLine(to: pt(68, 100))
                    creamBand.closeSubpath()
                    layer.fill(creamBand, with: .color(creamPaper.opacity(0.10)))

                    for stripeX in [79.0, 83.0, 87.0] {
                        var stripe = Path()
                        stripe.move(to: pt(stripeX, 0))
                        stripe.addLine(to: pt(stripeX + 1.4, 0))
                        stripe.addLine(to: pt(stripeX - 5.6, 100))
                        stripe.addLine(to: pt(stripeX - 7.0, 100))
                        stripe.closeSubpath()
                        layer.fill(stripe, with: .color(vermilion.opacity(0.55)))
                    }
                }

                ctx.stroke(steppedOuter, with: .color(creamPaper), lineWidth: max(1.0, 2.0 * sx))
            }

            let pad: CGFloat = framed ? 0.66 : 0.92
            let offset: CGFloat = (100.0 - 100.0 * pad) / 2.0
            func ept(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                pt(offset + x * pad, offset + y * pad)
            }

            for i in 0..<3 {
                let y = 55.0 + CGFloat(i) * 8.0
                let leftOuter = 4.0 + CGFloat(i) * 5.0
                let rightOuter = 96.0 - CGFloat(i) * 5.0
                let barH: CGFloat = 4.4

                var lBar = Path()
                lBar.move(to: ept(leftOuter, y))
                lBar.addLine(to: ept(34, y))
                lBar.addLine(to: ept(32, y + barH))
                lBar.addLine(to: ept(leftOuter + 3.2, y + barH))
                lBar.closeSubpath()
                ctx.fill(lBar, with: .color(i == 0 ? skyBlue : (i == 1 ? creamPaper : warmOchre)))

                var rBar = Path()
                rBar.move(to: ept(66, y))
                rBar.addLine(to: ept(rightOuter, y))
                rBar.addLine(to: ept(rightOuter - 3.2, y + barH))
                rBar.addLine(to: ept(68, y + barH))
                rBar.closeSubpath()
                ctx.fill(rBar, with: .color(i == 0 ? vermilion : (i == 1 ? creamPaper : warmOchre)))
            }

            var crossbar = Path()
            crossbar.move(to: ept(29, 71))
            crossbar.addLine(to: ept(71, 71))
            crossbar.addLine(to: ept(71, 77.5))
            crossbar.addLine(to: ept(29, 77.5))
            crossbar.closeSubpath()
            ctx.fill(crossbar, with: .color(warmOchre))

            var leftLeg = Path()
            leftLeg.move(to: ept(50, 7))
            leftLeg.addLine(to: ept(17, 89))
            leftLeg.addLine(to: ept(33.5, 89))
            leftLeg.addLine(to: ept(50, 44))
            leftLeg.closeSubpath()
            ctx.fill(leftLeg, with: .color(creamPaper))

            var rightLeg = Path()
            rightLeg.move(to: ept(50, 7))
            rightLeg.addLine(to: ept(83, 89))
            rightLeg.addLine(to: ept(66.5, 89))
            rightLeg.addLine(to: ept(50, 44))
            rightLeg.closeSubpath()
            ctx.fill(rightLeg, with: .color(vermilion))

            var inlineCutLeft = Path()
            inlineCutLeft.move(to: ept(48.5, 21))
            inlineCutLeft.addLine(to: ept(23.5, 84))
            inlineCutLeft.addLine(to: ept(26.2, 84))
            inlineCutLeft.addLine(to: ept(48.5, 28))
            inlineCutLeft.closeSubpath()
            ctx.fill(inlineCutLeft, with: .color(inkBlack))

            var counterDiamond = Path()
            counterDiamond.move(to: ept(50, 52))
            counterDiamond.addLine(to: ept(56.5, 62))
            counterDiamond.addLine(to: ept(50, 68.5))
            counterDiamond.addLine(to: ept(43.5, 62))
            counterDiamond.closeSubpath()
            ctx.fill(counterDiamond, with: .color(skyBlue))

            var baseRule = Path()
            baseRule.addRect(CGRect(
                x: ept(17, 92.5).x,
                y: ept(17, 92.5).y,
                width: 66 * pad * sx,
                height: 3.6 * pad * sy
            ))
            ctx.fill(baseRule, with: .color(creamPaper))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Aileron")
    }
}

public struct AileronWordmark: View {
    public let height: CGFloat
    public let color: Color?
    @Environment(\.aileronTheme) private var theme

    public init(height: CGFloat = 15, color: Color? = nil) {
        self.height = height
        self.color = color
    }

    public var body: some View {
        let ink = color ?? theme.textPrimary
        let width = height * 6.8
        Canvas { ctx, size in
            let s = size.height / 24.0
            let sw = max(1.3, 2.3 * s)
            let style = StrokeStyle(lineWidth: sw, lineCap: .square, lineJoin: .miter)

            func strokePath(_ build: (inout Path) -> Void) {
                var p = Path()
                build(&p)
                ctx.stroke(p, with: .color(ink), style: style)
            }

            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
            }

            strokePath { p in
                p.move(to: pt(2, 22))
                p.addLine(to: pt(10, 2))
                p.addLine(to: pt(18, 22))
                p.move(to: pt(4.5, 16.5))
                p.addLine(to: pt(15.5, 16.5))
            }

            strokePath { p in
                p.move(to: pt(27, 2))
                p.addLine(to: pt(27, 22))
            }

            strokePath { p in
                p.move(to: pt(36, 2))
                p.addLine(to: pt(36, 22))
                p.addLine(to: pt(49, 22))
            }

            strokePath { p in
                p.move(to: pt(70, 2))
                p.addLine(to: pt(57, 2))
                p.addLine(to: pt(57, 22))
                p.addLine(to: pt(70, 22))
                p.move(to: pt(57, 10))
                p.addLine(to: pt(67, 10))
            }

            strokePath { p in
                p.move(to: pt(79, 22))
                p.addLine(to: pt(79, 2))
                p.addLine(to: pt(88, 2))
                p.addArc(
                    center: pt(88, 7.5),
                    radius: 5.5 * s,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(90),
                    clockwise: false
                )
                p.addLine(to: pt(79, 13))
                p.move(to: pt(87, 13))
                p.addLine(to: pt(94, 22))
            }

            strokePath { p in
                p.addEllipse(in: CGRect(x: 103 * s, y: 2 * s, width: 20 * s, height: 20 * s))
            }

            strokePath { p in
                p.move(to: pt(132, 22))
                p.addLine(to: pt(132, 2))
                p.addLine(to: pt(148, 22))
                p.addLine(to: pt(148, 2))
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Aileron")
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
