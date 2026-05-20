import AppKit
import SwiftUI

struct QuickActions: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                appState.openInBrowser()
            } label: {
                Label(L("Open in Browser"), systemImage: "safari")
            }
            .disabled(appState.serverStatus != .running)

            Button {
                Task { await appState.restartServer() }
            } label: {
                Label(L("Restart Server"), systemImage: "arrow.clockwise")
            }

            Button {
                appState.stopServer()
            } label: {
                Label(L("Stop Server"), systemImage: "pause")
            }
            .disabled(appState.serverStatus == .stopped)

            Divider()

            Button {
                NSWorkspace.shared.open(Paths.logsDirectory)
            } label: {
                Label(L("View Logs"), systemImage: "doc.text.magnifyingglass")
            }

            Button {
                openPreferences()
            } label: {
                Label(L("Preferences..."), systemImage: "gearshape")
            }

            Button {
                appState.updateManager?.checkForUpdates()
            } label: {
                Label(L("Check for Updates..."), systemImage: "sparkles")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L("Quit Hermes Agent"), systemImage: "power")
            }
        }
        .buttonStyle(.plain)
    }

    private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
