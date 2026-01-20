import Foundation
import SwiftUI

/// Main service for managing actions
/// Loads from config files and watches for changes
@MainActor
class ActionService: ObservableObject {
    static let shared = ActionService()

    @Published var actions: [Action] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let configLoader = ConfigLoader.shared
    private var directoryWatcher: DirectoryWatcher?

    private init() {}

    /// Initialize the service - load actions and start watching
    func initialize() {
        // Ensure config directory exists
        _ = configLoader.ensureConfigDirectory()

        // Load initial actions
        loadActions()

        // Start watching for changes
        startWatching()
    }

    /// Load actions from config files
    func loadActions() {
        isLoading = true
        lastError = nil

        let configs = configLoader.loadAllConfigs()

        if configs.isEmpty {
            // Fall back to sample actions if no configs found
            actions = Action.samples
            print("ActionService: No configs found, using sample actions")
        } else {
            actions = configs.map { Action(from: $0) }
            print("ActionService: Loaded \(actions.count) actions from config")
        }

        isLoading = false

        // Start status polling for actions with hooks
        StatusPoller.shared.startPolling(for: self)
    }

    /// Apply a hook update to a specific action
    func applyHookUpdate(_ update: HookUpdate, to actionId: UUID) {
        guard let index = actions.firstIndex(where: { $0.id == actionId }) else {
            return
        }
        actions[index].applyHookUpdate(update)
    }

    /// Apply hook update from script result
    func processScriptResult(_ result: ScriptResult, for action: Action) -> (cleanOutput: String, updates: HookUpdate) {
        guard action.hookConfig?.shouldParseOutput ?? true else {
            return (result.output, HookUpdate())
        }

        let parsed = HookParser.shared.parse(result.output)

        if parsed.updates.hasUpdates {
            applyHookUpdate(parsed.updates, to: action.id)
        }

        return parsed
    }

    /// Start watching the config directory for changes
    func startWatching() {
        directoryWatcher = DirectoryWatcher(
            path: configLoader.configDirectory
        ) { [weak self] in
            print("ActionService: Config directory changed, reloading...")
            self?.loadActions()
        }

        if directoryWatcher?.start() == false {
            print("ActionService: Could not start directory watcher")
        }
    }

    /// Stop watching for changes
    func stopWatching() {
        directoryWatcher?.stop()
        directoryWatcher = nil
        StatusPoller.shared.stopAll()
    }

    /// Manually trigger a reload
    func refresh() {
        loadActions()
    }
}
