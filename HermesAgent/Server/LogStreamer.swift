import Foundation

@MainActor
final class LogStreamer: ObservableObject {
    @Published private(set) var lines: [String] = []
    private var fileHandle: FileHandle?

    func start(url: URL, limit: Int = 500) {
        stop()
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return }

        fileHandle = handle
        let data = (try? handle.readToEnd()) ?? Data()
        if let text = String(data: data, encoding: .utf8) {
            lines = Array(text.split(separator: "\n").suffix(limit)).map(String.init)
        }

        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.lines.append(contentsOf: text.split(separator: "\n").map(String.init))
                if let count = self?.lines.count, count > limit {
                    self?.lines.removeFirst(count - limit)
                }
            }
        }
    }

    func stop() {
        fileHandle?.readabilityHandler = nil
        try? fileHandle?.close()
        fileHandle = nil
    }
}
