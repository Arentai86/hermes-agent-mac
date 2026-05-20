import Darwin
import Foundation
import Security

enum AuthToken {
    static func ensureToken(in dataDirectory: URL) throws -> String {
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let tokenURL = dataDirectory.appendingPathComponent("auth_token")

        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 64 {
            try hardenPermissions(for: tokenURL)
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }

        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let fileDescriptor = open(tokenURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { close(fileDescriptor) }

        let data = Data((token + "\n").utf8)
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let written = write(fileDescriptor, baseAddress, buffer.count)
            guard written == buffer.count else { throw CocoaError(.fileWriteUnknown) }
        }
        try hardenPermissions(for: tokenURL)
        return token
    }

    private static func hardenPermissions(for url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
