import SwiftUI

struct WelcomeStep: View {
    @ObservedObject var coordinator: WizardCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Welcome to Hermes Agent"))
                    .font(.system(size: 32, weight: .semibold))
                Text(L("Hermes Agent runs the local server, keeps it healthy, and gives you one-click access from the macOS menu bar."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
}

struct WizardFooter: View {
    let canGoBack: Bool
    let canContinue: Bool
    let continueTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            Button(L("Back"), action: onBack)
                .disabled(!canGoBack)
            Spacer()
            Button(continueTitle, action: onContinue)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
    }
}
