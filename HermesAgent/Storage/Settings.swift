import Foundation
import ServiceManagement

enum AppSettingKeys {
    static let serverPort = "serverPort"
    static let autoRestartServer = "autoRestartServer"
    static let dataLocation = "dataLocation"
    static let launchAtLogin = "launchAtLogin"
    static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
    static let startServerOnLaunch = "startServerOnLaunch"
    static let maxLogSizeMB = "maxLogSizeMB"
    static let customNodePath = "customNodePath"
    static let environmentVariablesRaw = "environmentVariablesRaw"
    static let enabledAuthProviders = "enabledAuthProviders"
    static let primaryAuthProvider = "primaryAuthProvider"
    static let authProviderMethodPrefix = "authProviderMethod."
    static let wizardCompleted = "wizardCompleted"
    static let runtimeSource = "runtimeSource"
}

enum AppSettings {
    static var serverPort: Int {
        let value = UserDefaults.standard.integer(forKey: AppSettingKeys.serverPort)
        return value == 0 ? 9119 : value
    }

    static var autoRestartServer: Bool {
        if UserDefaults.standard.object(forKey: AppSettingKeys.autoRestartServer) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: AppSettingKeys.autoRestartServer)
    }

    static var startServerOnLaunch: Bool {
        if UserDefaults.standard.object(forKey: AppSettingKeys.startServerOnLaunch) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: AppSettingKeys.startServerOnLaunch)
    }

    static var launchAtLogin: Bool {
        if UserDefaults.standard.object(forKey: AppSettingKeys.launchAtLogin) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: AppSettingKeys.launchAtLogin)
    }

    static var dataLocationURL: URL {
        let path = UserDefaults.standard.string(forKey: AppSettingKeys.dataLocation)
        return URL(fileURLWithPath: path?.isEmpty == false ? path! : Paths.defaultDataDirectory.path, isDirectory: true)
    }

    static var checkForUpdatesAutomatically: Bool {
        if UserDefaults.standard.object(forKey: AppSettingKeys.checkForUpdatesAutomatically) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: AppSettingKeys.checkForUpdatesAutomatically)
    }

    static var maxLogSizeMB: Int {
        let value = UserDefaults.standard.integer(forKey: AppSettingKeys.maxLogSizeMB)
        return value == 0 ? 25 : value
    }

    static var customNodePath: String {
        UserDefaults.standard.string(forKey: AppSettingKeys.customNodePath) ?? ""
    }

    static var environmentVariables: [String: String] {
        let raw = UserDefaults.standard.string(forKey: AppSettingKeys.environmentVariablesRaw) ?? ""
        return raw
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") else { return nil }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key, value)
            }
            .reduce(into: [:]) { result, pair in
                result[pair.0] = pair.1
            }
    }

    static var enabledAuthProviderIDs: [String] {
        let ids = UserDefaults.standard.stringArray(forKey: AppSettingKeys.enabledAuthProviders)
        return ids?.isEmpty == false ? ids! : ["codex"]
    }

    static var primaryAuthProviderID: String {
        UserDefaults.standard.string(forKey: AppSettingKeys.primaryAuthProvider)
            ?? enabledAuthProviderIDs.first
            ?? "codex"
    }

    static func authMethodID(for providerID: String) -> String {
        guard let provider = AuthProviderCatalog.provider(id: providerID) else {
            return "api-key"
        }
        let stored = UserDefaults.standard.string(forKey: AppSettingKeys.authProviderMethodPrefix + providerID)
        if let stored, provider.methods.contains(where: { $0.id == stored }) {
            return stored
        }
        return provider.defaultMethodID
    }
}

enum AuthFieldKind {
    case username
    case password
    case apiKey
    case accessToken
    case oauthToken
    case endpoint
    case organization
    case clientID
    case clientSecret
    case region
    case host
    case callbackURL

    var titleKey: String {
        switch self {
        case .username: return "Login"
        case .password: return "Password"
        case .apiKey: return "API key"
        case .accessToken: return "Access token"
        case .oauthToken: return "OAuth token"
        case .endpoint: return "Endpoint URL"
        case .organization: return "Organization ID"
        case .clientID: return "Client ID"
        case .clientSecret: return "Client secret"
        case .region: return "Region"
        case .host: return "Host"
        case .callbackURL: return "Callback URL"
        }
    }

