import XCTest
import Combine
@testable import Exmen

// ORCH-03: @Published progress model emits updates live during a run.
// Uses short fixtures to keep feedback under 120s.

final class ProgressModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    // MARK: - ORCH-03: subtaskStates are initially empty

    @MainActor
    func testInitialSubtaskStatesEmpty() {
        let orchestrator = SubtaskOrchestrator()
        XCTAssertTrue(orchestrator.subtaskStates.isEmpty)
    }

    // MARK: - ORCH-03: isRunning transitions during run

    func testIsRunningTransitionsDuringRun() async throws {
        let subtask = SubtaskConfig(
            id: "work",
            name: "Work",
            script: ScriptConfig(type: .inline, content: "echo running", path: nil),
            timeout: 5.0,
            depends_on: nil
        )

        let orchestrator = await SubtaskOrchestrator()
        var runningStates: [Bool] = []

        await MainActor.run {
            orchestrator.$isRunning
                .sink { runningStates.append($0) }
                .store(in: &cancellables)
        }

        try await orchestrator.run(subtasks: [subtask], concurrencyLimit: 1)

        // Should have seen: false (initial) → true (started) → false (done)
        XCTAssertTrue(runningStates.contains(true), "isRunning should have been true during the run")
        XCTAssertFalse(runningStates.last ?? true, "isRunning should be false after run completes")
    }

    // MARK: - ORCH-03: subtaskStates populated after run

    func testSubtaskStatesPopulatedAfterRun() async throws {
        let subtasks = [
            SubtaskConfig(id: "a", name: "A",
                         script: ScriptConfig(type: .inline, content: "echo a", path: nil),
                         timeout: 5.0, depends_on: nil),
            SubtaskConfig(id: "b", name: "B",
                         script: ScriptConfig(type: .inline, content: "echo b", path: nil),
                         timeout: 5.0, depends_on: nil),
        ]

        let orchestrator = await SubtaskOrchestrator()
        try await orchestrator.run(subtasks: subtasks, concurrencyLimit: 2)

        let states = await orchestrator.subtaskStates
        XCTAssertEqual(states.count, 2)
        XCTAssertTrue(states.allSatisfy { $0.status.isTerminal },
            "All subtasks should be in terminal state after run completes")
    }

    // MARK: - ORCH-03: subtaskStates emit @Published update on status change

    func testSubtaskStatesPublishedEmitsUpdate() async throws {
        let subtask = SubtaskConfig(
            id: "pubtest",
            name: "Pub Test",
            script: ScriptConfig(type: .inline, content: "sleep 0.2", path: nil),
            timeout: 5.0,
            depends_on: nil
        )

        let orchestrator = await SubtaskOrchestrator()
        var updateCount = 0

        await MainActor.run {
            orchestrator.$subtaskStates
                .dropFirst()  // skip initial empty value
                .sink { _ in updateCount += 1 }
                .store(in: &cancellables)
        }

        try await orchestrator.run(subtasks: [subtask], concurrencyLimit: 1)

        // At minimum: populated (1) + status change to running (2) + final status (3)
        XCTAssertGreaterThanOrEqual(updateCount, 1,
            "subtaskStates @Published should emit at least 1 update during run")
    }

    // MARK: - ORCH-03: overallProgressPercent moves from 0 to 100

    func testOverallProgressReachesHundred() async throws {
        let subtasks = (1...3).map { i in
            SubtaskConfig(
                id: "step\(i)", name: "Step \(i)",
                script: ScriptConfig(type: .inline, content: "echo \(i)", path: nil),
                timeout: 5.0, depends_on: nil
            )
        }

        let orchestrator = await SubtaskOrchestrator()
        try await orchestrator.run(subtasks: subtasks, concurrencyLimit: 3)

        let progress = await orchestrator.overallProgressPercent
        XCTAssertEqual(progress, 100,
            "overallProgressPercent should be 100 when all subtasks complete")
    }

    // MARK: - ORCH-03: completionSummary is set after run

    func testCompletionSummarySetAfterRun() async throws {
        let subtask = SubtaskConfig(
            id: "final",
            name: "Final",
            script: ScriptConfig(type: .inline, content: "echo done", path: nil),
            timeout: 5.0,
            depends_on: nil
        )

        let orchestrator = await SubtaskOrchestrator()
        try await orchestrator.run(subtasks: [subtask], concurrencyLimit: 1)

        let summary = await orchestrator.completionSummary
        XCTAssertNotNil(summary, "completionSummary should be set after run completes")
    }
}
