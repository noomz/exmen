import XCTest
@testable import Exmen

// Regression tests for the managed-service menu: status dot colour, stoppability
// from every state, config adoption on reload, and the restart budget that
// bounds a crash loop.

@MainActor
final class ServiceLifecycleTests: XCTestCase {

    // MARK: - Helpers

    private func makeServiceAction(
        name: String = "Test Service",
        command: String = "/bin/echo",
        args: [String]? = ["hello"],
        restart: RestartPolicy? = nil,
        maxRestarts: Int? = nil
    ) -> Action {
        let config = ServiceConfig(
            command: command,
            args: args,
            restart: restart,
            max_restarts: maxRestarts,
            keep_alive: false,
            working_dir: nil,
            env: nil
        )
        return Action(
            name: name,
            icon: "gear",
            description: "",
            serviceConfig: config,
            isService: true
        )
    }

    // MARK: - Status dot colour

    // A status script reporting "not running" must paint the dot red.
    // "not running" contains "running", so matching positives first turned a
    // dead service green while the row text said "not running".
    func testNotRunningStatusIsRed() {
        XCTAssertEqual(ServiceState.dotColor(state: .stopped, hookStatus: "not running"), .red)
    }

    func testNotRunningStatusIsRedEvenWhenStateSaysRunning() {
        XCTAssertEqual(ServiceState.dotColor(state: .running, hookStatus: "not running"), .red)
    }

    func testRunningStatusIsGreen() {
        XCTAssertEqual(ServiceState.dotColor(state: .stopped, hookStatus: "running on :8787"), .green)
    }

    func testInactiveStatusIsRedNotGreen() {
        // "inactive" contains "active"
        XCTAssertEqual(ServiceState.dotColor(state: .running, hookStatus: "inactive"), .red)
    }

    func testCrashedStatusIsRed() {
        XCTAssertEqual(ServiceState.dotColor(state: .running, hookStatus: "crashed"), .red)
    }

    func testStatusMatchingIsCaseInsensitive() {
        XCTAssertEqual(ServiceState.dotColor(state: .stopped, hookStatus: "NOT RUNNING"), .red)
        XCTAssertEqual(ServiceState.dotColor(state: .stopped, hookStatus: "Running"), .green)
    }

    func testNilStatusFallsBackToState() {
        XCTAssertEqual(ServiceState.dotColor(state: .running, hookStatus: nil), .green)
        XCTAssertEqual(ServiceState.dotColor(state: .crashed, hookStatus: nil), .red)
        XCTAssertEqual(ServiceState.dotColor(state: .stopped, hookStatus: nil), .gray)
        XCTAssertEqual(ServiceState.dotColor(state: .restarting, hookStatus: nil), .yellow)
    }

    func testUnrecognisedStatusFallsBackToState() {
        XCTAssertEqual(ServiceState.dotColor(state: .restarting, hookStatus: "reticulating splines"), .yellow)
    }

    // MARK: - stop() is valid from every state

    // The old guard only accepted .running/.starting, so Stop was a silent
    // no-op exactly when a service was cycling through a crash loop.
    func testStopFromRestartingSettlesAtStopped() {
        let service = ManagedService(action: makeServiceAction())
        service.state = .restarting

        service.stop()

        XCTAssertEqual(service.state, .stopped)
    }

    func testStopFromCrashedSettlesAtStopped() {
        let service = ManagedService(action: makeServiceAction())
        service.state = .crashed

        service.stop()

        XCTAssertEqual(service.state, .stopped)
    }

    func testStopFromStoppedIsANoOp() {
        let service = ManagedService(action: makeServiceAction())

        service.stop()

        XCTAssertEqual(service.state, .stopped)
    }

    func testStopClearsPid() {
        let service = ManagedService(action: makeServiceAction())
        service.state = .crashed
        service.pid = 12345

        service.stop()

        XCTAssertNil(service.pid)
    }

    // MARK: - Missing / invalid configuration fails loudly

    func testStartWithoutServiceConfigReportsError() {
        let action = Action(name: "Broken", isService: true)  // no serviceConfig
        let service = ManagedService(action: action)

        service.start()

        XCTAssertEqual(service.state, .crashed)
        XCTAssertNotNil(service.lastError, "a service that cannot start must say why")
    }

    func testStartWithMissingExecutableReportsError() {
        let service = ManagedService(
            action: makeServiceAction(command: "/nonexistent/definitely/not/here", args: nil)
        )

        service.start()

        XCTAssertEqual(service.state, .crashed)
        XCTAssertEqual(
            service.lastError,
            "command not found or not executable: /nonexistent/definitely/not/here"
        )
    }

    // MARK: - Config adoption across reloads