    var isSecure: Bool {
        switch self {
        case .password, .apiKey, .accessToken, .oauthToken, .clientSecret:
            return true
        case .username, .endpoint, .organization, .clientID, .region, .host, .callbackURL:
            return false
        }
    }
}

struct AuthFieldDefinition: Identifiable {
    let id: String
    let kind: AuthFieldKind
    let environmentKey: String
    let isRequired: Bool
}

struct AuthProviderDefinition: Identifiable {
    let id: String
    let displayName: String
    let categoryKey: String
    let descriptionKey: String
    let methods: [AuthMethodDefinition]

    var defaultMethodID: String {
        methods.first?.id ?? "api-key"
    }

    func method(id: String) -> AuthMethodDefinition {
        methods.first { $0.id == id } ?? methods[0]
    }

    func keychainKey(for field: AuthFieldDefinition) -> String {
        "auth.\(id).\(field.id)"
    }
}

struct AuthMethodDefinition: Identifiable {
    let id: String
    let titleKey: String
    let descriptionKey: String
    let actionTitleKey: String?
    let actionURL: URL?
    let fields: [AuthFieldDefinition]
    /// If non-nil, the wizard shows a "Sign in" button that opens this URL in the browser and
    /// then polls `CLISessionDetector` for an existing CLI session.
    let signInURL: URL?
    /// When true, the wizard exposes a "Detect existing session" button alongside the Sign in
    /// button and treats a detected CLI session as a valid credential (no manual fields needed).
    let detectsCLISession: Bool

    init(
        id: String,
        titleKey: String,
        descriptionKey: String,
        actionTitleKey: String? = nil,
        actionURL: URL? = nil,
        fields: [AuthFieldDefinition] = [],
        signInURL: URL? = nil,
        detectsCLISession: Bool = false
    ) {
        self.id = id
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.actionTitleKey = actionTitleKey
        self.actionURL = actionURL
        self.fields = fields
        self.signInURL = signInURL
        self.detectsCLISession = detectsCLISession
    }
}

