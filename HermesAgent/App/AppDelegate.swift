import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updateManager: UpdateManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let updateManager = UpdateManager()
        self.updateManager = updateManager
        AppState.shared.updateManager = updateManager
        updateManager.automaticallyChecksForUpdates = AppSettings.checkForUpdatesAutomatically

        Task { @MainActor in
            await AppState.shared.bootstrapIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopServerForTermination()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme?.lowercased() == "hermes" else { continue }
            NSApp.activate(ignoringOtherApps: true)
            switch url.host?.lowercased() {
            case "settings", "preferences":
                if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            case "restart":
                Task { @MainActor in await AppState.shared.restartServer() }
            case "stop":
                AppState.shared.stopServer()
            case "open", nil:
                AppState.shared.openInBrowser()
            default:
                break
            }
        }
    }
}
