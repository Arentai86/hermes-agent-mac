import Foundation

enum Paths {
    static var isAppSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var hermesHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
    }

    static var defaultDataDirectory: URL {
        isAppSandboxed ? applicationSupportDirectory : hermesHomeDirectory
    }

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
        var directories = [
            applicationSupportDirectory,
            applicationSupportDirectory.appendingPathComponent("data", isDirectory: true),
            applicationSupportDirectory.appendingPathComponent("config", isDirectory: true),
            skillsDirectory,
            applicationSupportDirectory.appendingPathComponent("cache", isDirectory: true),
            cachesDirectory,
            logsDirectory
        ]
        if !isAppSandboxed {
            directories.append(contentsOf: [
                hermesHomeDirectory,
                hermesHomeDirectory.appendingPathComponent("auth", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("cache", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("logs", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("profiles", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("runtime", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("sessions", isDirectory: true),
                hermesHomeDirectory.appendingPathComponent("skills", isDirectory: true)
            ])
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
