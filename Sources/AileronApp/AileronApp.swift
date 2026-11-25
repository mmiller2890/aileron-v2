import AileronCore
import AppKit
import SwiftUI

@main
@MainActor
final class AileronAppDelegate: NSObject, NSApplicationDelegate {
    private var engine: AileronEngine!
    private var hudController: StealthPanelController!
    private var dashboardController: DashboardWindowController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AileronAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = AileronEngine()

        dashboardController = DashboardWindowController(
            engine: engine,
            onToggleHUD: { [weak self] in
                self?.hudController.toggleVisibility()
            }
        )

        hudController = StealthPanelController(
            engine: engine,
            onOpenDashboard: { [weak self] in
                self?.dashboardController.showAndFocus()
            },
            onReturnToApp: { [weak self] in
                self?.hudController.hide()
                self?.dashboardController.showAndFocus()
            },
            onHideHUD: { [weak self] in
                self?.hudController.hide()
            }
        )

        engine.onStealthSettingChanged = { [weak self] enabled in
            self?.hudController.setStealthProtection(enabled)
            self?.dashboardController.setStealthProtection(enabled)
        }
        engine.onHUDOpacityChanged = { [weak self] opacity in
            self?.hudController.setOpacity(opacity)
        }
        engine.onAppearanceChanged = { [weak self] appearance in
            self?.hudController.applyAppearance(appearance)
            self?.dashboardController.applyAppearance(appearance)
        }

        hotKeyManager = HotKeyManager { [weak self] key in
            self?.handleHotKey(key)
        }

        setupMainMenu()
        setupStatusBarItem()

        dashboardController.showAndFocus()
        hudController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardController.showAndFocus()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stopListening()
        engine.persistSessionNow()
    }

    private func handleHotKey(_ key: AileronHotKey) {
        switch key {
        case .toggleHUD:
            hudController.toggleVisibility()
        case .toggleDashboard:
            dashboardController.toggle()
        case .toggleListening:
            engine.toggleListening()
        case .answerLast:
            hudController.show()
            engine.answerLastUtterance()
        case .captureScreen:
            hudController.show()
            engine.captureScreen(analyzeImmediately: true)
        case .toggleMic:
            hudController.show()
            engine.toggleMicDictation()
        }
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aileron")
            button.toolTip = "Aileron"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Floating Bar (⌘\\)", action: #selector(menuToggleHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Return Floating Bar to App", action: #selector(menuReturnToApp), keyEquivalent: "")
        menu.addItem(withTitle: "Open Aileron Window (⌘⇧D)", action: #selector(menuOpenDashboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Start / Stop Listening (⌘⇧A)", action: #selector(menuToggleListening), keyEquivalent: "")
        menu.addItem(withTitle: "Answer Last Utterance (⌘⇧L)", action: #selector(menuAnswerLast), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Screen & Analyze (⌘⇧S)", action: #selector(menuCaptureScreen), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Aileron", action: #selector(menuQuit), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Aileron", action: #selector(menuOpenDashboard), keyEquivalent: "d")
        appMenu.addItem(withTitle: "Toggle Floating Bar", action: #selector(menuToggleHUD), keyEquivalent: "\\")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Aileron", action: #selector(menuQuit), keyEquivalent: "q")
        for item in appMenu.items { item.target = self }
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(menuToggleSidebar), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .option]
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)

        let transcriptItem = NSMenuItem(title: "Toggle Transcript Panel", action: #selector(menuToggleTranscript), keyEquivalent: "t")
        transcriptItem.keyEquivalentModifierMask = [.command, .option]
        transcriptItem.target = self
        viewMenu.addItem(transcriptItem)
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuToggleHUD() { hudController.toggleVisibility() }
    @objc private func menuReturnToApp() {
        hudController.hide()
        dashboardController.showAndFocus()
    }
    @objc private func menuOpenDashboard() { dashboardController.showAndFocus() }
    @objc private func menuToggleSidebar() { dashboardController.layoutState.toggleNavSidebar() }
    @objc private func menuToggleTranscript() { dashboardController.layoutState.toggleTranscriptDrawer() }
    @objc private func menuToggleListening() { engine.toggleListening() }
    @objc private func menuAnswerLast() {
        hudController.show()
        engine.answerLastUtterance()
    }
    @objc private func menuCaptureScreen() {
        hudController.show()
        engine.captureScreen(analyzeImmediately: true)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
