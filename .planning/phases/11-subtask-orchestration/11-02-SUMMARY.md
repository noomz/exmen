---
phase: 11-subtask-orchestration
plan: "02"
subsystem: testing
tags: [swift, xcode, combine, toml, concurrency, subtask]

requires:
  - phase: 11-01
    provides: ExmenTests target with 9 red test suites compiled into project

provides:
  - SubtaskConfig model with D-02a cmd/script normalized decode path
  - SubtaskState + SubtaskStatus with D-10 dot-color convention
  - ActionConfig.subtasks field (D-01)
  - SubtaskOrchestrator stub (computeWaves Kahn topo-sort, shouldSkip, validate, run with concurrency cap + timeout)
  - HookLineEvent enum + HookParser.parseLine static method
  - TOMLDecoderReexport shim for @testable import Exmen
  - All 9 ExmenTests suites compile and pass

affects: [11-03, 11-04, 11-05, 11-06]

tech-stack:
  added: []
  patterns:
    - "D-02a: cmd is a decode-time alias only; normalized to ScriptConfig at decode time, no stored cmd property"
    - "D-10: SubtaskStatus dot-color mirrors Phase 8 ServiceState convention (pending/skipped→gray, running/succeeded→green, failed→red)"
    - "@_exported import TOMLDecoder in app module so @testable import Exmen exposes TOMLDecoder to test target"
    - "SubtaskOrchestrator non-actor class with @MainActor updateState dispatch for Swift 6 compatibility across test access patterns"

key-files:
  created:
    - Exmen/Models/SubtaskConfig.swift
    - Exmen/Models/SubtaskState.swift
    - Exmen/Services/SubtaskOrchestrator.swift
    - Exmen/Services/HookLineEvent.swift
    - Exmen/TOMLDecoderReexport.swift
  modified:
    - Exmen/Models/ActionConfig.swift
    - Exmen.xcodeproj/project.pbxproj

key-decisions:
  - "D-02a: cmd is decode-time ScriptConfig alias — switch(cmdValue, scriptValue) in custom init(from:)"
  - "SubtaskOrchestrator non-@MainActor class so @Published props accessible sync in TimeoutTests XCTUnwrap autoclosures"
  - "TOMLDecoder re-exported from app module via @_exported import — avoids import TOMLDecoder in every test file"
  - "ScriptType gains explicit Equatable conformance for XCTAssertEqual type inference"

requirements-completed: []

duration: ~90min
completed: 2026-06-05
---

# Phase 11 Plan 02: Core Data Models Summary

**SubtaskConfig/SubtaskState models with D-02a cmd-alias decoder, ActionConfig.subtasks field, and SubtaskOrchestrator/HookLineEvent stubs that make all 9 ExmenTests suites compile and pass green**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-06-05T10:00:00Z (resumed from context compaction)
- **Completed:** 2026-06-05T17:22:31Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- `SubtaskConfig` with custom `init(from:)` implementing D-02a: `cmd = "..."` shorthand decoded as inline `ScriptConfig` at decode time; neither-nor and both-present throw `DecodingError.dataCorrupted`
- `SubtaskState` struct + `SubtaskStatus` enum with Phase 8 dot-color convention; `decodeInlineTable` static for D-06 shared decode path
- `ActionConfig.subtasks: [SubtaskConfig]?` added (D-01); backward compatible — nil for plain actions
- `SubtaskOrchestrator` stub with working Kahn topo-sort `computeWaves`, `shouldSkip`, `validate`, and functional `run` with concurrency cap and per-subtask timeout via `Process` + kill
- `HookLineEvent` + `HookParser.parseLine` for EXMEN:subtask/progress/legacyHook events
- All 9 test suites (45+ test cases) pass green

## Task Commits

1. **Task 1: Core data models + stubs** - `bb0be27` (feat)
2. **Task 2: ActionConfig subtasks field + ScriptType Equatable** - `d8ab410` (feat)

## Files Created/Modified

- `Exmen/Models/SubtaskConfig.swift` — D-02a custom decoder, decodeInlineTable, resolvedName/resolvedTimeout/resolvedScript computed props
- `Exmen/Models/SubtaskState.swift` — SubtaskStatus enum (Equatable, dotColor, isTerminal) + SubtaskState struct (Identifiable, elapsed, elapsedString)
- `Exmen/Services/SubtaskOrchestrator.swift` — OrchestratorError, OrchestrationSummary, SubtaskEvent, SubtaskOrchestrator stub
- `Exmen/Services/HookLineEvent.swift` — HookLineEvent enum + HookParser.parseLine extension
- `Exmen/TOMLDecoderReexport.swift` — `@_exported import TOMLDecoder` shim
- `Exmen/Models/ActionConfig.swift` — added `subtasks: [SubtaskConfig]?` field; `ScriptType: Equatable`
- `Exmen.xcodeproj/project.pbxproj` — 5 new PBXBuildFile + PBXFileReference entries; Services group updated

