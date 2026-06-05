import Foundation
import Combine

// MARK: - OrchestratorError

enum OrchestratorError: Error {
    case dependencyCycle(ids: [String])
    case unknownDependency(subtask: String, dependency: String)
    case maxSubtaskCountExceeded
}

// MARK: - SubtaskEvent (orchestration progress hook)

enum SubtaskEvent {
    case started(id: String)
    case finished(id: String, status: SubtaskStatus)
    case stateChanged(id: String, state: SubtaskState)
}

// MARK: - OrchestrationSummary

struct OrchestrationSummary: CustomStringConvertible {
    let succeededCount: Int
    let failedCount: Int
    let skippedCount: Int

    var totalCount: Int { succeededCount + failedCount + skippedCount }
    var isFailure: Bool { failedCount > 0 }

    /// Overall verdict: failed when ≥1 subtask failed (D-15).
    var verdictFailed: Bool { isFailure }

    var description: String {
        "\(succeededCount) succeeded, \(failedCount) failed, \(skippedCount) skipped"
    }

    /// One-line summary for notifications/popups (D-15).
    var summaryLine: String { description }

    init(subtaskStates: [SubtaskState]) {
        var succeeded = 0
        var failed = 0
        var skipped = 0
        for state in subtaskStates {
            switch state.status {
            case .succeeded:        succeeded += 1
            case .failed:           failed    += 1
            case .skipped:          skipped   += 1
            case .pending, .running: break
            }
        }
        succeededCount = succeeded
        failedCount    = failed
        skippedCount   = skipped
    }
}

// MARK: - SubtaskOrchestrator

/// Wave topo-sort scheduler (ORCH-02) + bounded-concurrency execution (ORCH-06)
/// driving live `@Published` progress (ORCH-03) through `SubtaskRunner`, with
/// runtime dynamic spawn + per-subtask progress from `HookParser.parseLine`
/// (ORCH-04) and cascade-skip on dependency failure (D-13/D-14).
///
/// Not marked @MainActor at the class level so that @Published properties can
/// be read synchronously from nonisolated test contexts (e.g. XCTUnwrap in
/// TimeoutTests). The `await orchestrator.subtaskStates` calls in ProgressModelTests
/// are "redundant await" warnings under Swift 6 — not errors — and compile fine.
/// Mutation of @Published state is dispatched to the main actor explicitly.
final class SubtaskOrchestrator: ObservableObject, @unchecked Sendable {

    // MARK: Published state (ORCH-03)
    @Published var subtaskStates: [SubtaskState] = []
    @Published var isRunning: Bool = false
    @Published var overallProgressPercent: Int = 0

    /// Set after a run completes (nil before first run).
    var completionSummary: OrchestrationSummary?

    /// Shared instance used by the menu-bar UI (tests construct their own instances).
    static let shared = SubtaskOrchestrator()

    init() {}

    // MARK: - Static constants

    static let defaultConcurrencyLimit: Int = 4
    static let maxSubtaskCount: Int = 1000

    // MARK: - Static helpers (ORCH-02 wave scheduler stubs)

