import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updateManager: UpdateManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if shouldQuitAfterDiskImageWarning() {
            return
        }

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

    private func shouldQuitAfterDiskImageWarning() -> Bool {
        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasPrefix("/Volumes/") else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Move Hermes Agent to Applications")
        alert.informativeText = L("Hermes Agent is running from a mounted disk image. Quit the app, copy HermesAgent.app to Applications, then open it from there so macOS can eject the disk image cleanly.")
        alert.addButton(withTitle: L("Quit"))
        alert.addButton(withTitle: L("Continue Anyway"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
            return true
        }
        return false
    }
}
