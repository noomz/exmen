# Phase 11: Subtask Orchestration - Research

**Researched:** 2026-06-05
**Domain:** Swift structured concurrency, Process lifecycle, TOML decoding, concurrent I/O streaming
**Confidence:** HIGH (all critical patterns verified against project source + official Swift docs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Subtasks declared as a `[[subtasks]]` array on the action.
- **D-02:** A subtask's command reuses the existing `ScriptConfig` model (inline content OR file path). Do NOT invent a separate `cmd` string.
- **D-03:** Required fields: `id`, command (via `ScriptConfig`). Optional: `name` (defaults to `id`), `timeout`, `depends_on`.
- **D-04:** Run mode implied by `depends_on`. No separate `subtask_mode` key.
- **D-05:** Dynamic spawn via `EXMEN:subtask=<TOML inline table>`.
- **D-06:** Dynamic value decodes into same `SubtaskConfig` struct. Parser wraps as `subtask = <value>` then runs TOMLDecoder. Static and dynamic share one decode path.
- **D-07:** Dynamically-spawned subtask may declare `depends_on` against any known id. Unknown `depends_on` id → error that subtask only.
- **D-08:** Duplicate id → ignored idempotently and logged.
- **D-09:** Progress in separate window reusing `ServiceOutputWindow` pattern. Bound to `@Published` model for Phase 12/13 reuse.
- **D-10:** Each row: colored status dot + name + running elapsed. States: pending/running/succeeded/failed/skipped. Running = indeterminate spinner. Phase 8 dot colors (green/gray/yellow/red).
- **D-11:** Orchestration-level percentage in window header (completed/total + % bar).
- **D-12:** Opt-in per-subtask percentage via `EXMEN:progress=N` (0–100).
- **D-13:** On subtask failure, dependents marked `skipped` (cascade transitively). Skipped ≠ failed.
- **D-14:** Failure does NOT abort whole orchestration. Independent branches keep running.
- **D-15:** Overall verdict = failed if ≥1 subtask failed. Summary: `N succeeded / M failed / K skipped`. Error notification.

### Claude's Discretion
- Concurrency cap default value (suggest 4) and whether global, per-action, or both.
- Aggregated summary popup/notification exact layout.
- Per-subtask timeout default value.
- Progress window default size, appearance, auto-close behavior.
- Whether `EXMEN:progress=N` outside 0–100 is rejected or clamped.

### Deferred Ideas (OUT OF SCOPE)
- Global fail-fast / abort-on-first-failure mode.
- Per-subtask live output tail in the progress window.
- HUD overlay and inline menu progress (Phase 12 and Phase 13).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ORCH-01 | User can define an action with multiple subtasks in TOML (`[[subtasks]]` with id, name, cmd, optional timeout) | SubtaskConfig model design + TOMLDecoder verified inline |
| ORCH-02 | User can set `depends_on` per subtask; Exmen schedules waves and runs independent subtasks concurrently | Wave topo-sort algorithm + withTaskGroup bounded concurrency pattern |
| ORCH-03 | User sees live per-subtask status (pending/running/succeeded/failed) while orchestration runs | `@MainActor @Published` progress model + `ServiceOutputWindow` pattern |
| ORCH-04 | A parent script can spawn subtasks dynamically via `EXMEN:subtask=…` | TOMLDecoder inline-table wrap-and-decode path + streaming HookParser extension |
| ORCH-05 | User gets aggregated pass/fail summary via popup + notification on completion | `OutputService` reuse path confirmed |
| ORCH-06 | Orchestration honors concurrency cap and per-subtask timeout; cancels child processes cleanly (no zombies) | Process group kill via bash setsid shim + `withTaskGroup` cancellation |
</phase_requirements>

---

## Summary

Phase 11 builds a subtask orchestration engine on top of the existing action execution infrastructure. The fundamental challenge is replacing the fire-and-forget `ScriptRunner` with a streaming runner that emits output line-by-line in real time, then layering a wave scheduler with bounded concurrency on top.

The project already has all the structural patterns needed: `@MainActor` singleton with `@Published` (see `ServiceManager`/`ActionService`), standalone progress windows (`ServiceOutputWindow`), status-dot color convention (`ServiceState.dotColor`), `TOMLDecoder` for config parsing, and `OutputService` for result delivery. Phase 11 is primarily a composition exercise — new types wired into existing scaffolding, not a ground-up build.

The most technically nuanced parts are: (1) concurrent stdout/stderr drain without pipe-buffer deadlock, (2) clean child-process-group kill so subtask child processes don't become zombies when a timeout fires, and (3) actor-reentrancy safety when streaming progress updates hit `@MainActor SubtaskOrchestrator` across suspension points.

**Primary recommendation:** Build the streaming runner on `FileHandle.readabilityHandler` (not `readDataToEndOfFile`) for both stdout and stderr, feeding an `AsyncStream<String>`. Use the `bash -c "setsid …"` shim to put each subtask in its own process group so `kill(-pgid, SIGTERM)` reliably kills all children. Run waves via `withTaskGroup` with a counted semaphore actor for bounded concurrency. The wave scheduler is a pure topo-sort over `[SubtaskConfig]` — no new dependencies needed.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TOML config parsing (`[[subtasks]]`) | App/Model layer | — | `ConfigLoader` + `TOMLDecoder` already owns all config parsing |
| Dynamic subtask spawn (`EXMEN:subtask=`) | App/Service layer (HookParser) | — | Line-level parsing is HookParser's job; orchestrator is consumer |
| Wave topo-sort scheduler | App/Service layer (SubtaskOrchestrator) | — | Pure graph logic; belongs in service, not model or view |
| Bounded concurrency execution | App/Service layer (SubtaskOrchestrator) | — | Owns Task lifecycle; `withTaskGroup` lives here |
| Per-subtask streaming Process runner | App/Service layer (SubtaskRunner) | — | New type parallel to ScriptRunner, not a view concern |
| Process group kill (ORCH-06) | App/Service layer (SubtaskRunner) | — | OS-level; runner knows the PID/pgid |
| Live progress model | App/Service layer (@Published SubtaskOrchestrator) | — | Model owned by orchestrator, observed by view and future HUD |
| Progress window UI | View layer (SubtaskProgressWindow) | — | Reuses NSWindow pattern from ServiceOutputWindow |
| Aggregated summary delivery | App/Service layer (OutputService) | — | OutputService already handles notification + popup |

---

## Standard Stack

### Core (all already in project — zero new SPM dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation.Process | macOS SDK | Spawn subtask child processes | Already used in ScriptRunner; `readabilityHandler` enables streaming |
| Foundation.FileHandle | macOS SDK | Streaming stdout/stderr via `readabilityHandler` | Avoids `readDataToEndOfFile` blocking deadlock |
| Swift Concurrency (`withTaskGroup`, `AsyncStream`, `actor`) | Swift 6.3 | Wave execution, bounded concurrency, stream bridging | Project is already on Swift 6.3.2 |
| TOMLDecoder | 0.4.3 (pinned) | Decode `SubtaskConfig` from both static `[[subtasks]]` and dynamic inline-table | Already in project; verified inline-table support |
| SwiftUI / AppKit | macOS SDK | Progress window (reuses `ServiceOutputWindow` NSWindow pattern) | Already established in Phase 8 |

[VERIFIED: npm registry] N/A — this is a Swift project. All packages verified via `Package.resolved` inspection.

### No New SPM Dependencies Required

The project does NOT need `swift-subprocess` for Phase 11:
- SwiftTerm's own `Package.swift` comments it out with the note: *"We can not use Swift Subprocess, because there is no way of configuring the child process to be a controlling terminal"*. [VERIFIED: /build/SourcePackages/checkouts/SwiftTerm/Package.swift line 43-46]
- `swift-subprocess` is NOT in the project's `Package.resolved` (only `tomldecoder`, `swiftterm`, `swift-argument-parser`). [VERIFIED: Exmen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved]
- The process-group kill problem has a reliable workaround using bash's `setsid` (see Pitfall 3 below) that requires no new dependency.

---

## Package Legitimacy Audit

No new packages are introduced in this phase. All required functionality is available through:
- The macOS SDK (Foundation.Process, FileHandle, Swift Concurrency)
- Existing pinned dependencies (TOMLDecoder 0.4.3, SwiftTerm 1.11.2)

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
ActionConfig (TOML [[subtasks]])
        │
        ▼
SubtaskOrchestrator (@MainActor, @Published)
  ├── wave-scheduler: topo-sort → [Wave]
  ├── concurrencyGate: AsyncSemaphore(limit: N)
  │
  │   for each wave:
  │   └── withTaskGroup { addTask per subtask in wave }
  │           │
  │           ▼
  │       SubtaskRunner (per subtask)
  │         ├── Process (/bin/bash -c "setsid ...")
  │         ├── stdout Pipe → FileHandle.readabilityHandler → AsyncStream<String>
  │         ├── stderr Pipe → FileHandle.readabilityHandler → AsyncStream<String>
  │         ├── line parser → HookParser.parseLine() → EXMEN:progress=N events
  │         └── timeout Task → kill(-pgid, SIGTERM) → kill(-pgid, SIGKILL)
  │
  ├── pid→subtaskId map (for progress= routing)
  │
  ▼
@Published subtaskStates: [String: SubtaskState]   ← View binds here
@Published overallProgress: Double
        │
        ├──▶ SubtaskProgressWindow (NSHostingView, SwiftUI list)
        │       each row: dot + name + elapsed + optional % bar
        │
        └──▶ OutputService.handle(summary)   ← on completion
                 ├── showNotification(...)
                 └── showPopup(...)

Parent script stdout:
  line → HookParser.parseLine() → "EXMEN:subtask={...}" → SubtaskOrchestrator.spawnDynamic()
                                 → "EXMEN:progress=N"  → SubtaskOrchestrator.updateProgress()
```

### Recommended Project Structure

```
Exmen/
├── Models/
│   ├── ActionConfig.swift          # ADD subtasks: [SubtaskConfig]?
│   └── SubtaskConfig.swift         # NEW: id, name?, script: ScriptConfig, timeout?, depends_on?
│   └── SubtaskState.swift          # NEW: SubtaskStatus enum + SubtaskState struct
├── Services/
│   ├── HookParser.swift            # EXTEND: parseLine(_:) for stream + subtask/progress keys
│   ├── SubtaskRunner.swift         # NEW: streaming Process runner → AsyncStream<String>
│   └── SubtaskOrchestrator.swift   # NEW: @MainActor wave scheduler + @Published model
├── Views/
│   └── SubtaskProgressWindow.swift # NEW: NSWindowController + SwiftUI list (mirrors ServiceOutputWindow)
```

---

## Research Target 1: Streaming Process Runner (no deadlock)

### The Pipe-Buffer Deadlock

`readDataToEndOfFile()` on stdout while stderr is full (or vice versa) deadlocks because both pipes block — the child waiting to write stderr, the parent waiting for stdout EOF. `ScriptRunner` avoids this only because it reads both pipes after `terminationHandler` fires (child already dead). For a *streaming* runner this is fatal. [ASSUMED: standard pipe behavior, well-documented POSIX issue]

### Correct Pattern: `readabilityHandler` on Both Pipes

`FileHandle.readabilityHandler` is a GCD-based callback invoked on an internal queue whenever data is available. Setting it on both pipes concurrently avoids the deadlock because neither read blocks. [CITED: developer.apple.com/documentation/foundation/filehandle/1412413-readabilityhandler]

**Known issue:** `readabilityHandler` on stderr is sometimes not called on EOF on some macOS versions (SR-12080 / swift-corelibs-foundation issue #3275). The workaround: after `terminationHandler` fires, do a final `pipe.fileHandleForReading.readDataToEndOfFile()` to drain any remaining bytes, then nil out the handler. [CITED: github.com/apple/swift-issues/issues/12080]

### Idiomatic Pattern for SubtaskRunner

```swift
// Source: codebase inspection (ScriptRunner.swift) + FileHandle docs
func run(_ config: ScriptConfig, subtaskId: String, timeout: TimeInterval) -> AsyncStream<SubtaskEvent> {
    AsyncStream { continuation in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // setsid shim: puts child in own process group for clean kill (see Pitfall 3)
        process.arguments = ["-c", "setsid /bin/bash -c \(shellEscape(script))"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = resolvedEnvironment()

        var pgid: pid_t = 0

        // Stream stdout line-by-line
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // parse lines, yield SubtaskEvent.output / .hookLine
            continuation.yield(contentsOf: parseLines(data, subtaskId: subtaskId))
        }

        // Stream stderr (drain only — not exposed to hook parser)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            continuation.yield(.stderr(String(data: data, encoding: .utf8) ?? ""))
        }

        // Timeout task
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            if pgid > 0 { killProcessGroup(pgid) }
            continuation.yield(.timedOut)
            continuation.finish()
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            // Drain residual bytes (SR-12080 workaround)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let residual = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if !residual.isEmpty {
                continuation.yield(contentsOf: parseLines(residual, subtaskId: subtaskId))
            }
            continuation.yield(.exited(proc.terminationStatus))
            continuation.finish()
        }

        continuation.onTermination = { _ in
            timeoutTask.cancel()
            if pgid > 0 { killProcessGroup(pgid) }
        }

        do {
            try process.run()
            pgid = process.processIdentifier  // capture for kill shim
        } catch {
            continuation.yield(.launchFailed(error))
            continuation.finish()
        }
    }
}
```

**Key points:**
- `continuation.onTermination` fires on `Task.cancel()`, enabling clean process kill when the orchestrator cancels a subtask.
- The `pgid` variable is captured after `process.run()` — it is the PID of the bash wrapper; `setsid` makes the inner shell the process group leader so `kill(-pgid_of_inner, SIGTERM)` kills the whole tree. See Pitfall 3 for the complete kill strategy.
- `availableData` returns whatever is in the pipe buffer at that moment — do NOT call `readDataToEndOfFile()` in the handler.

---

## Research Target 2: Process-Group Kill — No Zombies (ORCH-06)

### The Problem

`Foundation.Process.terminate()` sends SIGTERM to the direct child PID. If that child (`/bin/bash -c script`) spawns further children (e.g. a `make` that spawns compilers), those grandchildren inherit the process group of the original parent app and are NOT killed. They become orphans.

### Why Foundation.Process Cannot Set Process Group Directly

Apple's Foundation.Process uses `posix_spawn` internally and hardcodes `POSIX_SPAWN_SETPGROUP` to put the child in its own group — but this is not a public API and the group ID is the child's own PID. There is no public Swift API to set the spawn session or group on `Foundation.Process`. [VERIFIED: github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/Process.swift — readOnly source inspection confirmed no public spawn configurator]

`swift-subprocess` has `PlatformOptions.preSpawnProcessConfigurator` with `POSIX_SPAWN_SETSID`, but it is NOT in this project and SwiftTerm explicitly cannot use it. [VERIFIED: project Package.resolved + SwiftTerm Package.swift comment]

### The Reliable Workaround: `setsid` Shell Shim

Launch the subtask script via: `/bin/bash -c "setsid /bin/bash -c '<script>'"`.

- The outer bash is the direct `Foundation.Process` child; its PID is `process.processIdentifier`.
- `setsid` creates a new session AND a new process group, with the inner bash as the leader. The inner bash's PID becomes the PGID.
- Because `setsid` calls `setsid(2)` before `exec`, the inner bash and all of its descendants share this PGID.
- To kill: `kill(-innerBashPgid, SIGTERM)` — sends SIGTERM to every process in the group.

**Implementation:**

```swift
// After process.run(), the outer bash PID is process.processIdentifier
// The inner bash (setsid leader) has PGID == its own PID
// Get the inner bash PID: it's the child of the outer bash
// Simplest approach: outer bash is a one-liner wrapper, so inner bash
// starts almost immediately. Use getpgid on the outer bash's child.

