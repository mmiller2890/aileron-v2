import AileronCore
import Observation
import SwiftUI

@MainActor
@Observable
public final class DashboardLayoutState {
    public var showNavSidebar: Bool = true
    public var showTranscriptDrawer: Bool = false
    public var showSessionsList: Bool = true
    public var showProfilesList: Bool = true

    public init() {}

    public func toggleNavSidebar() {
        withAnimation(.snappy(duration: 0.22)) {
            showNavSidebar.toggle()
        }
    }

    public func toggleTranscriptDrawer() {
        withAnimation(.snappy(duration: 0.22)) {
            showTranscriptDrawer.toggle()
        }
    }
}

public enum DashboardTab: String, CaseIterable, Identifiable {
    case live = "Live"
    case sessions = "Sessions"
    case prep = "Prep"
    case models = "Models"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .live: return "waveform"
        case .sessions: return "clock"
        case .prep: return "doc.text"
        case .models: return "sparkles"
        case .settings: return "gearshape"
        }
    }
}

public struct DashboardView: View {
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState
    public let onToggleHUD: () -> Void

    public var body: some View {
        DashboardRootContent(engine: engine, layout: layout, onToggleHUD: onToggleHUD)
            .aileronTheme(engine.settings.appearance)
    }
}

private struct DashboardRootContent: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable var engine: AileronEngine
    @Bindable var layout: DashboardLayoutState
    let onToggleHUD: () -> Void
    @State private var selectedTab: DashboardTab = .live

    var body: some View {
        HStack(spacing: 0) {
            if layout.showNavSidebar {
                navigationSidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle()
                    .fill(theme.sidebarDivider)
                    .frame(width: 1)
            }

            VStack(spacing: 0) {
                if let notice = engine.bannerNotice {
                    noticeStrip(notice)
                }

                switch selectedTab {
                case .live:
                    LiveStudioView(engine: engine, layout: layout, onToggleHUD: onToggleHUD)
                case .sessions:
                    SessionsLibraryView(engine: engine, layout: layout, onOpenInLive: {
                        selectedTab = .live
                    })
                case .prep:
                    PrepProfilesView(engine: engine, layout: layout)
                case .models:
                    ProvidersAndSpeechView(engine: engine, layout: layout)
                case .settings:
                    SettingsPanelView(engine: engine, layout: layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.canvas)
        }
        .background(theme.canvas)
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                AileronLogo(size: 24, framed: true)
                AileronWordmark(height: 12.5, color: theme.sidebarTextPrimary)
                Spacer()
                Button {
                    layout.toggleNavSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(QuietIconButtonStyle(onSidebar: true))
                .help("Hide Sidebar (⌘⌥S)")
            }
            .padding(.top, 38)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(DashboardTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                                .frame(width: 18)
                                .foregroundStyle(isSelected ? theme.sidebarSelectionText : theme.sidebarTextSecondary)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? theme.sidebarSelectionText : theme.sidebarTextSecondary)

                            Spacer()

                            if tab == .live && engine.telemetry.isCapturing {
                                Circle()
                                    .fill(theme.live)
                                    .frame(width: 6.5, height: 6.5)
                            } else if tab == .sessions && !engine.sessionList.isEmpty {
                                Text("\(engine.sessionList.count)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.sidebarTextTertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? theme.sidebarSelectionFill : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    onToggleHUD()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "pip")
                            .font(.system(size: 12))
                        Text("Floating Bar")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        Text("⌘\\")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.sidebarTextTertiary)
                    }
                    .foregroundStyle(theme.sidebarTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.sidebarSelectionFill.opacity(0.55))
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Circle()
                        .fill(engine.settings.stealthScreenShareProtection ? theme.live : theme.sidebarTextTertiary)
                        .frame(width: 6.5, height: 6.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.settings.config(for: engine.settings.activeProvider).model)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.sidebarTextSecondary)
                            .lineLimit(1)
                        Text(engine.settings.stealthScreenShareProtection ? "Hidden from screen share" : "Visible to screen share")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.sidebarTextTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .padding(12)
        }
        .frame(width: 212)
        .background(
            LinearGradient(
                colors: [theme.sidebarTop, theme.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func noticeStrip(_ notice: EngineNotice) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(notice.level == .error ? theme.danger : (notice.level == .warning ? theme.warn : theme.live))
                .frame(width: 6, height: 6)
            Text(notice.message)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                engine.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
        }
    }
}
