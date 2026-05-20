import Darwin
import Foundation

enum RuntimeError: LocalizedError {
    case missingResource(String)
    case placeholderRuntime

    var errorDescription: String? {
        switch self {
        case let .missingResource(path):
            return "Missing bundled runtime resource: \(path)"
        case .placeholderRuntime:
            return "Hermes Agent runtime is not installed yet. Choose a real runtime before starting the dashboard."
        }
    }
}

struct RuntimeManifest: Decodable {
    let version: String?
    let node: String?
    let source: String?
    let kind: String?
    let runtime: String?
    let fallback: Bool?
    let placeholder: Bool?
}

struct RuntimeBundle {
    var userInstalledRuntimeDirectory: URL {
        Paths.applicationSupportDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    var bundledRuntimeDirectory: URL {
        Bundle.main.resourceURL?.appendingPathComponent("runtime", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/runtime", isDirectory: true)
    }

    var runtimeDirectory: URL {
        if userInstalledRuntimeIsUsable {
            return userInstalledRuntimeDirectory
        }
        return bundledRuntimeDirectory
    }

    var requiresRuntimeSetup: Bool {
        !isUsableRuntime(at: runtimeDirectory)
    }

    var bundledRuntimeIsUsable: Bool {
        isUsableRuntime(at: bundledRuntimeDirectory)
    }

    var bundledNodeIsAvailable: Bool {
        runnerURL(in: bundledRuntimeDirectory).map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    }

    var userInstalledRuntimeIsUsable: Bool {
        isUsableRuntime(at: userInstalledRuntimeDirectory)
    }

    /// Kept with the old method name so the rest of the launcher can stay generic.
    /// For Hermes this is the runtime launcher script, not Node.js.
    func nodeExecutableURL() throws -> URL {
        if !AppSettings.customNodePath.isEmpty {
            let custom = URL(fileURLWithPath: AppSettings.customNodePath)
            if FileManager.default.isExecutableFile(atPath: custom.path) {
                return custom
            }
        }
        for base in [userInstalledRuntimeDirectory, bundledRuntimeDirectory] {
            if let runner = runnerURL(in: base),
               FileManager.default.isExecutableFile(atPath: runner.path) {
                return runner
            }
        }
        throw RuntimeError.missingResource("runtime/bin/run-hermes-dashboard.sh")
    }

    func serverEntryPointURL() throws -> URL {
        if let entry = serverEntryPointURL(in: runtimeDirectory) {
            return entry
        }
        throw RuntimeError.missingResource("runtime/server/hermes")
    }

    func serverArguments(port: Int, dataDirectory: URL, tokenFile: URL, token: String) throws -> [String] {
        _ = try serverEntryPointURL()
        return [
            "--port", "\(port)",
            "--data-dir", dataDirectory.path,
            "--token-file", tokenFile.path
        ]
    }

    func prepareRuntimeConfiguration(port: Int, token: String, dataDirectory: URL) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDirectory.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
    }

    func browserURL(port: Int, token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/"
        return components.url
    }

    func serverEnvironment(port: Int, token: String, dataDirectory: URL) -> [String: String] {
        var environment = AppSettings.environmentVariables
        let authEnvironment = AuthProviderCatalog.environmentVariables(
            store: KeychainStore(),
            enabledProviderIDs: AppSettings.enabledAuthProviderIDs
        )
        environment.merge(authEnvironment) { _, new in new }

        let serverDirectory = runtimeDirectory.appendingPathComponent("server", isDirectory: true)
        let webDist = serverDirectory.appendingPathComponent("hermes_cli/web_dist", isDirectory: true)
        let binDirectory = runtimeDirectory.appendingPathComponent("bin", isDirectory: true)
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"

        environment["HERMES_HOME"] = dataDirectory.path
        environment["HERMES_LAUNCHER_PORT"] = "\(port)"
        environment["HERMES_LAUNCHER_DATA_DIR"] = dataDirectory.path
        environment["HERMES_WEB_DIST"] = webDist.path
        environment["HERMES_DASHBOARD_TUI"] = "1"
        environment["HERMES_QUIET"] = "1"
        environment["PYTHONPATH"] = serverDirectory.path
        environment["PATH"] = "\(binDirectory.path):\(serverDirectory.appendingPathComponent("venv/bin").path):\(existingPath)"
        return environment
    }

    func isFallbackRuntime(at directory: URL) -> Bool {
        guard let manifest = manifest(in: directory) else { return false }
        if manifest.fallback == true || manifest.placeholder == true {
            return true
        }
        let markerValues = [manifest.version, manifest.source, manifest.kind, manifest.runtime]
            .compactMap { $0?.lowercased() }
        return markerValues.contains { value in
            value.contains("fallback") || value.contains("placeholder") || value.contains("smoke-test")
        }
    }

    private func isUsableRuntime(at directory: URL) -> Bool {
        guard let runner = runnerURL(in: directory),
              FileManager.default.isExecutableFile(atPath: runner.path),
              let server = serverEntryPointURL(in: directory),
              FileManager.default.fileExists(atPath: server.path),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("server/hermes_cli/web_dist/index.html").path) else {
            return false
        }
        return !isFallbackRuntime(at: directory)
    }

    private func runnerURL(in directory: URL) -> URL? {
        directory.appendingPathComponent("bin/run-hermes-dashboard.sh")
    }

    private func serverEntryPointURL(in directory: URL) -> URL? {
        let candidates = [
            directory.appendingPathComponent("server/hermes"),
            directory.appendingPathComponent("server/hermes_cli/main.py")
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func manifest(in directory: URL) -> RuntimeManifest? {
        let url = directory.appendingPathComponent("version.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RuntimeManifest.self, from: data)
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}