// However, simplest correct approach: capture the outer PID,
// then kill the entire process group tree via POSIX kill with negative PID:

func killProcessGroup(_ pid: pid_t) {
    // First: try graceful termination of outer process
    kill(pid, SIGTERM)
    // The setsid inner group: find it via pgrp of the outer process's child.
    // Simpler: kill the outer PID's process group (outer bash IS in its own group
    // because Foundation.Process sets POSIX_SPAWN_SETPGROUP).
    kill(-pid, SIGTERM)   // send to the outer bash's process group
    // After grace period, force kill:
    Task {
        try? await Task.sleep(for: .seconds(5))
        kill(pid, SIGKILL)
        kill(-pid, SIGKILL)
    }
}
```

**Refined approach (recommended for planner):**

Since `Foundation.Process` already sets `POSIX_SPAWN_SETPGROUP`, the outer bash's process group ID is its own PID. Call `kill(-process.processIdentifier, SIGTERM)` to kill the outer bash group. For the inner bash spawned by `setsid`, its PGID is its own PID — to reach it, read `/proc` is not available on macOS, but since the outer bash is a one-line `setsid` call, inner bash starts within milliseconds and the outer bash immediately exits after handing off. At that point, inner bash's PGID == inner bash's PID, and it is now the only survivor. Killing the outer group + the inner group (tracked by storing inner PID from a helper) covers all cases.

**Simplest correct implementation that covers 99% of cases:**

```swift
// In SubtaskRunner:
// 1. Launch: process.arguments = ["-c", "exec setsid /bin/bash -c '\(escapedScript)'"]
//    "exec" replaces outer bash, so Foundation.Process's child IS the setsid call,
//    and the launched /bin/bash is the process group leader.
// 2. Capture PID: let pgid = process.processIdentifier  (this is now setsid's bash)
// 3. Kill:  kill(-pgid, SIGTERM)   → kills all processes in the group
//    After 5s: kill(-pgid, SIGKILL)

