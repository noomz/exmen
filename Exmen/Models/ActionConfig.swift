import Foundation

/// Script execution type
enum ScriptType: String, Codable, Equatable {
    case inline  // Script content embedded in TOML
    case file    // Path to external script file
}

/// Output handling method
enum OutputHandler: String, Codable {
    case clipboard     // Copy output to clipboard
    case notification  // Show macOS notification
    case popup         // Show in popup window
}

/// Script configuration from TOML
struct ScriptConfig: Codable {
    let type: ScriptType
    let content: String?  // For inline scripts
    let path: String?     // For file scripts

    /// Get the script content, reading from file if needed
    func resolvedContent() -> String? {
        switch type {
        case .inline:
            return content
        case .file:
            guard let path = path else { return nil }
            let expandedPath = NSString(string: path).expandingTildeInPath
            return try? String(contentsOfFile: expandedPath, encoding: .utf8)
        }
    }
}

/// Output configuration from TOML
struct OutputConfig: Codable {
    let handler: OutputHandler

    init(handler: OutputHandler = .clipboard) {
        self.handler = handler
    }
}

/// Result of evaluating a `[when]` block. Unsatisfied items are hidden
/// from the menu unless the user enables "Show hidden".
struct WhenEvaluation: Equatable {
    let isSatisfied: Bool
    let reasons: [String]

    var reasonCaption: String { reasons.joined(separator: ", ") }

    static let satisfied = WhenEvaluation(isSatisfied: true, reasons: [])
}

/// Optional visibility conditions on an action or service.
///
/// Every specified field must pass (AND). Omit the `[when]` table — or leave
/// a field blank — to skip that check.
struct WhenConfig: Codable, Equatable {
    let command: String?
    let file: String?
    let env: String?

    /// Same Homebrew-aware prefixes ScriptRunner / services use, plus the
    /// process PATH so a user-installed CLI still counts as present.
    static let standardSearchPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

    static func resolvedSearchPath(
        processEnv: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let existing = processEnv["PATH"], !existing.isEmpty {
            return standardSearchPath + ":" + existing
        }
        return standardSearchPath
    }

    func evaluate(
        path: String = WhenConfig.resolvedSearchPath(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> WhenEvaluation {
        var reasons: [String] = []

        if let command = trimmed(command) {
            if !Self.commandExists(
                command,
                path: path,
                fileExists: fileExists,
                isExecutable: isExecutable
            ) {
                reasons.append("\(command) not found")
            }
        }

        if let file = trimmed(file) {
            let expanded = (file as NSString).expandingTildeInPath
            if !fileExists(expanded) {
                reasons.append("missing \(file)")
            }
        }

        if let env = trimmed(env) {
            let value = environment[env]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                reasons.append("$\(env) not set")
            }
        }

        return reasons.isEmpty
            ? .satisfied
            : WhenEvaluation(isSatisfied: false, reasons: reasons)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func commandExists(
        _ command: String,
        path: String,
        fileExists: (String) -> Bool,
        isExecutable: (String) -> Bool
    ) -> Bool {
        let expanded = (command as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return fileExists(expanded) && isExecutable(expanded)
        }
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(expanded)
                .path
            if fileExists(candidate) && isExecutable(candidate) {
                return true
            }
        }
        return false
    }
}

/// Full action configuration from TOML file
struct ActionConfig: Codable {
    let name: String
    let icon: String?
    let description: String?
    /// Optional — regular actions have [script], services use [service].command instead
    let script: ScriptConfig?
    let output: OutputConfig?
    let hook: HookConfig?
    let hide_on_click: Bool?
    /// Discriminator: nil defaults to .action for full backward compatibility
    let type: ActionType?
    /// Service configuration — only present when type == "service"
    let service: ServiceConfig?
    /// Optional subtasks for orchestrated multi-step actions (Phase 11, D-01)
    let subtasks: [SubtaskConfig]?
    /// Optional visibility conditions. Missing `[when]` = always shown.
    let when: WhenConfig?

    /// Resolved action type (default: .action)
    var resolvedType: ActionType { type ?? .action }

    /// Whether this config describes a managed long-running service
    var isService: Bool { resolvedType == .service }

    /// Default output handler if not specified
    var resolvedOutput: OutputConfig {
        output ?? OutputConfig(handler: .clipboard)
    }

    /// Whether to hide menu on click (default: true)
    var resolvedHideOnClick: Bool {
        hide_on_click ?? true
    }
}
