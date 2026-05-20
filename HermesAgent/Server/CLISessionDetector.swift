import Foundation

/// Detects existing CLI / desktop-app sessions on this Mac so Hermes Agent can reuse them
/// instead of asking the user for raw API keys.
///
/// The idea: for major providers, the official CLI (or desktop app) keeps an OAuth-derived
/// token on disk after the user signs in once. If that file exists we know the user is
/// authenticated and the launcher can pass its path to the Hermes Agent server, which then
/// shells out to the right CLI or reads the credential file directly.
struct CLISessionDetector {
    struct Session: Equatable {
        let providerID: String
        let path: URL
        let displayName: String
    }

    /// Provider IDs that have any chance of producing a detectable CLI session.
    static let supportedProviderIDs: Set<String> = [
        "codex",
        "openai",
        "anthropic",
        "github",
        "google",
        "gemini",
        "azure-openai",
        "aws-bedrock",
        "gitlab"
    ]

    static func supportsCLISession(providerID: String) -> Bool {
        supportedProviderIDs.contains(providerID)
    }

    func detect(providerID: String) -> Session? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch providerID {
        case "codex":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".codex/auth.json"),
                    home.appendingPathComponent(".codex/credentials.json"),
                    home.appendingPathComponent("Library/Application Support/Codex/auth.json")
                ],
                providerID: providerID,
                displayName: "Codex CLI"
            )
        case "openai":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".openai/auth.json"),
                    home.appendingPathComponent(".config/openai/auth.json")
                ],
                providerID: providerID,
                displayName: "OpenAI CLI"
            )
        case "anthropic":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".claude/credentials"),
                    home.appendingPathComponent(".claude/auth.json"),
                    home.appendingPathComponent("Library/Application Support/Claude/credentials"),
                    home.appendingPathComponent(".config/anthropic/credentials.json")
                ],
                providerID: providerID,
                displayName: "Claude desktop / CLI"
            )
        case "github":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".config/gh/hosts.yml")
                ],
                providerID: providerID,
                displayName: "gh CLI"
            )
        case "google", "gemini":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".config/gcloud/application_default_credentials.json"),
                    home.appendingPathComponent(".config/gcloud/credentials.db")
                ],
                providerID: providerID,
                displayName: "gcloud CLI"
            )
        case "azure-openai":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".azure/accessTokens.json"),
                    home.appendingPathComponent(".azure/azureProfile.json"),
                    home.appendingPathComponent(".azure/msal_token_cache.json")
                ],
                providerID: providerID,
                displayName: "az CLI"
            )
        case "aws-bedrock":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".aws/sso/cache"),
                    home.appendingPathComponent(".aws/credentials")
                ],
                providerID: providerID,
                displayName: "AWS CLI"
            )
        case "gitlab":
            return firstExisting(
                paths: [
                    home.appendingPathComponent(".config/glab-cli/config.yml")
                ],
                providerID: providerID,
                displayName: "glab CLI"
            )
        default:
            return nil
        }
    }

    private func firstExisting(paths: [URL], providerID: String, displayName: String) -> Session? {
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            return Session(providerID: providerID, path: path, displayName: displayName)
        }
        return nil
    }

    /// Environment-variable name passed to the Hermes Agent server so it knows which credential
    /// file to read for each provider (e.g. `HERMES_AUTH_CLI_CODEX=/Users/.../auth.json`).
    static func environmentKey(for providerID: String) -> String {
        let upper = providerID.uppercased().replacingOccurrences(of: "-", with: "_")
        return "HERMES_AUTH_CLI_\(upper)"
    }
}
