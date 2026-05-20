import AppKit
import SwiftUI

/// Lets the user pick where the Hermes Agent server runtime comes from:
/// the bundled copy, latest internet download, a direct archive URL, or a local file/folder.
struct SourceStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @State private var selection: Selection = .bundled
    @State private var localServerURL: URL?
    @State private var serverURLText: String = ""
    @State private var installing = false
    @State private var stage: String = ""
    @State private var fraction: Double = 0
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let installer = RuntimeInstaller()
    private let runtime = RuntimeBundle()

    enum Selection: String, CaseIterable {
        case bundled
        case download
        case url
        case local

        var titleKey: String {
            switch self {
            case .bundled: return "Use built-in runtime"
            case .download: return "Download latest from internet"
            case .url: return "Install from link"
            case .local: return "Use local file on this Mac"
            }
        }

        var descriptionKey: String {
            switch self {
            case .bundled: return "Run the Hermes Agent server bundled inside this .app. Recommended."
            case .download: return "Download the latest Hermes Agent source from GitHub and reuse bundled dashboard assets if the source archive omits them."
            case .url: return "Paste a direct .tgz, .tar.gz, .tar, or .zip link to an Hermes Agent server archive."
            case .local: return "Pick an Hermes Agent server folder, zip, or tarball already on this Mac."
            }
        }
    }

    private var bundledAvailable: Bool {
        runtime.bundledRuntimeIsUsable
    }

    private var bundledPlaceholder: Bool {
        runtime.isFallbackRuntime(at: runtime.bundledRuntimeDirectory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Runtime Source"))
                    .font(.system(size: 28, weight: .semibold))
                Text(L("Choose where Hermes Agent should get its local server runtime from."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Selection.allCases, id: \.self) { option in
                    sourceCard(option)
                }
            }

            if selection == .local {
                localPickers
            } else if selection == .download {
                downloadOptions
            } else if selection == .url {
                urlOptions
            }

            if installing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    Text(stage).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let successMessage {
                Label(successMessage, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            Spacer()

            HStack {
                Button(L("Back"), action: coordinator.back)
                    .disabled(installing)
                Spacer()
                if selection == .bundled {
                    Button(L("Continue")) {
                        Task { await proceed() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(installing || !bundledAvailable)
                } else {
                    Button(installing ? L("Installing...") : actionTitle) {
                        Task { await proceed() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(installing || !canProceed)
                }
            }
        }
        .padding(28)
        .onAppear(perform: chooseDefaultSelection)
    }

    private var canProceed: Bool {
        switch selection {
        case .bundled:
            return bundledAvailable
        case .download:
            return true
        case .url:
            return serverURL != nil
        case .local:
            return localServerURL != nil
        }
    }

    private func chooseDefaultSelection() {
        if installer.isInstalled {
            successMessage = LF("Runtime already installed at %@", installer.installedRuntimeURL.lastPathComponent)
        }
        if !bundledAvailable {
            selection = .download
            if bundledPlaceholder {
                errorMessage = L("This build contains only a launcher test runtime, not the real Hermes Agent server.")
            }
        }
    }

    private func sourceCard(_ option: Selection) -> some View {
        Button {
            selection = option
            errorMessage = nil
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection == option ? Color.accentColor : .secondary)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L(option.titleKey))
                            .font(.headline)
                        if option == .bundled, !bundledAvailable {
                            Text(L(bundledPlaceholder ? "Test placeholder only" : "Not bundled in this build"))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(L(option == .bundled && bundledPlaceholder
                           ? "This build contains only a launcher test runtime, not the real Hermes Agent server."
                           : option.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selection == option ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.18), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == option ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(option == .bundled && !bundledAvailable)
    }

    private var downloadOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Will fetch the latest Hermes Agent source from GitHub. If GitHub does not include a built dashboard, the installer restores the bundled dashboard assets automatically. Python dependencies are prepared on first launch if needed."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 30)
    }

    private var urlOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Hermes Agent archive link"))
                    .font(.caption.weight(.semibold))
                TextField("https://example.com/hermes.tgz", text: $serverURLText)
                    .textFieldStyle(.roundedBorder)
                Text(L("Direct links to .tgz, .tar.gz, .tar, and .zip archives are supported."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 30)
    }

    private var localPickers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Hermes Agent server"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(localServerURL?.lastPathComponent ?? L("Required"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(localServerURL == nil ? .red : .secondary)
                Button(L("Choose...")) {
                    if let url = pickFile(allowedTypes: ["tar.gz", "tgz", "gz", "zip"], allowDirectories: true) {
                        localServerURL = url
                    }
                }
            }
            Text(L("Folder, .tar.gz, .tgz, or .zip are supported."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 30)
    }

    private func pickFile(allowedTypes: [String], allowDirectories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowDirectories
        panel.allowsMultipleSelection = false
        panel.message = L("Pick the file or folder.")
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private func proceed() async {
        errorMessage = nil
        successMessage = nil
        installing = true
        fraction = 0
        stage = ""

        let source: RuntimeInstaller.Source
        switch selection {
        case .bundled: source = .bundled
        case .download: source = .download
        case .url:
            guard let url = serverURL else {
                errorMessage = L("Enter a valid Hermes Agent server archive link.")
                installing = false
                return
            }
            source = .url(url)
        case .local:
            guard let server = localServerURL else {
                errorMessage = L("Pick the Hermes Agent server folder or archive first.")
                installing = false
                return
            }
            source = .local(server: server)
        }

        do {
            try await installer.install(
                source: source,
                serverRef: RuntimeInstaller.defaultServerRef
            ) { progress in
                self.fraction = progress.fraction
                self.stage = progress.stage
            }
            UserDefaults.standard.set(selectionTag(selection), forKey: AppSettingKeys.runtimeSource)
            coordinator.markRuntimeInstalled()
            successMessage = L("Runtime is ready.")
            installing = false
            coordinator.next()
        } catch {
            errorMessage = error.localizedDescription
            installing = false
        }
    }

    private func selectionTag(_ selection: Selection) -> String {
        switch selection {
        case .bundled: return "bundled"
        case .download: return "download"
        case .url: return "url"
        case .local: return "local"
        }
    }

    private var serverURL: URL? {
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private var actionTitle: String {
        switch selection {
        case .download:
            return L("Download latest & Continue")
        case .url:
            return L("Download from Link & Continue")
        case .bundled, .local:
            return L("Install & Continue")
        }
    }
}
