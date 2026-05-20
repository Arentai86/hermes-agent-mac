import Foundation

enum Paths {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hermes Agent", isDirectory: true)
    }

    static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hermes Agent", isDirectory: true)
    }

    static var logsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Hermes Agent", isDirectory: true)
    }

    static var skillsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    static var preferencesFile: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/com.hermes.app.plist")
    }

    static func ensureBaseDirectories() throws {
        let directories = [
            applicationSupportDirectory,
            applicationSupportDirectory.appendingPathComponent("data", isDirectory: true),
            applicationSupportDirectory.appendingPathComponent("config", isDirectory: true),
            skillsDirectory,
            applicationSupportDirectory.appendingPathComponent("cache", isDirectory: true),
            cachesDirectory,
            logsDirectory
        ]
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
