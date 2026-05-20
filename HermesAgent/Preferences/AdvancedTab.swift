import AppKit
import SwiftUI

struct AdvancedTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettingKeys.customNodePath) private var customNodePath = ""
    @AppStorage(AppSettingKeys.environmentVariablesRaw) private var environmentVariablesRaw = ""
    @State private var uninstallError: String?

    var body: some View {
        Form {
            TextField(L("Custom Python or runner path"), text: $customNodePath)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading) {
                Text(L("Environment variables"))
                TextEditor(text: $environmentVariablesRaw)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 90)
                    .border(.quaternary)
            }

            HStack {
                Button(L("Open Data Folder")) {
                    NSWorkspace.shared.open(AppSettings.dataLocationURL)
                }
                Button(L("Open Logs Folder")) {
                    NSWorkspace.shared.open(Paths.logsDirectory)
                }
                Button(L("Export Diagnostics")) {
                    Task.detached(priority: .userInitiated) {
                        guard let url = try? DiagnosticsExporter().export() else { return }
                        await MainActor.run {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }

            Divider()

            Button(L("Uninstall Hermes Agent..."), role: .destructive) {
                uninstall()
            }

            if let uninstallError {
                Text(uninstallError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func uninstall() {
        let alert = NSAlert()
        alert.messageText = L("Uninstall Hermes Agent?")
        alert.informativeText = L("This stops the server and removes Hermes Agent data, logs, preferences, and stored credentials.")
        alert.addButton(withTitle: L("Uninstall"))
        alert.addButton(withTitle: L("Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            appState.stopServer()
            try Uninstaller().uninstall()
        } catch {
            uninstallError = error.localizedDescription
        }
    }
}
