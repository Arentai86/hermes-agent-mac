import SwiftUI

struct PortStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @AppStorage(AppSettingKeys.serverPort) private var serverPort = 9119
    @State private var portText = "\(AppSettings.serverPort)"

    private var validation: PortValidation {
        guard let port = Int(portText), (1...65535).contains(port) else {
            return .invalid(L("Enter a port between 1 and 65535."))
        }
        return PortManager().isPortAvailable(UInt16(port)) ? .ok : .invalid(LF("Port %d is already in use.", port))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Server Port"))
                .font(.system(size: 28, weight: .semibold))
            Text(L("Hermes Agent binds only to 127.0.0.1 and never listens on external interfaces."))
                .foregroundStyle(.secondary)

            HStack {
                TextField(L("Port"), text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button(L("Auto-detect")) {
                    if let port = PortManager().firstAvailablePort(startingAt: 9119) {
                        portText = "\(port)"
                        serverPort = port
                    }
                }
            }

            Label(validation.message, systemImage: validation.icon)
                .foregroundStyle(validation.color)

            Spacer()
            WizardFooter(
                canGoBack: true,
                canContinue: validation.isValid,
                continueTitle: L("Continue"),
                onBack: coordinator.back,
                onContinue: {
                    if let port = Int(portText) {
                        serverPort = port
                    }
                    coordinator.next()
                }
            )
        }
        .padding(32)
        .onAppear {
            portText = "\(serverPort)"
        }
    }
}

enum PortValidation {
    case ok
    case invalid(String)

    var isValid: Bool {
        if case .ok = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .ok:
            return L("Port is available.")
        case let .invalid(message):
            return message
        }
    }

    var icon: String {
        isValid ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var color: Color {
        isValid ? .green : .red
    }
}