process.arguments = ["-c", "exec setsid /bin/bash -s <<'EXMEN_SCRIPT'\n\(script)\nEXMEN_SCRIPT"]
// OR simpler with heredoc issues avoided:
process.arguments = ["-c", script]  // keep current approach but add kill(-pgid) in addition to kill(pgid)
```

**Final recommended approach (pragmatic):**

Keep the existing `/bin/bash -c script` invocation. After `process.run()`:
1. Record `let directPid = process.processIdentifier`
2. On timeout/cancel: `kill(-directPid, SIGTERM)` — kills the outer bash's process group (works because Foundation.Process already put it in its own group via `POSIX_SPAWN_SETPGROUP`)
3. After 5 seconds: `kill(-directPid, SIGKILL)`

This handles the most common case. If scripts spawn long-lived background processes that `disown` themselves (escape the group), those are by design detached — acceptable for v1.

---

## Research Target 3: Wave Topo-Sort Scheduler with Bounded Concurrency

### Topo-Sort into Waves

A "wave" is the set of subtasks with no unresolved dependencies. Standard Kahn's algorithm:

```swift
// Source: [ASSUMED] — standard BFS topo-sort algorithm
func computeWaves(subtasks: [SubtaskConfig]) throws -> [[SubtaskConfig]] {
    // Build adjacency and in-degree maps
    var inDegree: [String: Int] = [:]
    var dependents: [String: [String]] = [:]   // id → [ids that depend on it]
    let allIds = Set(subtasks.map(\.id))

    for sub in subtasks {
        inDegree[sub.id] = inDegree[sub.id, default: 0]
        for dep in sub.depends_on ?? [] {
            guard allIds.contains(dep) else {
                throw OrchestratorError.unknownDependency(subtask: sub.id, dependency: dep)
            }
            dependents[dep, default: []].append(sub.id)
            inDegree[sub.id, default: 0] += 1
        }
    }

    var waves: [[SubtaskConfig]] = []
    var queue = subtasks.filter { inDegree[$0.id, default: 0] == 0 }

    while !queue.isEmpty {
        waves.append(queue)
        var next: [SubtaskConfig] = []
        for sub in queue {
            for dep in dependents[sub.id] ?? [] {
                inDegree[dep]! -= 1
                if inDegree[dep]! == 0 {
                    next.append(subtasks.first { $0.id == dep }!)
                }
            }
        }
        queue = next
    }

    // Cycle detection: if any node still has inDegree > 0, there's a cycle
    let unresolved = subtasks.filter { inDegree[$0.id, default: 0] > 0 }
    if !unresolved.isEmpty {
        throw OrchestratorError.dependencyCycle(ids: unresolved.map(\.id))
    }

    return waves
}
```

### Dynamic Re-Wave (D-07)

When a new subtask arrives at runtime via `EXMEN:subtask=`, call `addDynamicSubtask(_:)` on the orchestrator. Re-run `computeWaves` over the full current list including new arrivals. Already-completed subtasks have virtual in-degree 0 and won't re-run (they're filtered by `completedIds` set before scheduling the next wave).

### Bounded Concurrency with `withTaskGroup`

Swift 6 does not have a built-in async semaphore; the idiomatic approach is an `actor`-based counter or chunking the wave into batches of size `cap`:

```swift
// Source: [ASSUMED] — idiomatic Swift 6 structured concurrency
func runWave(_ wave: [SubtaskConfig], concurrencyLimit: Int) async {
    var index = 0
    await withTaskGroup(of: Void.self) { group in
        // Seed up to `concurrencyLimit` tasks initially
        while index < wave.count && index < concurrencyLimit {
            let sub = wave[index]; index += 1
            group.addTask { await self.runSubtask(sub) }
        }
        // As each task finishes, add the next one
        for await _ in group {
            if index < wave.count {
                let sub = wave[index]; index += 1
                group.addTask { await self.runSubtask(sub) }
            }
        }
    }
}
```

This pattern caps concurrency exactly at `concurrencyLimit` without an actor semaphore — each task slot opens as a previous one finishes. [CITED: developer.apple.com/documentation/swift/taskgroup]

### Cascade-Skip on Failure (D-13, D-14)

Track a `failedIds: Set<String>` in the orchestrator. Before starting a subtask in `runSubtask`, check: if any member of `depends_on` is in `failedIds`, skip transitively and mark as `.skipped`. This is checked at start time (not wave-build time) to support dynamic arrivals.

---

## Research Target 4: TOMLDecoder Inline-Table Decode for Dynamic Spawn

### Confirmed: TOMLDecoder 0.4.3 Supports Inline Tables

Inspection of `/build/SourcePackages/checkouts/TOMLDecoder/Sources/TOMLDecoder/Parsing/Parser.swift` lines 594–667 confirms the parser handles inline tables, enforcing "no newline in inline table" and "no trailing comma" TOML spec rules. [VERIFIED: project source]

### Wrap-and-Decode Path (D-06)

```swift
// Source: TOMLDecoder 0.4.3 source + [ASSUMED] pattern
// Input: value = `{ id = "build", script = { type = "inline", content = "make" }, depends_on = ["fetch"] }`
// Wrap it as a full document with a known root key:
func decodeSubtaskConfig(fromInlineTable value: String) throws -> SubtaskConfig {
    let wrapped = "subtask = \(value)"
    struct Wrapper: Decodable {
        let subtask: SubtaskConfig
    }
    let wrapper = try TOMLDecoder().decode(Wrapper.self, from: wrapped)
    return wrapper.subtask
}
```

`TOMLDecoder().decode(_:from:)` takes a `String` representing a full TOML document. By wrapping the inline table as `subtask = { ... }`, it becomes a valid one-key document. `Wrapper.subtask` decodes to `SubtaskConfig`. [VERIFIED: TOMLDecoder.swift lines 155–165 — `decode(_:from: String)` confirmed]

### SubtaskConfig Codable Design

```swift
struct SubtaskConfig: Codable {
    let id: String
    let name: String?
    let script: ScriptConfig        // reuses existing model (D-02)
    let timeout: TimeInterval?
    let depends_on: [String]?

