import AppKit
import SwiftUI

/// English-only first screen, by request: before the localized wizard starts, the user
/// chooses whether this launch should install/start HermesAgent or remove it.
struct SetupActionStep: View {
    @ObservedObject var coordinator: WizardCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 8)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Hermes Agent")
                    .font(.system(size: 34, weight: .semibold))
                Text("What do you want to do?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await coordinator.chooseInstall() }
                } label: {
                    Label("Install Hermes Agent", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(coordinator.isPerformingAction)

                Button {
                    coordinator.chooseUninstall()
                } label: {
                    Label("Uninstall Hermes Agent", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(coordinator.isPerformingAction)
            }

            if coordinator.isPerformingAction {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let actionError = coordinator.actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(32)
    }
}
