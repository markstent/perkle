import SwiftUI
import AppKit

/// A menu bar app that nudges you to stand on a schedule,
/// timed around the meetings in your calendars.
@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(AppState.shared)
        } label: {
            MenuBarLabel()
                .environmentObject(AppState.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}
