# Research: Parallel Subtask Orchestration

Research for adding a **parent action that orchestrates multiple subtasks** to Exmen,
in two flavors: **declarative** (subtasks listed in TOML with `depends_on`) and
**dynamic** (parent script spawns subtasks at runtime via hook lines).

## Overview

### Hard constraints discovered in the codebase

| Constraint | Source | Impact |
|---|---|---|
| **Deployment target macOS 13** | `Exmen.xcodeproj` `MACOSX_DEPLOYMENT_TARGET = 13.0`, `Package.swift` `.macOS(.v13)` | **`@Observable` (Observation framework) is macOS 14+ → NOT available.** Must use `ObservableObject` + `@Published`. |
| Swift language mode 5 | `SWIFT_VERSION = 5.0` (toolchain is 6.3) | No strict concurrency enforcement, but write code that *would* pass. `TaskGroup`, `AsyncStream`, `for try await line in handle.bytes.lines` are all available on macOS 13. |
| `ScriptRunner` is a fire-once `Process` wrapper | `Exmen/Services/ScriptRunner.swift` | Reads stdout only at termination (`readDataToEndOfFile`). **No streaming today**; subtasks need line-by-line streaming, so a new runner path is required. |
| Hook protocol is `EXMEN:key=value`, parsed post-hoc | `Exmen/Services/HookParser.swift`, only keys `title/status/badge/icon` | Already line-based and post-hoc (parses the *final* captured output). Dynamic subtasks need **live** parsing as lines arrive. |
| Config decoded via `TOMLDecoder` into `Codable` structs | `Exmen/Services/ConfigLoader.swift`, `Exmen/Models/ActionConfig.swift` | `[[subtasks]]` array-of-tables maps cleanly to `[SubtaskConfig]?`. TOMLDecoder supports arrays of tables. |
| `ScriptConfig` already models `inline` vs `file` | `ActionConfig.swift` | Reuse it for each subtask's body — don't invent a new command shape. |
| Output handlers: clipboard / notification / popup | `Exmen/Services/OutputHandler.swift`, `MenuContentView.handleResult` | Aggregated parent result feeds the *same* handlers; popup needs a richer view. |

### Architecture fit

The cleanest insertion point is a new `SubtaskOrchestrator` (an `ObservableObject`,
`@MainActor` for its published state) that sits beside `ScriptRunner`. The existing
single-script path (`MenuContentView.executeAction` → `ScriptRunner.run` → `handleResult`)
stays untouched for non-orchestrating actions. An action becomes an "orchestrator"
when its config has `[[subtasks]]` (declarative) **or** `[orchestrator]` mode is set
(dynamic). Detection happens in `Action(from:)`.

---

## Concurrency Model

### Run a `Process` async and stream stdout line-by-line

Two viable approaches; **prefer async `bytes.lines`** over `readabilityHandler`:

- `FileHandle.readabilityHandler` — callback on a background queue, you accumulate a
  buffer and split on `\n` yourself. Easy to leak/over-retain; you must `nil` the
  handler in the termination path or it fires forever. This is the "old" style.
- **`FileHandle.bytes.lines` (macOS 12+) — an `AsyncLineSequence`.** Cleaner, integrates
  with structured concurrency and cancellation. This is the recommended path on macOS 13.

A streaming runner that yields events as an `AsyncStream`:

```swift
enum ProcEvent {
    case stdout(String)      // one line
    case stderr(String)      // one line
    case exited(Int32)       // exit code
}

/// Run a bash script, streaming stdout/stderr lines, returning an AsyncStream.
/// Caller drains the stream; finishing the stream == process done.
func runStreaming(_ script: String,
                  env: [String: String]) -> AsyncStream<ProcEvent> {
    AsyncStream { continuation in
        let proc = Process()
        let outPipe = Pipe(), errPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", script]
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        environment.merge(env) { _, new in new }
        proc.environment = environment

        // IMPORTANT: drain BOTH pipes concurrently or a full stderr buffer (64KB)
        // deadlocks the child while we read stdout. See Pitfalls.
        let drain = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try? await line in outPipe.fileHandleForReading.bytes.lines {
                        continuation.yield(.stdout(line))
                    }
                }
                group.addTask {
                    for try? await line in errPipe.fileHandleForReading.bytes.lines {
                        continuation.yield(.stderr(line))
                    }
                }
            }
        }

        proc.terminationHandler = { p in
            Task { _ = await drain.value             // ensure all lines flushed first
                   continuation.yield(.exited(p.terminationStatus))
                   continuation.finish() }
        }

        // Terminate child if the consumer cancels / stream is torn down.
        continuation.onTermination = { @Sendable _ in
            drain.cancel()
            if proc.isRunning { proc.terminate() }
        }

        do { try proc.run() }
        catch { continuation.yield(.exited(-1)); continuation.finish() }
    }
}
```

