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

    /// Phrases in a hook-provided status that mean "this service is NOT up".
    /// Checked before `upPhrases` because several of them contain an "up" phrase
    /// as a substring — "not running" contains "running", "inactive" contains
    /// "active". Matching positives first paints a dead service green.
    private static let downPhrases = [
        "not running", "not-running", "notrunning",
        "not listening", "not available", "not started",
        "stopped", "stopping", "crashed", "failed", "error",
        "offline", "inactive", "dead", "down", "unavailable"
    ]

    /// Phrases in a hook-provided status that mean "this service is up".
    private static let upPhrases = [
        "running", "listening", "online", "active", "healthy", "started", "ready"
    ]

    /// Resolve the row's status dot color, letting a hook-provided status string
    /// override the raw lifecycle state.
    ///
    /// A service whose `[hook.status_script]` reports "not running" must show a
    /// red dot, not a green one — see `downPhrases` for why ordering matters.
    /// A status string that matches neither list falls back to `state`.
    static func dotColor(state: ServiceState, hookStatus: String?) -> Color {
        guard let hookStatus else { return state.dotColor }

        let normalized = hookStatus.lowercased()
        if downPhrases.contains(where: normalized.contains) {
            return .red
        }
        if upPhrases.contains(where: normalized.contains) {
            return .green
        }
        return state.dotColor
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
