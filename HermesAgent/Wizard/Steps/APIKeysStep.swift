import AppKit
import SwiftUI

struct APIKeysStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @StateObject private var signInController = BrowserSignInController()
    @State private var selectedProviderID = "codex"
    @State private var enabledProviderIDs: Set<String> = ["codex"]
    @State private var selectedMethodIDs: [String: String] = [:]
    @State private var credentialValues: [String: String] = [:]
    @State private var saveError: String?
    @State private var testStates: [String: TestState] = [:]
    @State private var testingProviderID: String?

    enum TestState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    private var selectedProvider: AuthProviderDefinition {
        AuthProviderCatalog.provider(id: selectedProviderID) ?? AuthProviderCatalog.providers[0]
    }

    private var selectedMethod: AuthMethodDefinition {
        selectedProvider.method(id: selectedMethodIDs[selectedProvider.id] ?? selectedProvider.defaultMethodID)
    }

    private var isValid: Bool {
        guard !enabledProviderIDs.isEmpty else { return false }
        for provider in AuthProviderCatalog.providers where enabledProviderIDs.contains(provider.id) {
            let method = provider.method(id: selectedMethodIDs[provider.id] ?? provider.defaultMethodID)
            // Methods that rely on a detected CLI / desktop session and have no manual fields
            // are valid only when the session is actually present on this Mac.
            if method.detectsCLISession, method.fields.isEmpty, !hasDetectedSession(providerID: provider.id) {
                return false
            }
            for field in method.fields where field.isRequired {
                if credentialValue(provider: provider, field: field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            }
        }
        return true
    }

    /// Whether this Mac has a CLI / desktop session Hermes Agent can pick up for the given provider.
    /// Codex is the most fleshed-out case (we actually parse its auth.json), the rest fall back
    /// to the lightweight `CLISessionDetector`.
    private func hasDetectedSession(providerID: String) -> Bool {
        if providerID == "codex" {
            return CodexCLIAuthReader().hasUsableCredential
        }
        return CLISessionDetector().detect(providerID: providerID) != nil
    }

    private func detectedSessionLabel(providerID: String) -> String? {
        if providerID == "codex" {
            return CodexCLIAuthReader().hasUsableCredential ? "Codex CLI" : nil
        }
        return CLISessionDetector().detect(providerID: providerID)?.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Authorization"))
                    .font(.system(size: 28, weight: .semibold))
                Text(L("Choose a provider first, then choose Google, official website, API key, token, or login/password where supported."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LF("%d authorization options", AuthProviderCatalog.providers.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                providerList
                    .frame(width: 220)
                Divider()
                providerDetail
            }
            .frame(maxHeight: .infinity)

            if let saveError {
                Label(saveError, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if !isValid {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Label(L("Credentials are stored in macOS Keychain."), systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            WizardFooter(
                canGoBack: true,
                canContinue: isValid,
                continueTitle: L("Continue"),
                onBack: coordinator.back,
                onContinue: saveAndContinue
            )
        }
        .padding(24)
        .onAppear(perform: loadStoredCredentials)
    }

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AuthProviderCatalog.providers) { provider in
                    Button {
                        selectedProviderID = provider.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: enabledProviderIDs.contains(provider.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(enabledProviderIDs.contains(provider.id) ? .green : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.subheadline.weight(provider.id == selectedProviderID ? .semibold : .regular))
                                    .lineLimit(1)
                                Text(L(provider.categoryKey))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 8)
                        .background(provider.id == selectedProviderID ? Color.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(provider.displayName)
                }
            }
        }
    }

    private var providerDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("Configure %@", selectedProvider.displayName))
                        .font(.headline)
                    Text(L(selectedProvider.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L("Enable this method"), isOn: enabledBinding(for: selectedProvider))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(L("Enable this method"))
            }

            if enabledProviderIDs.contains(selectedProvider.id) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Authentication method"))
                        .font(.caption.weight(.semibold))
                    Picker(L("Authentication method"), selection: methodBinding(for: selectedProvider)) {
                        ForEach(selectedProvider.methods) { method in
                            Text(L(method.titleKey)).tag(method.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L(selectedMethod.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitleKey = selectedMethod.actionTitleKey, let actionURL = selectedMethod.actionURL {
                    Button {
                        NSWorkspace.shared.open(actionURL)
                    } label: {
                        Label(L(actionTitleKey), systemImage: "safari")
                    }
                }

                accountSignInRow

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedMethod.fields) { field in
                        credentialField(provider: selectedProvider, field: field)
                    }
                }
                if selectedMethod.fields.isEmpty {
                    Label(emptyMethodMessage, systemImage: emptyMethodIcon)
                        .font(.caption)
                        .foregroundStyle(emptyMethodColor)
                } else if CredentialValidator.isSupported(providerID: selectedProvider.id, methodID: selectedMethod.id) {
                    testConnectionRow
                }
            } else {
                Text(L("Enable this method"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accountSignInRow: some View {
        if let signInURL = selectedMethod.signInURL, selectedMethod.detectsCLISession {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        signInController.startSignIn(providerID: selectedProvider.id, signInURL: signInURL)
                    } label: {
                        Label(L("Sign in via browser"), systemImage: "safari")
                    }
                    Button {
                        signInController.detectExisting(providerID: selectedProvider.id)
                    } label: {
                        Label(L("Detect existing session"), systemImage: "magnifyingglass")
                    }
                    Spacer()
                }
                signInStatusView
            }
        }
    }

    @ViewBuilder
    private var signInStatusView: some View {
        let providerID = selectedProvider.id
        switch signInController.status {
        case .idle:
            if let label = detectedSessionLabel(providerID: providerID) {
                Label(LF("Detected %@ session on this Mac.", label), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .waitingForCLI(waitingID, _):
            if waitingID == providerID {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("Waiting for the browser sign-in to complete..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let label = detectedSessionLabel(providerID: providerID) {
                Label(LF("Detected %@ session on this Mac.", label), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case let .detected(session):
            if session.providerID == providerID {
                Label(LF("Detected %@ session on this Mac.", session.displayName), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .notFound:
            Label(L("No existing session was found on this Mac yet. Sign in via the browser, then click Detect."), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .timedOut:
            Label(L("Timed out waiting for the browser sign-in. Click Detect after you finish."), systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .cancelled:
            EmptyView()
        }
    }

    private var testConnectionRow: some View {
        let key = testKey(provider: selectedProvider, method: selectedMethod)
        let state = testStates[key] ?? .idle
        let isRunning = (testingProviderID == key) || state == .running
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    Task { await runTest(for: selectedProvider, method: selectedMethod) }
                } label: {
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Testing..."))
                        }
                    } else {
                        Label(L("Test connection"), systemImage: "wifi")
                    }
                }
                .disabled(isRunning || !hasMinimumFields(for: selectedProvider, method: selectedMethod))
                Spacer()
            }
            switch state {
            case .success(let message):
                Label(message, systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .running:
                EmptyView()
            }
        }
    }

    private func testKey(provider: AuthProviderDefinition, method: AuthMethodDefinition) -> String {
        "\(provider.id).\(method.id)"
    }

    private func hasMinimumFields(for provider: AuthProviderDefinition, method: AuthMethodDefinition) -> Bool {
        for field in method.fields where field.isRequired {
            if credentialValue(provider: provider, field: field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return !method.fields.isEmpty
    }

    @MainActor
    private func runTest(for provider: AuthProviderDefinition, method: AuthMethodDefinition) async {
        let key = testKey(provider: provider, method: method)
        testStates[key] = .running
        testingProviderID = key

        var credentials: [String: String] = [:]
        for field in method.fields {
            credentials[field.id] = credentialValue(provider: provider, field: field)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let result = await CredentialValidator().validate(
            providerID: provider.id,
            methodID: method.id,
            credentials: credentials
        )

        guard testingProviderID == key else { return }
        switch result {
        case .ok(let message):
            testStates[key] = .success(message)
        case .unauthorized, .rateLimited, .networkError, .unsupported, .serverError:
            testStates[key] = .failure(result.message)
        }
        testingProviderID = nil
    }

    private func credentialField(provider: AuthProviderDefinition, field: AuthFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(L(field.kind.titleKey))
                    .font(.caption.weight(.semibold))
                Text(field.isRequired ? L("Required") : L("Optional"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if field.kind.isSecure {
                SecureField(L(field.kind.titleKey), text: credentialBinding(provider: provider, field: field))
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(L(field.kind.titleKey), text: credentialBinding(provider: provider, field: field))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var validationMessage: String {
        if enabledProviderIDs.isEmpty {
            return L("At least one authorization method is required.")
        }
        if selectedProvider.id == "codex",
           selectedMethod.id == "codex-cli",
           !CodexCLIAuthReader().hasUsableCredential {
            return L("Codex sign-in was not found on this Mac. Sign in with Codex first or use an OpenAI API key.")
        }
        return L("Fill required fields for enabled providers.")
    }

    private var emptyMethodMessage: String {
        if selectedProvider.id == "codex", selectedMethod.id == "codex-cli" {
            return CodexCLIAuthReader().hasUsableCredential
                ? L("Hermes Agent will import the existing Codex sign-in from this Mac when the server starts.")
                : L("Codex sign-in was not found on this Mac. Sign in with Codex first or use an OpenAI API key.")
        }
        return L("No local secret is required for this method.")
    }

    private var emptyMethodIcon: String {
        if selectedProvider.id == "codex", selectedMethod.id == "codex-cli", !CodexCLIAuthReader().hasUsableCredential {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var emptyMethodColor: Color {
        if selectedProvider.id == "codex", selectedMethod.id == "codex-cli", !CodexCLIAuthReader().hasUsableCredential {
            return .orange
        }
        return .secondary
    }

    private func credentialKey(provider: AuthProviderDefinition, field: AuthFieldDefinition) -> String {
        "\(provider.id).\(field.id)"
    }

    private func credentialValue(provider: AuthProviderDefinition, field: AuthFieldDefinition) -> String {
        credentialValues[credentialKey(provider: provider, field: field)] ?? ""
    }

    private func credentialBinding(provider: AuthProviderDefinition, field: AuthFieldDefinition) -> Binding<String> {
        let key = credentialKey(provider: provider, field: field)
        return Binding(
            get: { credentialValues[key] ?? "" },
            set: { credentialValues[key] = $0 }
        )
    }

    private func enabledBinding(for provider: AuthProviderDefinition) -> Binding<Bool> {
        Binding(
            get: { enabledProviderIDs.contains(provider.id) },
            set: { isEnabled in
                if isEnabled {
                    enabledProviderIDs.insert(provider.id)
                    selectedProviderID = provider.id
                } else {
                    enabledProviderIDs.remove(provider.id)
                }
                signInController.reset()
            }
        )
    }

    private func loadStoredCredentials() {
        let storedIDs = AppSettings.enabledAuthProviderIDs
        enabledProviderIDs = Set(storedIDs.isEmpty ? ["codex"] : storedIDs)
        selectedProviderID = AppSettings.primaryAuthProviderID
        selectedMethodIDs = AuthProviderCatalog.providers.reduce(into: [:]) { result, provider in
            result[provider.id] = AppSettings.authMethodID(for: provider.id)
        }
        let store = KeychainStore()
        for provider in AuthProviderCatalog.providers {
            for method in provider.methods {
                for field in method.fields {
                    if let value = try? store.get(provider.keychainKey(for: field)) {
                        credentialValues[credentialKey(provider: provider, field: field)] = value
                    }
                }
            }
        }
    }

    private func saveAndContinue() {
        saveError = nil
        do {
            let enabled = AuthProviderCatalog.providers
                .map(\.id)
                .filter { enabledProviderIDs.contains($0) }
            UserDefaults.standard.set(enabled, forKey: AppSettingKeys.enabledAuthProviders)
            let primaryProviderID = enabled.contains(selectedProviderID) ? selectedProviderID : (enabled.first ?? "codex")
            UserDefaults.standard.set(primaryProviderID, forKey: AppSettingKeys.primaryAuthProvider)
            for provider in AuthProviderCatalog.providers {
                UserDefaults.standard.set(
                    selectedMethodIDs[provider.id] ?? provider.defaultMethodID,
                    forKey: AppSettingKeys.authProviderMethodPrefix + provider.id
                )
            }

            let store = KeychainStore()
            for key in AuthProviderCatalog.allKeychainKeys {
                try? store.remove(key)
            }
            for provider in AuthProviderCatalog.providers where enabledProviderIDs.contains(provider.id) {
                let method = provider.method(id: selectedMethodIDs[provider.id] ?? provider.defaultMethodID)
                for field in method.fields {
                    let value = credentialValue(provider: provider, field: field).trimmingCharacters(in: .whitespacesAndNewlines)
                    try store.set(value, for: provider.keychainKey(for: field))
                }
            }
            coordinator.next()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func methodBinding(for provider: AuthProviderDefinition) -> Binding<String> {
        Binding(
            get: { selectedMethodIDs[provider.id] ?? provider.defaultMethodID },
            set: { newValue in
                selectedMethodIDs[provider.id] = newValue
                signInController.reset()
            }
        )
    }
}