This single primitive serves **both** modes: a declarative subtask consumes one stream
and tracks exit code; a dynamic parent consumes its stream and parses `EXMEN:` lines live.

### Parallel subtasks with a TaskGroup

`withThrowingTaskGroup` runs independent subtasks concurrently and lets us aggregate
results as each finishes:

```swift
func runWave(_ subtasks: [Subtask]) async -> [String: SubtaskResult] {
    await withTaskGroup(of: (String, SubtaskResult).self) { group in
        for st in subtasks {
            group.addTask { (st.id, await self.runOne(st)) }
        }
        var results: [String: SubtaskResult] = [:]
        for await (id, result) in group { results[id] = result }
        return results
    }
}
```

Use **non-throwing** `withTaskGroup` and model failure inside `SubtaskResult` (exit
code / error string), so one failing subtask doesn't cancel siblings unless you choose
"fail-fast". Throwing-group rethrow auto-cancels the group — useful only when you *want*
to abort all on first failure.

---

## Dependency Scheduling

Represent `depends_on: [String]` (subtask ids). Schedule by **topological wave**:
repeatedly run every subtask whose deps are all already completed, concurrently; then
the next wave. This is simpler than a per-task continuation graph and maps perfectly
onto "run a wave with a TaskGroup".

```swift
struct Subtask { let id: String; let script: ScriptConfig
                 let dependsOn: [String]; let timeout: TimeInterval }

enum ScheduleError: Error { case cycle([String]), unknownDependency(String, String) }

/// Kahn-style topological grouping into waves. Detects cycles + dangling deps.
func waves(_ tasks: [Subtask]) throws -> [[Subtask]] {
    let byId = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    for t in tasks { for d in t.dependsOn where byId[d] == nil {
        throw ScheduleError.unknownDependency(t.id, d) } }

    var remaining = Set(tasks.map(\.id))
    var done = Set<String>()
    var result: [[Subtask]] = []

    while !remaining.isEmpty {
        let ready = tasks.filter {
            remaining.contains($0.id) && Set($0.dependsOn).isSubset(of: done)
        }
        guard !ready.isEmpty else {
            throw ScheduleError.cycle(Array(remaining))   // nothing ready ⇒ cycle
        }
        result.append(ready)
        for t in ready { remaining.remove(t.id); done.insert(t.id) }
    }
    return result
}
```

Orchestrate the waves; gate dependents on dependency **success** (configurable):

```swift
for wave in try waves(tasks) {
    // Skip tasks whose deps failed (partial-failure policy below).
    let runnable = wave.filter { st in st.dependsOn.allSatisfy { results[$0]?.isSuccess == true } }
    for st in wave where !runnable.contains(where: { $0.id == st.id }) {
        results[st.id] = .skipped(reason: "dependency failed")
    }
    let waveResults = await runWave(runnable)   // respects concurrency cap (below)
    results.merge(waveResults) { _, new in new }
}
```

**Sequential mode** = treat the whole list as a single dependency chain (each `depends_on`
the previous), or simpler: if `mode == .sequential`, just `await runOne` in a `for` loop.
**Parallel mode with no deps** = one wave containing everything.

Cycle detection falls out for free: if a wave produces no ready tasks while tasks remain,
there is a cycle. Validate at load time (in `ConfigLoader`/`Action(from:)`) so a bad TOML
surfaces immediately rather than at click time.

---

## Concurrency Limits & Cancellation

### Bounding concurrent subprocesses

A `TaskGroup` started with N tasks tries to run all N at once. To cap at `maxConcurrent`,
use the **"prime then replace"** idiom (no semaphore, structured, cancellation-safe):

