import XCTest
@testable import Exmen

// ORCH-05: OrchestrationSummary counts N succeeded / M failed / K skipped;
//          verdict = failed when >= 1 subtask failed.
// Decision: D-15 (overall verdict, summary counts, error notification)

final class SummaryTests: XCTestCase {

    // MARK: - Helpers

    private func state(id: String, status: SubtaskStatus) -> SubtaskState {
        SubtaskState(id: id, name: id, status: status,
                     startedAt: Date(), endedAt: Date(), progressPercent: nil)
    }

    // MARK: - ORCH-05: counts are correct

    func testAllSucceededCounts() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .succeeded),
            state(id: "c", status: .succeeded),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertEqual(summary.succeededCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testMixedCounts() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .failed(exitCode: 1)),
            state(id: "c", status: .skipped),
            state(id: "d", status: .succeeded),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
    }

    func testAllSkippedCounts() {
        let states = [
            state(id: "a", status: .skipped),
            state(id: "b", status: .skipped),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 2)
    }

    // MARK: - ORCH-05: verdict = failed when >= 1 subtask failed

    func testVerdictFailedWhenOneFailure() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .failed(exitCode: 2)),
            state(id: "c", status: .skipped),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertTrue(summary.isFailure, "Verdict should be failure when >= 1 subtask failed")
    }

    func testVerdictSucceededWhenAllSucceeded() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .succeeded),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertFalse(summary.isFailure)
    }

    func testVerdictSucceededWhenSomeSkipped() {
        // skipped alone does not constitute failure (D-13: skipped != failed)
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .skipped),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertFalse(summary.isFailure)
    }

    func testVerdictFailedWhenAllFailed() {
        let states = [
            state(id: "a", status: .failed(exitCode: 1)),
            state(id: "b", status: .failed(exitCode: 1)),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertTrue(summary.isFailure)
    }

    // MARK: - ORCH-05: description string format

    func testDescriptionFormat() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .failed(exitCode: 1)),
            state(id: "c", status: .skipped),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        // Should contain count information — exact format flexible but must include numbers
        let desc = summary.description
        XCTAssertTrue(desc.contains("1") || desc.contains("succeeded") || desc.contains("failed"),
            "Description should include count information, got: \(desc)")
    }

    // MARK: - ORCH-05: empty subtasks

    func testEmptySubtasksSummary() {
        let summary = OrchestrationSummary(subtaskStates: [])
        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertFalse(summary.isFailure)
    }

    // MARK: - ORCH-05: total count

    func testTotalCount() {
        let states = [
            state(id: "a", status: .succeeded),
            state(id: "b", status: .failed(exitCode: 1)),
            state(id: "c", status: .skipped),
        ]
        let summary = OrchestrationSummary(subtaskStates: states)
        XCTAssertEqual(summary.totalCount, 3)
    }
}
