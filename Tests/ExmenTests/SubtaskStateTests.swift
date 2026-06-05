import XCTest
@testable import Exmen

// ORCH-03: SubtaskStatus cases, dotColor mapping, isTerminal flag,
//          and SubtaskState state transitions pending→running→succeeded/failed/skipped.
// Decision: D-10 (dot colors green/gray/yellow/red per Phase 8 convention)

final class SubtaskStateTests: XCTestCase {

    // MARK: - ORCH-03: SubtaskStatus dot colors follow Phase 8 convention

    func testPendingDotColorIsGray() {
        XCTAssertEqual(SubtaskStatus.pending.dotColor, .gray)
    }

    func testRunningDotColorIsGreen() {
        // Phase 8 convention: running = green (indeterminate spinner in UI)
        XCTAssertEqual(SubtaskStatus.running.dotColor, .green)
    }

    func testSucceededDotColorIsGreen() {
        XCTAssertEqual(SubtaskStatus.succeeded.dotColor, .green)
    }

    func testFailedDotColorIsRed() {
        XCTAssertEqual(SubtaskStatus.failed(exitCode: 1).dotColor, .red)
    }

    func testSkippedDotColorIsGray() {
        XCTAssertEqual(SubtaskStatus.skipped.dotColor, .gray)
    }

    // MARK: - ORCH-03: isTerminal

    func testPendingIsNotTerminal() {
        XCTAssertFalse(SubtaskStatus.pending.isTerminal)
    }

    func testRunningIsNotTerminal() {
        XCTAssertFalse(SubtaskStatus.running.isTerminal)
    }

    func testSucceededIsTerminal() {
        XCTAssertTrue(SubtaskStatus.succeeded.isTerminal)
    }

    func testFailedIsTerminal() {
        XCTAssertTrue(SubtaskStatus.failed(exitCode: 1).isTerminal)
    }

    func testSkippedIsTerminal() {
        XCTAssertTrue(SubtaskStatus.skipped.isTerminal)
    }

    // MARK: - ORCH-03: SubtaskState.elapsed

    func testElapsedZeroBeforeStart() {
        let state = SubtaskState(id: "x", name: "x", status: .pending,
                                 startedAt: nil, endedAt: nil, progressPercent: nil)
        XCTAssertEqual(state.elapsed, 0, accuracy: 0.001)
    }

    func testElapsedNonZeroAfterStart() throws {
        let startedAt = Date(timeIntervalSinceNow: -5)
        let state = SubtaskState(id: "x", name: "x", status: .running,
                                 startedAt: startedAt, endedAt: nil, progressPercent: nil)
        XCTAssertGreaterThan(state.elapsed, 4.9)
    }

    func testElapsedFixedWhenEnded() {
        let now = Date()
        let startedAt = now.addingTimeInterval(-10)
        let endedAt = now.addingTimeInterval(-2)
        let state = SubtaskState(id: "x", name: "x", status: .succeeded,
                                 startedAt: startedAt, endedAt: endedAt, progressPercent: nil)
        XCTAssertEqual(state.elapsed, 8.0, accuracy: 0.1)
    }

    // MARK: - ORCH-03: SubtaskStatus equatability for failed(exitCode:)

    func testFailedEqualitySameExitCode() {
        XCTAssertEqual(SubtaskStatus.failed(exitCode: 2), SubtaskStatus.failed(exitCode: 2))
    }

    func testFailedInequalityDifferentExitCode() {
        XCTAssertNotEqual(SubtaskStatus.failed(exitCode: 1), SubtaskStatus.failed(exitCode: 2))
    }

    // MARK: - ORCH-03: SubtaskState is Identifiable by id

    func testSubtaskStateIdentifiable() {
        let state = SubtaskState(id: "step1", name: "Step 1", status: .pending,
                                 startedAt: nil, endedAt: nil, progressPercent: nil)
        XCTAssertEqual(state.id, "step1")
    }

    // MARK: - ORCH-03: progressPercent is optional (nil = no EXMEN:progress= emitted)

    func testProgressPercentNilByDefault() {
        let state = SubtaskState(id: "x", name: "x", status: .pending,
                                 startedAt: nil, endedAt: nil, progressPercent: nil)
        XCTAssertNil(state.progressPercent)
    }

    func testProgressPercentStoredWhenSet() {
        var state = SubtaskState(id: "x", name: "x", status: .running,
                                 startedAt: Date(), endedAt: nil, progressPercent: nil)
        state.progressPercent = 42
        XCTAssertEqual(state.progressPercent, 42)
    }
}