```swift
func runBounded(_ tasks: [Subtask], limit: Int) async -> [String: SubtaskResult] {
    var results: [String: SubtaskResult] = [:]
    var iter = tasks.makeIterator()
    await withTaskGroup(of: (String, SubtaskResult).self) { group in
        // Prime the pump with `limit` tasks.
        for _ in 0..<limit { if let t = iter.next() {
            group.addTask { (t.id, await self.runOne(t)) } } }
        // Each time one finishes, start the next.
        for await (id, res) in group {
            results[id] = res
            if let t = iter.next() {
                group.addTask { (t.id, await self.runOne(t)) }
            }
        }
    }
    return results
}
```

Avoid `DispatchSemaphore.wait()` inside async code — it blocks a cooperative-pool thread
and can deadlock. If you must use a counting gate across waves, use an actor-based
`AsyncSemaphore` instead. Default cap: 4 (or `ProcessInfo.activeProcessorCount`).

### Timeout per subtask

Race the work against a sleep using a child group; whichever wins cancels the other:

```swift
func runOne(_ st: Subtask) async -> SubtaskResult {
    await withTaskGroup(of: SubtaskResult?.self) { group in
        group.addTask { await self.execute(st) }            // streams + collects
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(st.timeout * 1e9))
            return Task.isCancelled ? nil : .timedOut
        }
        let first = await group.next()!     // first non-nil wins
        group.cancelAll()                   // cancel the loser
        return first ?? .failed("unknown")
    }
}
```

### Terminating the process tree (critical)

`process.terminate()` (SIGTERM) only signals the **direct** child (`/bin/bash`), not its
grandchildren (a script that backgrounds `curl &` etc.). Leaked grandchildren = zombies /
runaway work. Fix: run each child in its **own process group** and kill the whole group.

```swift
// Before run(): put child in its own process group (pgid == child pid)
proc.executableURL = URL(fileURLWithPath: "/bin/bash")
// Easiest portable trick: prefix the command so bash starts a new session:
proc.arguments = ["-c", "exec setsid -w /bin/bash -c '\(escaped)'"] // if setsid available
// OR set the group in a posix_spawn attr; on macOS the pragmatic route:
// after run(), capture pid and kill the group with a negative pid.
let pid = proc.processIdentifier
kill(-pid, SIGTERM)   // negative pid ⇒ whole process group
```

macOS lacks `setsid` in `/usr/bin` by default; the robust approach is `posix_spawn` with
`POSIX_SPAWN_SETPGROUP`, or call `setpgid` — but `Process` doesn't expose a pre-exec hook.
**Pragmatic recommendation:** wrap the script body so bash itself establishes a trap and
the orchestrator sends SIGTERM to `-pid`; fall back to SIGKILL on `-pid` after a grace
period. Wire `continuation.onTermination` (shown earlier) so Swift `Task` cancellation
(parent action cancelled, app quitting) propagates down to `kill(-pid, …)`.

Cancellation chain: **user cancels parent → orchestrator Task cancelled → TaskGroup
children cancelled → each `runStreaming` stream torn down → `onTermination` → `kill(-pid)`.**

---

## Progress Model

macOS 13 ⇒ **no `@Observable`**. Use `ObservableObject` with `@Published`, mutated on
`@MainActor`, consistent with `ActionService` and `ManagedService` in the codebase.

```swift
enum SubtaskStatus: Equatable { case pending, running, succeeded, failed, skipped, timedOut }

@MainActor
final class SubtaskItem: ObservableObject, Identifiable {
    let id: String
    let name: String
    @Published var status: SubtaskStatus = .pending
    @Published var progress: Double = 0          // 0...1, driven by EXMEN:progress
    @Published var lastLine: String = ""         // most recent stdout line
    init(id: String, name: String) { self.id = id; self.name = name }
}

@MainActor
final class SubtaskOrchestrator: ObservableObject {
    @Published private(set) var items: [SubtaskItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var summary: OrchestratorSummary?

    /// Called from background stream consumers — always hop to main.
    func update(id: String, _ mutate: @escaping (SubtaskItem) -> Void) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        mutate(item)            // already on MainActor
    }
}
```

Thread-safety: subprocess lines arrive on background tasks; **every UI-visible mutation
must hop to `@MainActor`**. Because `SubtaskOrchestrator` is `@MainActor`, awaiting its
methods from a `Task` does the hop automatically. SwiftUI menu/HUD views bind via
`@ObservedObject` / `@StateObject`. Note: a `@Published var items: [SubtaskItem]` only
republishes when the *array* changes; mutating a child `SubtaskItem`'s `@Published`
property is what drives per-row updates — so views must observe each `SubtaskItem`
(e.g. a child `SubtaskRowView` taking `@ObservedObject var item: SubtaskItem`).

