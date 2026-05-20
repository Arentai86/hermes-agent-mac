import SwiftUI

struct PreferencesWindow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        OpenzenBrandedContainer {
            TabView {
                GeneralTab()
                    .environmentObject(appState)
                    .tabItem { Label(L("General"), systemImage: "gearshape") }
                ServerTab()
                    .environmentObject(appState)
                    .tabItem { Label(L("Server"), systemImage: "server.rack") }
                AdvancedTab()
                    .environmentObject(appState)
                    .tabItem { Label(L("Advanced"), systemImage: "slider.horizontal.3") }
                AboutTab()
                    .environmentObject(appState)
                    .tabItem { Label(L("About"), systemImage: "info.circle") }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}
