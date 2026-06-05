# Phase 11: Subtask Orchestration - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 8 (2 modified, 6 new)
**Analogs found:** 8 / 8

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Exmen/Models/ActionConfig.swift` | model | CRUD | self (modify) | self |
| `Exmen/Models/SubtaskConfig.swift` | model | CRUD | `Exmen/Models/ActionConfig.swift` | exact (Codable struct, TOMLDecoder) |
| `Exmen/Models/SubtaskState.swift` | model | event-driven | `Exmen/Models/ServiceState.swift` | exact (status enum + dot color convention) |
| `Exmen/Services/SubtaskRunner.swift` | service | streaming | `Exmen/Services/ScriptRunner.swift` | role-match (anti-pattern ref — do NOT copy buffered read) |
| `Exmen/Services/SubtaskOrchestrator.swift` | service | event-driven | `Exmen/Services/ServiceManager.swift` + `ActionService.swift` | exact (@MainActor @Published singleton) |
| `Exmen/Services/HookParser.swift` | service | request-response | self (extend) | self |
| `Exmen/Views/SubtaskProgressWindow.swift` | view | request-response | `Exmen/Views/ServiceOutputWindow.swift` | exact (NSWindowController scaffold) |
| `Exmen/Services/ConfigLoader.swift` | service | CRUD | self (extend) | self |

---

## Pattern Assignments

### `Exmen/Models/ActionConfig.swift` (modify — add `subtasks` field)

**Analog:** self

**What to add** — insert after the `service: ServiceConfig?` field (line 55):
```swift
/// Optional subtasks for orchestrated multi-step actions (Phase 11)
let subtasks: [SubtaskConfig]?
```

No other changes to `ActionConfig`. `ConfigLoader` decodes `ActionConfig` via `TOMLDecoder` (line 68 in ConfigLoader.swift); the new optional field auto-decodes because `[SubtaskConfig]?` is `Codable` and TOML `[[subtasks]]` is a TOML array of tables.

---

### `Exmen/Models/SubtaskConfig.swift` (NEW — Codable config model)

**Analog:** `Exmen/Models/ActionConfig.swift`

**Imports pattern** (copy from ActionConfig.swift line 1):
```swift
import Foundation
```

**Core Codable struct pattern** (modeled on ActionConfig.swift lines 45–74):
```swift
struct SubtaskConfig: Codable {
    let id: String
    let name: String?
    let script: ScriptConfig       // D-02: reuse existing ScriptConfig; same inline/file pattern
    let cmd: String?               // D-05 convenience shorthand → resolvedScript maps it to inline ScriptConfig
    let timeout: TimeInterval?
    let depends_on: [String]?

    var resolvedName: String { name ?? id }

    var resolvedTimeout: TimeInterval { timeout ?? SubtaskOrchestrator.defaultSubtaskTimeout }

    /// Single decode path for both [[subtasks]] and EXMEN:subtask= inline table (D-06)
    var resolvedScript: ScriptConfig {
        if let cmd = cmd {
            return ScriptConfig(type: .inline, content: cmd, path: nil)
        }
        return script
    }
}
```

**ScriptConfig reference** (ActionConfig.swift lines 17–33 — reuse as-is, no copy needed):
- `ScriptConfig.type: ScriptType` (`.inline` / `.file`)
- `ScriptConfig.resolvedContent() -> String?` — already handles tilde expansion for `.file`

**Dynamic inline-table decode helper** — place as a free function or `static func` on `SubtaskConfig`:
```swift
// TOMLDecoder.decode(_:from:String) confirmed at ConfigLoader.swift line 68 pattern
static func decodeInlineTable(_ rawValue: String) throws -> SubtaskConfig {
    let toml = "subtask = \(rawValue)"
    struct Root: Decodable { let subtask: SubtaskConfig }
    return try TOMLDecoder().decode(Root.self, from: toml).subtask
}
```

---

### `Exmen/Models/SubtaskState.swift` (NEW — status enum + state struct)

**Analog:** `Exmen/Models/ServiceState.swift`

**Imports pattern** (ServiceState.swift line 1):
```swift
import SwiftUI
```

**Status enum with dot color** (copy convention from ServiceState.swift lines 4–28):
```swift
// ServiceState.dotColor convention (lines 13–19):
// .running   → .green
// .stopped   → .gray
// .starting  → .yellow
// .crashed   → .red
//
// SubtaskStatus maps to same colors:
enum SubtaskStatus: Equatable {
    case pending               // gray  (not yet started)
    case running               // green (active, indeterminate spinner)
    case succeeded             // green (terminal)
    case failed(exitCode: Int32) // red (terminal)
    case skipped               // gray  (cascade-skip, terminal — distinct from failed)

