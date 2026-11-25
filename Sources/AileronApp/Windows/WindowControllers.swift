import AileronCore
import AppKit
import SwiftUI

public final class StealthPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

private func nsAppearance(for mode: ThemeColorMode) -> NSAppearance? {
    switch mode {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
}

@MainActor
public final class StealthPanelController {
    public let panel: StealthPanel
    private let width: CGFloat = 620
    private let collapsedHeight: CGFloat = 54
    private let expandedHeight: CGFloat = 390
    private var isExpanded = false

    public init(
        engine: AileronEngine,
        onOpenDashboard: @escaping () -> Void,
        onReturnToApp: @escaping () -> Void,
        onHideHUD: @escaping () -> Void
    ) {
        let initialRect = NSRect(x: 0, y: 0, width: width, height: collapsedHeight)
        let panel = StealthPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = nsAppearance(for: engine.settings.appearance.colorMode)
        panel.sharingType = engine.settings.stealthScreenShareProtection ? .none : .readOnly
        panel.alphaValue = CGFloat(max(0.5, min(1.0, engine.settings.hudOpacity)))
        self.panel = panel

        let rootView = HUDView(
            engine: engine,
            onExpandedChanged: { [weak self] expanded in
                self?.setExpanded(expanded)
            },
            onOpenDashboard: onOpenDashboard,
            onReturnToApp: onReturnToApp,
            onHideHUD: onHideHUD
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        positionAtTopCenter()
    }

    public func positionAtTopCenter() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.maxY - panel.frame.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    public func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        let targetHeight = expanded ? expandedHeight : collapsedHeight
        var frame = panel.frame
        let topY = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = topY - targetHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func toggleVisibility() {
        if panel.isVisible {
            hide()
        } else {
            show()
            panel.makeKey()
        }
    }

    public func setStealthProtection(_ enabled: Bool) {
        panel.sharingType = enabled ? .none : .readOnly
    }

    public func setOpacity(_ opacity: Double) {
        panel.alphaValue = CGFloat(max(0.45, min(1.0, opacity)))
    }

    public func applyAppearance(_ appearance: AppearanceSettings) {
        panel.appearance = nsAppearance(for: appearance.colorMode)
    }
}

@MainActor
public final class DashboardWindowController: NSObject, NSWindowDelegate {
    public let window: NSWindow
    public let layoutState = DashboardLayoutState()

    public init(engine: AileronEngine, onToggleHUD: @escaping () -> Void) {
        let rect = NSRect(x: 0, y: 0, width: 1080, height: 720)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Aileron"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 500)
        window.sharingType = engine.settings.stealthScreenShareProtection ? .none : .readOnly
        window.center()
        self.window = window
        super.init()

        applyAppearance(engine.settings.appearance)
        window.delegate = self
        let hosting = NSHostingView(rootView: DashboardView(
            engine: engine,
            layout: layoutState,
            onToggleHUD: onToggleHUD
        ))
        window.contentView = hosting
    }

    public func applyAppearance(_ appearance: AppearanceSettings) {
        window.appearance = nsAppearance(for: appearance.colorMode)
        switch appearance.colorMode {
        case .light:
            window.backgroundColor = NSColor.white
        case .dark:
            window.backgroundColor = NSColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1.0)
        case .system:
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }

    public func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func toggle() {
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showAndFocus()
        }
    }

    public func setStealthProtection(_ enabled: Bool) {
        window.sharingType = enabled ? .none : .readOnly
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
