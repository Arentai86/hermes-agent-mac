import Foundation

/// Validates user-supplied credentials against the real provider API.
/// Each provider has its own lightweight "ping" endpoint that returns 200 on a working key
/// (typically a "list models" or "whoami" call). Validation runs with an 8 s timeout and
/// reports the most useful HTTP signal (200, 401, 429, network failure) back to the UI.
struct CredentialValidator {
    enum Result: Equatable {
        case ok(String)
        case unauthorized
        case rateLimited
        case networkError(String)
        case unsupported(String)
        case serverError(Int, String)

        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .ok(let text):
                return text.isEmpty ? "Credentials accepted." : text
            case .unauthorized:
                return "Unauthorized. Check the credential value and try again."
            case .rateLimited:
                return "Rate limited by the provider. Try again later."
            case let .networkError(text):
                return "Network error: \(text)"
            case let .unsupported(text):
                return text
            case let .serverError(code, text):
                return "HTTP \(code)\(text.isEmpty ? "" : ": \(text)")"
            }
        }
    }

    static func isSupported(providerID: String, methodID: String) -> Bool {
        switch (providerID, methodID) {
        case ("openai", "api-key"),
             ("codex", "api-key"),
             ("anthropic", "api-key"),
             ("gemini", "api-key"),
             ("mistral", "api-key"),
             ("cohere", "api-key"),
             ("groq", "api-key"),
             ("openrouter", "api-key"),
             ("perplexity", "api-key"),
             ("huggingface", "api-key"),
             ("replicate", "api-key"),
             ("together", "api-key"),
             ("fireworks", "api-key"),
             ("deepseek", "api-key"),
             ("xai", "api-key"),
             ("azure-openai", "api-key"),
             ("github", "access-token"),
             ("slack", "access-token"),
             ("notion", "access-token"),
             ("gitlab", "access-token"),
             ("linear", "access-token"),
             ("jira", "api-key"):
            return true
        default:
            return false
        }
    }

    func validate(providerID: String, methodID: String, credentials: [String: String]) async -> Result {
        switch providerID {
        case "openai", "codex":
            return await openAICompatible(host: "api.openai.com", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "anthropic":
            return await anthropic(key: credentials["api-key"] ?? "")
        case "gemini":
            return await gemini(key: credentials["api-key"] ?? "")
        case "mistral":
            return await openAICompatible(host: "api.mistral.ai", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "cohere":
            return await openAICompatible(host: "api.cohere.com", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "groq":
            return await openAICompatible(host: "api.groq.com", path: "/openai/v1/models", key: credentials["api-key"] ?? "")
        case "openrouter":
            return await openAICompatible(host: "openrouter.ai", path: "/api/v1/models", key: credentials["api-key"] ?? "")
        case "perplexity":
            return await perplexity(key: credentials["api-key"] ?? "")
        case "huggingface":
            return await huggingface(key: credentials["api-key"] ?? "")
        case "replicate":
            return await replicate(key: credentials["api-key"] ?? "")
        case "together":
            return await openAICompatible(host: "api.together.xyz", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "fireworks":
            return await openAICompatible(host: "api.fireworks.ai", path: "/inference/v1/models", key: credentials["api-key"] ?? "")
        case "deepseek":
            return await openAICompatible(host: "api.deepseek.com", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "xai":
            return await openAICompatible(host: "api.x.ai", path: "/v1/models", key: credentials["api-key"] ?? "")
        case "azure-openai":
            return await azureOpenAI(endpoint: credentials["endpoint"] ?? "", key: credentials["api-key"] ?? "")
        case "github":
            return await github(token: credentials["token"] ?? "")
        case "slack":
            return await slack(token: credentials["token"] ?? "")
        case "notion":
            return await notion(token: credentials["token"] ?? "")
        case "gitlab":
            return await gitlab(token: credentials["token"] ?? "")
        case "linear":
            return await linear(token: credentials["token"] ?? "")
        case "jira":
            return await jira(
                host: credentials["host"] ?? "",
                login: credentials["login"] ?? "",
                token: credentials["api-key"] ?? ""
            )
        default:
            return .unsupported("Live validation is not implemented for \(providerID).")
        }
    }

    // MARK: - Generic helpers

    private func makeRequest(url: URL, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 8)
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func run(_ request: URLRequest, parse: ((Data) -> String?)? = nil) async -> Result {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError("Unexpected response.")
            }
            switch http.statusCode {
            case 200..<300:
                let detail = parse?(data) ?? ""
                return .ok(detail.isEmpty ? "Credentials accepted." : detail)
            case 401, 403:
                return .unauthorized
            case 429:
                return .rateLimited
            default:
                let body = String(data: data.prefix(180), encoding: .utf8) ?? ""
                return .serverError(http.statusCode, body)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Provider validators

    private func openAICompatible(host: String, path: String, key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://\(host)\(path)") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: ["Authorization": "Bearer \(key)"])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = json["data"] as? [Any] else { return nil }
            return "\(array.count) models available"
        }
    }

    private func anthropic(key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: [
            "x-api-key": key,
            "anthropic-version": "2023-06-01"
        ])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = json["data"] as? [Any] else { return nil }
            return "\(array.count) Claude models available"
        }
    }

    private func gemini(key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { return .networkError("Invalid URL.") }
        return await run(makeRequest(url: url)) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = json["models"] as? [Any] else { return nil }
            return "\(array.count) Gemini models available"
        }
    }

    private func perplexity(key: String) async -> Result {
        // Perplexity does not expose a public "list models" endpoint; use a minimal chat ping.
        guard !key.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.perplexity.ai/chat/completions") else {
            return .networkError("Invalid URL.")
        }
        var request = makeRequest(url: url, headers: [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json"
        ])
        request.httpMethod = "POST"
        let payload: [String: Any] = [
            "model": "sonar",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return await run(request) { _ in "Perplexity API key accepted." }
    }

    private func huggingface(key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://huggingface.co/api/whoami-v2") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: ["Authorization": "Bearer \(key)"])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else { return nil }
            return "Hugging Face: \(name)"
        }
    }

    private func replicate(key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.replicate.com/v1/account") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: ["Authorization": "Token \(key)"])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["username"] as? String else { return nil }
            return "Replicate: \(user)"
        }
    }

    private func azureOpenAI(endpoint: String, key: String) async -> Result {
        guard !key.isEmpty else { return .unauthorized }
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unsupported("Azure OpenAI requires an endpoint URL in addition to the API key.")
        }
        var components = URLComponents(string: trimmed)
        let basePath = (components?.path.isEmpty == false ? components!.path : "")
            .replacingOccurrences(of: "/openai/deployments", with: "")
        components?.path = basePath + "/openai/deployments"
        components?.queryItems = [URLQueryItem(name: "api-version", value: "2024-02-15-preview")]
        guard let url = components?.url else { return .networkError("Invalid Azure endpoint URL.") }
        let request = makeRequest(url: url, headers: ["api-key": key])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = json["data"] as? [Any] else { return nil }
            return "\(array.count) Azure deployments available"
        }
    }

    private func github(token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.github.com/user") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let login = json["login"] as? String else { return nil }
            return "GitHub: \(login)"
        }
    }

    private func slack(token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://slack.com/api/auth.test") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: ["Authorization": "Bearer \(token)"])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if (json["ok"] as? Bool) == false {
                return nil
            }
            if let team = json["team"] as? String, let user = json["user"] as? String {
                return "Slack: \(user) @ \(team)"
            }
            return "Slack token accepted."
        }
    }

    private func notion(token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.notion.com/v1/users/me") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: [
            "Authorization": "Bearer \(token)",
            "Notion-Version": "2022-06-28"
        ])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = (json["bot"] as? [String: Any])?["workspace_name"] as? String
                    ?? json["name"] as? String else { return nil }
            return "Notion: \(name)"
        }
    }

    private func gitlab(token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://gitlab.com/api/v4/user") else {
            return .networkError("Invalid URL.")
        }
        let request = makeRequest(url: url, headers: ["Authorization": "Bearer \(token)"])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let username = json["username"] as? String else { return nil }
            return "GitLab: \(username)"
        }
    }

    private func linear(token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        guard let url = URL(string: "https://api.linear.app/graphql") else {
            return .networkError("Invalid URL.")
        }
        var request = makeRequest(url: url, headers: [
            "Authorization": token,
            "Content-Type": "application/json"
        ])
        request.httpMethod = "POST"
        let body = ["query": "{ viewer { id name email } }"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let data = json["data"] as? [String: Any],
                  let viewer = data["viewer"] as? [String: Any],
                  let name = viewer["name"] as? String else { return nil }
            return "Linear: \(name)"
        }
    }

    private func jira(host: String, login: String, token: String) async -> Result {
        guard !token.isEmpty else { return .unauthorized }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !trimmedLogin.isEmpty else {
            return .unsupported("Jira validation requires host and login.")
        }
        let normalized = trimmedHost.hasPrefix("http") ? trimmedHost : "https://\(trimmedHost)"
        guard let base = URL(string: normalized),
              let url = URL(string: "/rest/api/3/myself", relativeTo: base) else {
            return .networkError("Invalid Jira host.")
        }
        let pair = "\(trimmedLogin):\(token)"
        let basic = Data(pair.utf8).base64EncodedString()
        let request = makeRequest(url: url, headers: [
            "Authorization": "Basic \(basic)",
            "Accept": "application/json"
        ])
        return await run(request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let display = json["displayName"] as? String else { return nil }
            return "Jira: \(display)"
        }
    }
}