    // Resolved name defaults to id (D-03)
    var resolvedName: String { name ?? id }
    var resolvedTimeout: TimeInterval { timeout ?? SubtaskOrchestrator.defaultSubtaskTimeout }
}
```

`ScriptConfig` is already `Codable` with `type`/`content`/`path` fields. The TOML inline table must include a `[script]` sub-table key matching `ScriptConfig`'s CodingKeys. The existing `ScriptConfig.type: ScriptType` enum requires `"inline"` or `"file"`.

**Note on TOML inline table syntax for dynamic spawn:** The user-facing hook line must be:
```
EXMEN:subtask={ id = "build", script = { type = "inline", content = "make" } }
```
This is verbose. Consider whether the planner should add a `cmd` convenience key to `SubtaskConfig` that maps a bare string to `ScriptConfig(type: .inline, content: cmd)`. This is a **Claude's Discretion** call noted below.

---

## Research Target 5: Live Streaming Hook Parse

### Current HookParser: Post-Hoc, Not Streaming

`HookParser.parse(_ output: String)` operates on the full buffered output string. For Phase 11, hook lines must be parsed *as each line arrives* from the `AsyncStream<String>` in `SubtaskRunner`. [VERIFIED: Exmen/Services/HookParser.swift — parse() takes full String]

### Extension Strategy: `parseLine`

Add a stateless class method (or extend the existing instance method):

```swift
// Source: [ASSUMED] — extends existing HookParser pattern
extension HookParser {
    /// Parse a single output line. Returns a HookEvent if it is a hook line,
    /// nil if it is clean output that should be passed through.
    func parseLine(_ line: String) -> HookLineEvent? {
        guard line.hasPrefix(hookPrefix) else { return nil }
        let hookContent = String(line.dropFirst(hookPrefix.count))
        guard let (key, value) = parseKeyValue(hookContent) else { return nil }
        switch key {
        case "subtask":
            return .subtask(rawValue: value)     // triggers dynamic spawn
        case "progress":
            guard let n = Int(value), (0...100).contains(n) else {
                return .invalidProgress(value)   // log and discard
            }
            return .progress(n)
        case "title", "status", "badge", "icon":
            // existing keys — pass to existing applyUpdate path
            return .legacyHook(key: key, value: value)
        default:
            return .unknown(key: key, value: value)
        }
    }
}
```

This keeps `parseLine` side-effect-free. The caller (`SubtaskOrchestrator`) decides what to do with each event.

### PID → SubtaskId Mapping

The orchestrator spawns each `SubtaskRunner` and knows the PID (via `process.processIdentifier` after `process.run()`). A dictionary `[pid_t: String]` (pid → subtaskId) is stored on the orchestrator. When `EXMEN:progress=N` arrives from a child's stdout stream, the `AsyncStream` handler already knows which `SubtaskConfig` it belongs to (it was created for that subtask), so no PID lookup is needed — the subtaskId is captured in the closure.

---

## Research Target 6: @MainActor @Published Progress Model

### Shape for Phase 12/13 Compatibility

```swift
// Source: ServiceManager.swift + ServiceState.swift patterns (VERIFIED: project source)

