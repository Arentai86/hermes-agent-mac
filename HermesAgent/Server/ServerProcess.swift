import Darwin
import Foundation

final class ServerProcess: @unchecked Sendable {
    var onStdoutLine: ((String) -> Void)?
    var onStderrLine: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

    private let ioQueue = DispatchQueue(label: "Hermes Agent.ServerProcess.IO")
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let logURL: URL
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    init(executableURL: URL, arguments: [String], environment: [String: String], logURL: URL) throws {
        self.logURL = logURL
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.ioQueue.async {
                self.closePipes()
                self.onTermination?(process.terminationStatus)
            }
        }
    }

    func start() throws {
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.ioQueue.async {
                self.consume(data: data, isStdout: true)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.ioQueue.async {
                self.consume(data: data, isStdout: false)
            }
        }

        try process.run()
    }

    func terminate(gracePeriod: TimeInterval) {
        guard process.isRunning else {
            closePipes()
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            let pid = process.processIdentifier
            if pid > 0 {
                kill(pid, SIGKILL)
            }
        }
        closePipes()
    }

    private func closePipes() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func consume(data: Data, isStdout: Bool) {
        guard !data.isEmpty else { return }
        appendToLog(data)

        if isStdout {
            stdoutBuffer.append(data)
            drainLines(from: &stdoutBuffer, handler: onStdoutLine)
        } else {
            stderrBuffer.append(data)
            drainLines(from: &stderrBuffer, handler: onStderrLine)
        }
    }

    private func drainLines(from buffer: inout Data, handler: ((String) -> Void)?) {
        while let newline = buffer.firstIndex(of: 10) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                handler?(line)
            }
        }
    }

    private func appendToLog(_ data: Data) {
        rotateLogIfNeeded()
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rotateLogIfNeeded() {
        let maxBytes = Int64(AppSettings.maxLogSizeMB) * 1024 * 1024
        guard let values = try? logURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              Int64(fileSize) > maxBytes else { return }
        let rotated = logURL.deletingLastPathComponent()
            .appendingPathComponent(logURL.deletingPathExtension().lastPathComponent + ".1.log")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: logURL, to: rotated)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
}
