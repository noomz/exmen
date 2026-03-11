import SwiftUI

/// Lifecycle state of a managed service
enum ServiceState: Equatable {
    case stopped
    case starting
    case running
    case restarting
    case crashed

    /// Status indicator dot color for the service row UI
    var dotColor: Color {
        switch self {
        case .running:               return .green
        case .stopped:               return .gray
        case .starting, .restarting: return .yellow
        case .crashed:               return .red
        }
    }

    /// Whether the service is currently active (running or transitioning)
    var isActive: Bool {
        switch self {
        case .running, .starting, .restarting: return true
        case .stopped, .crashed:               return false
        }
    }

    /// Human-readable display text, optionally including uptime when running
    static func displayText(state: ServiceState, startedAt: Date?) -> String {
        switch state {
        case .stopped:
            return "stopped"
        case .starting:
            return "starting..."
        case .restarting:
            return "restarting..."
        case .crashed:
            return "crashed"
        case .running:
            guard let start = startedAt else { return "running" }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour, .minute]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 2
            let uptime = formatter.string(from: start, to: Date()) ?? "—"
            return "running - uptime \(uptime)"
        }
    }
}
