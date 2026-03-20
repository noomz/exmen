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
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let serviceStatus = try? container.decode(ServiceStatusInfo.self) {
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
    }

    struct ServiceStatusInfo: Codable {
        let name: String
        let state: String
        let pid: Int32?
        let statusText: String
        let restartPolicy: String
        let keepAlive: Bool
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
                status: action.dynamicStatus
            )
        }
        return Response(success: true, data: .actions(actions))
    }

    /// Execute an action by name (async version for actual execution)
    private func runAction(name: String) -> Response {
        guard let action = findAction(name: name) else {
            return Response(success: false, error: "Action not found: \(name)")
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
                statusText: ServiceState.displayText(state: svc.state, startedAt: svc.startedAt)
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
        guard service.state == .running || service.state == .starting else {
            return Response(success: false, error: "Service '\(name)' is not running")
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
            keepAlive: config?.resolvedKeepAlive ?? false
        )
        return Response(success: true, data: .serviceStatus(info))
    }
}
