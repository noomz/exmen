import SwiftUI

/// A row view for a managed service in the menu.
/// Displays a colored status dot, service name, and status text.
/// Interaction is via right-click context menu only — left-click does NOT toggle the service.
struct ServiceRowView: View {
    @ObservedObject var service: ManagedService

    @State private var isHovered = false

    /// Dot color that respects hook-driven dynamic status over the raw service state.
    /// Phrase matching lives in `ServiceState.dotColor` so it can be tested and
    /// so negatives ("not running") are matched before positives ("running").
    private var effectiveDotColor: Color {
        ServiceState.dotColor(state: service.state, hookStatus: service.action.dynamicStatus)
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

                // Surface failures in the menu itself — a notification is easy
                // to miss, and a red dot alone does not say what went wrong.
                if let error = service.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(error)
                }
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

            // Enabled for .crashed too: stopping a crashed service clears a
            // pending restart backoff and settles it at .stopped.
            Button("Stop") {
                ServiceManager.shared.stop(service)
            }
            .disabled(service.state == .stopped)

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
