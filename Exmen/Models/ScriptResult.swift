import Foundation

/// Result of a script execution
struct ScriptResult {
    let output: String
    let error: String
    let exitCode: Int32
    let duration: TimeInterval

    /// Whether the script succeeded (exit code 0)
    var isSuccess: Bool {
        exitCode == 0
    }

    /// Combined output (stdout + stderr if any)
    var combinedOutput: String {
        if error.isEmpty {
            return output
        } else if output.isEmpty {
            return error
        } else {
            return output + "\n" + error
        }
    }

    /// Trimmed output (removes trailing whitespace/newlines)
    var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Errors that can occur during script execution
enum ScriptError: Error, LocalizedError {
    case noScriptContent
    case scriptFileNotFound(String)
    case executionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noScriptContent:
            return "No script content provided"
        case .scriptFileNotFound(let path):
            return "Script file not found: \(path)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .timeout:
            return "Script execution timed out"
        }
    }
}