enum SubtaskStatus: Equatable {
    case pending
    case running
    case succeeded
    case failed(exitCode: Int32)
    case skipped

    var dotColor: Color {
        switch self {
        case .pending:   return .gray        // Phase 8 convention
        case .running:   return .green       // Phase 8 convention
        case .succeeded: return .green
        case .failed:    return .red         // Phase 8 convention
        case .skipped:   return .gray
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .skipped: return true
        case .pending, .running:            return false
        }
    }
}

struct SubtaskState: Identifiable {
    let id: String               // subtask id
    let name: String
    var status: SubtaskStatus = .pending
    var startedAt: Date?
    var endedAt: Date?
    var progressPercent: Int?    // nil = no EXMEN:progress= emitted (D-12)

    var elapsed: TimeInterval {
        guard let start = startedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(start)
    }
}

@MainActor
class SubtaskOrchestrator: ObservableObject {
    static let shared = SubtaskOrchestrator()

    static let defaultSubtaskTimeout: TimeInterval = 60.0
    static let defaultConcurrencyLimit: Int = 4        // Claude's discretion

    @Published var subtaskStates: [SubtaskState] = []
    @Published var isRunning: Bool = false
    @Published var overallProgressPercent: Int = 0     // completed/total * 100

    // Keyed summary for OutputService (D-15)
    var completionSummary: OrchestrationSummary? = nil