    /// Topological sort: returns subtasks grouped by wave (BFS Kahn's algorithm).
    /// Throws OrchestratorError on cycle or unknown dependency.
    static func computeWaves(_ subtasks: [SubtaskConfig]) throws -> [[SubtaskConfig]] {
        guard !subtasks.isEmpty else { return [] }

        let byId: [String: SubtaskConfig] = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, $0) })

        // Validate all dependencies exist
        for sub in subtasks {
            for dep in (sub.depends_on ?? []) {
                if byId[dep] == nil {
                    throw OrchestratorError.unknownDependency(subtask: sub.id, dependency: dep)
                }
            }
        }

        // Kahn's algorithm
        var inDegree: [String: Int] = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, 0) })
        var dependents: [String: [String]] = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, []) })

        for sub in subtasks {
            for dep in (sub.depends_on ?? []) {
                inDegree[sub.id, default: 0] += 1
                dependents[dep, default: []].append(sub.id)
            }
        }

        var queue: [String] = inDegree.filter { $0.value == 0 }.map(\.key)
        var waves: [[SubtaskConfig]] = []
        var processed = 0

        while !queue.isEmpty {
            let currentWave = queue
            waves.append(currentWave.compactMap { byId[$0] })
            queue = []
            for id in currentWave {
                processed += 1
                for dependent in (dependents[id] ?? []) {
                    inDegree[dependent, default: 1] -= 1
                    if inDegree[dependent] == 0 {
                        queue.append(dependent)
                    }
                }
            }
        }

        if processed != subtasks.count {
            // Cycle detected — find participating ids
            let cycleIds = inDegree.filter { $0.value > 0 }.map(\.key)
            throw OrchestratorError.dependencyCycle(ids: cycleIds)
        }

        return waves
    }

    /// Returns true if `subtask` should be skipped because one of its
    /// dependencies is in `failedIds` (which includes both failed and
    /// already-skipped ids for cascade propagation).
    static func shouldSkip(_ subtask: SubtaskConfig, failedIds: Set<String>) -> Bool {
        for dep in (subtask.depends_on ?? []) {
            if failedIds.contains(dep) { return true }
        }
        return false
    }

    /// Validates subtask list without running.
    /// Throws OrchestratorError.maxSubtaskCountExceeded when count > maxSubtaskCount.
    static func validate(subtasks: [SubtaskConfig]) throws {
        if subtasks.count > maxSubtaskCount {
            throw OrchestratorError.maxSubtaskCountExceeded
        }
    }

    // MARK: - Run (ORCH-03 / ORCH-06)

    /// Execute subtasks respecting dependency waves and the concurrency cap.
    /// The optional `eventHandler` receives lifecycle events for testing.
    func run(
        subtasks: [SubtaskConfig],
        concurrencyLimit: Int = SubtaskOrchestrator.defaultConcurrencyLimit,
        _ eventHandler: ((SubtaskEvent) -> Void)? = nil
    ) async throws {
        try SubtaskOrchestrator.validate(subtasks: subtasks)

        await MainActor.run {
            self.isRunning = true
            self.subtaskStates = subtasks.map { SubtaskState(id: $0.id, name: $0.resolvedName) }
            self.overallProgressPercent = 0
        }

        let waves: [[SubtaskConfig]]
        do {
            waves = try SubtaskOrchestrator.computeWaves(subtasks)
        } catch {
            await MainActor.run {
                self.isRunning = false
                self.overallProgressPercent = 0
                self.completionSummary = OrchestrationSummary(subtaskStates: self.subtaskStates)
            }
            throw error
        }
        var failedIds: Set<String> = []
        let total = subtasks.count

        for wave in waves {
            // Partition: skip dependents of failed tasks
            var toRun: [SubtaskConfig] = []
            for sub in wave {
                if SubtaskOrchestrator.shouldSkip(sub, failedIds: failedIds) {
                    await updateState(id: sub.id, status: .skipped)
                    failedIds.insert(sub.id)
                } else {
                    toRun.append(sub)
                }
            }

            // Execute wave tasks with concurrency cap
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var index = 0

                while index < toRun.count || running > 0 {
                    while running < concurrencyLimit && index < toRun.count {
                        let sub = toRun[index]
                        index += 1
                        running += 1
                        group.addTask {
                            await self.executeSubtask(sub, timeout: sub.resolvedTimeout, eventHandler: eventHandler)
                        }
                    }
                    if running > 0 {
                        await group.next()
                        running -= 1
                    }
                }
            }

            // Collect failures for next wave (read on MainActor)
            let statesSnapshot = await MainActor.run { self.subtaskStates }
            for sub in toRun {
                if let state = statesSnapshot.first(where: { $0.id == sub.id }),
                   case .failed = state.status {
                    failedIds.insert(sub.id)
                }
            }

            // Update overall progress after each wave
            let done = statesSnapshot.filter { $0.status.isTerminal }.count
            await MainActor.run { self.overallProgressPercent = total > 0 ? (done * 100 / total) : 100 }
        }

        // Finalize — synchronously before returning so tests can read state immediately
        await MainActor.run {
            self.isRunning = false
            self.completionSummary = OrchestrationSummary(subtaskStates: self.subtaskStates)
            self.overallProgressPercent = 100
        }
    }

    // MARK: - Private helpers

    private func executeSubtask(
        _ sub: SubtaskConfig,
        timeout: TimeInterval,
        eventHandler: ((SubtaskEvent) -> Void)?
    ) async {
        await updateState(id: sub.id, status: .running, startedAt: Date())
        eventHandler?(.started(id: sub.id))

        var exitCode: Int32 = 0
        var timedOut = false

        // Stream the subtask live via SubtaskRunner: process-group kill on timeout
        // (ORCH-06), and EXMEN: hook lines dispatched for progress (D-12) and
        // dynamic spawn (ORCH-04) as they arrive (ORCH-03).
        for await event in SubtaskRunner.shared.run(script: sub.resolvedScript, timeout: timeout) {
            switch event {
            case .hookLine(let line):
                await handleHookLine(line, subtaskId: sub.id, eventHandler: eventHandler)
            case .exited(let code):
                exitCode = code
            case .timedOut:
                timedOut = true
                exitCode = 124   // conventional timeout exit code
            case .launchFailed:
                exitCode = 1
            case .stdoutLine, .stderrLine:
                break            // raw output not required by the progress model
            }
        }

        let finalStatus: SubtaskStatus = (!timedOut && exitCode == 0)
            ? .succeeded
            : .failed(exitCode: exitCode)
        await updateState(id: sub.id, status: finalStatus, endedAt: Date())
        eventHandler?(.finished(id: sub.id, status: finalStatus))
    }

    /// Dispatch a single `EXMEN:` hook line emitted by a running subtask.
    /// `progress` updates the per-subtask bar (D-12); `subtask` spawns a new
    /// subtask at runtime (ORCH-04, D-05). Malformed/legacy/unknown lines are ignored.
    private func handleHookLine(
        _ line: String,
        subtaskId: String,
        eventHandler: ((SubtaskEvent) -> Void)?
    ) async {
        guard let event = HookParser.parseLine(line) else { return }
        switch event {
        case .progress(let percent):
            await updateProgress(id: subtaskId, percent: percent)
        case .subtask(let rawValue):
            await spawnDynamicSubtask(rawValue, eventHandler: eventHandler)
        case .invalidProgress, .legacyHook, .unknown:
            break
        }
    }

    /// Dynamically decode and run a subtask requested via `EXMEN:subtask=` (ORCH-04).
    /// Idempotent on id (D-08): a duplicate id is ignored. Honors the global
    /// `maxSubtaskCount` cap and ignores malformed inline tables (D-07).
    /// v1 limitation: dynamic subtasks run outside the wave concurrency cap and
    /// do not participate in dependency ordering.
    private func spawnDynamicSubtask(
        _ rawValue: String,
        eventHandler: ((SubtaskEvent) -> Void)?
    ) async {
        guard let config = try? SubtaskConfig.decodeInlineTable(rawValue) else { return }

        let shouldRun: Bool = await MainActor.run {
            if self.subtaskStates.contains(where: { $0.id == config.id }) { return false }       // D-08 idempotent
            if self.subtaskStates.count >= SubtaskOrchestrator.maxSubtaskCount { return false }   // hard cap
            self.subtaskStates.append(SubtaskState(id: config.id, name: config.resolvedName))
            return true
        }
        guard shouldRun else { return }

        await executeSubtask(config, timeout: config.resolvedTimeout, eventHandler: eventHandler)
    }

    @MainActor
    private func updateState(id: String, status: SubtaskStatus, startedAt: Date? = nil, endedAt: Date? = nil) {
        guard let idx = subtaskStates.firstIndex(where: { $0.id == id }) else { return }
        subtaskStates[idx].status = status
        if let s = startedAt { subtaskStates[idx].startedAt = s }
        if let e = endedAt   { subtaskStates[idx].endedAt = e }
    }

    /// Update a subtask's opt-in progress percentage from an `EXMEN:progress=` hook (D-12).
    @MainActor
    private func updateProgress(id: String, percent: Int) {
        guard let idx = subtaskStates.firstIndex(where: { $0.id == id }) else { return }
        subtaskStates[idx].progressPercent = max(0, min(100, percent))
    }
}