    var dotColor: Color {
        switch self {
        case .pending:   return .gray
        case .running:   return .green
        case .succeeded: return .green
        case .failed:    return .red
        case .skipped:   return .gray
        }
    }

    var isTerminal: Bool {
        switch self { case .succeeded, .failed, .skipped: return true; default: return false }
    }
}
```

**State struct** (mirrors `ManagedService` observable fields pattern):
```swift
struct SubtaskState: Identifiable {
    let id: String          // subtask id — used as Identifiable.id
    let name: String
    var status: SubtaskStatus = .pending
    var startedAt: Date?
    var endedAt: Date?
    var progressPercent: Int? = nil   // nil = no EXMEN:progress= emitted (D-12)

    var elapsed: TimeInterval {
        guard let start = startedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(start)
    }
}
```

**Elapsed display pattern** (copy `ServiceState.displayText` approach, lines 30–49):
```swift
// ServiceState uses DateComponentsFormatter for uptime; copy same pattern for elapsed:
static func elapsedString(_ elapsed: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: elapsed) ?? "—"
}
```

---

### `Exmen/Services/SubtaskRunner.swift` (NEW — streaming Process runner)

**Analog:** `Exmen/Services/ScriptRunner.swift` — ANTI-PATTERN reference only. Do NOT copy `readDataToEndOfFile` or `withCheckedThrowingContinuation` approach.

**What to copy from ScriptRunner.swift:**

Environment setup (lines 46–49 — copy verbatim):
```swift
var environment = ProcessInfo.processInfo.environment
environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
process.environment = environment
```

Process launch + error handling shell (lines 41–43, 92–101):
```swift
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["-c", script]
// ... then try process.run() in a do/catch, yield .launchFailed(error) on catch
```

**What NOT to copy from ScriptRunner.swift:**
- `withCheckedThrowingContinuation` — use `AsyncStream` instead
- `readDataToEndOfFile()` inside `terminationHandler` on running process — deadlock risk
- `DispatchQueue.global().asyncAfter` for timeout — use `Task.sleep` instead
- `process.terminate()` alone — use `kill(-pid, SIGTERM)` for process group

**Core streaming pattern** (new — based on RESEARCH.md Research Target 1):
```swift
// SubtaskEvent enum — define alongside the runner
enum SubtaskEvent {
    case stdoutLine(String)
    case stderrLine(String)
    case hookLine(String)        // raw EXMEN:... line, forwarded to orchestrator
    case exited(Int32)
    case timedOut
    case launchFailed(Error)
}

