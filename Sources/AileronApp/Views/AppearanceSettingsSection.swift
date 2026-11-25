import AileronCore
import AppKit
import SwiftUI

public struct AppearanceSettingsSection: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine

    @State private var themeStringInput: String = ""
    @State private var themeStringStatus: String?
    @State private var copiedThemeString: Bool = false

    private var appearance: AppearanceSettings {
        engine.settings.appearance
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            colorModeSection
            presetsSection
            customThemeSection
            displayComfortSection
        }
        .onAppear {
            themeStringInput = appearance.effectiveColors.themeString
        }
        .onChange(of: engine.settings.appearance) { _, newValue in
            themeStringInput = newValue.effectiveColors.themeString
        }
    }

    private var colorModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Mode")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 12) {
                ForEach(ThemeColorMode.allCases) { mode in
                    let isSelected = appearance.colorMode == mode
                    Button {
                        engine.settings.appearance.colorMode = mode
                        engine.saveSettings()
                    } label: {
                        VStack(spacing: 8) {
                            colorModeThumbnail(for: mode)
                                .frame(height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelected ? theme.accent : theme.borderSubtle, lineWidth: isSelected ? 2 : 1)
                                )
                            HStack(spacing: 5) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.accent)
                                }
                                Text(mode.displayName)
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .softCard(
                            background: isSelected ? theme.surfaceElevated : theme.surface,
                            radius: 12,
                            border: isSelected ? theme.accent.opacity(0.6) : theme.borderSubtle
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func colorModeThumbnail(for mode: ThemeColorMode) -> some View {
        switch mode {
        case .light:
            HStack(spacing: 0) {
                Color(hex: 0xECEEF2).frame(width: 28)
                Color.white
            }
        case .dark:
            HStack(spacing: 0) {
                Color(hex: 0x1D1F24).frame(width: 28)
                Color(hex: 0x131416)
            }
        case .system:
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color(hex: 0xECEEF2).frame(width: 16)
                    Color.white
                }
                HStack(spacing: 0) {
                    Color(hex: 0x1D1F24).frame(width: 16)
                    Color(hex: 0x131416)
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Themes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if appearance.preset == .custom {
                    SoftPill("Custom Active", color: theme.accent, fill: theme.accentTint)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(ThemePresetID.curatedPresets) { preset in
                    presetTile(preset)
                }
            }
        }
    }

    private func presetTile(_ preset: ThemePresetID) -> some View {
        let isSelected = appearance.preset == preset
        let palette = preset.palette
        let sidebarColor: Color = (!theme.isDark && preset.usesNeutralLightSidebar)
            ? Color(hex: 0xECEEF2)
            : Color(hexString: palette.sidebarHex)
        let accentColor = Color(hexString: palette.accentHex)
        let liveColor = Color(hexString: palette.presenceHex)
        let canvasColor = theme.isDark ? Color(hex: 0x131416) : Color.white

        return Button {
            engine.settings.appearance.preset = preset
            engine.settings.appearance.customColors = palette
            engine.saveSettings()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            Circle().fill(liveColor).frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.65)).frame(width: 22, height: 4)
                        }
                        RoundedRectangle(cornerRadius: 2.5).fill(accentColor.opacity(0.9)).frame(width: 30, height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.28)).frame(width: 24, height: 4)
                        Spacer()
                    }
                    .padding(6)
                    .frame(width: 46, alignment: .leading)
                    .background(sidebarColor)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)).frame(width: 44, height: 5)
                        RoundedRectangle(cornerRadius: 2).fill(theme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)).frame(width: 60, height: 4)
                        Spacer()
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3).fill(accentColor).frame(width: 18, height: 7)
                        }
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(canvasColor)
                }
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

                HStack {
                    Text(preset.displayName)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(9)
            .softCard(
                background: isSelected ? theme.surfaceElevated : theme.surface,
                radius: 12,
                border: isSelected ? theme.accent : theme.borderSubtle
            )
        }
        .buttonStyle(.plain)
    }

    private var customThemeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Theme")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            VStack(spacing: 0) {
                colorPickerRow(
                    title: "Sidebar Color",
                    hex: appearance.effectiveColors.sidebarHex,
                    binding: colorBinding(
                        get: { appearance.effectiveColors.sidebarHex },
                        set: { hex in
                            var colors = appearance.effectiveColors
                            colors.sidebarHex = hex
                            engine.settings.appearance.customColors = colors
                            engine.settings.appearance.preset = .custom
                            engine.saveSettings()
                        }
                    )
                )

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                colorPickerRow(
                    title: "Accent & Buttons",
                    hex: appearance.effectiveColors.accentHex,
                    binding: colorBinding(
                        get: { appearance.effectiveColors.accentHex },
                        set: { hex in
                            var colors = appearance.effectiveColors
                            colors.accentHex = hex
                            engine.settings.appearance.customColors = colors
                            engine.settings.appearance.preset = .custom
                            engine.saveSettings()
                        }
                    )
                )

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                colorPickerRow(
                    title: "Live Indicator",
                    hex: appearance.effectiveColors.presenceHex,
                    binding: colorBinding(
                        get: { appearance.effectiveColors.presenceHex },
                        set: { hex in
                            var colors = appearance.effectiveColors
                            colors.presenceHex = hex
                            engine.settings.appearance.customColors = colors
                            engine.settings.appearance.preset = .custom
                            engine.saveSettings()
                        }
                    )
                )

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Window Gradient")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("Adds a subtle depth gradient to the sidebar and floating bar")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appearance.windowGradient },
                        set: {
                            engine.settings.appearance.windowGradient = $0
                            engine.saveSettings()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Theme String")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("Paste 3-hex or Slack theme string")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }

                    HStack(spacing: 8) {
                        TextField("#3F0E40,#C084FC,#2BAC76", text: $themeStringInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .padding(8)
                            .softCard(background: theme.inputBackground, radius: 8)
                            .onSubmit { applyThemeString() }

                        Button("Apply") {
                            applyThemeString()
                        }
                        .buttonStyle(SoftButtonStyle(.subtle, compact: true))

                        Button(copiedThemeString ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appearance.effectiveColors.themeString, forType: .string)
                            copiedThemeString = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                copiedThemeString = false
                            }
                        }
                        .buttonStyle(SoftButtonStyle(.quiet, compact: true))
                    }

                    if let themeStringStatus {
                        Text(themeStringStatus)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private var displayComfortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display & Privacy")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            VStack(spacing: 0) {
                HStack {
                    Text("Spacing Density")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appearance.density },
                        set: {
                            engine.settings.appearance.density = $0
                            engine.saveSettings()
                        }
                    )) {
                        ForEach(ThemeDensity.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack {
                    Text("Text Size")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appearance.textSize },
                        set: {
                            engine.settings.appearance.textSize = $0
                            engine.saveSettings()
                        }
                    )) {
                        ForEach(ThemeTextSize.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack(spacing: 12) {
                    Text("Floating Bar Opacity")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Slider(value: Binding(
                        get: { engine.settings.hudOpacity },
                        set: {
                            engine.settings.hudOpacity = $0
                            engine.saveSettings()
                        }
                    ), in: 0.55...1.0, step: 0.02)
                    .frame(width: 150)
                    Text("\(Int(engine.settings.hudOpacity * 100))%")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider().overlay(theme.borderSubtle).padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide From Screen Share")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                        Text("Invisible to Zoom, Google Meet, Teams, and recordings")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { engine.settings.stealthScreenShareProtection },
                        set: {
                            engine.settings.stealthScreenShareProtection = $0
                            engine.saveSettings()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .softCard(background: theme.surface, radius: 14)
        }
    }

    private func colorPickerRow(title: String, hex: String, binding: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(hex)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func colorBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Color> {
        Binding(
            get: { Color(hexString: get()) },
            set: { newColor in
                if let hex = newColor.toHexString() {
                    set(hex)
                }
            }
        )
    }

    private func applyThemeString() {
        guard let parsed = CustomThemeColors.parse(themeString: themeStringInput) else {
            themeStringStatus = "Enter 3 comma-separated hex colors (or paste a Slack theme string)."
            return
        }
        engine.settings.appearance.customColors = parsed
        engine.settings.appearance.preset = .custom
        engine.saveSettings()
        themeStringStatus = "Applied custom theme."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            themeStringStatus = nil
        }
    }
}
