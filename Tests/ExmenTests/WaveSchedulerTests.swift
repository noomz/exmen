import XCTest
@testable import Exmen

// ORCH-02: Wave topo-sort produces correct ordering; depends_on gates dependents;
//          cycle detection throws naming the cycle ids.
// Decision: D-04 (run mode implied by depends_on)

final class WaveSchedulerTests: XCTestCase {

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

    // MARK: - ORCH-02: independent subtasks share wave 0

    func testNoDepSubtasksAllInWave0() throws {
        let subtasks = [makeConfig(id: "a"), makeConfig(id: "b"), makeConfig(id: "c")]
        let waves = try SubtaskOrchestrator.computeWaves(subtasks)
        XCTAssertEqual(waves.count, 1, "All independent subtasks should share wave 0")
        let ids = waves[0].map(\.id).sorted()
        XCTAssertEqual(ids, ["a", "b", "c"])
    }

    // MARK: - ORCH-02: linear chain produces sequential waves

    func testLinearChainProducesOnePerWave() throws {
        // a → b → c
        let subtasks = [
            makeConfig(id: "a"),
            makeConfig(id: "b", dependsOn: ["a"]),
            makeConfig(id: "c", dependsOn: ["b"]),
        ]
        let waves = try SubtaskOrchestrator.computeWaves(subtasks)
        XCTAssertEqual(waves.count, 3)
        XCTAssertEqual(waves[0].map(\.id), ["a"])
        XCTAssertEqual(waves[1].map(\.id), ["b"])
        XCTAssertEqual(waves[2].map(\.id), ["c"])
    }

    // MARK: - ORCH-02: diamond graph — wave 0 has independents, wave 1 converges

    func testDiamondGraphWaveOrdering() throws {
        // fetch → [build, lint] → package
        let subtasks = [
            makeConfig(id: "fetch"),
            makeConfig(id: "build", dependsOn: ["fetch"]),
            makeConfig(id: "lint", dependsOn: ["fetch"]),
            makeConfig(id: "package", dependsOn: ["build", "lint"]),
        ]
        let waves = try SubtaskOrchestrator.computeWaves(subtasks)
        XCTAssertEqual(waves.count, 3)
        XCTAssertEqual(waves[0].map(\.id), ["fetch"])
        let wave1Ids = waves[1].map(\.id).sorted()
        XCTAssertEqual(wave1Ids, ["build", "lint"])
        XCTAssertEqual(waves[2].map(\.id), ["package"])
    }

    // MARK: - ORCH-02: cycle detection throws and names offending ids

    func testCycleDetectionThrows() throws {
        // a → b → c → a (cycle)
        let subtasks = [
            makeConfig(id: "a", dependsOn: ["c"]),
            makeConfig(id: "b", dependsOn: ["a"]),
            makeConfig(id: "c", dependsOn: ["b"]),
        ]
        XCTAssertThrowsError(try SubtaskOrchestrator.computeWaves(subtasks)) { error in
            guard case OrchestratorError.dependencyCycle(let ids) = error else {
                XCTFail("Expected OrchestratorError.dependencyCycle, got \(error)")
                return
            }
            let cycleIds = Set(ids)
            XCTAssertTrue(cycleIds.contains("a") || cycleIds.contains("b") || cycleIds.contains("c"),
                "Cycle error should name at least one of the cycle participants")
        }
    }

    func testSelfCycleThrows() throws {
        // a depends on itself
        let subtasks = [makeConfig(id: "a", dependsOn: ["a"])]
        XCTAssertThrowsError(try SubtaskOrchestrator.computeWaves(subtasks)) { error in
            if case OrchestratorError.dependencyCycle(_) = error { return }
            if case OrchestratorError.unknownDependency(let subtask, _) = error {
                XCTAssertEqual(subtask, "a")
                return
            }
            XCTFail("Expected OrchestratorError, got \(error)")
        }
    }

    // MARK: - ORCH-02: unknown dependency throws unknownDependency

    func testUnknownDependencyThrows() throws {
        let subtasks = [
            makeConfig(id: "build", dependsOn: ["nonexistent"]),
        ]
        XCTAssertThrowsError(try SubtaskOrchestrator.computeWaves(subtasks)) { error in
            guard case OrchestratorError.unknownDependency(let subtask, let dep) = error else {
                XCTFail("Expected OrchestratorError.unknownDependency, got \(error)")
                return
            }
            XCTAssertEqual(subtask, "build")
            XCTAssertEqual(dep, "nonexistent")
        }
    }

    // MARK: - ORCH-02: empty subtasks list returns empty waves

    func testEmptySubtasksReturnsEmptyWaves() throws {
        let waves = try SubtaskOrchestrator.computeWaves([])
        XCTAssertTrue(waves.isEmpty)
    }

    // MARK: - ORCH-02: single subtask returns one wave

    func testSingleSubtaskOnWave() throws {
        let subtasks = [makeConfig(id: "solo")]
        let waves = try SubtaskOrchestrator.computeWaves(subtasks)
        XCTAssertEqual(waves.count, 1)
        XCTAssertEqual(waves[0].count, 1)
        XCTAssertEqual(waves[0][0].id, "solo")
    }

    // MARK: - ORCH-02: defaultConcurrencyLimit is defined

    func testDefaultConcurrencyLimitIsPositive() {
        XCTAssertGreaterThan(SubtaskOrchestrator.defaultConcurrencyLimit, 0)
    }
}
