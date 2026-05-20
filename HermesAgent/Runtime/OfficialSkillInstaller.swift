import Foundation

struct OfficialSkill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let sourceURL: URL
}

struct SkillInstallSummary {
    let installed: Int
    let skipped: Int
}

struct OfficialSkillInstaller {
    enum SkillInstallError: LocalizedError {
        case missingBundledSkills

        var errorDescription: String? {
            switch self {
            case .missingBundledSkills:
                return L("Official skills are not bundled in this build.")
            }
        }
    }

    private var bundledSkillsDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true)
    }

    func availableSkills() throws -> [OfficialSkill] {
        guard let bundledSkillsDirectory,
              FileManager.default.fileExists(atPath: bundledSkillsDirectory.path) else {
            throw SkillInstallError.missingBundledSkills
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: bundledSkillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { return nil }
            let skillFile = url.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillFile.path) else { return nil }
            let metadata = parseMetadata(from: skillFile)
            let id = metadata.name.isEmpty ? url.lastPathComponent : metadata.name
            return OfficialSkill(
                id: id,
                name: readableName(from: id),
                description: metadata.description.isEmpty ? L("Official Hermes Agent skill.") : metadata.description,
                sourceURL: url
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func install(skillIDs: Set<String>) throws -> SkillInstallSummary {
        let skills = try availableSkills()
        try FileManager.default.createDirectory(at: Paths.skillsDirectory, withIntermediateDirectories: true)

        var installed = 0
        var skipped = 0
        for skill in skills where skillIDs.contains(skill.id) {
            let destination = Paths.skillsDirectory.appendingPathComponent(skill.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                if hasOfficialMarker(at: destination) {
                    try FileManager.default.removeItem(at: destination)
                } else {
                    skipped += 1
                    continue
                }
            }
            try FileManager.default.copyItem(at: skill.sourceURL, to: destination)
            let marker = destination.appendingPathComponent(".hermes-official-skill")
            try "installedAt=\(ISO8601DateFormatter().string(from: Date()))\n".write(
                to: marker,
                atomically: true,
                encoding: .utf8
            )
            installed += 1
        }

        for skill in skills where !skillIDs.contains(skill.id) {
            let destination = Paths.skillsDirectory.appendingPathComponent(skill.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path), hasOfficialMarker(at: destination) {
                try FileManager.default.removeItem(at: destination)
            }
        }

        return SkillInstallSummary(installed: installed, skipped: skipped)
    }

    func uninstallOfficialSkills(skillIDs: Set<String>? = nil) throws {
        guard FileManager.default.fileExists(atPath: Paths.skillsDirectory.path) else { return }
        let directories = try FileManager.default.contentsOfDirectory(
            at: Paths.skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            let isDirectory = (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory, hasOfficialMarker(at: directory) else { continue }
            if let skillIDs, !skillIDs.contains(directory.lastPathComponent) {
                continue
            }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func parseMetadata(from skillFile: URL) -> (name: String, description: String) {
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8),
              text.hasPrefix("---") else {
            return ("", "")
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var name = ""
        var description = ""
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                break
            }
            if line.hasPrefix("name:") {
                name = cleanMetadataValue(String(line.dropFirst("name:".count)))
            } else if line.hasPrefix("description:") {
                description = cleanMetadataValue(String(line.dropFirst("description:".count)))
            }
        }
        return (name, description)
    }

    private func cleanMetadataValue(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned.removeFirst()
            cleaned.removeLast()
        }
        return cleaned
    }

    private func readableName(from id: String) -> String {
        id
            .split(separator: "-")
            .map { part in
                part.count <= 3 ? part.uppercased() : part.prefix(1).uppercased() + String(part.dropFirst())
            }
            .joined(separator: " ")
    }

    private func hasOfficialMarker(at directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".hermes-official-skill").path)
    }
}
