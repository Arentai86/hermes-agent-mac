import SwiftUI

@main
struct HermesAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var localization = AppLocalization.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(localization)
                .environment(\.layoutDirection, localization.layoutDirection)
        } label: {
            StatusIndicator(status: appState.serverStatus)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesWindow()
                .environmentObject(appState)
                .environmentObject(localization)
                .environment(\.layoutDirection, localization.layoutDirection)
        }
    }
}

