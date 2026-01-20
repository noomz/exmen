import Foundation

/// Represents a dynamic update from a script's hook output
struct HookUpdate {
    var title: String?
    var status: String?
    var badge: String?
    var icon: String?

    /// Whether any update was received
    var hasUpdates: Bool {
        title != nil || status != nil || badge != nil || icon != nil
    }

    /// Merge another update into this one (newer values override)
    mutating func merge(_ other: HookUpdate) {
        if let title = other.title { self.title = title }
        if let status = other.status { self.status = status }
        if let badge = other.badge { self.badge = badge }
        if let icon = other.icon { self.icon = icon }
    }
}

/// Configuration for hook behavior in TOML
struct HookConfig: Codable {
    /// Script to run for status updates (optional)
    let statusScript: ScriptConfig?

    /// Polling interval in seconds (0 = disabled)
    let pollInterval: Int?

    /// Whether to parse main script output for hooks
    let parseOutput: Bool?

    enum CodingKeys: String, CodingKey {
        case statusScript = "status_script"
        case pollInterval = "poll_interval"
        case parseOutput = "parse_output"
    }

    /// Default poll interval (60 seconds)
    static let defaultPollInterval = 60

    /// Resolved poll interval
    var resolvedPollInterval: Int {
        pollInterval ?? Self.defaultPollInterval
    }

    /// Whether to parse output (default true)
    var shouldParseOutput: Bool {
        parseOutput ?? true
    }
}