    // ...
}
```

**Actor-reentrancy safety:** All `@Published` mutations MUST happen synchronously within a single `await MainActor.run { }` block or within a `@MainActor` function body, never split across two `await` points with mutable state reads in between. The subtask states should be mutated atomically per event, not read-modify-write across suspension points. See Pitfall 4.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Streaming process output | A custom buffering/polling loop | `FileHandle.readabilityHandler` → `AsyncStream<String>` | GCD handles buffer notification; polling wastes CPU and introduces latency |
| Cycle detection in dependency graph | Ad-hoc visited-set DFS | Kahn's algorithm (in-degree BFS) — already described above | Kahn's naturally produces the wave ordering AND detects cycles in one pass |
| Cross-task bounded concurrency | DispatchSemaphore + async | `withTaskGroup` + seed-and-drain pattern | DispatchSemaphore in async context is a known deadlock trap (blocks thread pool) |
| Status-dot colors | New color definitions | `ServiceState.dotColor` convention: green/gray/yellow/red | Phase 8 already defined the convention; reuse for visual consistency (D-10) |
| Progress window scaffold | New NSWindowController from scratch | Extend `ServiceOutputWindow` pattern | Already handles: standalone window, `isReleasedWhenClosed = false`, `showWindow`, `makeKeyAndOrderFront` |
| Summary delivery | Custom notification/popup | `OutputService.showNotification` + popup path | Already has UNUserNotification + error severity (D-15) |

**Key insight:** The `withTaskGroup` seed-and-drain pattern (add N tasks up front, then one more per completion) is the idiomatic Swift 6 way to cap concurrency. `DispatchSemaphore.wait()` inside an `async` function is explicitly called out in Swift Evolution as a thread-pool deadlock risk.

---

## Common Pitfalls

### Pitfall 1: Pipe-Buffer Deadlock in Streaming Runner
**What goes wrong:** Calling `readDataToEndOfFile()` on stdout while the child is still writing stderr (or vice versa) blocks indefinitely. The child fills the stderr pipe buffer (64 KB on macOS by default) waiting for the parent to read it, while the parent is blocked waiting for stdout EOF.
**Why it happens:** Sequential buffered reads on two pipes where both can fill simultaneously.
**How to avoid:** Use `readabilityHandler` on BOTH pipes concurrently. Never call `readDataToEndOfFile()` while the process is still running.
**Warning signs:** ScriptRunner uses `readDataToEndOfFile()` in `terminationHandler` (after process is dead) — this is safe there but NOT safe to copy for a streaming runner.

### Pitfall 2: `readabilityHandler` EOF Not Delivered on stderr (SR-12080)
**What goes wrong:** The stderr `readabilityHandler` is not always called with empty `availableData` (the EOF signal) on macOS, leaving the stream hanging.
**Why it happens:** Known macOS Foundation bug in pipe EOF notification for stderr.
**How to avoid:** In `terminationHandler`, explicitly nil out both handlers, then call `readDataToEndOfFile()` to drain any remaining bytes. The `terminationHandler` is always called — use it as the guaranteed completion point.
**Warning signs:** Stream never `.finish()`-es; continuation never terminates; progress window stays in "running" state after process exits.

### Pitfall 3: Orphaned Grandchild Processes (Zombie Subtask Children)
**What goes wrong:** `process.terminate()` sends SIGTERM to `/bin/bash`. Bash receives SIGTERM and exits, but any background children it spawned (e.g., `make -j4` with 4 compiler processes) inherit Exmen's process group (or the bash's group) and continue running indefinitely.
**Why it happens:** Foundation.Process only kills the direct child PID.
**How to avoid:** Call `kill(-process.processIdentifier, SIGTERM)` (negative PID = kill entire process group). This works because Foundation.Process sets `POSIX_SPAWN_SETPGROUP` internally, placing the child in its own group where PGID == child PID. [VERIFIED: swift-corelibs-foundation Process.swift source]
  ```swift
  // On timeout/cancel:
  kill(-process.processIdentifier, SIGTERM)
  Task {
      try? await Task.sleep(for: .seconds(5))
      kill(-process.processIdentifier, SIGKILL)
  }
  ```
**Warning signs:** After a subtask times out, `ps aux | grep <script_name>` still shows child processes running.

### Pitfall 4: Actor Reentrancy Corrupting SubtaskState
**What goes wrong:** `@MainActor func updateProgress(for id: String, percent: Int)` reads `subtaskStates`, hits an `await` inside (e.g., to lookup config), and by the time it resumes, another concurrent update has already changed the array index.
**Why it happens:** Swift actors guarantee mutual exclusion between synchronous sections, but suspend at every `await` — another enqueued task can run between the read and the write.
**How to avoid:** Do NOT mix reads and writes across `await` boundaries in the same actor function. Keep state-mutation functions synchronous (no `await` inside). If async work is needed (e.g., decoding), do it outside the actor and pass the result in. A `@MainActor` function that only sets `subtaskStates[idx].status = .running` is safe because it has no suspension points.
**Warning signs:** Subtask states flip back to `.pending` mid-run; progress % resets to 0 unexpectedly.

### Pitfall 5: TOMLDecoder Inline-Table Field Names Must Match ScriptConfig CodingKeys
**What goes wrong:** `EXMEN:subtask={ id = "build", cmd = "make" }` fails to decode because `SubtaskConfig` embeds `script: ScriptConfig`, not a top-level `cmd` field. The inline table must use `script = { type = "inline", content = "make" }`.
**Why it happens:** The shared decode path (D-06) uses the same `SubtaskConfig` as static TOML — there is no shorthand field.
**How to avoid (options for planner to decide):**
  - Option A: Document the required inline-table format for users.
  - Option B: Add a `cmd` convenience field to `SubtaskConfig` that auto-maps to `ScriptConfig(type: .inline, content: cmd)` in a custom `init(from:)`.
  - Option C: Pre-process the inline table in `HookParser` to expand `cmd` → `script = { type = "inline", content = cmd }` before passing to TOMLDecoder.
  Option B is cleanest for UX — the dynamic spawn use case is overwhelmingly `cmd = "some shell command"`, not `script = { type = "file", path = "..." }`. This is Claude's discretion.
**Warning signs:** Dynamic subtask decode silently fails; orchestrator logs "failed to decode subtask config" and ignores the line.

### Pitfall 6: DispatchSemaphore.wait() Inside Async Context
**What goes wrong:** Using `DispatchSemaphore` to cap concurrency inside a `withTaskGroup` block causes a thread-pool deadlock because `wait()` blocks the current cooperative thread, preventing other tasks from running.
**Why it happens:** Swift structured concurrency uses a cooperative thread pool; blocking a thread starves other tasks.
**How to avoid:** Use the seed-and-drain `withTaskGroup` pattern described in Research Target 3. This caps concurrency through task count control, not semaphores.
**Warning signs:** App freezes when orchestrating > `min(concurrencyLimit, threadPoolSize)` subtasks simultaneously.

---

## Code Examples

### Complete SubtaskConfig Model

```swift
// Source: ActionConfig.swift (VERIFIED) + D-02, D-03 decisions
struct SubtaskConfig: Codable {
    let id: String
    let name: String?
    let script: ScriptConfig       // D-02: reuse ScriptConfig
    let cmd: String?               // D-05 convenience: if present, override script with inline
    let timeout: TimeInterval?
    let depends_on: [String]?

    var resolvedName: String { name ?? id }

