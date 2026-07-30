import SwiftUI

/// A row view for a managed service in the menu.
/// Displays a colored status dot, service name, and status text.
/// Interaction is via right-click context menu only — left-click does NOT toggle the service.
struct ServiceRowView: View {
    @ObservedObject var service: ManagedService

    @State private var isHovered = false

    /// Dot color that respects hook-driven dynamic status over the raw service state
    private var effectiveDotColor: Color {
        if let status = service.action.dynamicStatus {
            if status.lowercased().contains("running") {
                return .green
            }
            if status.lowercased().contains("crashed") || status.lowercased().contains("stop") {
                return .red
            }
        }
        return service.state.dotColor
    }

    var body: some View {
        HStack(spacing: 8) {
            // Colored status dot
            Circle()
                .fill(effectiveDotColor)
                .frame(width: 8, height: 8)

            // Name and status
            VStack(alignment: .leading, spacing: 1) {
                Text(service.action.name)
                    .font(.callout)

                Text(service.action.dynamicStatus ?? ServiceState.displayText(state: service.state, startedAt: service.startedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Start") {
                ServiceManager.shared.start(service)
            }
            .disabled(service.state.isActive)

            Button("Stop") {
                ServiceManager.shared.stop(service)
            }
            .disabled(!service.state.isActive)

            Button("Restart") {
                ServiceManager.shared.restart(service)
            }

            Divider()

            Button("View Output") {
                ServiceManager.shared.showOutput(for: service)
            }
        }
    }
}
