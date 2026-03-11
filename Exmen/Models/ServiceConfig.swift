import Foundation

/// Discriminator for top-level action TOML entries
enum ActionType: String, Codable {
    case action   // default — existing behavior
    case service  // long-running managed service
}

/// Restart policy for managed services
enum RestartPolicy: String, Codable {
    case never      = "never"
    case onFailure  = "on-failure"
    case always     = "always"
}

/// Configuration for a managed long-running service (from [service] TOML section)
struct ServiceConfig: Codable {
    let command: String
    let args: [String]?
    let restart: RestartPolicy?
    let max_restarts: Int?
    let keep_alive: Bool?
    let working_dir: String?
    let env: [String: String]?

    /// Resolved restart policy (default: .never)
    var resolvedRestart: RestartPolicy { restart ?? .never }

    /// Maximum restart attempts before transitioning to .crashed (default: 3)
    var resolvedMaxRestarts: Int { max_restarts ?? 3 }

    /// Whether the service should continue running after Exmen quits (default: false)
    var resolvedKeepAlive: Bool { keep_alive ?? false }

    /// Resolved working directory with tilde expansion
    var resolvedWorkingDir: String? {
        guard let dir = working_dir else { return nil }
        return NSString(string: dir).expandingTildeInPath
    }

    /// Resolved environment: current process env + Homebrew PATH + TERM + service-specific overrides
    var resolvedEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Ensure common tool locations are on PATH, including Homebrew
        let basePath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        if let existing = environment["PATH"] {
            environment["PATH"] = basePath + ":" + existing
        } else {
            environment["PATH"] = basePath
        }
        // Full color support for PTY programs
        environment["TERM"] = "xterm-256color"
        // Overlay service-specific environment variables
        for (key, value) in env ?? [:] {
            environment[key] = value
        }
        return environment
    }
}