enum AuthProviderCatalog {
    static let providers: [AuthProviderDefinition] = [
        AuthProviderDefinition(
            id: "codex",
            displayName: "Codex / ChatGPT",
            categoryKey: "Codex account",
            descriptionKey: "Use an existing Codex sign-in on this Mac or an OpenAI API key backup.",
            methods: [
                codexCLI(),
                apiKey("https://platform.openai.com/api-keys", "OPENAI_API_KEY", optionalFields: [
                    AuthFieldDefinition(id: "organization", kind: .organization, environmentKey: "OPENAI_ORG_ID", isRequired: false)
                ])
            ]
        ),
        api("openai", "OpenAI", "OPENAI_API_KEY", websiteURL: "https://platform.openai.com/api-keys"),
        AuthProviderDefinition(
            id: "anthropic",
            displayName: "Claude / Anthropic",
            categoryKey: "Cloud provider",
            descriptionKey: "Anthropic Claude via web sign-in, email code, or API key.",
            methods: [
                accountSignIn(
                    id: "claude-account",
                    titleKey: "Sign in to Claude",
                    descriptionKey: "Sign in to Claude in your browser. If Claude desktop or CLI is installed, Hermes Agent will pick up its session automatically.",
                    signInURL: "https://claude.ai/login"
                ),
                emailCode([
                    AuthFieldDefinition(id: "email", kind: .username, environmentKey: "ANTHROPIC_LOGIN_EMAIL", isRequired: true)
                ]),
                apiKey("https://console.anthropic.com/settings/keys", "ANTHROPIC_API_KEY")
            ]
        ),
        AuthProviderDefinition(
            id: "gemini",
            displayName: "Gemini / Google AI",
            categoryKey: "Cloud provider",
            descriptionKey: "Google AI Studio via Google sign-in, API key, or service account.",
            methods: [
                accountSignIn(
                    id: "google-account",
                    titleKey: "Sign in with Google",
                    descriptionKey: "Sign in to Google AI Studio in your browser. If gcloud CLI is set up, Hermes Agent will reuse its credentials.",
                    signInURL: "https://aistudio.google.com/"
                ),
                apiKey("https://aistudio.google.com/app/apikey", "GEMINI_API_KEY"),
                serviceAccount([
                    AuthFieldDefinition(id: "client-email", kind: .username, environmentKey: "GOOGLE_CLIENT_EMAIL", isRequired: true),
                    AuthFieldDefinition(id: "private-key", kind: .clientSecret, environmentKey: "GOOGLE_PRIVATE_KEY", isRequired: true)
                ])
            ]
        ),
        AuthProviderDefinition(
            id: "github",
            displayName: "GitHub",
            categoryKey: "Workspace provider",
            descriptionKey: "Sign in via the GitHub website (and gh CLI if installed) or paste a personal access token.",
            methods: [
                accountSignIn(
                    id: "github-account",
                    titleKey: "Sign in to GitHub",
                    descriptionKey: "Sign in to GitHub.com in your browser. If gh CLI is set up, Hermes Agent will reuse its session.",
                    signInURL: "https://github.com/login"
                ),
                accessToken([AuthFieldDefinition(id: "token", kind: .accessToken, environmentKey: "GITHUB_TOKEN", isRequired: true)])
            ]
        ),
        oauth("google", "Google", "GOOGLE_OAUTH_TOKEN"),
        oauth("microsoft", "Microsoft", "MICROSOFT_OAUTH_TOKEN"),
        AuthProviderDefinition(
            id: "azure-openai",
            displayName: "Azure OpenAI",
            categoryKey: "Cloud provider",
            descriptionKey: "Azure OpenAI deployments via API key + endpoint.",
            methods: [
                accountSignIn(
                    id: "azure-account",
                    titleKey: "Sign in to Azure",
                    descriptionKey: "Sign in via Azure Portal. If az CLI is set up, Hermes Agent will reuse its session.",
                    signInURL: "https://ai.azure.com/"
                ),
                apiKey("https://ai.azure.com/", "AZURE_OPENAI_API_KEY", optionalFields: [
                    AuthFieldDefinition(id: "endpoint", kind: .endpoint, environmentKey: "AZURE_OPENAI_ENDPOINT", isRequired: true)
                ])
            ]
        ),
        AuthProviderDefinition(
            id: "aws-bedrock",
            displayName: "AWS Bedrock",
            categoryKey: "Cloud provider",
            descriptionKey: "AWS Bedrock with access key, secret, and region.",
            methods: [
                accountSignIn(
                    id: "aws-account",
                    titleKey: "Sign in to AWS",
                    descriptionKey: "Sign in via AWS Console. If AWS CLI is set up (~/.aws/credentials or SSO), Hermes Agent will reuse its session.",
                    signInURL: "https://console.aws.amazon.com/bedrock/"
                ),
                accessToken([
                    AuthFieldDefinition(id: "access-key", kind: .accessToken, environmentKey: "AWS_ACCESS_KEY_ID", isRequired: true),
                    AuthFieldDefinition(id: "secret-key", kind: .clientSecret, environmentKey: "AWS_SECRET_ACCESS_KEY", isRequired: true),
                    AuthFieldDefinition(id: "region", kind: .region, environmentKey: "AWS_REGION", isRequired: true)
                ])
            ]
        ),
        api("mistral", "Mistral", "MISTRAL_API_KEY", websiteURL: "https://console.mistral.ai/"),
        api("cohere", "Cohere", "COHERE_API_KEY", websiteURL: "https://dashboard.cohere.com/"),
        api("groq", "Groq", "GROQ_API_KEY", websiteURL: "https://console.groq.com/"),
        api("openrouter", "OpenRouter", "OPENROUTER_API_KEY", websiteURL: "https://openrouter.ai/keys"),
        api("perplexity", "Perplexity", "PERPLEXITY_API_KEY", websiteURL: "https://www.perplexity.ai/settings/api"),
        api("huggingface", "Hugging Face", "HUGGINGFACE_API_KEY", websiteURL: "https://huggingface.co/settings/tokens"),
        api("replicate", "Replicate", "REPLICATE_API_TOKEN", websiteURL: "https://replicate.com/account/api-tokens"),
        api("together", "Together AI", "TOGETHER_API_KEY", websiteURL: "https://api.together.ai/settings/api-keys"),
        api("fireworks", "Fireworks AI", "FIREWORKS_API_KEY", websiteURL: "https://fireworks.ai/account/api-keys"),
        api("deepseek", "DeepSeek", "DEEPSEEK_API_KEY", websiteURL: "https://platform.deepseek.com/api_keys"),
        api("xai", "xAI", "XAI_API_KEY", websiteURL: "https://console.x.ai/"),
        local("ollama", "Ollama", "OLLAMA_HOST"),
        local("lm-studio", "LM Studio", "LM_STUDIO_HOST"),
        token("slack", "Slack", "SLACK_BOT_TOKEN", category: "Workspace provider"),
        token("notion", "Notion", "NOTION_TOKEN", category: "Workspace provider"),
        token("linear", "Linear", "LINEAR_API_KEY", category: "Workspace provider"),
        token("gitlab", "GitLab", "GITLAB_TOKEN", category: "Workspace provider"),
        AuthProviderDefinition(
            id: "jira",
            displayName: "Jira",
            categoryKey: "Workspace provider",
            descriptionKey: "Atlassian Jira via API token + host + login.",
            methods: [
                website("https://id.atlassian.com/login"),
                apiKey("https://id.atlassian.com/manage-profile/security/api-tokens", "JIRA_API_TOKEN", optionalFields: [
                    AuthFieldDefinition(id: "host", kind: .host, environmentKey: "JIRA_HOST", isRequired: true),
                    AuthFieldDefinition(id: "login", kind: .username, environmentKey: "JIRA_LOGIN", isRequired: true)
                ])
            ]
        )
    ]

