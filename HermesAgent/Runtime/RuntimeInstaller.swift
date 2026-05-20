import Foundation

/// Installs a Hermes Agent server tree into Application Support.
/// Python dependencies are resolved by the bundled runner script at launch time.
struct RuntimeInstaller {
    enum Source: Equatable {
        case bundled
        case download
        case url(URL)
        case local(server: URL)
    }

    enum InstallError: LocalizedError {
        case missingServer
        case unsupportedArchive(URL)
        case missingServerEntryPoint
        case missingWebDashboard
        case extractionFailed(String)
        case downloadFailed(String)
        case writeFailed(String)
        case placeholderBundledRuntime

        var errorDescription: String? {
            switch self {
            case .missingServer:
                return L("Hermes Agent server location is required.")
            case let .unsupportedArchive(url):
                return LF("Unsupported archive format: %@", url.lastPathComponent)
            case .missingServerEntryPoint:
                return L("Hermes Agent server package did not contain a runnable entry point.")
            case .missingWebDashboard:
                return L("Hermes Agent server package does not contain the built web dashboard.")
            case let .extractionFailed(text):
                return LF("Extraction failed: %@", text)
            case let .downloadFailed(text):
                return LF("Download failed: %@", text)
            case let .writeFailed(text):
                return LF("Could not write runtime: %@", text)
            case .placeholderBundledRuntime:
                return L("This build contains only a launcher test runtime, not the real Hermes Agent server.")
            }
        }
    }

    struct Progress {
        let fraction: Double
        let stage: String
    }

    static let defaultServerRef = "main"
    static let defaultServerArchive = "https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/main"

    var installedRuntimeURL: URL {
        Paths.applicationSupportDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    var manifestURL: URL {
        installedRuntimeURL.appendingPathComponent("version.json")
    }

    var isInstalled: Bool {
        RuntimeBundle().userInstalledRuntimeIsUsable
    }

    var serverFolderURL: URL {
        installedRuntimeURL.appendingPathComponent("server", isDirectory: true)
    }

    var runnerURL: URL {
        installedRuntimeURL.appendingPathComponent("bin/run-hermes-dashboard.sh")
    }

    var serverEntryURL: URL {
        serverFolderURL.appendingPathComponent("hermes")
    }

    func install(
        source: Source,
        serverRef: String = RuntimeInstaller.defaultServerRef,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws {
        await MainActor.run { progress(Progress(fraction: 0.02, stage: L("Preparing"))) }

        switch source {
        case .bundled:
            guard RuntimeBundle().bundledRuntimeIsUsable else {
                throw InstallError.placeholderBundledRuntime
            }
            try uninstall()
            await MainActor.run { progress(Progress(fraction: 1.0, stage: L("Using bundled runtime"))) }
            return

        case .download:
            try resetInstallDirectory()
            try await downloadServer(ref: serverRef, progress: progress)

        case let .url(url):
            try resetInstallDirectory()
            try await downloadServer(from: url, progress: progress)

        case let .local(server):
            try resetInstallDirectory()
            try await installLocalServer(from: server, progress: progress)
        }

        try installRunner()
        try normalizeServerEntryPoint()
        try restoreBundledWebDashboardIfMissing()
        try validateInstalledRuntime()
        try writeManifest(source: source, serverRef: serverRef)
        await MainActor.run { progress(Progress(fraction: 1.0, stage: L("Runtime ready"))) }
    }

    // MARK: - Internet install

    private func downloadServer(ref: String, progress: @escaping @MainActor (Progress) -> Void) async throws {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let refName = trimmed.isEmpty || trimmed == "latest" ? RuntimeInstaller.defaultServerRef : trimmed
        let isTag = refName.hasPrefix("v")
        let escaped = refName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? refName
        let kind = isTag ? "tags" : "heads"
        let urlString = "https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/\(kind)/\(escaped)"
        guard let url = URL(string: urlString) else {
            throw InstallError.downloadFailed("Bad Hermes Agent URL: \(urlString)")
        }

        await MainActor.run { progress(Progress(fraction: 0.25, stage: L("Downloading Hermes Agent from GitHub"))) }
        try await downloadServer(from: url, progress: progress, originalName: "hermes-agent-\(refName).tar.gz")
    }

    private func downloadServer(
        from url: URL,
        progress: @escaping @MainActor (Progress) -> Void,
        originalName: String? = nil
    ) async throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw InstallError.downloadFailed(L("Hermes Agent server link must start with http:// or https://."))
        }

        await MainActor.run { progress(Progress(fraction: 0.45, stage: L("Downloading Hermes Agent server"))) }
        let (tempFile, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw InstallError.downloadFailed("HTTP \(http.statusCode) from \(url.host ?? url.absoluteString)")
        }

        await MainActor.run { progress(Progress(fraction: 0.75, stage: L("Extracting Hermes Agent server"))) }
        try extractServerArchive(tempFile, originalName: originalName ?? url.lastPathComponent)
    }

