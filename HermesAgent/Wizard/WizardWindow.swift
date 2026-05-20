import AppKit
import SwiftUI

@MainActor
final class WizardWindowController: NSWindowController {
    static let shared = WizardWindowController()

    private var coordinator: WizardCoordinator?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hermes Agent Setup"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 560)
        window.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 1)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(appState: AppState) {
        let coordinator = WizardCoordinator(appState: appState)
        self.coordinator = coordinator
        window?.contentView = NSHostingView(rootView: WizardRootView(coordinator: coordinator))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWizard() {
        close()
        coordinator = nil
    }
}

struct WizardRootView: View {
    @ObservedObject var coordinator: WizardCoordinator

    var body: some View {
        ZStack(alignment: .topLeading) {
            OpenzenBrandedContainer {
                Group {
                    switch coordinator.step {
                    case .setupAction:
                        SetupActionStep(coordinator: coordinator)
                    case .language:
                        LanguageStep(coordinator: coordinator)
                    case .welcome:
                        WelcomeStep(coordinator: coordinator)
                    case .systemCheck:
                        SystemCheckStep(coordinator: coordinator)
                    case .source:
                        SourceStep(coordinator: coordinator)
                    case .dataLocation:
                        DataLocationStep(coordinator: coordinator)
                    case .port:
                        PortStep(coordinator: coordinator)
                    case .apiKeys:
                        APIKeysStep(coordinator: coordinator)
                    case .skills:
                        SkillsStep(coordinator: coordinator)
                    case .finish:
                        FinishStep(coordinator: coordinator)
                    }
                }
                .environment(\.layoutDirection, AppLocalization.shared.layoutDirection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if coordinator.canShowBackArrow {
                Button {
                    coordinator.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(L("Back"))
                .padding(.leading, 12)
                .padding(.top, 18)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}
