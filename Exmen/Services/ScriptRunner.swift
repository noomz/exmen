import Foundation

/// Service for executing shell scripts
class ScriptRunner {
    static let shared = ScriptRunner()

    /// Default timeout for script execution (30 seconds)
    let defaultTimeout: TimeInterval = 30.0

    private init() {}

    /// Execute a script from ScriptConfig
    func run(_ config: ScriptConfig, timeout: TimeInterval? = nil) async throws -> ScriptResult {
        guard let content = config.resolvedContent() else {
            if config.type == .file {
                throw ScriptError.scriptFileNotFound(config.path ?? "unknown")
            }
            throw ScriptError.noScriptContent
        }

        return try await runScript(content, timeout: timeout ?? defaultTimeout)
    }

    /// Execute a script string directly
    func runScript(_ script: String, timeout: TimeInterval? = nil) async throws -> ScriptResult {
        let startTime = Date()
        let effectiveTimeout = timeout ?? defaultTimeout

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Set up environment with common paths including Homebrew on Apple Silicon
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
            process.environment = environment

            // Timeout handling
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: ScriptError.timeout)
                }
            }

            DispatchQueue.global().asyncAfter(
                deadline: .now() + effectiveTimeout,
                execute: timeoutWorkItem
            )

            process.terminationHandler = { [weak outputPipe, weak errorPipe] proc in
                timeoutWorkItem.cancel()

                let outputData = outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let errorData = errorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                let duration = Date().timeIntervalSince(startTime)

                let result = ScriptResult(
                    output: output,
                    error: error,
                    exitCode: proc.terminationStatus,
                    duration: duration
                )

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                timeoutWorkItem.cancel()
                continuation.resume(throwing: ScriptError.executionFailed(error.localizedDescription))
            }
        }
    }
}
