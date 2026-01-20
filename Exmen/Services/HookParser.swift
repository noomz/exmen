import Foundation

/// Parser for extracting hook updates from script output
class HookParser {
    static let shared = HookParser()

    /// Prefix for hook lines
    private let hookPrefix = "EXMEN:"

    private init() {}

    /// Parse script output for hook updates
    /// Format: EXMEN:key=value (one per line)
    /// Supported keys: title, status, badge, icon
    func parse(_ output: String) -> (cleanOutput: String, updates: HookUpdate) {
        var updates = HookUpdate()
        var cleanLines: [String] = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix(hookPrefix) {
                // Parse hook line
                let hookContent = String(line.dropFirst(hookPrefix.count))
                if let (key, value) = parseKeyValue(hookContent) {
                    applyUpdate(key: key, value: value, to: &updates)
                }
            } else {
                // Keep non-hook lines for clean output
                cleanLines.append(line)
            }
        }

        let cleanOutput = cleanLines.joined(separator: "\n")
        return (cleanOutput, updates)
    }

    /// Parse a key=value string
    private func parseKeyValue(_ content: String) -> (key: String, value: String)? {
        guard let equalsIndex = content.firstIndex(of: "=") else {
            return nil
        }

        let key = String(content[..<equalsIndex]).trimmingCharacters(in: .whitespaces).lowercased()
        let value = String(content[content.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

        guard !key.isEmpty, !value.isEmpty else {
            return nil
        }

        return (key, value)
    }

    /// Apply a parsed key-value to the updates struct
    private func applyUpdate(key: String, value: String, to updates: inout HookUpdate) {
        switch key {
        case "title":
            updates.title = value
        case "status":
            updates.status = value
        case "badge":
            updates.badge = value
        case "icon":
            updates.icon = value
        default:
            print("HookParser: Unknown key '\(key)'")
        }
    }
}
