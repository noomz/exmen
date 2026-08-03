import Foundation

/// Service for polling action status scripts
@MainActor
class StatusPoller {
    static let shared = StatusPoller()

    private var timers: [UUID: Timer] = [:]
    private weak var actionService: ActionService?

    private init() {}

    /// Start polling for all actions that have hook configs
    func startPolling(for actionService: ActionService) {
        self.actionService = actionService
        stopAll()

        for action in actionService.actions {
            if let hookConfig = action.hookConfig,
               let statusScript = hookConfig.statusScript {
                startPolling(id: action.id, name: action.name, script: statusScript, interval: hookConfig.resolvedPollInterval)
            }
        }

        // Also poll service actions from ServiceManager
        startPollingServices(ServiceManager.shared.services)
    }

    /// Start polling for service actions (those managed by ServiceManager)
    func startPollingServices(_ services: [ManagedService]) {
        for service in services {
            if let hookConfig = service.action.hookConfig,
               let statusScript = hookConfig.statusScript {
                // Key on `service.id`, not `service.action.id`: Action.init(from:)
                // mints a new UUID on every config parse, while ManagedService.id
                // is the stable identity ServiceManager routes hook updates to.
                startPolling(id: service.id, name: service.action.name, script: statusScript, interval: hookConfig.resolvedPollInterval)
            }
        }
    }

    /// Start polling for a single action or service, keyed by its stable id
    private func startPolling(id: UUID, name: String, script: ScriptConfig, interval: Int) {
        guard interval > 0 else { return }

        // Run immediately first
        Task {
            await runStatusScript(for: id, script: script)
        }

        // Then schedule periodic updates
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runStatusScript(for: id, script: script)
            }
        }

        timers[id] = timer
        print("StatusPoller: Started polling for '\(name)' every \(interval)s")
    }

    /// Run the status script and update the action
    private func runStatusScript(for actionId: UUID, script: ScriptConfig) async {
        do {
            let result = try await ScriptRunner.shared.run(script, timeout: 10)

            guard result.isSuccess else {
                print("StatusPoller: Status script failed for \(actionId)")
                return
            }

            let (_, updates) = HookParser.shared.parse(result.output)

            if updates.hasUpdates {
                actionService?.applyHookUpdate(updates, to: actionId)
                ServiceManager.shared.applyHookUpdate(updates, to: actionId)
            }
        } catch {
            print("StatusPoller: Error running status script: \(error)")
        }
    }

    /// Stop polling for a specific action
    func stopPolling(for actionId: UUID) {
        timers[actionId]?.invalidate()
        timers.removeValue(forKey: actionId)
    }

    /// Stop all polling
    func stopAll() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
    }

    /// Restart polling (called when actions are reloaded)
    func restart() {
        if let actionService = actionService {
            startPolling(for: actionService)
        }
    }
}