func run(_ config: SubtaskConfig, subtaskId: String) -> AsyncStream<SubtaskEvent> {
    AsyncStream { continuation in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Resolve script content using same ScriptConfig.resolvedContent() pattern as ScriptRunner.swift line 14
        let script = config.resolvedScript.resolvedContent() ?? ""
        process.arguments = ["-c", script]

        // Environment: copy verbatim from ScriptRunner.swift lines 46–49
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = environment

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var buffer = ""   // partial-line accumulator for stdout

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer += text
            while let range = buffer.range(of: "\n") {
                let line = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])
                if line.hasPrefix("EXMEN:") {
                    continuation.yield(.hookLine(line))
                } else {
                    continuation.yield(.stdoutLine(line))
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            continuation.yield(.stderrLine(text))
        }

        // Timeout Task (replaces DispatchWorkItem from ScriptRunner.swift lines 52–66)
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(config.resolvedTimeout))
            kill(-process.processIdentifier, SIGTERM)
            Task {
                try? await Task.sleep(for: .seconds(5))
                kill(-process.processIdentifier, SIGKILL)
            }
            continuation.yield(.timedOut)
            continuation.finish()
        }

        process.terminationHandler = { proc in
            timeoutTask.cancel()
            // SR-12080 workaround: nil handlers then drain residual bytes
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let residual = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if !residual.isEmpty, let text = String(data: residual, encoding: .utf8) {
                for line in text.components(separatedBy: "\n") where !line.isEmpty {
                    if line.hasPrefix("EXMEN:") { continuation.yield(.hookLine(line)) }
                    else { continuation.yield(.stdoutLine(line)) }
                }
            }
            continuation.yield(.exited(proc.terminationStatus))
            continuation.finish()
        }

        continuation.onTermination = { _ in
            timeoutTask.cancel()
            kill(-process.processIdentifier, SIGTERM)
        }

        do {
            try process.run()
        } catch {
            timeoutTask.cancel()
            continuation.yield(.launchFailed(error))
            continuation.finish()
        }
    }
}
```

**Process-group kill** (ORCH-06 — do NOT use `process.terminate()` alone):
```swift
// Foundation.Process sets POSIX_SPAWN_SETPGROUP so child's PGID == child's PID
// kill(-pid, signal) sends to the whole process group (confirmed: swift-corelibs-foundation)
kill(-process.processIdentifier, SIGTERM)
// then after 5s grace:
kill(-process.processIdentifier, SIGKILL)
```

---

### `Exmen/Services/SubtaskOrchestrator.swift` (NEW — @MainActor wave scheduler)

**Analog:** `Exmen/Services/ServiceManager.swift` + `Exmen/Services/ActionService.swift`

**Imports pattern** (ActionService.swift lines 1–2):
```swift
import Foundation
import SwiftUI
```

**@MainActor ObservableObject singleton** (ServiceManager.swift lines 12–17, ActionService.swift lines 6–18):
```swift
@MainActor
class SubtaskOrchestrator: ObservableObject {
    static let shared = SubtaskOrchestrator()

    static let defaultSubtaskTimeout: TimeInterval = 60.0
    static let defaultConcurrencyLimit: Int = 4

    @Published var subtaskStates: [SubtaskState] = []
    @Published var isRunning: Bool = false
    @Published var overallProgressPercent: Int = 0

    private init() {}
}
```

**@Published mutation pattern** (ActionService.swift lines 36–37, 46 — synchronous, no await in mutating path):
```swift
// All @Published mutations must be synchronous (no await) to avoid actor reentrancy (Pitfall 4)
// Pattern from ActionService.swift applyHookUpdate (lines 74–79):
func updateSubtaskStatus(_ id: String, status: SubtaskStatus) {
    guard let idx = subtaskStates.firstIndex(where: { $0.id == id }) else { return }
    subtaskStates[idx].status = status
    // Recompute overallProgressPercent synchronously in same call
    let completed = subtaskStates.filter { $0.status.isTerminal }.count
    overallProgressPercent = subtaskStates.isEmpty ? 0 : (completed * 100 / subtaskStates.count)
}
```

**Wave execution with bounded concurrency** (RESEARCH.md Research Target 3):
```swift
// Seed-and-drain withTaskGroup pattern — do NOT use DispatchSemaphore (Pitfall 6)
func executeWave(_ wave: [SubtaskConfig], limit: Int) async {
    var idx = 0
    await withTaskGroup(of: Void.self) { group in
        while idx < wave.count && idx < limit {
            let sub = wave[idx]; idx += 1
            group.addTask { await self.runSubtask(sub) }
        }
        for await _ in group {
            if idx < wave.count {
                let sub = wave[idx]; idx += 1
                group.addTask { await self.runSubtask(sub) }
            }
        }
    }
}
```

**Dynamic subtask spawn** (D-05–D-08 — called from HookParser event dispatch):
```swift
func spawnDynamic(_ rawInlineTable: String) async {
    guard let config = try? SubtaskConfig.decodeInlineTable(rawInlineTable) else {
        print("SubtaskOrchestrator: failed to decode dynamic subtask from: \(rawInlineTable)")
        return
    }
    // D-08: duplicate id → ignore idempotently
    guard !subtaskStates.contains(where: { $0.id == config.id }) else {
        print("SubtaskOrchestrator: duplicate subtask id '\(config.id)' ignored")
        return
    }
    // Add to state and re-wave at runtime
    subtaskStates.append(SubtaskState(id: config.id, name: config.resolvedName))
    // ... re-schedule wave based on updated subtask list
}
```

**Error type pattern** (mirrors implicit error approach in ActionService.swift — use an enum):
```swift
enum OrchestratorError: Error {
    case unknownDependency(subtask: String, dependency: String)
    case dependencyCycle(ids: [String])
    case maxSubtaskCountExceeded
}
```

---

### `Exmen/Services/HookParser.swift` (extend — add `parseLine` + new keys)

**Analog:** self

**Current parse entry point** (lines 15–36 — keep as-is for existing single-action path):
```swift
func parse(_ output: String) -> (cleanOutput: String, updates: HookUpdate) { ... }
```

**Private helpers to reuse in new `parseLine`** (lines 39–67):
- `parseKeyValue(_ content: String) -> (key: String, value: String)?` (lines 39–48) — reuse verbatim
- `applyUpdate(key:value:to:)` (lines 50–68) — keep for existing path; new path returns an enum instead

**New streaming event type + parseLine method** — add below existing code:
```swift
// New enum — placed in HookParser.swift or a companion file
enum HookLineEvent {
    case subtask(rawValue: String)    // value starts with "{" — TOML inline table
    case progress(Int)                // clamped 0–100
    case legacyHook(key: String, value: String)   // title/status/badge/icon
    case unknown(key: String, value: String)
}

