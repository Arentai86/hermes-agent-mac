import AppKit
import SwiftUI

struct DataLocationStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @AppStorage(AppSettingKeys.dataLocation) private var dataLocation = Paths.applicationSupportDirectory.path

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Data Location"))
                .font(.system(size: 28, weight: .semibold))
            Text(L("Choose where Hermes Agent stores editable data, cache, skills, and configuration."))
                .foregroundStyle(.secondary)

            HStack {
                Text(dataLocation)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L("Choose..."), action: chooseLocation)
            }
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            Button(L("Use Default")) {
                dataLocation = Paths.applicationSupportDirectory.path
            }

            Spacer()
            WizardFooter(
                canGoBack: true,
                canContinue: true,
                continueTitle: L("Continue"),
                onBack: coordinator.back,
                onContinue: coordinator.next
            )
        }
        .padding(32)
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            dataLocation = url.path
        }
    }
}
