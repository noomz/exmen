import Foundation

// MARK: - HookLineEvent

/// Structured result of parsing a single EXMEN: hook line from script stdout.
/// Used by HookParser.parseLine(_:) — the per-line API introduced in Phase 11
/// for dynamic subtask spawning and progress reporting (D-05, D-12).
enum HookLineEvent {
    /// EXMEN:subtask=<inline TOML table> — dynamic subtask spawn request.
    /// `rawValue` is the text after "EXMEN:subtask=", passed to SubtaskConfig.decodeInlineTable.
    case subtask(rawValue: String)

    /// EXMEN:progress=N (0–100) — per-subtask opt-in progress update.
    case progress(Int)

    /// EXMEN:progress=N where N is outside 0–100 or not a valid integer.
    case invalidProgress(String)

    /// Legacy EXMEN:key=value hook (title, status, badge, icon) supported by Phase 8.
    case legacyHook(key: String, value: String)

    /// EXMEN:key=value where key is unrecognised.
    case unknown(key: String, value: String)
}

// MARK: - HookParser + parseLine

extension HookParser {

    /// Parse a single output line for EXMEN: hook content.
    /// Returns `nil` for non-hook lines (lines not prefixed with "EXMEN:").
    static func parseLine(_ line: String) -> HookLineEvent? {
        let prefix = "EXMEN:"
        guard line.hasPrefix(prefix) else { return nil }

        let rest = String(line.dropFirst(prefix.count))

        // Must contain "=" to be a valid key=value hook
        guard let eqIdx = rest.firstIndex(of: "=") else { return nil }

        let key   = String(rest[..<eqIdx])
        let value = String(rest[rest.index(after: eqIdx)...])

        switch key {
        case "subtask":
            return .subtask(rawValue: value)

        case "progress":
            if let n = Int(value) {
                if n >= 0 && n <= 100 {
                    return .progress(n)
                } else {
                    return .invalidProgress(value)
                }
            } else {
                return .invalidProgress(value)
            }

        case "title", "status", "badge", "icon":
            return .legacyHook(key: key, value: value)

        default:
            return .unknown(key: key, value: value)
        }
    }
}
