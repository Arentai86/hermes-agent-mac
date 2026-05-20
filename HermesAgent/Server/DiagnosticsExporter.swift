import Foundation

struct DiagnosticsExporter {
    func export() throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hermes Agent-Diagnostics-\(timestamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try copyIfExists(Paths.logsDirectory, to: folder.appendingPathComponent("Logs"))
        try writeRedactedSettings(to: folder.appendingPathComponent("settings.txt"))

        let archive = folder.deletingLastPathComponent()
            .appendingPathComponent("Hermes Agent-Diagnostics-\(timestamp).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", archive.path, folder.lastPathComponent]
        process.currentDirectoryURL = folder.deletingLastPathComponent()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return archive
    }

    private func copyIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func writeRedactedSettings(to url: URL) throws {
        let text = """
        port=\(AppSettings.serverPort)
        dataLocation=\(AppSettings.dataLocationURL.path)
        autoRestart=\(AppSettings.autoRestartServer)
        customRuntimePath=\(AppSettings.customNodePath.isEmpty ? "<bundled>" : "<custom>")
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
