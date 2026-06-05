import XCTest
@testable import Exmen

// ORCH-05: Dependents of a failed subtask are marked skipped (transitively);
//          independent branches still run.
// Decision: D-13 (cascade skip on failure), D-14 (independent branches keep running),
//           skipped != failed

final class CascadeSkipTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(id: String, dependsOn: [String] = []) -> SubtaskConfig {
        SubtaskConfig(
            id: id,
            name: nil,
            script: ScriptConfig(type: .inline, content: "echo \(id)", path: nil),
            timeout: nil,
            depends_on: dependsOn.isEmpty ? nil : dependsOn
        )
    }

    // MARK: - ORCH-05 / D-13: direct dependent is skipped when dependency fails

    func testDirectDependentSkippedOnFailure() throws {
        // fetch fails → build should be skipped
        //   fetch
        //     └── build
        let failedIds: Set<String> = ["fetch"]
        let build = makeConfig(id: "build", dependsOn: ["fetch"])
        let shouldSkip = SubtaskOrchestrator.shouldSkip(build, failedIds: failedIds)
        XCTAssertTrue(shouldSkip, "build should be skipped because its dependency 'fetch' failed")
    }

    // MARK: - ORCH-05 / D-13: transitive skip cascades through the graph

    func testTransitiveSkipCascades() throws {
        // fetch fails → build skipped → package skipped (transitively via build)
        // This is verified at orchestrator level: shouldSkip checks depends_on recursively
        // OR the orchestrator propagates failedIds as subtasks skip.

        // The orchestrator adds skipped subtasks' ids to failedIds for cascade purposes.
        // After fetch fails and build is skipped, package also has failed/skipped upstream.
        let failedAndSkippedIds: Set<String> = ["fetch", "build"]
        let pkg = makeConfig(id: "package", dependsOn: ["build"])
        let shouldSkip = SubtaskOrchestrator.shouldSkip(pkg, failedIds: failedAndSkippedIds)
        XCTAssertTrue(shouldSkip, "package should be skipped because build was skipped (transitively)")
    }

    // MARK: - ORCH-05 / D-14: independent branch still runs when another branch fails

    func testIndependentBranchNotSkipped() throws {
        // fetch fails, but lint has no dependency on fetch — lint should still run
        //   fetch   lint   (independent)
        let failedIds: Set<String> = ["fetch"]
        let lint = makeConfig(id: "lint")  // no depends_on
        let shouldSkip = SubtaskOrchestrator.shouldSkip(lint, failedIds: failedIds)
        XCTAssertFalse(shouldSkip, "lint is independent and should not be skipped")
    }

    func testUnrelatedBranchNotAffectedByFailure() throws {
        // Diamond failure: fetch fails, build (dep: fetch) skipped
        // docs (dep: none) is independent — should not be skipped
        let failedIds: Set<String> = ["fetch"]
        let docs = makeConfig(id: "docs")
        XCTAssertFalse(SubtaskOrchestrator.shouldSkip(docs, failedIds: failedIds))
    }

    // MARK: - ORCH-05: no skip when no failures

    func testNoSkipWhenNoFailures() throws {
        let subtask = makeConfig(id: "build", dependsOn: ["fetch"])
        let shouldSkip = SubtaskOrchestrator.shouldSkip(subtask, failedIds: [])
        XCTAssertFalse(shouldSkip, "build should not be skipped when fetch succeeded")
    }

    // MARK: - ORCH-05: skipped status is tracked in SubtaskState

    func testSkippedStatusIsTerminal() {
        // Verified in SubtaskStateTests but duplicated here for cascade semantics
        XCTAssertTrue(SubtaskStatus.skipped.isTerminal)
    }

    func testSkippedIsNotEqualToFailed() {
        // D-13: skipped != failed — skipped does NOT count toward isFailure by itself
        let skippedState = SubtaskState(id: "x", name: "x", status: .skipped,
                                        startedAt: nil, endedAt: nil, progressPercent: nil)
        // A summary with only skipped subtasks should not be a failure
        let summary = OrchestrationSummary(subtaskStates: [skippedState])
        XCTAssertFalse(summary.isFailure, "A skipped-only run should not be classified as failure")
    }

    // MARK: - ORCH-05: multiple dependents of a failed subtask all skip

    func testMultipleDependentsAllSkipped() throws {
        // fetch fails → both build and lint (both depend on fetch) should be skipped
        let failedIds: Set<String> = ["fetch"]
        let build = makeConfig(id: "build", dependsOn: ["fetch"])
        let lint = makeConfig(id: "lint", dependsOn: ["fetch"])
        XCTAssertTrue(SubtaskOrchestrator.shouldSkip(build, failedIds: failedIds))
        XCTAssertTrue(SubtaskOrchestrator.shouldSkip(lint, failedIds: failedIds))
    }
}