HUD reuse: there is already a `ServiceOutputWindow` pattern; a parallel "orchestrator HUD"
window or an expanded popup can bind to `orchestrator.items`.

---

## Hook Protocol for Dynamic Subtasks

Extend the existing `EXMEN:key=value` line protocol. Two channels of communication:

### Parent → app (declaring & updating subtasks): stdout hook lines (live-parsed)

Keep it line-based and backward compatible. New keys, namespaced under `subtask`:

```
EXMEN:subtask=build cmd="make all"            # declare/spawn a dynamic subtask (id=build)
EXMEN:subtask=build name="Build project"      # optional friendly name
EXMEN:subtask=build status=running            # pending|running|succeeded|failed
EXMEN:subtask=build progress=42               # 0..100
EXMEN:subtask=build line=Compiling foo.c      # arbitrary last-output line
EXMEN:subtask=build depends_on=lint,fetch     # optional deps (dynamic graph)
EXMEN:subtask=build done=0                     # completion + exit code
```

Parsing: extend `HookParser` to recognize a `subtask=<id>` token, then collect the
remaining `key=value` pairs **on the same line** (so one line is one atomic update).
Use shell-style quoting for values with spaces. This requires upgrading the parser from
"split final output" to "parse each line as it streams" — feed it the `.stdout(line)`
events from `runStreaming`.

Two sub-modes for what `cmd=` means:
1. **App-spawned** (recommended): app receives `subtask=…cmd=…`, the *app* runs that
   command via the same orchestrator (gets streaming, timeout, concurrency cap, the graph
   for free). The parent script is just a planner.
2. **Self-managed**: parent runs its own children and only *reports* status via hook
   lines (`status`, `progress`, `done`). App is a pure dashboard. Simpler app code,
   but no concurrency/timeout guarantees from Exmen.

### App → parent (results / completion back to the script)

Options considered:

| Mechanism | Verdict |
|---|---|
| **Env vars** | One-shot only (set at spawn). Good for passing *config in*, useless for streaming results *back*. |
| **stdin** | Workable: app writes `result lines` to the child's stdin. But the parent must be written to read stdin in a loop, and it conflicts with interactive scripts. |
| **Polling a status file** | App writes `~/.config/exmen/run/<runid>.json`; parent polls. Simple, debuggable, race-prone, filesystem churn. |
| **A dedicated fd / FIFO** | App creates a FIFO, passes its path via env (`EXMEN_RESULT_FIFO`); parent reads it. Clean unidirectional channel, no polling. Slightly more setup. |

**Recommendation:** For mode 1 (app-spawned), the parent **doesn't need results back** —
it only emits a plan, and the *app* aggregates. This is by far the simplest and most
robust; pick it as the default. If a parent genuinely needs child results (mode 2 with
feedback), provide a **FIFO whose path is in `EXMEN_RESULT_FIFO`**, app writes
`subtask=<id> done=<code>` lines the parent can `read` — symmetric with the stdout
protocol and no polling. Avoid stdin (collides with interactive/PTY use) and avoid status
files unless you want zero-dependency debuggability.

---

## TOML Schema

Array-of-tables decodes natively with `TOMLDecoder` into `[SubtaskConfig]?`. Reuse
`ScriptConfig` (inline/file) for each subtask body so the file/inline machinery and
`resolvedContent()` are shared.

### Declarative

```toml
name = "Deploy"
icon = "shippingbox"
description = "Build, test, and deploy in parallel where possible"

[output]
handler = "popup"

[orchestrator]
mode = "parallel"          # parallel | sequential
max_concurrent = 4         # optional, default = activeProcessorCount
fail_fast = false          # optional, default false (let siblings finish)
timeout = 120              # optional parent-level wall clock

[[subtasks]]
id = "fetch"
name = "Fetch deps"
script = { type = "inline", content = "npm ci" }
timeout = 60

[[subtasks]]
id = "lint"
name = "Lint"
script = { type = "inline", content = "npm run lint" }
depends_on = ["fetch"]

[[subtasks]]
id = "test"
name = "Test"
script = { type = "file", path = "~/scripts/test.sh" }
depends_on = ["fetch"]

[[subtasks]]
id = "deploy"
name = "Deploy"
script = { type = "inline", content = "./deploy.sh" }
depends_on = ["lint", "test"]
```

