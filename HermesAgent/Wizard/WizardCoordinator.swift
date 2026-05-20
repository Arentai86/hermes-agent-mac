import AppKit
import Foundation

@MainActor
final class WizardCoordinator: ObservableObject {
    enum Step: Int, CaseIterable {
        case setupAction
        case language
        case welcome
        case systemCheck
        case source
        case dataLocation
        case port
        case apiKeys
        case skills
        case finish
    }

    @Published var step: Step
    @Published var canContinue = true
    @Published var isFinishing = false
    @Published var finishError: String?
    @Published var actionError: String?
    @Published var isPerformingAction = false

    let appState: AppState

    private let runtimeWasInstalledAtStart: Bool
    private var didInstallRuntimeThisSession = false
    private var installedSkillIDsThisSession = Set<String>()

    init(appState: AppState) {
        self.appState = appState
        self.runtimeWasInstalledAtStart = RuntimeInstaller().isInstalled
        self.step = .setupAction
    }

    var canShowBackArrow: Bool {
        step != .setupAction && !isPerformingAction && !isFinishing
    }

    func chooseInstall() async {
        actionError = nil
        isPerformingAction = true
        defer { isPerformingAction = false }

        if RuntimeBundle().userInstalledRuntimeIsUsable,
           UserDefaults.standard.bool(forKey: AppSettingKeys.wizardCompleted) {
            await appState.startServer()
            if case let .error(message) = appState.serverStatus {
                actionError = message
                return
            }
            appState.openInBrowser()
            WizardWindowController.shared.closeWizard()
            return
        }

        if !AppLocalization.shared.hasUserSelection {
            step = .language
        } else {
            step = .welcome
        }
        canContinue = true
    }

    func chooseUninstall() {
        actionError = nil
        let alert = NSAlert()
        alert.messageText = "Uninstall Hermes Agent?"
        alert.informativeText = "This will stop Hermes Agent, remove its local data, logs, settings, saved credentials, and move the app to Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall Hermes Agent")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isPerformingAction = true
        do {
            appState.stopServer()
            try Uninstaller().uninstall()
        } catch {
            isPerformingAction = false
            actionError = error.localizedDescription
        }
    }

    func markRuntimeInstalled() {
        didInstallRuntimeThisSession = true
    }

    func markSkillsInstalled(_ skillIDs: Set<String>) {
        installedSkillIDsThisSession.formUnion(skillIDs)
    }

    func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        canContinue = true
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        rollbackMovingBack(to: previous)
        step = previous
        canContinue = true
    }

    func finish() async {
        isFinishing = true
        finishError = nil

        do {
            try LaunchAtLogin.setEnabled(AppSettings.launchAtLogin)
            await appState.startServer()
            if case let .error(message) = appState.serverStatus {
                throw NSError(domain: "Hermes Agent", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            FirstRunInstaller().markWizardCompleted()
            appState.openInBrowser()
            WizardWindowController.shared.closeWizard()
        } catch {
            finishError = error.localizedDescription
        }

        isFinishing = false
    }

    private func rollbackMovingBack(to previous: Step) {
        finishError = nil
        actionError = nil

        if previous.rawValue <= Step.skills.rawValue {
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.launchAtLogin)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.checkForUpdatesAutomatically)
        }

        if previous.rawValue <= Step.apiKeys.rawValue {
            clearInstalledSkills()
        }

        if previous.rawValue <= Step.port.rawValue {
            clearAuthorizationSettings()
        }

        if previous.rawValue <= Step.dataLocation.rawValue {
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.serverPort)
        }

        if previous.rawValue <= Step.source.rawValue {
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.dataLocation)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.runtimeSource)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.wizardCompleted)
            if shouldRemoveRuntimeDuringRollback {
                try? RuntimeInstaller().uninstall()
                didInstallRuntimeThisSession = false
            }
        }

        if previous.rawValue <= Step.language.rawValue {
            appState.stopServer()
            if shouldRemoveRuntimeDuringRollback {
                try? RuntimeInstaller().uninstall()
                didInstallRuntimeThisSession = false
            }
            clearAuthorizationSettings()
            clearInstalledSkills()
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.dataLocation)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.serverPort)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.runtimeSource)
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.wizardCompleted)
        }

        if previous == .setupAction {
            try? Uninstaller().removeHermesAgentData()
            installedSkillIDsThisSession.removeAll()
            AppLocalization.shared.resetSelectionToSystemLanguage()
        }
    }

    private var shouldRemoveRuntimeDuringRollback: Bool {
        didInstallRuntimeThisSession || (!runtimeWasInstalledAtStart && RuntimeInstaller().isInstalled)
    }

    private func clearAuthorizationSettings() {
        let store = KeychainStore()
        store.removeAllKnownItems(keys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY"] + AuthProviderCatalog.allKeychainKeys)
        UserDefaults.standard.removeObject(forKey: AppSettingKeys.enabledAuthProviders)
        UserDefaults.standard.removeObject(forKey: AppSettingKeys.primaryAuthProvider)
        for provider in AuthProviderCatalog.providers {
            UserDefaults.standard.removeObject(forKey: AppSettingKeys.authProviderMethodPrefix + provider.id)
        }
    }

    private func clearInstalledSkills() {
        guard !installedSkillIDsThisSession.isEmpty else { return }
        try? OfficialSkillInstaller().uninstallOfficialSkills(skillIDs: installedSkillIDsThisSession)
        installedSkillIDsThisSession.removeAll()
    }
}
