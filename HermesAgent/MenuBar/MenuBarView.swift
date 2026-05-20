import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpenzenLogoView(width: 58, height: 38)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                StatusDot(status: appState.serverStatus)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.serverStatus.title)
                        .font(.headline)
                    Text(LF("Port: %d", appState.currentPort))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()

            QuickActions()
                .environmentObject(appState)

            if let lastError = appState.lastError {
                Divider()
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            OpenzenBrandFooter(font: .caption2)
        }
        .padding(14)
        .frame(width: 320)
        .background(OpenzenBranding.background)
        .preferredColorScheme(.light)
    }
}

private struct StatusDot: View {
    let status: ServerStatus

    var body: some View {
        Circle()
            .fill(status.menuColor)
            .frame(width: 12, height: 12)
    }
}