### Dynamic

```toml
name = "Smart Deploy"
[output]
handler = "popup"

[orchestrator]
mode = "dynamic"           # parent script emits EXMEN:subtask=... lines
max_concurrent = 4

[script]                   # the planner/parent script
type = "inline"
content = '''
echo 'EXMEN:subtask=build cmd="make" name="Build"'
echo 'EXMEN:subtask=test cmd="make test" depends_on=build name="Test"'
'''
```

### Codable models (add to `ActionConfig.swift`)

```swift
enum OrchestratorMode: String, Codable { case parallel, sequential, dynamic }

struct SubtaskConfig: Codable {
    let id: String
    let name: String?
    let script: ScriptConfig
    let dependsOn: [String]?
    let timeout: TimeInterval?
    enum CodingKeys: String, CodingKey { case id, name, script
                                         case dependsOn = "depends_on", timeout }
    var resolvedName: String { name ?? id }
}

struct OrchestratorConfig: Codable {
    let mode: OrchestratorMode?
    let maxConcurrent: Int?
    let failFast: Bool?
    let timeout: TimeInterval?
    enum CodingKeys: String, CodingKey { case mode, timeout
                                         case maxConcurrent = "max_concurrent"
                                         case failFast = "fail_fast" }
    var resolvedMode: OrchestratorMode { mode ?? .parallel }
}
```

Then on `ActionConfig` add `let orchestrator: OrchestratorConfig?` and
`let subtasks: [SubtaskConfig]?` (both optional ⇒ fully backward compatible with the
existing decoder, exactly like the `service` discriminator pattern already in the file).
An action is an orchestrator iff `subtasks != nil || orchestrator?.mode == .dynamic`.

**Validate at load**: unique ids, every `depends_on` references a real id, and `waves()`
succeeds (no cycle). Surface errors via `ActionService.lastError`.

---

## Result Aggregation

Each subtask yields a `SubtaskResult` (reuse/wrap `ScriptResult`):

```swift
struct SubtaskResult {
    let id: String; let name: String
    let status: SubtaskStatus
    let exitCode: Int32?
    let output: String          // collected stdout (hook lines stripped)
    let duration: TimeInterval
    var isSuccess: Bool { status == .succeeded }
}

struct OrchestratorSummary {
    let total: Int, succeeded: Int, failed: Int, skipped: Int
    let duration: TimeInterval
    let results: [SubtaskResult]
    var allPassed: Bool { failed == 0 && skipped == 0 }
    var headline: String { "\(succeeded)/\(total) passed" +
        (failed > 0 ? ", \(failed) failed" : "") +
        (skipped > 0 ? ", \(skipped) skipped" : "") }
}
```

Feed the summary into the existing output handlers (`OutputService`):

- **notification**: title = action name, body = `summary.headline`,
  `isError: !summary.allPassed`. Reuse `OutputService.showNotification`.
- **clipboard**: copy a text table of `id  status  duration  exitcode`.
- **popup**: the richest path. The current `popupResult` tuple in `MenuContentView`
  is `(Action, ScriptResult, String)`; for orchestrators bind the popup to the
  live `SubtaskOrchestrator` instead, rendering a per-subtask list (status icon +
  progress + last line) and the headline summary. This also serves as the live HUD
  during execution, not just the final report.

