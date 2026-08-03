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

    /// Published so hook-driven status updates (StatusPoller → ServiceManager)
    /// repaint the menu row. Without this, `ServiceRowView` only refreshed when
    /// the popover happened to rebuild.
    @Published var action: Action

    @Published var state: ServiceState = .stopped
    @Published var pid: Int32?
    @Published var startedAt: Date?

    /// Last failure reason, surfaced in the menu row and as a notification.
    /// Nil whenever the service is healthy. Never fail silently: every path
    /// that ends in `.crashed` sets this first.
    @Published private(set) var lastError: String?

    /// The SwiftTerm terminal view hosting the PTY process.
    /// Not @Published — it's a reference-type NSView that must not trigger SwiftUI diffs.
    var terminalView: LocalProcessTerminalView?

    /// The output window controller. Set by ServiceManager.showOutput.
    weak var outputWindow: ServiceOutputWindow?

    /// Automatic restarts spent since the service was last known healthy.
    ///
    /// Deliberately NOT reset by `start()`: an auto-restart goes through
    /// `start()`, so resetting there made the `max_restarts` ceiling
    /// unreachable and turned any instantly-exiting command into an unbounded
    /// respawn loop. It is reset only by an explicit user start/restart
    /// (`resetRestartBudget`) or once the process has stayed up for
    /// `healthyUptimeThreshold`.
    private var restartCount: Int = 0
    private var restartBackoffTask: Task<Void, Never>?

    /// Fires `healthyUptimeThreshold` after a start; refunds the restart budget
    /// if the process is still up, so a service that runs for days and then
    /// crashes gets a full set of retries rather than an exhausted one.
    private var healthyUptimeTask: Task<Void, Never>?

    /// How long a process must stay up before its restart budget is refunded.
    private let healthyUptimeThreshold: TimeInterval = 10

    /// A process that dies faster than this never really started. Used only to
    /// add the "this looks like a launcher script" hint to the failure message.
    private let immediateExitThreshold: TimeInterval = 3

    /// Flag set before calling stop() to suppress restart logic in the delegate.
    private var manuallyStoppping: Bool = false

    /// Periodic liveness check for reconnected services (no PTY delegate).
    /// When a service is reconnected via PID file, terminalView is nil so
    /// processTerminated never fires. This timer polls kill(pid, 0) to detect
    /// when the external process dies and updates state accordingly.
    private var livenessTimer: Timer?

    init(action: Action) {
        self.id = action.id
        self.action = action
    }

    /// Adopt a freshly parsed config on reload, keeping the live hook-driven
    /// display fields. `ServiceManager` preserves the ManagedService instance
    /// across reloads so a running process is not disturbed; without this the
    /// reparsed Action was thrown away and edits to command/args/restart/hook
    /// were silently ignored until the app was relaunched.
    ///
    /// `id` is intentionally not updated — it is this service's stable identity
    /// (`Action.init(from:)` mints a new UUID on every parse) and is what
    /// StatusPoller and ServiceManager key hook updates on.
    func updateConfig(from newAction: Action) {
        var merged = newAction
        merged.dynamicTitle = action.dynamicTitle
        merged.dynamicStatus = action.dynamicStatus
        merged.dynamicBadge = action.dynamicBadge
        merged.dynamicIcon = action.dynamicIcon
        action = merged
    }

    // MARK: - Liveness monitoring

    /// Start polling to detect when a service process exits.
    ///
    /// The SwiftTerm Subprocess path has a known issue: `processTerminated`
    /// may never fire because (1) `shellPid` is never set (stays 0), and
    /// (2) the DispatchIO EOF handler in `childProcessRead` has the
    /// `processTerminated` call commented out. This monitor acts as a
    /// universal safety net by checking both the PTY `running` flag and
    /// the PID liveness via `kill(pid, 0)`.
    func startLivenessMonitor() {
        stopLivenessMonitor()
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkLiveness()
            }
        }
    }

    private func stopLivenessMonitor() {
        livenessTimer?.invalidate()
        livenessTimer = nil
    }

    private func checkLiveness() {
        guard state == .running || state == .starting || state == .restarting else {
            stopLivenessMonitor()
            return
        }

        var isDead = false

        // Check 1: PTY process running flag (set to false by childStopped() on EOF)
        if let tv = terminalView, !tv.process.running {
            isDead = true
        }

        // Check 2: PID-based liveness (for reconnected services without terminalView,
        // or when the PID is valid and non-zero)
        if let pid = self.pid, pid > 0 {
            if kill(pid, 0) != 0 {
                isDead = true
            }
        } else if terminalView == nil {
            // No terminalView and no valid PID — nothing to monitor
            isDead = true
        }

        if isDead {
            // Exit status is unrecoverable here: SwiftTerm has already reaped
            // the child, so the poll can only observe that it is gone.
            handleProcessExit(exitCode: nil)
        }
    }

    /// Single funnel for "the supervised process is no longer running",
    /// reached from both the PTY delegate (`processTerminated`, with a real
    /// exit code) and the liveness poll (without one).
    private func handleProcessExit(exitCode: Int32?) {
        // Both the poll and the delegate can report the same exit. Only the
        // first one may act — otherwise the second would spend another restart
        // from a service that has already settled into .stopped or .crashed.
        guard state.isActive else { return }

        stopLivenessMonitor()
        healthyUptimeTask?.cancel()
        healthyUptimeTask = nil

        let uptime = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        if manuallyStoppping {
            finishStop()
            return
        }

        if let exitedPid = pid {
            reapChild(pid: exitedPid)
        }
        pid = nil

        // A user-initiated restart parks in .restarting until the old process
        // is confirmed gone; now bring the new one up.
        if state == .restarting {
            start()
            return
        }

        attemptRestart(exitCode: exitCode, uptime: uptime)
    }

    // MARK: - Lifecycle

    /// Clear the automatic-restart budget. Called for user-initiated
    /// start/restart so a manual retry always gets a full set of attempts,
    /// even after the service has been parked in `.crashed`.
    func resetRestartBudget() {
        restartCount = 0
        lastError = nil
    }

    func start() {
        guard state != .running && state != .starting else { return }
        guard let serviceConfig = action.serviceConfig else {
            fail("action is marked type = \"service\" but has no [service] section")
            return
        }

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

        // Fail loudly on a bad command instead of forking something that dies
        // instantly and looks like a crash loop.
        if command.hasPrefix("/") && !FileManager.default.isExecutableFile(atPath: executable) {
            fail("command not found or not executable: \(executable)")
            return
        }

        stopLivenessMonitor()
        restartBackoffTask?.cancel()
        restartBackoffTask = nil
        healthyUptimeTask?.cancel()
        healthyUptimeTask = nil
        state = .starting
        manuallyStoppping = false

        // Create a fresh terminal view for each start
        let tv = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        tv.processDelegate = self
        terminalView = tv

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
        // shellPid stays 0 on SwiftTerm's Subprocess path. Storing 0 would make
        // every later kill(pid, …) address the whole process group.
        let launchedPid = tv.process.shellPid
        pid = launchedPid > 0 ? launchedPid : nil

        // If output window is already open, swap in the new terminal view
        outputWindow?.updateTerminalView(tv)

        // Start liveness monitor as a safety net. The SwiftTerm Subprocess
        // path may not reliably deliver processTerminated, so we poll to
        // detect when the process exits.
        startLivenessMonitor()
        scheduleRestartBudgetRefund()
    }

    private func scheduleRestartBudgetRefund() {
        healthyUptimeTask = Task { [weak self] in
            guard let self else { return }
            let threshold = self.healthyUptimeThreshold
            try? await Task.sleep(nanoseconds: UInt64(threshold * 1_000_000_000))
            guard !Task.isCancelled, self.state == .running else { return }
            self.restartCount = 0
            self.lastError = nil
        }
    }

    /// Stop the service and cancel any pending automatic restart.
    ///
    /// Valid from every state, including `.restarting` and `.crashed`. The old
    /// guard only accepted `.running`/`.starting`, which meant the menu's Stop
    /// button was a silent no-op during a crash-restart cycle — the one moment
    /// a user most needs it.
    func stop() {
        // Cancel pending auto-restart work first, unconditionally, so a
        // scheduled backoff can never resurrect the process after a stop.
        restartBackoffTask?.cancel()
        restartBackoffTask = nil
        healthyUptimeTask?.cancel()
        healthyUptimeTask = nil
        stopLivenessMonitor()

        guard state != .stopped else { return }

        manuallyStoppping = true

        // Nothing alive to signal (crashed, or waiting out a restart backoff).
        guard let tv = terminalView, tv.process.running else {
            finishStop()
            return
        }

        let currentPid = tv.process.shellPid

        // Send SIGTERM first (also closes PTY master fd → SIGHUP to child)
        tv.terminate()

        // Schedule SIGKILL after 5 seconds if still alive
        if currentPid > 0 {
            let pidCopy = currentPid
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if kill(pidCopy, 0) == 0 {
                    kill(pidCopy, SIGKILL)
                }
                self.reapChild(pid: pidCopy)
            }
        }

        // Safety net: if processTerminated delegate never fires (Subprocess
        // path issue), force state to .stopped after a timeout.
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.state != .stopped && self.manuallyStoppping {
                self.finishStop()
            }
        }
    }

    /// Settle into `.stopped`. Leaves `terminalView` in place so the output
    /// window keeps showing the exited process's scrollback.
    private func finishStop() {
        if let exitedPid = pid {
            reapChild(pid: exitedPid)
        }
        pid = nil
        state = .stopped
        manuallyStoppping = false
    }

    /// Reap an exited child so it does not linger as a zombie.
    ///
    /// SwiftTerm only calls `waitpid()` from its PTY read loop, which stops
    /// running once we terminate the process ourselves — so every stop/restart
    /// cycle used to leave a `<defunct>` entry parented to Exmen, leaking a PID
    /// table slot per cycle.
    ///
    /// Polls rather than blocking: the child may take a moment to die after
    /// SIGTERM, and a blocking waitpid would tie up a thread until it did.
    private nonisolated func reapChild(pid: Int32) {
        guard pid > 0 else { return }
        Task.detached {
            for _ in 0..<50 {
                var status: Int32 = 0
                // Returns the pid once reaped, 0 while it is still running, and
                // -1 (ECHILD) if something else already reaped it.
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func restart() {
        // User-initiated: always give the service a fresh restart budget,
        // including when it is parked in .crashed after exhausting one.
        resetRestartBudget()
        restartBackoffTask?.cancel()
        restartBackoffTask = nil
        healthyUptimeTask?.cancel()
        healthyUptimeTask = nil

        switch state {
        case .stopped, .crashed:
            // Not running — just start directly
            start()
        case .running, .starting, .restarting:
            stopLivenessMonitor()
            state = .restarting
            // Keep manuallyStoppping = false so processTerminated and
            // checkLiveness see .restarting state and trigger start().
            manuallyStoppping = false

            guard let tv = terminalView, tv.process.running else {
                // Nothing alive to wait for — go straight to a fresh start.
                start()
                return
            }
            tv.terminate()

            // Start liveness monitor to detect process exit as a safety
            // net in case processTerminated never fires (Subprocess path).
            startLivenessMonitor()
        }
    }

    // MARK: - Private restart logic

    private func attemptRestart(exitCode: Int32?, uptime: TimeInterval) {
        guard let serviceConfig = action.serviceConfig else {
            fail("action is marked type = \"service\" but has no [service] section")
            return
        }
        let policy = serviceConfig.resolvedRestart
        let maxRestarts = serviceConfig.resolvedMaxRestarts

        // A nil exit code means the status could not be recovered — the
        // liveness poll noticed the process was gone after SwiftTerm had
        // already reaped it. Treat unknown as failure so `on-failure` services
        // still recover, and rely on the restart budget to keep that bounded.
        // (The old code wrote `exitCode != 0` against an Optional, so a clean
        // exit 0 reported as nil also counted as a failure — but silently.)
        let didFail = (exitCode ?? 1) != 0

        switch policy {
        case .never:
            if didFail {
                state = .crashed
                reportFailure(exitCode: exitCode, uptime: uptime)
            } else {
                state = .stopped
            }

        case .onFailure:
            guard didFail else {
                state = .stopped
                return
            }
            scheduleRestartOrGiveUp(maxRestarts: maxRestarts, exitCode: exitCode, uptime: uptime)

        case .always:
            scheduleRestartOrGiveUp(maxRestarts: maxRestarts, exitCode: exitCode, uptime: uptime)
        }
    }

    /// Spend one restart from the budget, or park in `.crashed` with an
    /// explanation once it is exhausted. This ceiling is what stops a command
    /// that exits instantly from respawning forever.
    private func scheduleRestartOrGiveUp(maxRestarts: Int, exitCode: Int32?, uptime: TimeInterval) {
        guard restartCount < maxRestarts else {
            state = .crashed
            reportFailure(exitCode: exitCode, uptime: uptime, exhaustedAfter: maxRestarts)
            return
        }
        scheduleRestart()
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

    // MARK: - Failure reporting

    /// Record a failure that happened before the process ever launched.
    private func fail(_ message: String) {
        state = .crashed
        lastError = message
        OutputService.shared.showNotification(title: action.name, body: message, isError: true)
    }

    /// Explain why a service died and, when it gave up, why it stopped retrying.
    /// Nothing here is allowed to be silent: the message lands on `lastError`
    /// (shown in the menu row) and in a notification.
    private func reportFailure(exitCode: Int32?, uptime: TimeInterval, exhaustedAfter maxRestarts: Int? = nil) {
        let uptimeText = String(format: "%.1fs", uptime)
        var parts: [String] = []

        if let exitCode {
            parts.append("exited with code \(exitCode) after \(uptimeText)")
        } else {
            parts.append("exited after \(uptimeText)")
        }

        if let maxRestarts {
            parts.append("gave up after \(maxRestarts) restart attempt\(maxRestarts == 1 ? "" : "s")")
        }

        // The single most common cause of an instant exit: pointing [service].command
        // at a launcher that backgrounds the real daemon and returns. Exmen then
        // supervises the launcher, which is already gone.
        if uptime < immediateExitThreshold {
            parts.append(
                "the command exits immediately — if it is a launcher that backgrounds a daemon "
                + "(nohup/&), set [service].command to the daemon itself so Exmen can supervise it"
            )
        }

        let message = parts.joined(separator: "; ")
        lastError = message
        OutputService.shared.showNotification(title: action.name, body: message, isError: true)
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
            self.handleProcessExit(exitCode: exitCode)
        }
    }
}
