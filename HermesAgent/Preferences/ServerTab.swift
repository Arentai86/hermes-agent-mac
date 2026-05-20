import AppKit
import SwiftUI

struct ServerTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettingKeys.serverPort) private var serverPort = 9119
    @AppStorage(AppSettingKeys.autoRestartServer) private var autoRestartServer = true
    @AppStorage(AppSettingKeys.dataLocation) private var dataLocation = Paths.defaultDataDirectory.path
    @AppStorage(AppSettingKeys.maxLogSizeMB) private var maxLogSizeMB = 25

    var body: some View {
        Form {
            Stepper(LF("Port: %d", serverPort), value: $serverPort, in: 1024...65535)
            Toggle(L("Auto-restart on crash"), isOn: $autoRestartServer)
            Stepper(LF("Max log size: %d MB", maxLogSizeMB), value: $maxLogSizeMB, in: 5...500, step: 5)

            HStack {
                Text(L("Data location"))
                Spacer()
                Text(dataLocation)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(L("Choose..."), action: chooseDataLocation)
            }

            Button(L("Restart Server")) {
                Task { await appState.restartServer() }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDataLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            dataLocation = url.path
        }
    }
}
