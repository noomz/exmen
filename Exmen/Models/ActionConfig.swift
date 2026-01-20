import Foundation

/// Script execution type
enum ScriptType: String, Codable {
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

/// Full action configuration from TOML file
struct ActionConfig: Codable {
    let name: String
    let icon: String?
    let description: String?
    let script: ScriptConfig
    let output: OutputConfig?
    let hook: HookConfig?

    /// Default output handler if not specified
    var resolvedOutput: OutputConfig {
        output ?? OutputConfig(handler: .clipboard)
    }
}
