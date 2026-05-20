import AppKit
import Foundation

struct Uninstaller {
    func uninstall() throws {
        try removeHermesAgentData()

        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            if let error {
                NSLog("Failed to move app to Trash: \(error.localizedDescription)")
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    /// Removes HermesAgent's installed runtime, data, logs, preferences, and saved credentials
    /// without moving the .app to Trash. The setup wizard uses this for rollback when the
    /// user navigates back through installation steps.
    func removeHermesAgentData() throws {
        try? LaunchAtLogin.setEnabled(false)
        resetUserDefaults()

        let store = KeychainStore()
        store.removeAllKnownItems(keys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY"] + AuthProviderCatalog.allKeychainKeys)

        let urls = [
            Paths.applicationSupportDirectory,
            Paths.cachesDirectory,
            Paths.logsDirectory,
            Paths.preferencesFile
        ]

        for url in urls {
            try removeIfSafe(url)
        }
    }

    private func resetUserDefaults() {
        let keys = [
            AppSettingKeys.serverPort,
            AppSettingKeys.autoRestartServer,
            AppSettingKeys.dataLocation,
            AppSettingKeys.launchAtLogin,
            AppSettingKeys.checkForUpdatesAutomatically,
            AppSettingKeys.startServerOnLaunch,
            AppSettingKeys.maxLogSizeMB,
            AppSettingKeys.customNodePath,
            AppSettingKeys.environmentVariablesRaw,
            AppSettingKeys.enabledAuthProviders,
            AppSettingKeys.primaryAuthProvider,
            AppSettingKeys.wizardCompleted,
            AppSettingKeys.runtimeSource
        ]

        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for provider in AuthProviderCatalog.providers {
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.authProviderMethodPrefix + provider.id)
        }
        UserDefaults.standard.synchronize()
    }

    private func removeIfSafe(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else { return }
        guard isAllowedRemovalTarget(standardized) else {
            throw UninstallError.unsafePath(standardized.path)
        }
        try FileManager.default.removeItem(at: standardized)
    }

    private func isAllowedRemovalTarget(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.path
        let allowedPrefixes = [
            home + "/Library/Application Support/Hermes Agent",
            home + "/Library/Caches/Hermes Agent",
            home + "/Library/Logs/Hermes Agent",
            home + "/Library/Preferences/com.hermes.app.plist"
        ]
        return allowedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

enum UninstallError: LocalizedError {
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case let .unsafePath(path):
            return "Refusing to remove unsafe path during uninstall: \(path)"
        }
    }
}