extension HookParser {
    /// Stateless single-line parse for streaming use (SubtaskRunner / SubtaskOrchestrator).
    /// Existing parse(_:) is unchanged for single-action path.
    func parseLine(_ line: String) -> HookLineEvent? {
        guard line.hasPrefix(hookPrefix) else { return nil }   // hookPrefix = "EXMEN:" (line 8)
        let hookContent = String(line.dropFirst(hookPrefix.count))
        guard let (key, value) = parseKeyValue(hookContent) else { return nil }  // reuse line 39–48
        switch key {
        case "subtask":
            return .subtask(rawValue: value)
        case "progress":
            // Clamp rather than reject (A4 from RESEARCH.md)
            let n = max(0, min(100, Int(value) ?? 0))
            return .progress(n)
        case "title", "status", "badge", "icon":
            return .legacyHook(key: key, value: value)
        default:
            print("HookParser: Unknown streaming key '\(key)'")
            return .unknown(key: key, value: value)
        }
    }
}
```

**Key detail:** `parseKeyValue` is currently `private` (line 39). To reuse it in the extension, either change the access level to `internal` (default) or move the extension into the same file. Same-file is simplest.

---

### `Exmen/Views/SubtaskProgressWindow.swift` (NEW — progress window)

**Analog:** `Exmen/Views/ServiceOutputWindow.swift`

**Imports pattern** (ServiceOutputWindow.swift lines 1–2):
```swift
import AppKit
import SwiftUI
```

**NSWindowController scaffold** (ServiceOutputWindow.swift lines 9–39 — copy structure verbatim, substitute content view):
```swift
class SubtaskProgressWindow: NSWindowController, NSWindowDelegate {

    // ServiceOutputWindow uses: contentRect 800x500, titled+closable+resizable+miniaturizable
    // SubtaskProgressWindow: use 600x400 (list of rows, narrower)
    init(orchestrator: SubtaskOrchestrator) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Subtask Progress"
        window.isReleasedWhenClosed = false   // critical — same as ServiceOutputWindow line 25

        super.init(window: window)
        window.delegate = self

        // Use NSHostingView with SwiftUI list bound to orchestrator @Published state
        let rootView = SubtaskProgressView().environmentObject(orchestrator)
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // NSWindowDelegate — same pattern as ServiceOutputWindow lines 54–57
    func windowWillClose(_ notification: Notification) {
        // optional: notify orchestrator or caller
    }
}
```

**How to show the window** (ServiceManager.swift lines 74–81 — copy pattern):
```swift
// In SubtaskOrchestrator or a caller:
if progressWindow == nil {
    progressWindow = SubtaskProgressWindow(orchestrator: self)
}
progressWindow?.showWindow(nil)
progressWindow?.window?.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

**SwiftUI content view** — `SubtaskProgressView` is a SwiftUI `View` embedded via `NSHostingView`. It observes `SubtaskOrchestrator` via `@EnvironmentObject`. Each row: status dot (`Circle().foregroundColor(state.status.dotColor)`), name, elapsed time, optional progress bar. Header: overall percent bar (`overallProgressPercent`).

