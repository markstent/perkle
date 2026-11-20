import SwiftUI
import AppKit
import QuartzCore

/// A borderless panel that floats above other windows without stealing focus
/// from the app you're typing in.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, level windowLevel: NSWindow.Level = .floating) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = windowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        appearance = NSAppearance(named: .aqua)
    }

    // Can take clicks on its buttons, but never becomes the main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Opens and closes every window the app shows: the corner nudge, the
/// full-screen break, Settings and the welcome window.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var nudgePanel: FloatingPanel?
    private var insistPanels: [FloatingPanel] = []
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var alertIsPreview = false

    private init() {}

    // MARK: Corner nudge

    func showNudge(preview: Bool = false) {
        closeAlerts()
        alertIsPreview = preview
        let state = AppState.shared

        let size = NudgeView.panelSize
        let hosting = NSHostingView(rootView: NudgeView(preview: preview).environmentObject(state))
        hosting.frame = NSRect(origin: .zero, size: size)

        let visible = Self.activeScreen().visibleFrame
        let finalOrigin = NSPoint(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 8)
        let startFrame = NSRect(origin: NSPoint(x: finalOrigin.x + 48, y: finalOrigin.y), size: size)

        let panel = FloatingPanel(contentRect: startFrame)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(origin: finalOrigin, size: size), display: true)
            panel.animator().alphaValue = 1
        }

        nudgePanel = panel
        state.nudgeVisible = true
        scheduleAutoDismiss()
    }

    func closeNudge() {
        guard let panel = nudgePanel else { return }
        nudgePanel = nil
        cancelAutoDismiss()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            panel.orderOut(nil)
        }
        updateVisibility()
    }

    // MARK: Full-screen break ("Insist")

    func showInsist(preview: Bool = false) {
        closeAlerts()
        alertIsPreview = preview
        let state = AppState.shared
        let main = Self.activeScreen()

        for screen in NSScreen.screens {
            let panel = FloatingPanel(contentRect: screen.frame, level: .screenSaver)
            let view = InsistView(showCard: screen == main, preview: preview).environmentObject(state)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hosting
            panel.setFrame(screen.frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                panel.animator().alphaValue = 1
            }
            insistPanels.append(panel)
        }

        state.nudgeVisible = true
        scheduleAutoDismiss()
    }

    func closeInsist() {
        guard !insistPanels.isEmpty else { return }
        let panels = insistPanels
        insistPanels = []
        cancelAutoDismiss()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            for panel in panels { panel.animator().alphaValue = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            for panel in panels { panel.orderOut(nil) }
        }
        updateVisibility()
    }

    func closeAlerts() {
        closeNudge()
        closeInsist()
    }

    // MARK: Auto-dismiss

    func cancelAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        let seconds = max(AppState.shared.settings.autoDismissSeconds, 10)
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            let manager = WindowManager.shared
            if manager.alertIsPreview {
                manager.closeAlerts()
            } else {
                AppState.shared.noResponse()
            }
        }
    }

    private func updateVisibility() {
        AppState.shared.nudgeVisible = nudgePanel != nil || !insistPanels.isEmpty
    }

    // MARK: Settings & welcome

    func showSettings(section: SettingsSection? = nil) {
        let state = AppState.shared
        if let section { state.settingsSection = section }

        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environmentObject(state))
            let window = NSWindow(contentViewController: controller)
            window.title = "\(AppInfo.name) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(SettingsView.windowSize)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showWelcome() {
        let state = AppState.shared
        if welcomeWindow == nil {
            let controller = NSHostingController(rootView: WelcomeView().environmentObject(state))
            let window = NSWindow(contentViewController: controller)
            window.title = "Welcome to \(AppInfo.name)"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(WelcomeView.windowSize)
            window.center()
            welcomeWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func closeWelcome() {
        welcomeWindow?.close()
    }

    // MARK: Helpers

    /// The screen the mouse pointer is on, so nudges appear where you're looking.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}