    static var allKeychainKeys: [String] {
        providers.flatMap { provider in
            provider.methods.flatMap { method in
                method.fields.map { provider.keychainKey(for: $0) }
            }
        }
    }

    static func provider(id: String) -> AuthProviderDefinition? {
        providers.first { $0.id == id }
    }

    static func environmentVariables(store: KeychainStore, enabledProviderIDs: [String]) -> [String: String] {
        var environment: [String: String] = [
            "HERMES_AUTH_PROVIDERS": enabledProviderIDs.joined(separator: ","),
            "HERMES_PRIMARY_AUTH_PROVIDER": AppSettings.primaryAuthProviderID
        ]

        let detector = CLISessionDetector()
        for provider in providers where enabledProviderIDs.contains(provider.id) {
            let methodID = AppSettings.authMethodID(for: provider.id)
            environment["HERMES_AUTH_METHOD_\(provider.id.uppercased().replacingOccurrences(of: "-", with: "_"))"] = methodID
            for field in provider.method(id: methodID).fields {
                let key = provider.keychainKey(for: field)
                if let value = try? store.get(key), !value.isEmpty {
                    environment[field.environmentKey] = value
                }
            }
            // If this provider's chosen method relies on a CLI session, pass the credential
            // file path to the server so it can read or shell out to the right CLI.
            let method = provider.method(id: methodID)
            if method.detectsCLISession, let session = detector.detect(providerID: provider.id) {
                environment[CLISessionDetector.environmentKey(for: provider.id)] = session.path.path
            }
        }
        return environment
    }

    private static func api(_ id: String, _ name: String, _ envKey: String, websiteURL: String? = nil) -> AuthProviderDefinition {
        var methods = [apiKey(websiteURL, envKey)]
        if let websiteURL {
            methods.insert(website(websiteURL), at: 0)
        }
        return AuthProviderDefinition(
            id: id,
            displayName: name,
            categoryKey: "API provider",
            descriptionKey: "Generate an API key in the provider dashboard and paste it here.",
            methods: methods
        )
    }

    private static func token(_ id: String, _ name: String, _ envKey: String, category: String) -> AuthProviderDefinition {
        AuthProviderDefinition(
            id: id,
            displayName: name,
            categoryKey: category,
            descriptionKey: "Sign in on the official site and paste an access token here.",
            methods: [
                website(officialURL(for: id) ?? "https://www.google.com/search?q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)+login"),
                accessToken([AuthFieldDefinition(id: "token", kind: .accessToken, environmentKey: envKey, isRequired: true)])
            ]
        )
    }

    private static func oauth(_ id: String, _ name: String, _ envKey: String) -> AuthProviderDefinition {
        AuthProviderDefinition(
            id: id,
            displayName: name,
            categoryKey: "OAuth provider",
            descriptionKey: "Complete the provider's OAuth flow, then paste the token here.",
            methods: [
                website(officialURL(for: id) ?? "https://accounts.google.com/"),
                oauthToken([AuthFieldDefinition(id: "oauth-token", kind: .oauthToken, environmentKey: envKey, isRequired: true)])
            ]
        )
    }

