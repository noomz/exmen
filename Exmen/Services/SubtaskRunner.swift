import Foundation

// MARK: - SubtaskIOEvent

/// IO-level events emitted by `SubtaskRunner` while a subtask process runs.
///
/// Distinct from `SubtaskEvent` (the orchestrator-level lifecycle hook in
/// `SubtaskOrchestrator`). These are per-line streaming events drained live from
/// the child process's stdout/stderr — they enable live progress (ORCH-03) and
/// dynamic subtask spawn (ORCH-04) without buffering the whole output to EOF.
enum SubtaskIOEvent {
    /// A clean stdout line (no trailing newline), not an `EXMEN:` hook.
    case stdoutLine(String)
    /// A stderr line (no trailing newline).
    case stderrLine(String)
    /// A stdout line beginning with `EXMEN:` — a hook directive for the orchestrator.
    case hookLine(String)
    /// The process exited; carries its termination status.
    case exited(Int32)
    /// The per-subtask timeout fired; the process group was killed.
    case timedOut
    /// `process.run()` threw — the child never started.
    case launchFailed(Error)
}

// MARK: - SubtaskRunner

/// Streaming `Process` runner for the orchestration path (ORCH-06).
///
/// Spawns one `Process` per subtask, drains stdout and stderr concurrently via
/// `FileHandle.readabilityHandler` into an `AsyncStream<SubtaskIOEvent>`,
/// classifies `EXMEN:` lines as hook events, enforces a per-subtask timeout, and
/// kills the child's entire process group on timeout or consumer cancellation so
/// no zombie grandchildren survive (e.g. a `make -j` fan-out).
///
/// The single-action path keeps using `ScriptRunner` unchanged; this runner only
/// serves subtask orchestration where live streaming is required.
final class SubtaskRunner {
    static let shared = SubtaskRunner()
    private init() {}

    /// Convenience: run a `SubtaskConfig` using its resolved script + timeout.
    func run(_ config: SubtaskConfig) -> AsyncStream<SubtaskIOEvent> {
        run(script: config.resolvedScript, timeout: config.resolvedTimeout)
    }

    /// Run a shell script, streaming classified line events until the process exits,
    /// times out, or the consuming `Task` is cancelled.
    func run(script: String, timeout: TimeInterval) -> AsyncStream<SubtaskIOEvent> {
        AsyncStream { continuation in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Same PATH augmentation as ScriptRunner so Homebrew tools resolve.
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
            process.environment = environment

            // Finish-once guard: terminationHandler, timeout, and launch-failure can race.
            let finishLock = NSLock()
            var didFinish = false
            func finishOnce() {
                finishLock.lock()
                defer { finishLock.unlock() }
                guard !didFinish else { return }
                didFinish = true
                continuation.finish()
            }

            // Per-pipe line buffers. Each pipe's readabilityHandler is serialized by
            // Foundation, and the two handlers touch only their own buffer, so no lock
            // is needed around the buffers themselves. AsyncStream.yield is thread-safe.
            var outBuffer = Data()
            var errBuffer = Data()

            func drain(_ buffer: inout Data, appending data: Data, classify: (String) -> SubtaskIOEvent) {
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    continuation.yield(classify(line))
                }
            }

            func classifyStdout(_ line: String) -> SubtaskIOEvent {
                line.hasPrefix("EXMEN:") ? .hookLine(line) : .stdoutLine(line)
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                drain(&outBuffer, appending: data, classify: classifyStdout)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                drain(&errBuffer, appending: data) { .stderrLine($0) }
            }

            // Per-subtask timeout: kill the whole process group, emit .timedOut, finish.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                if Task.isCancelled { return }
                SubtaskRunner.terminateProcessTree(process.processIdentifier)
                continuation.yield(.timedOut)
                finishOnce()
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                // Stop live draining, then flush any residual buffered bytes.
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                let residualOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                if !residualOut.isEmpty { drain(&outBuffer, appending: residualOut, classify: classifyStdout) }
                if !outBuffer.isEmpty {
                    continuation.yield(classifyStdout(String(decoding: outBuffer, as: UTF8.self)))
                    outBuffer.removeAll()
                }

                let residualErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !residualErr.isEmpty { drain(&errBuffer, appending: residualErr) { .stderrLine($0) } }
                if !errBuffer.isEmpty {
                    continuation.yield(.stderrLine(String(decoding: errBuffer, as: UTF8.self)))
                    errBuffer.removeAll()
                }

                continuation.yield(.exited(proc.terminationStatus))
                finishOnce()
            }

            // Consumer cancellation (e.g. orchestrator cancels its for-await) tears the child down.
            continuation.onTermination = { _ in
                timeoutTask.cancel()
                if process.isRunning {
                    SubtaskRunner.terminateProcessTree(process.processIdentifier)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                continuation.yield(.launchFailed(error))
                finishOnce()
            }
        }
    }

    // MARK: - Process-group teardown (ORCH-06)

    /// Kill the child's entire process group with a SIGTERM→SIGKILL escalation.
    ///
    /// `Foundation.Process` launches the child as its own process-group leader
    /// (POSIX_SPAWN_SETPGROUP), so the child's PGID equals its PID and `kill(-pid, …)`
    /// reaches grandchildren (e.g. compilers under `make -j`) that a plain
    /// `terminate()` would orphan. A direct `kill(pid, …)` is also sent as a
    /// belt-and-suspenders fallback in case the child is not a group leader.
    /// Processes that `disown`/detach from the group are intentionally not reaped (v1 limitation).
    private static func terminateProcessTree(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        Task.detached {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s grace
            if kill(-pid, 0) == 0 || kill(pid, 0) == 0 {
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
            }
        }
    }
}
