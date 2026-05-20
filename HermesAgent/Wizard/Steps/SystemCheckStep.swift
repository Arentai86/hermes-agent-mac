import Foundation
import Network
import SwiftUI

struct SystemCheckStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @StateObject private var runner = SystemCheckRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("System Check"))
                .font(.system(size: 28, weight: .semibold))
            Text(L("Hermes Agent checks the parts it needs before creating your local workspace."))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(runner.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.state.symbol)
                            .foregroundStyle(item.state.color)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(item.title)).font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            WizardFooter(
                canGoBack: true,
                canContinue: runner.canContinue,
                continueTitle: L("Continue"),
                onBack: coordinator.back,
                onContinue: coordinator.next
            )
        }
        .padding(32)
        .task {
            await runner.run()
        }
    }
}

@MainActor
final class SystemCheckRunner: ObservableObject {
    @Published var items: [SystemCheckItem] = [
        SystemCheckItem(title: "macOS 13 or newer", detail: L("Checking OS version"), state: .pending),
        SystemCheckItem(title: "Application Support writable", detail: L("Checking storage permissions"), state: .pending),
        SystemCheckItem(title: "Free disk space", detail: L("Checking available capacity"), state: .pending),
        SystemCheckItem(title: "Network path", detail: L("Checking network reachability"), state: .pending)
    ]

    var canContinue: Bool {
        items.allSatisfy { !$0.isCritical || $0.state == .ok }
    }

    func run() async {
        set("macOS 13 or newer", state: ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)
        ) ? .ok : .failed, detail: L("Ventura or newer is required."))

        do {
            try Paths.ensureBaseDirectories()
            set("Application Support writable", state: .ok, detail: Paths.applicationSupportDirectory.path)
        } catch {
            set("Application Support writable", state: .failed, detail: error.localizedDescription)
        }

        let capacity = (try? Paths.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
            .flatMap(\.volumeAvailableCapacityForImportantUsage)
        if let capacity, capacity > 2_000_000_000 {
            set("Free disk space", state: .ok, detail: ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))
        } else {
            set("Free disk space", state: .failed, detail: L("At least 2 GB is recommended."))
        }

        let isReachable = await NetworkProbe().isNetworkReachable()
        set("Network path", state: isReachable ? .ok : .warning, detail: isReachable ? L("Network appears reachable.") : L("You can continue, but updates may fail."))
    }

    private func set(_ title: String, state: SystemCheckState, detail: String) {
        guard let index = items.firstIndex(where: { $0.title == title }) else { return }
        items[index].state = state
        items[index].detail = detail
    }
}

struct SystemCheckItem: Identifiable {
    let id = UUID()
    let title: String
    var detail: String
    var state: SystemCheckState
    var isCritical: Bool { title != "Network path" }
}

enum SystemCheckState {
    case pending
    case ok
    case warning
    case failed

    var symbol: String {
        switch self {
        case .pending:
            return "clock"
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .ok:
            return .green
        case .warning:
            return .yellow
        case .failed:
            return .red
        }
    }
}

struct NetworkProbe {
    func isNetworkReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "Hermes Agent.NetworkProbe")
            monitor.pathUpdateHandler = { path in
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }
}
