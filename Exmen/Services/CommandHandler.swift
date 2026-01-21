import Foundation

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

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .actions(let actions):
                try container.encode(actions)
            case .output(let output):
                try container.encode(output)
            case .status(let status):
                try container.encode(status)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let actions = try? container.decode([ActionInfo].self) {
                self = .actions(actions)
            } else if let output = try? container.decode(String.self) {
                self = .output(output)
            } else if let status = try? container.decode(ActionStatus.self) {
                self = .status(status)
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
}
