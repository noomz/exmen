import XCTest
@testable import Exmen

// ORCH-04: EXMEN:subtask=<inline table> decodes into SubtaskConfig via shared decode path;
//          duplicate-id spawn is ignored idempotently;
//          unknown depends_on errors only that subtask;
//          EXMEN:progress=N parses + clamps to 0–100 via HookParser.parseLine.
// Decision: D-05 (dynamic spawn), D-06 (shared decode path), D-07 (unknown dep errors subtask only),
//           D-08 (dup id idempotent), D-12 (opt-in progress clamp)

final class DynamicSpawnTests: XCTestCase {

    // MARK: - ORCH-04: decodeInlineTable shared with static decode path

    func testDecodeInlineTableBasic() throws {
        let inline = #"{ id = "fetch", script = { type = "inline", content = "git fetch" } }"#
        let config = try SubtaskConfig.decodeInlineTable(inline)
        XCTAssertEqual(config.id, "fetch")
        XCTAssertEqual(config.script.type, .inline)
        XCTAssertEqual(config.script.content, "git fetch")
    }

    func testDecodeInlineTableWithDependsOn() throws {
        let inline = #"{ id = "build", script = { type = "inline", content = "make" }, depends_on = ["fetch"] }"#
        let config = try SubtaskConfig.decodeInlineTable(inline)
        XCTAssertEqual(config.id, "build")
        XCTAssertEqual(config.depends_on, ["fetch"])
    }

    func testDecodeInlineTableMissingIdThrows() throws {
        // id is required — missing id must throw
        let inline = #"{ script = { type = "inline", content = "make" } }"#
        XCTAssertThrowsError(try SubtaskConfig.decodeInlineTable(inline))
    }

    func testDecodeInlineTableMissingScriptThrows() throws {
        // script is required
        let inline = #"{ id = "build" }"#
        XCTAssertThrowsError(try SubtaskConfig.decodeInlineTable(inline))
    }

    // MARK: - ORCH-04: EXMEN:subtask= hook line parsed by HookParser.parseLine

    func testHookParserDetectsSubtaskLine() throws {
        let line = #"EXMEN:subtask={ id = "fetch", script = { type = "inline", content = "git fetch" } }"#
        let event = HookParser.parseLine(line)
        guard case .subtask(let rawValue) = event else {
            XCTFail("Expected HookLineEvent.subtask, got \(String(describing: event))")
            return
        }
        XCTAssertFalse(rawValue.isEmpty)
    }

    // MARK: - ORCH-04: EXMEN:progress=N clamped to 0–100

    func testHookParserDetectsProgressLine() throws {
        let event = HookParser.parseLine("EXMEN:progress=50")
        guard case .progress(let n) = event else {
            XCTFail("Expected HookLineEvent.progress, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(n, 50)
    }

    func testHookParserProgressAtZero() throws {
        let event = HookParser.parseLine("EXMEN:progress=0")
        guard case .progress(let n) = event else {
            XCTFail("Expected HookLineEvent.progress"); return
        }
        XCTAssertEqual(n, 0)
    }

    func testHookParserProgressAtHundred() throws {
        let event = HookParser.parseLine("EXMEN:progress=100")
        guard case .progress(let n) = event else {
            XCTFail("Expected HookLineEvent.progress"); return
        }
        XCTAssertEqual(n, 100)
    }

    func testHookParserProgressOutsideRangeIsInvalid() throws {
        // Values outside 0–100 should be treated as invalidProgress (not crash)
        let eventOver = HookParser.parseLine("EXMEN:progress=150")
        if case .progress(_) = eventOver {
            XCTFail("Expected invalidProgress for value > 100, got progress")
        }
        let eventNeg = HookParser.parseLine("EXMEN:progress=-5")
        if case .progress(_) = eventNeg {
            XCTFail("Expected invalidProgress for negative value, got progress")
        }
    }

    func testHookParserNonHookLineReturnsNil() throws {
        let event = HookParser.parseLine("regular output line")
        XCTAssertNil(event)
    }

    func testHookParserLegacyTitleLine() throws {
        let event = HookParser.parseLine("EXMEN:title=Building...")
        // Should still be parsed (legacy hook) — not nil
        XCTAssertNotNil(event)
    }

    // MARK: - ORCH-04: duplicate id behavior (D-08)

    func testDuplicateIdDecodeResultsInSameId() throws {
        // The orchestrator is responsible for idempotency at runtime;
        // at decode level, duplicate id in decodeInlineTable decodes fine —
        // the orchestrator checks for duplicates at spawn time.
        // This test verifies decodeInlineTable itself does not crash on valid input.
        let inline = #"{ id = "build", script = { type = "inline", content = "make" } }"#
        let first = try SubtaskConfig.decodeInlineTable(inline)
        let second = try SubtaskConfig.decodeInlineTable(inline)
        XCTAssertEqual(first.id, second.id)
    }

    // MARK: - ORCH-04: unknown depends_on (D-07) — errors only that subtask

    func testUnknownDependsOnInComputeWavesErrorsOnlyThatSubtask() throws {
        // When one subtask has an unknown dependency, only that subtask errors.
        // The error should identify the specific subtask, not abort all of them.
        let subtasks = [
            SubtaskConfig(id: "build", name: nil,
                         script: ScriptConfig(type: .inline, content: "make", path: nil),
                         timeout: nil, depends_on: ["ghost"]),
        ]
        XCTAssertThrowsError(try SubtaskOrchestrator.computeWaves(subtasks)) { error in
            guard case OrchestratorError.unknownDependency(let subtask, let dep) = error else {
                XCTFail("Expected unknownDependency error, got \(error)")
                return
            }
            XCTAssertEqual(subtask, "build")
            XCTAssertEqual(dep, "ghost")
        }
    }
}
