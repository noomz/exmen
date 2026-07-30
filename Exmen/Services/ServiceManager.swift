import Foundation
import AppKit

/// Singleton that manages all active ManagedService instances.
///
/// Responsible for:
/// - Registering services from config (preserving running services on reload)
/// - Starting, stopping, restarting services
/// - Opening the standalone output window for a service
/// - PID file management for keep_alive services
/// - Cleanup on app termination
@MainActor
class ServiceManager: ObservableObject {
    static let shared = ServiceManager()

    @Published var services: [ManagedService] = []

    private init() {}

    // MARK: - Registration

    /// Sync services list from the latest loaded actions.
    /// Running services whose config was NOT deleted are preserved.
    /// New services are added. Deleted services are removed (stopped first if running).
    func register(_ actions: [Action]) {
        let serviceActions = actions.filter { $0.isService }

        // Build lookup by name for existing services
        var existingByName: [String: ManagedService] = [:]
        for svc in services {
            existingByName[svc.action.name] = svc
        }

        var updated: [ManagedService] = []

        for action in serviceActions {
            if let existing = existingByName[action.name] {
                // Config reload: preserve running service, don't restart it
                updated.append(existing)
                existingByName.removeValue(forKey: action.name)
            } else {
                // New service from config
                updated.append(ManagedService(action: action))
            }
        }

        // Remaining entries in existingByName were deleted from config
        for removed in existingByName.values {
            if removed.state.isActive {
                removed.stop()
            }
        }

        services = updated
    }

    // MARK: - Hook updates

    /// Apply a hook update to a service's action by ID (called from StatusPoller)
    func applyHookUpdate(_ update: HookUpdate, to actionId: UUID) {
        guard let index = services.firstIndex(where: { $0.id == actionId }) else {
            return
        }
        services[index].action.applyHookUpdate(update)
    }

    // MARK: - Lifecycle control

    func start(_ service: ManagedService) {
        service.start()
    }

    func stop(_ service: ManagedService) {
        service.stop()
    }

    func restart(_ service: ManagedService) {
        service.restart()
    }

    // MARK: - Output window

    /// Open (or bring to front) the standalone output window for the given service.
    func showOutput(for service: ManagedService) {
        if service.outputWindow == nil {
            let window = ServiceOutputWindow(for: service)
            service.outputWindow = window
        }
        service.outputWindow?.showWindow(nil)
        service.outputWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - App lifecycle

    /// Call from AppDelegate/App when the application is about to terminate.
    /// keep_alive services are persisted via PID file; others are terminated.
    func handleAppWillTerminate() {
        for service in services {
            guard let config = service.action.serviceConfig else { continue }

            if config.resolvedKeepAlive {
                // Write PID file so we can reconnect on next launch
                if let pid = service.pid {
                    writePIDFile(name: service.action.name, pid: pid)
                }
                // Do NOT terminate — let the process keep running
            } else {
                // Graceful termination
                service.stop()
            }
        }
    }

    /// Call at app launch to reconnect to any still-running keep_alive services.
    func reconnectKeepAliveServices() {
        let pidDir = pidDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: pidDir) else { return }

        for file in files where file.hasSuffix(".pid") {
            let name = String(file.dropLast(4))
            guard let pid = readPIDFile(name: name) else { continue }

            // Check if process is still alive
            if kill(pid, 0) == 0 {
                // Find matching service in the registered list
                if let service = services.first(where: { $0.action.name == name }) {
                    service.pid = pid
                    service.state = .running
                    service.startedAt = Date() // approximate; real start time not persisted
                    // terminalView is nil — output unavailable until restart.
                    // Start liveness monitor since there is no PTY delegate
                    // to deliver processTerminated when the process exits.
                    service.startLivenessMonitor()
                }
                // If no matching service found, the config may have been deleted; leave PID file
            } else {
                // Process dead — clean up stale PID file
                deletePIDFile(name: name)
            }
        }
    }

    // MARK: - PID file helpers

    private func pidDirectory() -> String {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/exmen/services")
        // Create if missing
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return dir
    }

    private func writePIDFile(name: String, pid: Int32) {
        let dir = pidDirectory()
        let path = (dir as NSString).appendingPathComponent("\(name).pid")
        try? String(pid).write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func readPIDFile(name: String) -> Int32? {
        let dir = pidDirectory()
        let path = (dir as NSString).appendingPathComponent("\(name).pid")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    private func deletePIDFile(name: String) {
        let dir = pidDirectory()
        let path = (dir as NSString).appendingPathComponent("\(name).pid")
        try? FileManager.default.removeItem(atPath: path)
    }
}
