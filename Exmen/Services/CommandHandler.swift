import Foundation

// MARK: - ServiceState extension

extension ServiceState {
    var rawStringValue: String {
        switch self {
        case .stopped:    return "stopped"
        case .starting:   return "starting"
        case .running:    return "running"
        case .restarting: return "restarting"
        case .crashed:    return "crashed"
        }
    }
}

/// Handles IPC commands from socket clients
@MainActor
class CommandHandler {
    static let shared = CommandHandler()

    private init() {}

    // MARK: - Request/Response Types

    struct Request: Codable {
        let command: String
        let name: String?
        /// Reserved for future synchronous variants. `run` is always non-blocking
        /// for subtask actions — `handle` executes on the main thread, so waiting
        /// here would deadlock the orchestration it is waiting on. The CLI's
        /// `--wait` polls `orchestration-status` instead.
        let wait: Bool?
    }

    struct Response: Codable {
        let success: Bool
        let data: ResponseData?
        let error: String?

        init(success: Bool, data: ResponseData? = nil, error: String? = nil) {
            self.success = success
            self.data = data
            self.error = error
        }
    }

    enum ResponseData: Codable {
        case actions([ActionInfo])
        case output(String)
        case status(ActionStatus)
        case services([ServiceInfo])
        case serviceStatus(ServiceStatusInfo)
        case orchestration(OrchestrationStatusInfo)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .actions(let actions):
                try container.encode(actions)
            case .output(let output):
                try container.encode(output)
            case .status(let status):
                try container.encode(status)
            case .services(let services):
                try container.encode(services)
            case .serviceStatus(let status):
                try container.encode(status)
            case .orchestration(let status):
                try container.encode(status)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Tried first: `isRunning` is unique to this payload, so it cannot
            // shadow (or be shadowed by) the other status shapes.
            if let orchestration = try? container.decode(OrchestrationStatusInfo.self) {
                self = .orchestration(orchestration)
            } else if let serviceStatus = try? container.decode(ServiceStatusInfo.self) {
                self = .serviceStatus(serviceStatus)
            } else if let status = try? container.decode(ActionStatus.self) {
                self = .status(status)
            } else if let services = try? container.decode([ServiceInfo].self) {
                self = .services(services)
            } else if let actions = try? container.decode([ActionInfo].self) {
                self = .actions(actions)
            } else if let output = try? container.decode(String.self) {
                self = .output(output)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown response data type")
            }
        }
    }

    struct ActionInfo: Codable {
        let name: String
        let icon: String
        let description: String
        let status: String?
        let hidden: Bool
    }

    struct ActionStatus: Codable {
        let name: String
        let dynamicTitle: String?
        let dynamicStatus: String?
        let dynamicBadge: String?
        let dynamicIcon: String?
    }

    struct ServiceInfo: Codable {
        let name: String
        let state: String
        let pid: Int32?
        let statusText: String
        let hidden: Bool
    }

    struct ServiceStatusInfo: Codable {
        let name: String
        let state: String
        let pid: Int32?
        let statusText: String
        let restartPolicy: String
        let keepAlive: Bool
        /// Why the service last failed, when it did. Optional so older clients
        /// that predate this field still decode.
        let lastError: String?
    }

    /// Live state of the shared SubtaskOrchestrator, so a CLI caller can poll a
    /// fire-and-return `run` to completion (G-11-9).
    struct OrchestrationStatusInfo: Codable {
        let isRunning: Bool
        let completed: Int
        let total: Int
        let overallProgressPercent: Int
        /// Populated once a run has finished; nil before the first run.
        let summary: String?
        /// True when the finished run had at least one failed subtask (D-15).
        let failed: Bool
        /// Human-readable line for the triggering command ("Started: …",
        /// "Already running: …"). Absent on plain status polls.
        let message: String?

        init(
            isRunning: Bool,
            completed: Int,
            total: Int,
            overallProgressPercent: Int,
            summary: String?,
            failed: Bool,
            message: String? = nil
        ) {
            self.isRunning = isRunning
            self.completed = completed
            self.total = total
            self.overallProgressPercent = overallProgressPercent
            self.summary = summary
            self.failed = failed
            self.message = message
        }
    }

    // MARK: - Command Handling

    /// Handle incoming request data and return response string
    func handle(_ data: Data) -> String {
        do {
            let request = try JSONDecoder().decode(Request.self, from: data)
            let response = handleCommand(request)
            let responseData = try JSONEncoder().encode(response)
            return String(data: responseData, encoding: .utf8) ?? "{\"success\":false,\"error\":\"Encoding error\"}"
        } catch {
            return "{\"success\":false,\"error\":\"Invalid JSON: \(error.localizedDescription)\"}"
        }
    }

    /// Route command to appropriate handler
    private func handleCommand(_ request: Request) -> Response {
        switch request.command {
        case "list-actions":
            return listActions()
        case "run":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return runAction(name: name)
        case "status":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return getStatus(name: name)
        case "orchestration-status":
            return getOrchestrationStatus()
        case "list-services":
            return listServices()
        case "start-service":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return startService(name: name)
        case "stop-service":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return stopService(name: name)
        case "restart-service":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return restartService(name: name)
        case "service-status":
            guard let name = request.name else {
                return Response(success: false, error: "Missing 'name' parameter")
            }
            return getServiceStatus(name: name)
        default:
            return Response(success: false, error: "Unknown command: \(request.command)")
        }
    }

    // MARK: - Command Implementations

    /// List all available actions
    private func listActions() -> Response {
        let actions = ActionService.shared.actions.map { action in
            ActionInfo(
                name: action.name,
                icon: action.displayIcon,
                description: action.description,
                status: action.dynamicStatus,
                hidden: action.isHidden
            )
        }
        return Response(success: true, data: .actions(actions))
    }

    /// Report live orchestration state so a CLI caller can poll a fire-and-return
    /// `run` through to its summary (G-11-9).
    private func getOrchestrationStatus() -> Response {
        let orchestrator = SubtaskOrchestrator.shared
        let states = orchestrator.subtaskStates
        let summary = orchestrator.completionSummary

        return Response(success: true, data: .orchestration(OrchestrationStatusInfo(
            isRunning: orchestrator.isRunning,
            completed: states.filter { $0.status.isTerminal }.count,
            total: states.count,
            overallProgressPercent: orchestrator.overallProgressPercent,
            summary: summary?.summaryLine,
            failed: summary?.verdictFailed ?? false
        )))
    }

    /// Start an orchestrated (subtask) action and return immediately (G-11-9).
    ///
    /// Fire-and-return is the only safe shape here: `handle` runs on the main
    /// thread (SocketServer dispatches it there), and `SubtaskOrchestrator.run`
    /// hops to the main actor on every state update — blocking for completion
    /// would deadlock the very orchestration being awaited. A caller that wants
    /// the summary polls `orchestration-status`, which is what `exmen run --wait` does.
    private func runSubtaskAction(_ action: Action, subtasks: [SubtaskConfig]) -> Response {
        let orchestrator = SubtaskOrchestrator.shared

        // Idempotent: a run already in flight is reported as success, not an
        // error — the caller asked for these subtasks to be running, and they are.
        // Starting a second run would corrupt the shared @Published state that
        // the single progress window is bound to.
        if orchestrator.isRunning {
            let completed = orchestrator.subtaskStates.filter { $0.status.isTerminal }.count
            let total = orchestrator.subtaskStates.count
            // `total` is 0 in the brief window between pre-arming isRunning and
            // `run` seeding the states — report plainly rather than "0/0".
            let progress = total > 0 ? " (\(completed)/\(total) subtasks complete)" : ""
            return Response(success: true, data: .orchestration(OrchestrationStatusInfo(
                isRunning: true,
                completed: completed,
                total: total,
                overallProgressPercent: orchestrator.overallProgressPercent,
                summary: nil,
                failed: false,
                message: "Already running: \(action.name)\(progress)"
            )))
        }

        SubtaskProgressWindow.present(orchestrator: orchestrator, title: "\(action.name) — Subtasks")

        // Pre-arm on the main thread so an immediate `orchestration-status` poll
        // cannot observe the gap before `run` flips the flag itself.
        orchestrator.isRunning = true

        Task { @MainActor in
            do {
                try await orchestrator.run(subtasks: subtasks)
            } catch {
                // `validate` rejects before `run` clears the flag — clear it here
                // so the orchestrator does not stay wedged as permanently running.
                orchestrator.isRunning = false
            }
            deliverSummary(for: action)
        }

        return Response(success: true, data: .orchestration(OrchestrationStatusInfo(
            isRunning: true,
            completed: 0,
            total: subtasks.count,
            overallProgressPercent: 0,
            summary: nil,
            failed: false,
            message: "Started: \(action.name) (\(subtasks.count) subtasks)"
        )))
    }

    /// Mirror the menu's completion feedback (ORCH-05/D-15) for CLI-triggered runs.
    private func deliverSummary(for action: Action) {
        guard let summary = SubtaskOrchestrator.shared.completionSummary else { return }
        OutputService.shared.showNotification(
            title: action.name,
            body: summary.summaryLine,
            isError: summary.verdictFailed
        )
    }

    /// Execute an action by name (async version for actual execution)
    private func runAction(name: String) -> Response {
        guard let action = findAction(name: name) else {
            return Response(success: false, error: "Action not found: \(name)")
        }

        // An action declaring [[subtasks]] runs on the orchestrator, mirroring
        // MenuContentView.executeAction (D-01). Without this branch the IPC path
        // fell through to the scriptConfig guard below and rejected a perfectly
        // valid subtask action with "Action has no script" (G-11-9).
        if let subtasks = action.subtasks, !subtasks.isEmpty {
            return runSubtaskAction(action, subtasks: subtasks)
        }

        guard let scriptConfig = action.scriptConfig else {
            return Response(success: false, error: "Action has no script: \(name)")
        }

        // Run synchronously on a detached task to avoid main actor deadlock
        let semaphore = DispatchSemaphore(value: 0)
        var result: ScriptResult?

        // Use detached task to avoid inheriting MainActor context
        Task.detached {
            do {
                result = try await ScriptRunner.shared.run(scriptConfig)
            } catch {
                result = ScriptResult(output: "", error: error.localizedDescription, exitCode: -1, duration: 0)
            }
            semaphore.signal()
        }

        // Wait with timeout
        let waitResult = semaphore.wait(timeout: .now() + 35) // 30s script timeout + 5s buffer
        if waitResult == .timedOut {
            return Response(success: false, error: "Execution timed out")
        }

        guard let scriptResult = result else {
            return Response(success: false, error: "No result")
        }

        if scriptResult.isSuccess {
            // Process hooks and get clean output
            let (cleanOutput, _) = ActionService.shared.processScriptResult(scriptResult, for: action)
            return Response(success: true, data: .output(cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            return Response(success: false, error: scriptResult.error ?? "Execution failed")
        }
    }

    /// Get status of an action
    private func getStatus(name: String) -> Response {
        guard let action = findAction(name: name) else {
            return Response(success: false, error: "Action not found: \(name)")
        }

        let status = ActionStatus(
            name: action.name,
            dynamicTitle: action.dynamicTitle,
            dynamicStatus: action.dynamicStatus,
            dynamicBadge: action.dynamicBadge,
            dynamicIcon: action.dynamicIcon
        )
        return Response(success: true, data: .status(status))
    }

    /// Find action by name (case-insensitive)
    private func findAction(name: String) -> Action? {
        ActionService.shared.actions.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Find service by name (case-insensitive)
    private func findService(name: String) -> ManagedService? {
        ServiceManager.shared.services.first { $0.action.name.lowercased() == name.lowercased() }
    }

    // MARK: - Service Command Implementations

    private func listServices() -> Response {
        let infos = ServiceManager.shared.services.map { svc in
            ServiceInfo(
                name: svc.action.name,
                state: svc.state.rawStringValue,
                pid: svc.pid,
                statusText: ServiceState.displayText(state: svc.state, startedAt: svc.startedAt),
                hidden: svc.action.isHidden
            )
        }
        return Response(success: true, data: .services(infos))
    }

    private func startService(name: String) -> Response {
        guard let service = findService(name: name) else {
            return Response(success: false, error: "Service not found: \(name)")
        }
        guard !service.state.isActive else {
            return Response(success: false, error: "Service '\(name)' is already running")
        }
        ServiceManager.shared.start(service)
        return Response(success: true)
    }

    private func stopService(name: String) -> Response {
        guard let service = findService(name: name) else {
            return Response(success: false, error: "Service not found: \(name)")
        }
        // Stoppable from .restarting and .crashed too — stopping cancels a
        // pending restart backoff, which is the whole point during a crash loop.
        guard service.state != .stopped else {
            return Response(success: false, error: "Service '\(name)' is already stopped")
        }
        ServiceManager.shared.stop(service)
        return Response(success: true)
    }

    private func restartService(name: String) -> Response {
        guard let service = findService(name: name) else {
            return Response(success: false, error: "Service not found: \(name)")
        }
        ServiceManager.shared.restart(service)
        return Response(success: true)
    }

    private func getServiceStatus(name: String) -> Response {
        guard let service = findService(name: name) else {
            return Response(success: false, error: "Service not found: \(name)")
        }
        let config = service.action.serviceConfig
        let info = ServiceStatusInfo(
            name: service.action.name,
            state: service.state.rawStringValue,
            pid: service.pid,
            statusText: ServiceState.displayText(state: service.state, startedAt: service.startedAt),
            restartPolicy: config?.resolvedRestart.rawValue ?? "never",
            keepAlive: config?.resolvedKeepAlive ?? false,
            lastError: service.lastError
        )
        return Response(success: true, data: .serviceStatus(info))
    }
}