    private func extractServerArchive(_ archive: URL, originalName: String) throws {
        if FileManager.default.fileExists(atPath: serverFolderURL.path) {
            try FileManager.default.removeItem(at: serverFolderURL)
        }

        let lowerName = originalName.lowercased()
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") || lowerName.hasSuffix(".gz") {
            try FileManager.default.createDirectory(at: serverFolderURL, withIntermediateDirectories: true)
            try runTarSync(["-xzf", archive.path, "-C", serverFolderURL.path, "--strip-components=1"])
        } else if lowerName.hasSuffix(".tar") {
            try FileManager.default.createDirectory(at: serverFolderURL, withIntermediateDirectories: true)
            try runTarSync(["-xf", archive.path, "-C", serverFolderURL.path, "--strip-components=1"])
        } else if lowerName.hasSuffix(".zip") {
            try extractServerZip(archive)
        } else {
            throw InstallError.unsupportedArchive(URL(fileURLWithPath: originalName))
        }
    }

    private func extractServerZip(_ archive: URL) throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-server-zip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try runSync(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-q", archive.path, "-d", tempDirectory.path])

        let root = normalizedExtractionRoot(in: tempDirectory)
        try FileManager.default.createDirectory(at: serverFolderURL, withIntermediateDirectories: true)
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for child in children {
            try FileManager.default.copyItem(
                at: child,
                to: serverFolderURL.appendingPathComponent(child.lastPathComponent)
            )
        }
    }

    private func normalizedExtractionRoot(in directory: URL) -> URL {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        guard children.count == 1, let only = children.first else {
            return directory
        }
        let isDirectory = (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDirectory ? only : directory
    }

    // MARK: - Local install

    private func installLocalServer(from url: URL, progress: @escaping @MainActor (Progress) -> Void) async throws {
        await MainActor.run { progress(Progress(fraction: 0.45, stage: L("Installing local Hermes Agent server"))) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw InstallError.missingServer
        }
        if FileManager.default.fileExists(atPath: serverFolderURL.path) {
            try FileManager.default.removeItem(at: serverFolderURL)
        }
        if isDir.boolValue {
            try FileManager.default.copyItem(at: url, to: serverFolderURL)
        } else if isSupportedServerArchive(url) {
            try extractServerArchive(url, originalName: url.lastPathComponent)
        } else {
            throw InstallError.unsupportedArchive(url)
        }
    }

    private func isSupportedServerArchive(_ url: URL) -> Bool {
        let lowerName = url.lastPathComponent.lowercased()
        return lowerName.hasSuffix(".tar.gz")
            || lowerName.hasSuffix(".tgz")
            || lowerName.hasSuffix(".gz")
            || lowerName.hasSuffix(".tar")
            || lowerName.hasSuffix(".zip")
    }

    // MARK: - Runtime layout

    private func installRunner() throws {
        let bundledRunner = RuntimeBundle().bundledRuntimeDirectory.appendingPathComponent("bin/run-hermes-dashboard.sh")
        guard FileManager.default.fileExists(atPath: bundledRunner.path) else {
            throw InstallError.writeFailed("Bundled Hermes runner is missing.")
        }
        let binDirectory = runnerURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: runnerURL.path) {
            try FileManager.default.removeItem(at: runnerURL)
        }
        try FileManager.default.copyItem(at: bundledRunner, to: runnerURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerURL.path)
    }

    private func normalizeServerEntryPoint() throws {
        if FileManager.default.fileExists(atPath: serverEntryURL.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serverEntryURL.path)
            return
        }

        let wrapper = """
        #!/usr/bin/env python3
        if __name__ == "__main__":
            from hermes_cli.main import main
            main()
        """
        do {
            try wrapper.write(to: serverEntryURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serverEntryURL.path)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
    }

    private func validateInstalledRuntime() throws {
        guard FileManager.default.isExecutableFile(atPath: runnerURL.path) else {
            throw InstallError.writeFailed("Hermes runtime launcher is not executable.")
        }
        guard FileManager.default.fileExists(atPath: serverEntryURL.path) else {
            throw InstallError.missingServerEntryPoint
        }
        guard FileManager.default.fileExists(atPath: serverFolderURL.appendingPathComponent("pyproject.toml").path) else {
            throw InstallError.missingServerEntryPoint
        }
        guard FileManager.default.fileExists(atPath: serverFolderURL.appendingPathComponent("hermes_cli/web_dist/index.html").path) else {
            throw InstallError.missingWebDashboard
        }
    }

    private func restoreBundledWebDashboardIfMissing() throws {
        let installedWebDashboard = serverFolderURL.appendingPathComponent("hermes_cli/web_dist", isDirectory: true)
        let installedIndex = installedWebDashboard.appendingPathComponent("index.html")
        guard !FileManager.default.fileExists(atPath: installedIndex.path) else {
            return
        }

        let bundledWebDashboard = RuntimeBundle()
            .bundledRuntimeDirectory
            .appendingPathComponent("server/hermes_cli/web_dist", isDirectory: true)
        let bundledIndex = bundledWebDashboard.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: bundledIndex.path) else {
            return
        }

        let parent = installedWebDashboard.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedWebDashboard.path) {
            try FileManager.default.removeItem(at: installedWebDashboard)
        }
        try FileManager.default.copyItem(at: bundledWebDashboard, to: installedWebDashboard)
    }

    // MARK: - Manifest / cleanup

    private func resetInstallDirectory() throws {
        if FileManager.default.fileExists(atPath: installedRuntimeURL.path) {
            try FileManager.default.removeItem(at: installedRuntimeURL)
        }
        try FileManager.default.createDirectory(at: installedRuntimeURL, withIntermediateDirectories: true)
    }

    private func writeManifest(source: Source, serverRef: String) throws {
        let sourceTag: String
        switch source {
        case .bundled: sourceTag = "bundled"
        case .download: sourceTag = "download"
        case .url: sourceTag = "url"
        case .local: sourceTag = "local"
        }
        var manifest: [String: Any] = [
            "version": serverRef,
            "runtime": "hermes-dashboard",
            "source": sourceTag,
            "installedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if case let .url(url) = source {
            manifest["serverURL"] = url.absoluteString
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: installedRuntimeURL.path) {
            try FileManager.default.removeItem(at: installedRuntimeURL)
        }
    }

    // MARK: - Process helpers

    private func runTarSync(_ arguments: [String]) throws {
        try runSync(URL(fileURLWithPath: "/usr/bin/tar"), arguments: arguments)
    }

    private func runSync(_ executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw InstallError.extractionFailed("Failed to launch \(executable.lastPathComponent): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw InstallError.extractionFailed("\(executable.lastPathComponent) exited \(process.terminationStatus): \(output)")
        }
    }
}
