import SwiftUI

struct StatusIndicator: View {
    let status: ServerStatus

    var body: some View {
        Image(systemName: status.symbolName)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(status.title)
    }
}

extension ServerStatus {
    var symbolName: String {
        switch self {
        case .stopped:
            return "circle"
        case .starting:
            return "circle.lefthalf.filled"
        case .running:
            return "checkmark.circle.fill"
        case .stopping:
            return "pause.circle"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var menuColor: Color {
        switch self {
        case .stopped:
            return .secondary
        case .starting:
            return .yellow
        case .running:
            return .green
        case .stopping:
            return .orange
        case .error:
            return .red
        }
    }
}

