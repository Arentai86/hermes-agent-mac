import Foundation

struct DependencyResolver {
    let runtime: RuntimeBundle

    func validate() throws {
        _ = try runtime.nodeExecutableURL()
        _ = try runtime.serverEntryPointURL()
        if runtime.isFallbackRuntime(at: runtime.runtimeDirectory) {
            throw RuntimeError.placeholderRuntime
        }
    }

    func statusItems() -> [DependencyStatus] {
        [
            DependencyStatus(name: "Hermes runtime launcher", isAvailable: (try? runtime.nodeExecutableURL()) != nil),
            DependencyStatus(name: "Hermes Agent source", isAvailable: (try? runtime.serverEntryPointURL()) != nil),
            DependencyStatus(name: "Production runtime", isAvailable: !runtime.requiresRuntimeSetup),
            DependencyStatus(name: "Application Support", isAvailable: FileManager.default.isWritableFile(atPath: Paths.applicationSupportDirectory.path))
        ]
    }
}

struct DependencyStatus: Identifiable {
    let id = UUID()
    let name: String
    let isAvailable: Bool
}
