import AppKit
import Foundation

@MainActor
final class ServerManager {
    var onStatusChange: ((ServerStatus) -> Void)?
    var onPortDetected: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private var process: ServerProcess?
    private var healthTimer: DispatchSourceTimer?
    private var activityToken: NSObjectProtocol?
    private var restartAttempt = 0
    private var shouldAutoRestart = true
    private var configuredPort = AppSettings.serverPort
    private var configuredDataDirectory = AppSettings.dataLocationURL
    private let runtime = RuntimeBundle()

    func start(preferredPort: Int, dataDirectory: URL, autoRestart: Bool) throws {
        stop()

        shouldAutoRestart = autoRestart
        configuredPort = preferredPort
        configuredDataDirectory = dataDirectory

        try DependencyResolver(runtime: runtime).validate()
        try FileManager.default.createDirectory(at: Paths.logsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        let token = try AuthToken.ensureToken(in: dataDirectory)
        try runtime.prepareRuntimeConfiguration(port: preferredPort, token: token, dataDirectory: dataDirectory)
        try HermesAgentModelAuthConfigurator().prepareModelAuth(dataDirectory: dataDirectory)
        let logURL = Paths.logsDirectory.appendingPathComponent("server.log")
        let process = try ServerProcess(
            executableURL: runtime.nodeExecutableURL(),
            arguments: runtime.serverArguments(
                port: preferredPort,
                dataDirectory: dataDirectory,
                tokenFile: dataDirectory.appendingPathComponent("auth_token"),
                token: token
            ),
            environment: runtime.serverEnvironment(port: preferredPort, token: token, dataDirectory: dataDirectory),
            logURL: logURL
        )

        process.onStdoutLine = { [weak self] line in
            Task { @MainActor in
                self?.handleServerLine(line)
            }
        }
        process.onStderrLine = { [weak self] line in
            Task { @MainActor in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self?.appendDiagnostic("stderr: \(trimmed)")
            }
        }
        process.onTermination = { [weak self] terminationStatus in
            Task { @MainActor in
                self?.handleTermination(status: terminationStatus)
            }
        }

        self.process = process
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Hermes Agent local server is running"
        )
        activityToken = activity
        onStatusChange?(.starting)
        do {
            try process.start()
        } catch {
            ProcessInfo.processInfo.endActivity(activity)
            activityToken = nil
            self.process = nil
            throw error
        }
        startHealthChecks(port: preferredPort, token: token)
    }

    func stop() {
        healthTimer?.cancel()
        healthTimer = nil
        shouldAutoRestart = false
        process?.terminate(gracePeriod: 5)
        process = nil
        endActivity()
        onStatusChange?(.stopped)
    }

    func stopForTermination() {
        healthTimer?.cancel()
        healthTimer = nil
        shouldAutoRestart = false
        process?.terminate(gracePeriod: 5)
        endActivity()
    }

    private func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    private func handleServerLine(_ line: String) {
        appendDiagnostic("stdout: \(line)")
        if let port = parseListeningPort(from: line) {
            configuredPort = port
            onPortDetected?(port)
            onStatusChange?(.running)
        }
    }

    private func parseListeningPort(from line: String) -> Int? {
        guard let range = line.range(of: "LISTENING_ON:") else { return nil }
        let suffix = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(suffix)
    }

    private func handleTermination(status: Int32) {
        healthTimer?.cancel()
        healthTimer = nil
        process = nil

        guard shouldAutoRestart else {
            onStatusChange?(.stopped)
            return
        }

        let delay = min(pow(2.0, Double(restartAttempt)), 30.0)
        restartAttempt += 1
        onError?("Server exited with status \(status). Restarting in \(Int(delay))s.")

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.shouldAutoRestart else { return }
            do {
                try self.start(
                    preferredPort: self.configuredPort,
                    dataDirectory: self.configuredDataDirectory,
                    autoRestart: self.shouldAutoRestart
                )
            } catch {
                self.onError?(error.localizedDescription)
            }
        }
    }

    private func startHealthChecks(port: Int, token: String) {
        healthTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                let isHealthy = await HealthCheck().ping(port: port, token: token)
                guard let self else { return }
                if isHealthy {
                    self.restartAttempt = 0
                    self.onPortDetected?(port)
                    self.onStatusChange?(.running)
                }
            }
        }
        timer.resume()
        healthTimer = timer
    }

    private func appendDiagnostic(_ line: String) {
        let message = "[\(Date())] \(line)\n"
        guard let data = message.data(using: .utf8) else { return }
        let url = Paths.logsDirectory.appendingPathComponent("launcher.log")
        try? FileManager.default.createDirectory(at: Paths.logsDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            }
        } else {
            try? data.write(to: url)
        }
    }
}
