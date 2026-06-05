---
phase: 11-subtask-orchestration
plan: "05"
subsystem: services
tags: [orchestrator, asyncstream, dynamic-spawn, progress, cascade-skip, orch-03, orch-04, orch-06]
provides:
  - "SubtaskOrchestrator wired to SubtaskRunner stream (real process-group kill, ORCH-06)"
  - "Live per-subtask streaming + @Published state (ORCH-03)"
  - "Runtime dynamic subtask spawn via HookParser.parseLine (ORCH-04, D-05/D-08)"
  - "Opt-in per-subtask progress from EXMEN:progress= (D-12)"
  - "SubtaskOrchestrator.shared singleton for the UI"
affects:
  - 11-06-progress-window
key-files:
  modified:
    - Exmen/Services/SubtaskOrchestrator.swift
---

## What shipped

Replaced the orchestrator's inline poll/`terminate` `runScript` stub with
`SubtaskRunner` stream consumption. `executeSubtask` now `for await`s
`SubtaskIOEvent`s: `.exited`/`.timedOut`/`.launchFailed` set the terminal status,
and `.hookLine` is dispatched through `HookParser.parseLine` →
`.progress` updates the per-subtask bar (D-12), `.subtask` spawns a new subtask at
runtime (ORCH-04, D-05) with idempotent dup-id handling (D-08) and the
`maxSubtaskCount` cap. The existing wave topo-sort (ORCH-02), seed-and-drain
concurrency cap, cascade-skip (D-13/D-14), and `OrchestrationSummary` (ORCH-05) are
preserved. Added `summaryLine`/`verdictFailed` aliases and a `shared` singleton.

## Key decisions / deviations

- Timeout maps to `.failed(exitCode: 124)` (conventional timeout code); TimeoutTests
  assert `.failed(_)` so this passes and the process is dead via the runner's
  process-group kill.
- **v1 limitation**: dynamically-spawned subtasks run inline under their parent —
  outside the wave concurrency cap and without dependency ordering. Documented in code.

## Verification

- `xcodebuild test` 84/84 green — ConcurrencyCap (started/finished cap), Timeout
  (terminal + dead process), ProgressModel, CascadeSkip, Summary all pass against
  the rewired engine.

## Self-Check: PASSED