    // ServiceManager keeps the ManagedService instance across config reloads so
    // a running process is not disturbed; it must still adopt the new config.
    func testUpdateConfigAdoptsNewCommand() {
        let service = ManagedService(action: makeServiceAction(command: "/bin/echo"))

        service.updateConfig(from: makeServiceAction(command: "/bin/cat"))

        XCTAssertEqual(service.action.serviceConfig?.command, "/bin/cat")
    }

    func testUpdateConfigPreservesHookDrivenDisplayFields() {
        let service = ManagedService(action: makeServiceAction())
        service.action.applyHookUpdate(
            HookUpdate(title: "Live Title", status: "running on :8787", badge: "OK", icon: "bolt")
        )

        service.updateConfig(from: makeServiceAction(command: "/bin/cat"))

        XCTAssertEqual(service.action.dynamicTitle, "Live Title")
        XCTAssertEqual(service.action.dynamicStatus, "running on :8787")
        XCTAssertEqual(service.action.dynamicBadge, "OK")
        XCTAssertEqual(service.action.dynamicIcon, "bolt")
    }

    func testUpdateConfigKeepsStableIdentity() {
        // Action.init(from:) mints a fresh UUID per parse; ManagedService.id is
        // the stable key StatusPoller and ServiceManager route hook updates on.
        let service = ManagedService(action: makeServiceAction())
        let originalId = service.id

        service.updateConfig(from: makeServiceAction())

        XCTAssertEqual(service.id, originalId)
    }

    // MARK: - Working directory

    // A bundled .app runs with cwd `/`. Inheriting that meant any service
    // keeping state relative to the working directory failed to start with no
    // explanation, which surfaced as a crash loop.
    func testWorkingDirDefaultsToHomeNotFilesystemRoot() {
        let config = ServiceConfig(
            command: "/bin/echo", args: nil, restart: nil,
            max_restarts: nil, keep_alive: nil, working_dir: nil, env: nil
        )

        XCTAssertEqual(config.resolvedWorkingDir, NSHomeDirectory())
        XCTAssertNotEqual(config.resolvedWorkingDir, "/")
    }

    func testExplicitWorkingDirIsTildeExpanded() {
        let config = ServiceConfig(
            command: "/bin/echo", args: nil, restart: nil,
            max_restarts: nil, keep_alive: nil, working_dir: "~/Documents", env: nil
        )

        XCTAssertEqual(config.resolvedWorkingDir, NSHomeDirectory() + "/Documents")
    }

    // MARK: - Restart budget bounds a crash loop

    // /bin/echo exits ~instantly. With restart = "always" the supervisor must
    // spend its budget and park at .crashed. Before the fix, start() reset the
    // counter on every attempt, so max_restarts was unreachable and this
    // respawned about once a second forever.
    func testInstantlyExitingServiceStopsRestartingAfterBudget() async throws {
        let service = ManagedService(
            action: makeServiceAction(restart: .always, maxRestarts: 2)
        )

        service.start()

        let settled = await waitForState(service, timeout: 40) { $0 == .crashed }

        XCTAssertTrue(
            settled,
            "service still cycling in \(service.state) — restart budget is not bounding the loop"
        )
        XCTAssertNotNil(service.lastError, "giving up must be explained, not silent")

        service.stop()
    }

    // A service that exits immediately should be told why, including the hint
    // about launcher scripts that background the real daemon.
    func testImmediateExitExplainsLauncherScriptPitfall() async throws {
        let service = ManagedService(
            action: makeServiceAction(restart: .always, maxRestarts: 1)
        )

        service.start()
        _ = await waitForState(service, timeout: 40) { $0 == .crashed }

        let message = try XCTUnwrap(service.lastError)
        XCTAssertTrue(
            message.contains("exits immediately"),
            "expected an immediate-exit diagnostic, got: \(message)"
        )
        XCTAssertTrue(
            message.contains("gave up after 1 restart attempt"),
            "expected the give-up reason, got: \(message)"
        )

        service.stop()
    }

    // restart = "never" must not respawn at all.
    func testRestartPolicyNeverDoesNotRespawn() async throws {
        let service = ManagedService(
            action: makeServiceAction(restart: .never)
        )

        service.start()

        let settled = await waitForState(service, timeout: 20) { !$0.isActive }

        XCTAssertTrue(settled, "service stuck in \(service.state) with restart = never")
        service.stop()
    }

    // MARK: - Polling helper

    /// Poll `service.state` until `predicate` holds or `timeout` elapses.
    /// Returns whether the predicate was satisfied.
    private func waitForState(
        _ service: ManagedService,
        timeout: TimeInterval,
        until predicate: (ServiceState) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(service.state) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return predicate(service.state)
    }
}