    private static func local(_ id: String, _ name: String, _ envKey: String) -> AuthProviderDefinition {
        AuthProviderDefinition(
            id: id,
            displayName: name,
            categoryKey: "Local provider",
            descriptionKey: "Point Hermes Agent at a local service URL running on this Mac.",
            methods: [
                AuthMethodDefinition(
                    id: "local-host",
                    titleKey: "Local host",
                    descriptionKey: "Connect to a local service running on this Mac.",
                    actionTitleKey: nil,
                    actionURL: nil,
                    fields: [AuthFieldDefinition(id: "host", kind: .host, environmentKey: envKey, isRequired: true)]
                )
            ]
        )
    }

    private static func google(_ url: String) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "google",
            titleKey: "Sign in with Google",
            descriptionKey: "Use Google sign-in on the provider's official website.",
            actionTitleKey: "Open Google sign-in",
            actionURL: URL(string: url),
            fields: []
        )
    }

    private static func website(_ url: String) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "official-website",
            titleKey: "Authorize on official website",
            descriptionKey: "Open the provider's official website and complete authorization there.",
            actionTitleKey: "Open official website",
            actionURL: URL(string: url),
            fields: []
        )
    }

    private static func loginPassword(_ fields: [AuthFieldDefinition]) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "login-password",
            titleKey: "Login and password",
            descriptionKey: "Store login and password in macOS Keychain.",
            actionTitleKey: nil,
            actionURL: nil,
            fields: fields
        )
    }

    private static func codexCLI() -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "codex-cli",
            titleKey: "Use existing Codex sign-in",
            descriptionKey: "Sign in to ChatGPT in your browser or detect an existing Codex CLI session on this Mac.",
            signInURL: URL(string: "https://chatgpt.com/auth/login"),
            detectsCLISession: true
        )
    }

    private static func accountSignIn(
        id: String,
        titleKey: String,
        descriptionKey: String,
        signInURL: String
    ) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: id,
            titleKey: titleKey,
            descriptionKey: descriptionKey,
            signInURL: URL(string: signInURL),
            detectsCLISession: true
        )
    }

    private static func emailCode(_ fields: [AuthFieldDefinition]) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "email-code",
            titleKey: "Email code",
            descriptionKey: "Use an email-based sign-in flow.",
            actionTitleKey: nil,
            actionURL: nil,
            fields: fields
        )
    }

    private static func apiKey(_ url: String?, _ envKey: String, optionalFields: [AuthFieldDefinition] = []) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "api-key",
            titleKey: "API key",
            descriptionKey: "Paste an API key generated by the provider.",
            actionTitleKey: url == nil ? nil : "Open API key page",
            actionURL: url.flatMap(URL.init(string:)),
            fields: [AuthFieldDefinition(id: "api-key", kind: .apiKey, environmentKey: envKey, isRequired: true)] + optionalFields
        )
    }

    private static func accessToken(_ fields: [AuthFieldDefinition]) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "access-token",
            titleKey: "Access token",
            descriptionKey: "Paste an access token generated by the provider.",
            actionTitleKey: nil,
            actionURL: nil,
            fields: fields
        )
    }

    private static func oauthToken(_ fields: [AuthFieldDefinition]) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "oauth-token",
            titleKey: "OAuth token",
            descriptionKey: "Paste an OAuth token or use a connected browser session.",
            actionTitleKey: nil,
            actionURL: nil,
            fields: fields
        )
    }

    private static func serviceAccount(_ fields: [AuthFieldDefinition]) -> AuthMethodDefinition {
        AuthMethodDefinition(
            id: "service-account",
            titleKey: "Service account",
            descriptionKey: "Use a cloud service account for server-to-server access.",
            actionTitleKey: nil,
            actionURL: nil,
            fields: fields
        )
    }

    private static func officialURL(for id: String) -> String? {
        [
            "github": "https://github.com/login",
            "google": "https://accounts.google.com/",
            "microsoft": "https://login.microsoftonline.com/",
            "slack": "https://slack.com/signin",
            "notion": "https://www.notion.so/login",
            "linear": "https://linear.app/login",
            "gitlab": "https://gitlab.com/users/sign_in"
        ][id]
    }
}

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
