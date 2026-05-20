import Darwin
import Foundation

struct CodexCLICredential {
    let access: String
    let refresh: String
    let expires: Int64
    let accountID: String?
    let idToken: String?
    let email: String?
    let profileName: String
}

struct CodexCLIAuthReader {
    func readCredential() -> CodexCLICredential? {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String,
              let refresh = tokens["refresh_token"] as? String,
              !access.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let idToken = tokens["id_token"] as? String
        let accountID = tokens["account_id"] as? String
        let email = jwtStringClaim("https://api.openai.com/profile", nestedKey: "email", in: access)
            ?? jwtStringClaim("email", in: access)
            ?? jwtStringClaim("email", in: idToken)
        let expires = jwtExpiryMilliseconds(access)
            ?? fallbackExpiryMilliseconds(root: root, authURL: authURL)
        let profileName = sanitizedProfileName(email ?? accountID ?? "codex-cli")

        return CodexCLICredential(
            access: access,
            refresh: refresh,
            expires: expires,
            accountID: accountID,
            idToken: idToken,
            email: email,
            profileName: profileName
        )
    }

    var hasUsableCredential: Bool {
        readCredential() != nil
    }

    private func fallbackExpiryMilliseconds(root: [String: Any], authURL: URL) -> Int64 {
        if let raw = root["last_refresh"] as? String,
           let date = ISO8601DateFormatter().date(from: raw) {
            return Int64(date.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        }
        if let values = try? authURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = values.contentModificationDate {
            return Int64(date.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        }
        return Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
    }

    private func jwtExpiryMilliseconds(_ token: String?) -> Int64? {
        guard let exp = jwtNumberClaim("exp", in: token), exp > 0 else { return nil }
        return Int64(exp * 1000)
    }

    private func jwtStringClaim(_ key: String, nestedKey: String? = nil, in token: String?) -> String? {
        guard let payload = jwtPayload(token) else { return nil }
        if let nestedKey,
           let nested = payload[key] as? [String: Any],
           let value = nested[nestedKey] as? String,
           !value.isEmpty {
            return value
        }
        if let value = payload[key] as? String, !value.isEmpty {
            return value
        }
        return nil
    }

    private func jwtNumberClaim(_ key: String, in token: String?) -> Double? {
        guard let payload = jwtPayload(token) else { return nil }
        if let value = payload[key] as? Double { return value }
        if let value = payload[key] as? Int { return Double(value) }
        if let value = payload[key] as? String { return Double(value) }
        return nil
    }

    private func jwtPayload(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func sanitizedProfileName(_ value: String) -> String {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._@-")
        let scalars = lowercased.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "codex-cli" : sanitized
    }
}

struct HermesAgentModelAuthConfigurator {
    private let keychain = KeychainStore()

    func prepareModelAuth(dataDirectory: URL) throws {
        var profiles: [String: [String: Any]] = [:]
        var metadataProfiles: [String: [String: Any]] = [:]
        var openAIOrder: [String] = []
        var codexOrder: [String] = []

        if shouldConfigureCodexAuth {
            if let codexCredential = CodexCLIAuthReader().readCredential() {
                let profileID = "openai-codex:\(codexCredential.profileName)"
                profiles[profileID] = oauthProfile(from: codexCredential)
                metadataProfiles[profileID] = [
                    "provider": "openai-codex",
                    "mode": "oauth"
                ].merging(optionalMetadata(email: codexCredential.email)) { _, new in new }
                openAIOrder.append(profileID)
                codexOrder.append(profileID)
            }

            if let apiKey = openAIAPIKeyFromCodexProvider() ?? openAIAPIKeyFromOpenAIProvider() {
                let profileID = "openai:default"
                profiles[profileID] = [
                    "type": "api_key",
                    "provider": "openai",
                    "key": apiKey
                ]
                metadataProfiles[profileID] = [
                    "provider": "openai",
                    "mode": "api_key"
                ]
                openAIOrder.append(profileID)
            }
        } else if let apiKey = openAIAPIKeyFromOpenAIProvider() {
            let profileID = "openai:default"
            profiles[profileID] = [
                "type": "api_key",
                "provider": "openai",
                "key": apiKey
            ]
            metadataProfiles[profileID] = [
                "provider": "openai",
                "mode": "api_key"
            ]
            openAIOrder.append(profileID)
        }

        guard !profiles.isEmpty else { return }

        try writeAuthProfileStore(
            profiles: profiles,
            openAIOrder: dedupe(openAIOrder),
            codexOrder: dedupe(codexOrder),
            dataDirectory: dataDirectory
        )
        try updateHermesAgentConfig(
            metadataProfiles: metadataProfiles,
            openAIOrder: dedupe(openAIOrder),
            codexOrder: dedupe(codexOrder),
            dataDirectory: dataDirectory
        )
    }

    private var shouldConfigureCodexAuth: Bool {
        AppSettings.enabledAuthProviderIDs.contains("codex")
            || AppSettings.enabledAuthProviderIDs.contains("openai-codex")
            || AppSettings.primaryAuthProviderID == "codex"
            || AppSettings.primaryAuthProviderID == "openai-codex"
    }

    private func openAIAPIKeyFromCodexProvider() -> String? {
        guard AppSettings.authMethodID(for: "codex") == "api-key" else { return nil }
        return keychainValue(providerID: "codex", fieldID: "api-key")
    }

    private func openAIAPIKeyFromOpenAIProvider() -> String? {
        guard AppSettings.enabledAuthProviderIDs.contains("openai"),
              AppSettings.authMethodID(for: "openai") == "api-key" else { return nil }
        return keychainValue(providerID: "openai", fieldID: "api-key")
    }

    private func keychainValue(providerID: String, fieldID: String) -> String? {
        guard let provider = AuthProviderCatalog.provider(id: providerID),
              let field = provider.methods.flatMap(\.fields).first(where: { $0.id == fieldID }),
              let value = try? keychain.get(provider.keychainKey(for: field))?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func oauthProfile(from credential: CodexCLICredential) -> [String: Any] {
        var profile: [String: Any] = [
            "type": "oauth",
            "provider": "openai-codex",
            "access": credential.access,
            "refresh": credential.refresh,
            "expires": credential.expires
        ]
        if let accountID = credential.accountID, !accountID.isEmpty {
            profile["accountId"] = accountID
        }
        if let idToken = credential.idToken, !idToken.isEmpty {
            profile["idToken"] = idToken
        }
        if let email = credential.email, !email.isEmpty {
            profile["email"] = email
        }
        return profile
    }

    private func optionalMetadata(email: String?) -> [String: Any] {
        guard let email, !email.isEmpty else { return [:] }
        return ["email": email]
    }

    private func writeAuthProfileStore(
        profiles: [String: [String: Any]],
        openAIOrder: [String],
        codexOrder: [String],
        dataDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let authURL = dataDirectory.appendingPathComponent("auth.json")
        var root = readJSONDictionary(at: authURL) ?? ["version": 1, "providers": [:]]

        var providers = root["providers"] as? [String: Any] ?? [:]
        var credentialPool = root["credential_pool"] as? [String: Any] ?? [:]

        if let profileID = codexOrder.first,
           let profile = profiles[profileID],
           let access = profile["access"] as? String,
           let refresh = profile["refresh"] as? String {
            var tokens: [String: Any] = [
                "access_token": access,
                "refresh_token": refresh
            ]
            if let idToken = profile["idToken"] as? String {
                tokens["id_token"] = idToken
            }
            if let accountID = profile["accountId"] as? String {
                tokens["account_id"] = accountID
            }

            providers["openai-codex"] = [
                "tokens": tokens,
                "last_refresh": iso8601Now(),
                "auth_mode": "chatgpt"
            ]
            root["active_provider"] = "openai-codex"
            credentialPool["openai-codex"] = [
                [
                    "id": stableCredentialID(from: profileID),
                    "label": profile["email"] as? String ?? "Codex",
                    "auth_type": "oauth",
                    "priority": 0,
                    "source": "device_code",
                    "access_token": access,
                    "refresh_token": refresh,
                    "base_url": "https://chatgpt.com/backend-api/codex",
                    "expires_at_ms": profile["expires"] as? Int64 ?? 0,
                    "last_refresh": iso8601Now()
                ]
            ]
        }

        root["providers"] = providers
        root["credential_pool"] = credentialPool
        try writeJSONDictionary(root, to: authURL, permissions: S_IRUSR | S_IWUSR)
    }

    private func updateHermesAgentConfig(
        metadataProfiles: [String: [String: Any]],
        openAIOrder: [String],
        codexOrder: [String],
        dataDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let configURL = dataDirectory.appendingPathComponent("config.yaml")
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        let provider = codexOrder.isEmpty ? "auto" : "openai-codex"
        let yaml = """
        # Created by Hermes Agent for macOS on first launch.
        model:
          provider: \(provider)
          default: gpt-5.5
        toolsets:
          - hermes-cli
        """
        try yaml.appending("\n").write(to: configURL, atomically: true, encoding: .utf8)
        chmod(configURL.path, S_IRUSR | S_IWUSR)
    }

    private func stableCredentialID(from value: String) -> String {
        let sanitized = value
            .lowercased()
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
            }
        let id = String(sanitized)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return id.isEmpty ? "codex" : String(id.prefix(48))
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func mergeDictionary(_ existing: Any?, with updates: [String: Any]) -> [String: Any] {
        var dictionary = existing as? [String: Any] ?? [:]
        for (key, value) in updates {
            dictionary[key] = value
        }
        return dictionary
    }

    private func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func readJSONDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func writeJSONDictionary(_ dictionary: [String: Any], to url: URL, permissions: mode_t) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        chmod(url.path, permissions)
    }
}
