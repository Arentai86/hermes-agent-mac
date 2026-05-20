import SwiftUI

struct FinishStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @AppStorage(AppSettingKeys.launchAtLogin) private var launchAtLogin = true
    @AppStorage(AppSettingKeys.checkForUpdatesAutomatically) private var checkForUpdatesAutomatically = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("All Set"))
                .font(.system(size: 28, weight: .semibold))
            Text(L("Hermes Agent will start now and open in your browser once the local health check passes."))
                .foregroundStyle(.secondary)

            Toggle(L("Launch at login"), isOn: $launchAtLogin)
            Toggle(L("Check for updates automatically"), isOn: $checkForUpdatesAutomatically)

            if let error = coordinator.finishError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            HStack {
                Button(L("Back"), action: coordinator.back)
                    .disabled(coordinator.isFinishing)
                Spacer()
                Button(coordinator.isFinishing ? L("Starting...") : L("Finish")) {
                    Task {
                        await coordinator.finish()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.isFinishing)
            }
        }
        .padding(32)
    }
}
