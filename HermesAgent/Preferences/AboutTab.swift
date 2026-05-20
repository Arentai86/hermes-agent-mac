import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hermes Agent")
                .font(.system(size: 28, weight: .semibold))
            Text(LF("Version %@ (%@)", bundleValue("CFBundleShortVersionString"), bundleValue("CFBundleVersion")))
                .foregroundStyle(.secondary)

            Link(L("GitHub"), destination: URL(string: "https://github.com/hermes/hermes-mac")!)
            Link(L("License"), destination: URL(string: "https://github.com/hermes/hermes-mac/blob/main/LICENSE")!)

            Button(L("Check for Updates")) {
                appState.updateManager?.checkForUpdates()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "0"
    }
}