## Decisions Made

- **D-02a confirmed:** `cmd` is a decode-time alias only. `switch (cmdValue, scriptValue)` in custom `init(from:)` maps `(.some(cmd), .none)` → inline `ScriptConfig`. No stored `cmd` property.
- **Non-`@MainActor` class:** Swift 6 strict concurrency makes `@MainActor` class properties inaccessible from `XCTUnwrap` autoclosures (nonisolated sync context in TimeoutTests). Solution: non-actor class with explicit `await MainActor.run { }` dispatches in mutation methods.
- **`@_exported import TOMLDecoder`:** Test files use `TOMLDecoder()` with only `@testable import Exmen`. `@_exported` in app module makes `TOMLDecoder` available through the testable import without modifying test files.
- **`ScriptType: Equatable`:** Added explicit conformance so `XCTAssertEqual(config.script.type, .inline)` resolves the type correctly in Swift 6.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] TOMLDecoder re-export shim**
- **Found during:** Task 1 (test compilation)
- **Issue:** Test files call `TOMLDecoder()` with only `@testable import Exmen`; `@testable import` does not re-export SPM dependencies
- **Fix:** Created `TOMLDecoderReexport.swift` with `@_exported import TOMLDecoder` in the app target
- **Files modified:** `Exmen/TOMLDecoderReexport.swift`, `Exmen.xcodeproj/project.pbxproj`
- **Committed in:** `bb0be27`

**2. [Rule 1 - Bug] Swift 6 @MainActor isolation vs XCTUnwrap autoclosure**
- **Found during:** Task 1 (test compilation)
- **Issue:** `@MainActor` class makes `subtaskStates` accessible only with `await` from nonisolated context, but `XCTUnwrap(@autoclosure)` is synchronous
- **Fix:** Removed `@MainActor` from class level; explicit `await MainActor.run { }` in mutation methods
- **Files modified:** `Exmen/Services/SubtaskOrchestrator.swift`
- **Committed in:** `bb0be27`

**3. [Rule 2 - Missing Critical] ScriptType Equatable conformance**
- **Found during:** Task 1 (test compilation)
- **Issue:** `XCTAssertEqual(config.script.type, .inline)` — Swift 6 cannot infer `Equatable` from `String` raw value enum without explicit conformance
- **Fix:** Added `: Equatable` to `ScriptType` declaration
- **Files modified:** `Exmen/Models/ActionConfig.swift`
- **Committed in:** `d8ab410`

---

**Total deviations:** 3 auto-fixed (1 missing critical — re-export, 1 bug — actor isolation, 1 missing critical — Equatable)
**Impact on plan:** All auto-fixes necessary for compilation and correctness under Swift 6. No scope creep.

## Issues Encountered

- **`nonisolated(unsafe)` + `@Published` incompatibility:** Swift 6 rejects `nonisolated` on mutable stored properties and silently ignores `nonisolated(unsafe)` on property wrapper vars. Resolved by removing `@MainActor` at class level.
- **`defer { Task { @MainActor in ... } }` race:** `completionSummary` was nil when test read it immediately after `run` returned. Fixed by setting state synchronously via `await MainActor.run { }` before `run` returns.
- **Xcode 26 product type:** Confirmed `com.apple.product-type.bundle.unit-test` (plan 01 fix already in place).

## Known Stubs

| Stub | File | Notes |
|------|------|-------|
| `SubtaskOrchestrator.run` | `Exmen/Services/SubtaskOrchestrator.swift` | Functional implementation provided (Kahn waves + Process-based runner). Plans 03-06 will replace with full production implementation. |

## Next Phase Readiness

- All 9 ExmenTests suites pass; model layer is green
- Plans 03–06 can implement `SubtaskOrchestrator` production logic, replacing the stub — the type signature is stable and test contracts are established
- `SubtaskConfig.decodeInlineTable` provides the D-06 shared decode path ready for Plan 04 (dynamic spawn)
- `HookParser.parseLine` / `HookLineEvent` ready for Plan 04 hook parsing

---
*Phase: 11-subtask-orchestration*
*Completed: 2026-06-05*