---

### `Exmen/Services/ConfigLoader.swift` (extend — decode `subtasks` field)

**Analog:** self

**Current decode path** (ConfigLoader.swift lines 59–73 — no changes needed):
```swift
let decoder = TOMLDecoder()
return try decoder.decode(ActionConfig.self, from: content)
```

Because `subtasks: [SubtaskConfig]?` is an optional `Codable` field on `ActionConfig`, and `TOMLDecoder` handles TOML array-of-tables (`[[subtasks]]`) automatically, **no code changes are required in ConfigLoader**. The only required change is adding `subtasks: [SubtaskConfig]?` to `ActionConfig` and defining `SubtaskConfig` as `Codable`. `ConfigLoader` gets the new field for free.

Verify: `TOMLDecoder 0.4.3` `decode(_:from:String)` confirmed at ConfigLoader.swift line 68 pattern; inline table support confirmed in RESEARCH.md Research Target 4.

---

## Shared Patterns

### @MainActor + @Published Singleton
**Source:** `Exmen/Services/ServiceManager.swift` lines 12–17, `Exmen/Services/ActionService.swift` lines 6–18
**Apply to:** `SubtaskOrchestrator`
```swift
@MainActor
class SubtaskOrchestrator: ObservableObject {
    static let shared = SubtaskOrchestrator()
    @Published var subtaskStates: [SubtaskState] = []
    private init() {}
}
```
**Critical rule:** All `@Published` mutations must be in synchronous, no-`await` functions. Never read-modify-write across an `await` suspension point (Pitfall 4 in RESEARCH.md).

### Environment Setup for Process
**Source:** `Exmen/Services/ScriptRunner.swift` lines 46–49
**Apply to:** `SubtaskRunner`
```swift
var environment = ProcessInfo.processInfo.environment
environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
process.environment = environment
```

### Process Lifecycle: Kill Process Group (NOT just direct child)
**Source:** `Exmen/Services/ScriptRunner.swift` line 54 (ScriptRunner uses `process.terminate()` — do NOT copy this; use group kill instead)
**Apply to:** `SubtaskRunner` timeout handler, `continuation.onTermination`
```swift
// Foundation.Process sets POSIX_SPAWN_SETPGROUP; child's PGID == child's PID
kill(-process.processIdentifier, SIGTERM)   // kills entire process group
Task {
    try? await Task.sleep(for: .seconds(5))
    kill(-process.processIdentifier, SIGKILL)
}
```

### TOMLDecoder Usage
**Source:** `Exmen/Services/ConfigLoader.swift` lines 67–68
**Apply to:** `SubtaskConfig.decodeInlineTable`
```swift
let decoder = TOMLDecoder()
return try decoder.decode(T.self, from: content)   // content is a String, not Data
```

### NSWindow: isReleasedWhenClosed = false
**Source:** `Exmen/Views/ServiceOutputWindow.swift` line 25
**Apply to:** `SubtaskProgressWindow`
```swift
window.isReleasedWhenClosed = false
// Without this, the NSWindow is deallocated when closed and can't be re-shown
```

### Status Dot Color Convention
**Source:** `Exmen/Models/ServiceState.swift` lines 13–19
**Apply to:** `SubtaskStatus.dotColor`, `SubtaskProgressView` row rendering
```swift
// green = running/succeeded, gray = stopped/pending/skipped, yellow = transitioning, red = failed/crashed
```

### ScriptConfig Reuse (inline/file)
**Source:** `Exmen/Models/ActionConfig.swift` lines 17–33
**Apply to:** `SubtaskConfig.script: ScriptConfig` field — embed directly, do not duplicate
```swift
// ScriptConfig.resolvedContent() handles both .inline (return content) and .file (read from path)
// SubtaskConfig.resolvedScript returns ScriptConfig; caller calls .resolvedContent() on it
```

---

## No Analog Found

All files have close analogs. No entries in this section.

---

## Metadata

**Analog search scope:** `Exmen/Models/`, `Exmen/Services/`, `Exmen/Views/`
**Files scanned:** 9 source files (8 analogs + 1 self-reference for ConfigLoader)
**Pattern extraction date:** 2026-06-05

---

## PATTERN MAPPING COMPLETE