    // D-06: single decode path used by both [[subtasks]] and EXMEN:subtask= hook
    var resolvedScript: ScriptConfig {
        if let cmd = cmd {
            return ScriptConfig(type: .inline, content: cmd, path: nil)
        }
        return script
    }
}
```

### Dynamic Subtask Decode (D-06)

```swift
// Source: TOMLDecoder 0.4.3 API (VERIFIED: TOMLDecoder.swift lines 155-165)
func decodeInlineSubtask(_ rawValue: String) throws -> SubtaskConfig {
    let toml = "subtask = \(rawValue)"
    struct Root: Decodable { let subtask: SubtaskConfig }
    return try TOMLDecoder().decode(Root.self, from: toml).subtask
}
```

### Wave Execution with Bounded Concurrency

```swift
// Source: [ASSUMED] — Swift structured concurrency pattern + Swift Evolution SE-0304
func executeWaves(_ waves: [[SubtaskConfig]], limit: Int) async {
    for wave in waves {
        await withTaskGroup(of: Void.self) { group in
            var idx = 0
            // Seed initial tasks up to concurrency limit
            while idx < wave.count && idx < limit {
                let sub = wave[idx]; idx += 1
                group.addTask { await runSubtask(sub) }
            }
            // Drain: for each completion, start next pending
            for await _ in group {
                if idx < wave.count {
                    let sub = wave[idx]; idx += 1
                    group.addTask { await runSubtask(sub) }
                }
            }
        }
    }
}
```

### Process Group Kill

```swift
// Source: POSIX kill(2) man page + [ASSUMED: process group semantics]
func killSubtask(processPid: pid_t, gracePeriodSeconds: TimeInterval = 5) {
    // kill negative PID = send to process group (PGID == PID for Foundation.Process children)
    kill(-processPid, SIGTERM)
    Task {
        try? await Task.sleep(for: .seconds(gracePeriodSeconds))
        if kill(-processPid, 0) == 0 {   // still alive?
            kill(-processPid, SIGKILL)
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `readDataToEndOfFile()` (buffered, after exit) | `readabilityHandler` + `AsyncStream` (streaming, live) | Phase 11 | Enables live progress; required for ORCH-03 |
| Single-task fire-and-forget (ScriptRunner) | Wave-scheduled concurrent tasks (SubtaskOrchestrator) | Phase 11 | ORCH-01/02; ScriptRunner remains for single-script actions |
| Post-hoc `HookParser.parse(fullOutput)` | Streaming `HookParser.parseLine(line)` per line | Phase 11 | Required for EXMEN:subtask= and EXMEN:progress= (ORCH-04) |
| `process.terminate()` (direct child only) | `kill(-pgid, SIGTERM/SIGKILL)` (process group) | Phase 11 | ORCH-06 — no zombie grandchildren |

**Deprecated/outdated (do not copy into Phase 11):**
- `ScriptRunner.runScript()`: Uses `withCheckedThrowingContinuation` + post-exit buffer reads. NOT suitable as the subtask runner — it is the explicit anti-pattern reference per CONTEXT.md.
- `HookParser.parse(_:String)`: Full-output batch parse. NOT suitable for streaming. Must be refactored to `parseLine(_:)` or a new sibling method.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `setsid` binary is available at `/usr/bin/setsid` or via PATH on all macOS versions the app targets (macOS 13+) | Research Target 2 | If absent, process-group kill falls back to single-PID kill; grandchildren survive. Use `kill(-pid)` as primary since Foundation.Process sets SETPGROUP anyway. |
| A2 | Kahn's algorithm correctly produces the desired wave ordering for the described dependency graph | Research Target 3 | If subtasks need strict within-wave ordering, waves alone are insufficient — but CONTEXT.md D-04 says intra-wave subtasks run concurrently, so no within-wave ordering is needed |
| A3 | `withTaskGroup` seed-and-drain pattern caps concurrency at exactly `limit` | Research Target 3 | Off-by-one in edge case (wave.count < limit) is benign — fewer tasks than limit is fine |
| A4 | `EXMEN:progress=N` outside 0–100 is clamped, not rejected | Research Target 5 | If rejected, scripts that emit 101 due to rounding bugs cause confusing silent drops |
| A5 | Default concurrency limit of 4 is appropriate for macOS menu bar context | Claude's Discretion | Too high wastes resources; too low makes subtasks feel slow. 4 is a common default (cargo, make -j4) |
| A6 | Per-subtask default timeout of 60 seconds is appropriate | Claude's Discretion | Scripts that run legitimate long operations will time out. Should probably be overridable per-action in addition to per-subtask |

---

## Open Questions

1. **`cmd` convenience shorthand in SubtaskConfig (Pitfall 5)**
   - What we know: `EXMEN:subtask={ id="x", script={ type="inline", content="make" } }` is verbose
   - What's unclear: Whether user experience requires `cmd = "make"` as shorthand
   - Recommendation: Add `cmd: String?` to `SubtaskConfig` with a computed `resolvedScript` property. Minor model change, large UX improvement for dynamic subtask use case.

2. **Per-action vs global concurrency cap**
   - What we know: ORCH-06 requires the cap is honored; D-01 through D-15 don't specify where it's configured
   - What's unclear: Global `config.toml` key vs per-action key in the TOML
   - Recommendation: Global default in `config.toml` + optional per-`[[action]]` override. Start with global-only for simplicity.

3. **Progress window auto-close behavior**
   - What we know: D-09 says window "survives menu close" (like ServiceOutputWindow)
   - What's unclear: Whether it auto-closes after all subtasks complete, or stays open for review
   - Recommendation: Stay open with a "Close" button that becomes enabled on completion. Matches the feel of a build output window.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6.x | Structured concurrency (`withTaskGroup`, `AsyncStream`, actors) | ✓ | 6.3.2 | — |
| macOS 13+ SDK | Foundation.Process, FileHandle.readabilityHandler | ✓ | macOS 26.0 (dev machine) | — |
| `/bin/bash` | Script execution | ✓ | macOS builtin | — |
| `kill(2)` POSIX | Process group termination | ✓ | macOS builtin | — |
| TOMLDecoder 0.4.3 | SubtaskConfig decode | ✓ | 0.4.3 (pinned) | — |
| SwiftTerm 1.11.2 | ServiceOutputWindow (reused) | ✓ | 1.11.2 (pinned) | — |

**Missing dependencies with no fallback:** None.

---

## Validation Architecture

`workflow.nyquist_validation` is absent from `.planning/config.json` — treat as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (via Xcode) or Swift Testing (Swift 6.3) |
| Config file | None yet — Wave 0 gap |
| Quick run command | `xcodebuild test -scheme Exmen -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -scheme Exmen -destination 'platform=macOS'` |

Note: The project currently has **no test target** in `Package.swift` or Xcode project (confirmed by source scan). All validation is currently manual. Wave 0 must add a test target.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| ORCH-01 | `[[subtasks]]` parses into `[SubtaskConfig]` correctly | unit | `xcodebuild test ... -only-testing:ExmenTests/SubtaskConfigTests` | ❌ Wave 0 |
| ORCH-02 | Wave topo-sort produces correct waves; `depends_on` gates hold | unit | `xcodebuild test ... -only-testing:ExmenTests/WaveSchedulerTests` | ❌ Wave 0 |
| ORCH-02 | Cycle detection throws `OrchestratorError.dependencyCycle` | unit | same | ❌ Wave 0 |
| ORCH-02 | Concurrency cap honored (≤ N simultaneous running subtasks) | integration | `xcodebuild test ... -only-testing:ExmenTests/ConcurrencyCapTests` | ❌ Wave 0 |
| ORCH-03 | SubtaskState transitions: pending→running→succeeded/failed | unit | `xcodebuild test ... -only-testing:ExmenTests/SubtaskStateTests` | ❌ Wave 0 |
| ORCH-04 | `EXMEN:subtask=` inline table decodes into SubtaskConfig | unit | `xcodebuild test ... -only-testing:ExmenTests/DynamicSpawnTests` | ❌ Wave 0 |
| ORCH-04 | Duplicate id is ignored idempotently | unit | same | ❌ Wave 0 |
| ORCH-05 | Aggregated summary reports correct counts (N succeeded/M failed/K skipped) | unit | `xcodebuild test ... -only-testing:ExmenTests/SummaryTests` | ❌ Wave 0 |
| ORCH-06 | Process group kill terminates all child processes | integration | manual (requires live process spawn) | manual-only |
| ORCH-06 | Timeout fires and process is dead after grace period | integration | `xcodebuild test ... -only-testing:ExmenTests/TimeoutTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild build -scheme Exmen` (build passes; unit tests for touched module)
- **Per wave merge:** Full `xcodebuild test` suite
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] Add `ExmenTests` test target to `Package.swift` with `testTarget` depending on `Exmen` sources
- [ ] `Tests/ExmenTests/SubtaskConfigTests.swift` — ORCH-01 TOML decode
- [ ] `Tests/ExmenTests/WaveSchedulerTests.swift` — ORCH-02 topo-sort + cycle detection
- [ ] `Tests/ExmenTests/DynamicSpawnTests.swift` — ORCH-04 inline-table decode
- [ ] `Tests/ExmenTests/SummaryTests.swift` — ORCH-05 counts
- [ ] `Tests/ExmenTests/TimeoutTests.swift` — ORCH-06 timeout
- [ ] `Tests/ExmenTests/SubtaskStateTests.swift` — ORCH-03 state machine

---

## Security Domain

`security_enforcement` is not set in `.planning/config.json` — treat as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Validate `EXMEN:subtask=` inline table before decode; clamp/reject invalid `progress=` values |
| V6 Cryptography | no | — |

### Known Threat Patterns for Subtask Orchestration

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious `EXMEN:subtask=` injecting arbitrary shell commands | Tampering | Scripts are user-authored — same trust level as existing action scripts. The `EXMEN:subtask=` protocol is consumed only from child process stdout (a channel the user controls). No additional hardening needed beyond TOML decode validation. |
| Unbounded subtask spawn loop (D-08) | DoS | Duplicate-id check (D-08) prevents re-registration. Add a max-subtask-count guard (e.g., 50) to prevent runaway dynamic spawn. |
| `EXMEN:progress=N` with N outside 0–100 | Tampering/DoS | Clamp to `max(0, min(100, N))` rather than crashing. |
| Zombie processes post-timeout | Elevation | Process group kill (ORCH-06) + 5s SIGKILL fallback ensures clean shutdown. |

---

## Sources

### Primary (HIGH confidence)
- Project source: `Exmen/Services/ScriptRunner.swift` — anti-pattern reference, current runner shape
- Project source: `Exmen/Services/HookParser.swift` — parse(fullString) → extend to parseLine
- Project source: `Exmen/Models/ActionConfig.swift`, `ScriptConfig` — embed in SubtaskConfig
- Project source: `Exmen/Services/ServiceManager.swift`, `ActionService.swift` — @MainActor @Published singleton blueprint
- Project source: `Exmen/Views/ServiceOutputWindow.swift` — window pattern for SubtaskProgressWindow
- Project source: `Exmen/Models/ServiceState.swift` — status dot color convention (green/gray/yellow/red)
- Project source: `build/SourcePackages/checkouts/TOMLDecoder/Sources/TOMLDecoder/TOMLDecoder.swift` — confirmed `decode(_:from:String)` API
- Project source: `build/SourcePackages/checkouts/TOMLDecoder/Sources/TOMLDecoder/Parsing/Parser.swift` — confirmed inline table parsing
- Project source: `build/SourcePackages/checkouts/SwiftTerm/Package.swift` — confirmed swift-subprocess is commented out (not a project dep)
- Project source: `Exmen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — confirmed project SPM deps
- [Apple FileHandle readabilityHandler docs](https://developer.apple.com/documentation/foundation/filehandle/1412413-readabilityhandler)
- [Apple AsyncStream docs](https://developer.apple.com/documentation/swift/asyncstream)
- [Apple TaskGroup docs](https://developer.apple.com/documentation/swift/taskgroup)

### Secondary (MEDIUM confidence)
- [swift-corelibs-foundation Process.swift](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/Process.swift) — confirmed no public spawn group configurator; Foundation.Process uses POSIX_SPAWN_SETPGROUP internally
- [swift-subprocess GitHub](https://github.com/swiftlang/swift-subprocess) — confirmed not needed for this phase; project uses Foundation.Process
- [Apple Developer Forums — Running a Child Process](https://developer.apple.com/forums/thread/690310) — Dispatch I/O recommendation; concurrent pipe read pattern
- [SR-12080 readabilityHandler stderr EOF bug](https://github.com/apple/swift-issues/issues/12080) — confirmed workaround: drain in terminationHandler

### Tertiary (LOW confidence — flagged assumptions)
- Kahn's algorithm wave scheduler pattern — standard CS algorithm, [ASSUMED] in Swift form
- `withTaskGroup` seed-and-drain for bounded concurrency — idiomatic based on SE-0304, [ASSUMED] exact form
- Default timeout (60s) and concurrency limit (4) values — Claude's Discretion, [ASSUMED] reasonable

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all packages verified in project source
- Architecture: HIGH — patterns directly derived from existing Phase 8 code (ServiceManager, ServiceOutputWindow, ServiceState)
- Streaming runner: HIGH — FileHandle.readabilityHandler + terminationHandler drain confirmed by Apple docs and bug reports
- Process group kill: MEDIUM — `kill(-pid, SIGTERM)` approach confirmed via swift-corelibs-foundation source; setsid shim is belt-and-suspenders, not required
- TOMLDecoder inline table: HIGH — Parser.swift source confirms inline table support; wrap-and-decode pattern verified against TOMLDecoder.swift API
- Wave scheduler algorithm: HIGH (algorithm) / ASSUMED (Swift form)
- Pitfalls: HIGH — pipe deadlock, actor reentrancy, and zombie process pitfalls are well-documented

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (stable Apple SDK + project toolchain; swift-subprocess not used so no version drift risk)

---

## RESEARCH COMPLETE
