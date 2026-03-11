import Foundation
import SwiftUI
import AppKit
import SwiftTerm

/// Manages the lifecycle of a single long-running CLI service.
/// Uses SwiftTerm's LocalProcessTerminalView for real PTY support (isatty() == true).
///
/// Note on stderr: PTY merges stdout and stderr at the OS level. Programs that use
/// ANSI escape codes for error output will render naturally, but Exmen cannot
/// force arbitrary stderr to appear in a distinct color.
@MainActor
class ManagedService: ObservableObject, Identifiable {
    let id: UUID
    let action: Action

    @Published var state: ServiceState = .stopped
    @Published var pid: Int32?
    @Published var startedAt: Date?

    /// The SwiftTerm terminal view hosting the PTY process.
    /// Not @Published — it's a reference-type NSView that must not trigger SwiftUI diffs.
    var terminalView: LocalProcessTerminalView?

    /// The output window controller. Set by ServiceManager.showOutput.
    weak var outputWindow: ServiceOutputWindow?

    private var restartCount: Int = 0
    private var restartBackoffTask: Task<Void, Never>?

    /// Flag set before calling stop() to suppress restart logic in the delegate.
    private var manuallyStoppping: Bool = false

    init(action: Action) {
        self.id = action.id
        self.action = action
    }

    // MARK: - Lifecycle

    func start() {
        guard state != .running && state != .starting else { return }
        guard let serviceConfig = action.serviceConfig else { return }

        state = .starting
        restartCount = 0
        manuallyStoppping = false

        // Create a fresh terminal view for each start
        let tv = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        tv.processDelegate = self
        terminalView = tv

        // Resolve executable: absolute paths used directly, otherwise via /usr/bin/env
        let command = serviceConfig.command
        let executable: String
        let args: [String]

        if command.hasPrefix("/") {
            executable = command
            args = serviceConfig.args ?? []
        } else {
            executable = "/usr/bin/env"
            args = [command] + (serviceConfig.args ?? [])
        }

        // Convert [String: String] environment dict to ["KEY=VALUE"] array for SwiftTerm
        let envDict = serviceConfig.resolvedEnvironment
        let envArray = envDict.map { "\($0.key)=\($0.value)" }

        tv.startProcess(
            executable: executable,
            args: args,
            environment: envArray,
            execName: action.name,
            currentDirectory: serviceConfig.resolvedWorkingDir
        )

        state = .running
        startedAt = Date()
        pid = tv.process.shellPid

        // If output window is already open, swap in the new terminal view
        outputWindow?.updateTerminalView(tv)
    }

    func stop() {
        guard state == .running || state == .starting else { return }

        manuallyStoppping = true
        restartBackoffTask?.cancel()
        restartBackoffTask = nil

        if let tv = terminalView {
            let currentPid = tv.process.shellPid

            // Send SIGTERM first
            tv.terminate()

            // Schedule SIGKILL after 5 seconds if still alive
            if currentPid != 0 {
                let pidCopy = currentPid
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if kill(pidCopy, 0) == 0 {
                        kill(pidCopy, SIGKILL)
                    }
                }
            }
        }

        // State is set to .stopped via processTerminated delegate; set it here too
        // in case the terminal view was already nil
        if terminalView == nil {
            state = .stopped
        }
    }

    func restart() {
        switch state {
        case .stopped, .crashed:
            // Not running — just start directly
            restartCount = 0
            start()
        case .running, .starting, .restarting:
            state = .restarting
            manuallyStoppping = false

            let tv = terminalView
            // Stop current process (without triggering restart logic)
            let tempManual = manuallyStoppping
            manuallyStoppping = true

            if let tv {
                tv.terminate()
            } else {
                // No process running, start directly
                manuallyStoppping = tempManual
                start()
            }
            // processTerminated will fire; we detect .restarting state there to trigger start()
        }
    }

    // MARK: - Private restart logic

    private func attemptRestart(exitCode: Int32?) {
        guard let serviceConfig = action.serviceConfig else { return }
        let policy = serviceConfig.resolvedRestart
        let maxRestarts = serviceConfig.resolvedMaxRestarts

        switch policy {
        case .never:
            state = (exitCode == 0) ? .stopped : .crashed

        case .onFailure:
            if exitCode != 0 {
                if restartCount < maxRestarts {
                    scheduleRestart()
                } else {
                    state = .crashed
                }
            } else {
                state = .stopped
            }

        case .always:
            if restartCount < maxRestarts {
                scheduleRestart()
            } else {
                state = .crashed
            }
        }
    }

    private func scheduleRestart() {
        restartCount += 1
        let delay = min(pow(2.0, Double(restartCount - 1)), 30.0)
        state = .restarting

        restartBackoffTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.start()
            }
        }
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension ManagedService: LocalProcessTerminalViewDelegate {

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // No-op: window resize is handled automatically by SwiftTerm
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // No-op: window title is managed by ServiceOutputWindow
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // No-op: directory tracking not needed for service lifecycle
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.pid = nil

            if self.state == .restarting && !self.manuallyStoppping {
                // restart() called while running — start fresh
                self.manuallyStoppping = false
                self.start()
                return
            }

            if self.manuallyStoppping {
                self.state = .stopped
                self.manuallyStoppping = false
                return
            }

            self.attemptRestart(exitCode: exitCode)
        }
    }
}
