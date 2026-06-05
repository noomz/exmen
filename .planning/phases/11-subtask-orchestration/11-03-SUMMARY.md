---
phase: 11-subtask-orchestration
plan: "03"
subsystem: services
tags: [process, asyncstream, streaming, process-group, timeout, orch-06]
provides:
  - "SubtaskRunner: streaming Process runner returning AsyncStream<SubtaskIOEvent>"
  - "Concurrent stdout/stderr readabilityHandler drain (no pipe deadlock)"
  - "EXMEN: line classification as .hookLine events"
  - "Per-subtask timeout with process-group kill (kill(-pid) SIGTERM->SIGKILL), ORCH-06"
affects:
  - 11-05-orchestrator
key-files:
  created:
    - Exmen/Services/SubtaskRunner.swift
  modified:
    - Exmen.xcodeproj/project.pbxproj
---

## What shipped

`SubtaskRunner` — a streaming `Process` runner for the orchestration path (ORCH-06).
Spawns one process per subtask, drains stdout and stderr concurrently via
`FileHandle.readabilityHandler` into an `AsyncStream<SubtaskIOEvent>`, classifies
`EXMEN:`-prefixed stdout lines as `.hookLine`, enforces a per-subtask timeout, and
kills the child's entire process group (`kill(-pid, SIGTERM)` then `SIGKILL` after a
5s grace) on timeout or consumer cancellation so no zombie grandchildren survive.
`ScriptRunner` is untouched — the single-action path is unaffected.

## Key decisions / deviations

- **Event enum named `SubtaskIOEvent`** (not the plan's `SubtaskEvent`) to avoid a
  collision with the orchestrator's existing `SubtaskEvent` lifecycle enum (created
  during the Wave 1 overrun). No test referenced the IO enum, so the rename is free.
- **Belt-and-suspenders kill**: both `kill(-pid, …)` (process group, ORCH-06 goal)
  and `kill(pid, …)` (direct child) are sent, so timeout teardown is robust whether
  or not the child is a group leader. No `process.terminate()`.
- Residual stdout/stderr drained inside `terminationHandler` (SR-12080 workaround).

## Verification

- `xcodebuild build -scheme Exmen` green; `xcodebuild test` 84/84 green.
- Runner is additive; TimeoutTests (via the orchestrator, post-11-05) still pass.

## Self-Check: PASSED
