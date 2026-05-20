import SwiftUI

private extension View {
    @ViewBuilder
    func onChangeCompat<T: Equatable>(of value: T, perform action: @escaping (T) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

struct GeneralTab: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = AppLocalization.shared
    @AppStorage(AppSettingKeys.launchAtLogin) private var launchAtLogin = true
    @AppStorage(AppSettingKeys.checkForUpdatesAutomatically) private var checkForUpdatesAutomatically = true
    @AppStorage(AppSettingKeys.startServerOnLaunch) private var startServerOnLaunch = true
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Picker(L("Language"), selection: Binding(
                get: { localization.languageCode },
                set: { localization.setLanguage($0) }
            )) {
                ForEach(AppLocalization.supportedLanguages) { language in
                    Text(language.nativeName).tag(language.code)
                }
            }

            Toggle(L("Start server when Hermes Agent launches"), isOn: $startServerOnLaunch)

            Toggle(L("Launch at login"), isOn: $launchAtLogin)
                .onChangeCompat(of: launchAtLogin) { enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                    }
                }

            Toggle(L("Check for updates automatically"), isOn: $checkForUpdatesAutomatically)
                .onChangeCompat(of: checkForUpdatesAutomatically) { enabled in
                    appState.updateManager?.automaticallyChecksForUpdates = enabled
                }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            Button(L("Open Setup Assistant...")) {
                WizardWindowController.shared.show(appState: appState)
            }
        }
        .formStyle(.grouped)
    }
}
