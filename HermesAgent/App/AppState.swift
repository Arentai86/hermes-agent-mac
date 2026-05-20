import AppKit
import Combine
import Foundation
import SwiftUI

enum ServerStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    var title: String {
        switch self {
        case .stopped:
            return L("Hermes Agent is stopped")
        case .starting:
            return L("Hermes Agent is starting")
        case .running:
            return L("Hermes Agent is running")
        case .stopping:
            return L("Hermes Agent is stopping")
        case let .error(message):
            return LF("Hermes Agent error: %@", message)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStatus: ServerStatus = .stopped
    @Published var currentPort: Int = AppSettings.serverPort
    @Published var lastError: String?
    @Published var isFirstRun = false
    @Published var serverStartedAt: Date?

    var updateManager: UpdateManager?

    private let installer = FirstRunInstaller()
    private let serverManager = ServerManager()
    private var didBootstrap = false
    private var localizationObserver: AnyCancellable?

    var serverUptime: TimeInterval? {
        guard let serverStartedAt else { return nil }
        return Date().timeIntervalSince(serverStartedAt)
    }

    private init() {
        serverManager.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.serverStatus = status
                switch status {
                case .running:
                    if self?.serverStartedAt == nil {
                        self?.serverStartedAt = Date()
                    }
                    self?.lastError = nil
                case .stopped, .error:
                    self?.serverStartedAt = nil
                case .starting, .stopping:
                    break
                }
            }
        }
        serverManager.onPortDetected = { [weak self] port in
            Task { @MainActor in
                self?.currentPort = port
            }
        }
        serverManager.onError = { [weak self] message in
            Task { @MainActor in
                self?.lastError = message
                self?.serverStatus = .error(message)
                self?.serverStartedAt = nil
            }
        }

        // Bridge language changes to AppState so every view that observes AppState (via
        // @EnvironmentObject or @StateObject) re-renders when the user picks a new language.
        localizationObserver = AppLocalization.shared.$languageCode
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        do {
            isFirstRun = try installer.installOrMigrateIfNeeded()
            currentPort = AppSettings.serverPort
            if RuntimeBundle().requiresRuntimeSetup {
                let message = L("Hermes Agent runtime is not installed yet. Choose a real runtime before starting the server.")
                isFirstRun = true
                lastError = message
                serverStatus = .error(message)
            }
            // This installer build must ask on launch whether to install/start HermesAgent or
            // remove it. The first screen is intentionally English-only.
            WizardWindowController.shared.show(appState: self)
        } catch {
            lastError = error.localizedDescription
            serverStatus = .error(error.localizedDescription)
        }
    }

    func startServer() async {
        lastError = nil

        if RuntimeBundle().requiresRuntimeSetup {
            let message = L("Hermes Agent runtime is not installed yet. Choose a real runtime before starting the server.")
            lastError = message
            serverStatus = .error(message)
            WizardWindowController.shared.show(appState: self)
            return
        }

        serverStatus = .starting

        do {
            guard let port = PortManager().firstAvailablePort(startingAt: AppSettings.serverPort) else {
                let message = L("No available local port in the Hermes Agent range.")
                lastError = message
                serverStatus = .error(message)
                return
            }
            currentPort = port
            let token = try AuthToken.ensureToken(in: AppSettings.dataLocationURL)
            try serverManager.start(
                preferredPort: port,
                dataDirectory: AppSettings.dataLocationURL,
                autoRestart: AppSettings.autoRestartServer
            )
            let isHealthy = await waitForHealthyServer(token: token, timeout: 20)
            if !isHealthy {
                lastError = L("Server did not pass health check within 20 seconds.")
                serverStatus = .error(lastError ?? L("Health check failed."))
            }
        } catch {
            lastError = error.localizedDescription
            serverStatus = .error(error.localizedDescription)
        }
    }

    func stopServer() {
        serverStatus = .stopping
        serverManager.stop()
        serverStartedAt = nil
        serverStatus = .stopped
    }

    func restartServer() async {
        stopServer()
        await startServer()
    }

    func openInBrowser() {
        if RuntimeBundle().requiresRuntimeSetup {
            lastError = L("Hermes Agent runtime is not installed yet. Choose a real runtime before starting the server.")
            WizardWindowController.shared.show(appState: self)
            return
        }
        guard currentPort > 0 else { return }
        let token = try? AuthToken.ensureToken(in: AppSettings.dataLocationURL)
        if let token, let url = RuntimeBundle().browserURL(port: currentPort, token: token) {
            NSWorkspace.shared.open(url)
        }
    }

    private func waitForHealthyServer(token: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await HealthCheck().ping(port: currentPort, token: token) {
                serverStatus = .running
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    func stopServerForTermination() {
        serverManager.stopForTermination()
    }
}
