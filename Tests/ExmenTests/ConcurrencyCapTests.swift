import XCTest
@testable import Exmen

// ORCH-06: Concurrency cap is honored — no more than `cap` subtasks run simultaneously.
// Uses short fixtures (0.5s sleeps) to keep feedback under 120s.

final class ConcurrencyCapTests: XCTestCase {

    // MARK: - ORCH-06: concurrency cap honored at runtime

    func testConcurrencyCapHonored() async throws {
        // Create 6 subtasks that all have no dependencies (wave 0).
        // Cap = 2. At no point should more than 2 be running simultaneously.
        let cap = 2
        let subtasks = (1...6).map { i in
            SubtaskConfig(
                id: "task\(i)",
                name: "Task \(i)",
                script: ScriptConfig(type: .inline, content: "sleep 0.3", path: nil),
                timeout: 5.0,
                depends_on: nil
            )
        }

        let orchestrator = SubtaskOrchestrator()
        var maxConcurrent = 0
        var currentConcurrent = 0
        let lock = NSLock()

        // Run with a concurrency cap of 2
        // The orchestrator must expose a way to observe running count or accept a hook.
        // We measure via subtaskStates changes.
        try await orchestrator.run(subtasks: subtasks, concurrencyLimit: cap) { event in
            lock.lock()
            defer { lock.unlock() }
            switch event {
            case .started:
                currentConcurrent += 1
                maxConcurrent = max(maxConcurrent, currentConcurrent)
            case .finished:
                currentConcurrent -= 1
            default:
                break
            }
        }

        XCTAssertLessThanOrEqual(maxConcurrent, cap,
            "Max concurrent tasks (\(maxConcurrent)) exceeded cap (\(cap))")
        XCTAssertGreaterThan(maxConcurrent, 0,
            "At least some tasks must have run concurrently")
    }

    // MARK: - ORCH-06: defaultConcurrencyLimit is positive integer

    func testDefaultConcurrencyLimitIsReasonable() {
        let limit = SubtaskOrchestrator.defaultConcurrencyLimit
        XCTAssertGreaterThanOrEqual(limit, 1)
        XCTAssertLessThanOrEqual(limit, 16,
            "Default concurrency limit should be a reasonable value (1–16)")
    }

    // MARK: - ORCH-06: single-task run never exceeds cap of 1

    func testSingleTaskRunWithCapOne() async throws {
        let subtask = SubtaskConfig(
            id: "solo",
            name: "Solo",
            script: ScriptConfig(type: .inline, content: "echo done", path: nil),
            timeout: 5.0,
            depends_on: nil
        )
        var maxConcurrent = 0
        var current = 0
        let lock = NSLock()

        let orchestrator = SubtaskOrchestrator()
        try await orchestrator.run(subtasks: [subtask], concurrencyLimit: 1) { event in
            lock.lock()
            defer { lock.unlock() }
            switch event {
            case .started:
                current += 1
                maxConcurrent = max(maxConcurrent, current)
            case .finished:
                current -= 1
            default:
                break
            }
        }

        XCTAssertLessThanOrEqual(maxConcurrent, 1)
    }

    // MARK: - ORCH-06: maxSubtaskCountExceeded error

    func testMaxSubtaskCountExceededThrows() throws {
        // The orchestrator enforces a hard upper limit on subtask count
        // to prevent misconfigured TOML from spawning unbounded work.
        let tooMany = (1...1001).map { i in
            SubtaskConfig(
                id: "t\(i)", name: nil,
                script: ScriptConfig(type: .inline, content: "echo \(i)", path: nil),
                timeout: nil, depends_on: nil
            )
        }
        XCTAssertThrowsError(try SubtaskOrchestrator.validate(subtasks: tooMany)) { error in
            if case OrchestratorError.maxSubtaskCountExceeded = error { return }
            XCTFail("Expected maxSubtaskCountExceeded, got \(error)")
        }
    }
}