Partial-failure semantics (configurable via `fail_fast`): default = run all, report
mixed; `fail_fast = true` = cancel remaining waves on first failure. Dependents of a
failed task are always marked `skipped` (a dependency couldn't be satisfied).

---

## Pitfalls

1. **Pipe-buffer deadlock (most likely bug).** A child writing > ~64 KB to stderr while
   the parent only drains stdout will block forever. The current `ScriptRunner` dodges
   this by reading only at termination, but a *streaming* runner must drain **stdout and
   stderr concurrently** (two child tasks, as in `runStreaming`). Never read one pipe to
   EOF before the other.

2. **Zombie / orphan grandchildren.** `terminate()` signals only the direct `/bin/bash`.
   Backgrounded grandchildren survive. Kill the **process group** (`kill(-pid, …)`),
   SIGTERM then SIGKILL after a grace period. Always reap via `terminationHandler`.

3. **Double-resume of continuations.** The existing `ScriptRunner` already guards
   timeout-vs-termination races with an `NSLock` + `hasResumed`. The `AsyncStream`-based
   runner sidesteps this (no `CheckedContinuation`), but the per-subtask `timeout`
   group-race must `cancelAll()` exactly once and ignore late results.

4. **Main-thread blocking.** Never `DispatchSemaphore.wait()` or
   `readDataToEndOfFile()` on `@MainActor`. All process I/O on background tasks; only the
   `@Published` mutations hop to main. SwiftUI menu extras are sensitive — a blocked main
   thread freezes the whole menu bar.

5. **`@Published` array vs child mutation.** Mutating a `SubtaskItem.status` does NOT
   republish the parent's `items` array. Views must observe each `SubtaskItem`
   (`@ObservedObject` per row) or the list won't update mid-run.

6. **Cycle / dangling deps detected too late.** Validate the graph at config-load time,
   not click time, so a malformed TOML is visible immediately (consistent with how
   `ConfigLoader` already logs parse failures).

7. **Timeout vs dependents.** A timed-out/failed task must cascade `skipped` to its
   dependents; otherwise dependents run against a missing precondition. The wave loop's
   `runnable` filter handles this — make sure it runs *before* each wave, not just once.

8. **Cancellation propagation gaps.** App quit / menu dismissed must cancel the
   orchestrator Task. Wire `continuation.onTermination` → `kill(-pid)` and ensure the
   top-level orchestrator Task is stored (e.g. on the orchestrator object) so it can be
   cancelled, mirroring `ManagedService.restartBackoffTask`.

9. **Dynamic-subtask line atomicity.** Stream lines can be split if a script doesn't
   `\n`-terminate. `AsyncLineSequence` handles partial lines at EOF, but make each
   `EXMEN:subtask=…` update self-contained on one line so a missing trailing newline only
   loses the last (usually `done=`) update — and add a final reconcile from the exit code.

10. **TOMLDecoder strictness.** Confirm `[[subtasks]]` with nested inline tables
    (`script = { type = "inline", content = "…" }`) decodes; if the dependency version is
    finicky about inline tables, fall back to nested `[[subtasks.script]]`-style or a flat
    `cmd = "…"` string field on `SubtaskConfig`.

---

## Recommendation (suggested build order)

Default to **app-spawned** subtasks (parent is a planner; app runs/aggregates) — it gives
streaming, timeouts, concurrency caps, and the dependency graph for free, and avoids the
hard result-channel problem entirely. Keep the single-script path untouched.

1. **Streaming runner** — add `runStreaming(_:) -> AsyncStream<ProcEvent>` (new method on
   `ScriptRunner` or a new `StreamingRunner`), draining stdout+stderr concurrently, with
   `onTermination` → process-group kill. Unit-test deadlock with a >64 KB stderr script.
2. **Models + TOML** — add `SubtaskConfig`, `OrchestratorConfig` to `ActionConfig.swift`;
   wire optional fields; detect orchestrator in `Action(from:)`; validate graph in
   `ConfigLoader` (unique ids, deps exist, `waves()` ok).
3. **Scheduler** — `waves()` topo-sort + cycle detection (pure function, easy to test).
4. **Orchestrator core (declarative)** — `@MainActor SubtaskOrchestrator: ObservableObject`
   running waves with bounded concurrency + per-subtask timeout, publishing `SubtaskItem`
   state and an `OrchestratorSummary`.
5. **UI** — `SubtaskRowView` (`@ObservedObject` per item) + an orchestrator popup/HUD
   bound to the live orchestrator; reuse `OutputService` for notification/clipboard summary.
6. **Aggregation → handlers** — map `OrchestratorSummary` into the existing output paths.
7. **Dynamic mode** — upgrade `HookParser` to live, per-line parsing; recognize
   `subtask=<id> key=value…`; feed `.stdout` events into it; the parent's emitted plan
   builds the same `Subtask` list the declarative path runs. Reuse everything from steps 3–6.
8. **(Optional) result FIFO** — only if a real use case needs child→parent feedback;
   expose `EXMEN_RESULT_FIFO`. Skip until proven necessary.
