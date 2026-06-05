---
phase: 11
slug: subtask-orchestration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-05
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode test target) |
| **Config file** | none — Wave 0 adds `ExmenTests` target |
| **Quick run command** | `xcodebuild build -scheme Exmen -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -scheme Exmen -destination 'platform=macOS'` |
| **Estimated runtime** | ~60–120 seconds (cold build dominates) |

> **No test target exists today.** Confirmed by source scan — all current validation is manual. Wave 0 MUST add an `ExmenTests` target before any unit-testable task can be verified.

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme Exmen` (build green) + unit tests for the touched module
- **After every plan wave:** Run full `xcodebuild test` suite
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

> Task IDs are placeholders until plans are written; Plan/Wave columns are filled by the planner. Requirement + test-type mapping below is the contract the planner must satisfy.

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| ORCH-01 | `[[subtasks]]` parses into `[SubtaskConfig]`; `ScriptConfig` (inline/file) embeds correctly | unit | `xcodebuild test ... -only-testing:ExmenTests/SubtaskConfigTests` | ❌ W0 | ⬜ pending |
| ORCH-01 | Required `id` + command present; optional `name`/`timeout`/`depends_on` defaults applied | unit | same | ❌ W0 | ⬜ pending |
| ORCH-02 | Wave topo-sort produces correct waves; `depends_on` gates dependents | unit | `xcodebuild test ... -only-testing:ExmenTests/WaveSchedulerTests` | ❌ W0 | ⬜ pending |
| ORCH-02 | Cycle detection throws and names the cycle ids | unit | same | ❌ W0 | ⬜ pending |
| ORCH-03 | `SubtaskState` transitions pending→running→succeeded/failed/skipped | unit | `xcodebuild test ... -only-testing:ExmenTests/SubtaskStateTests` | ❌ W0 | ⬜ pending |
| ORCH-03 | `@Published` progress model emits updates live during a run | integration | `xcodebuild test ... -only-testing:ExmenTests/ProgressModelTests` | ❌ W0 | ⬜ pending |
| ORCH-04 | `EXMEN:subtask=<inline table>` decodes into `SubtaskConfig` via shared decode path | unit | `xcodebuild test ... -only-testing:ExmenTests/DynamicSpawnTests` | ❌ W0 | ⬜ pending |
| ORCH-04 | Duplicate id ignored idempotently + logged; unknown `depends_on` errors only that subtask | unit | same | ❌ W0 | ⬜ pending |
| ORCH-04 | `EXMEN:progress=N` clamped to 0–100; mapped to emitting child's subtask id | unit | same | ❌ W0 | ⬜ pending |
| ORCH-05 | Aggregated summary counts correct: `N succeeded / M failed / K skipped`; verdict failed if ≥1 failed | unit | `xcodebuild test ... -only-testing:ExmenTests/SummaryTests` | ❌ W0 | ⬜ pending |
| ORCH-05 | Dependents of a failed subtask marked `skipped` (cascades transitively); independent branches still run | unit | `xcodebuild test ... -only-testing:ExmenTests/CascadeSkipTests` | ❌ W0 | ⬜ pending |
| ORCH-06 | Concurrency cap honored (≤ cap simultaneously running) | integration | `xcodebuild test ... -only-testing:ExmenTests/ConcurrencyCapTests` | ❌ W0 | ⬜ pending |
| ORCH-06 | Per-subtask timeout fires; process dead after grace period | integration | `xcodebuild test ... -only-testing:ExmenTests/TimeoutTests` | ❌ W0 | ⬜ pending |
| ORCH-06 | Process-group kill terminates child-of-child processes (no zombies) | integration | manual — see Manual-Only below | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add `ExmenTests` XCTest target to the Xcode project depending on `Exmen` sources
- [ ] `Tests/ExmenTests/SubtaskConfigTests.swift` — ORCH-01 TOML decode (`[[subtasks]]` + embedded `ScriptConfig`)
- [ ] `Tests/ExmenTests/WaveSchedulerTests.swift` — ORCH-02 topo-sort + cycle detection
- [ ] `Tests/ExmenTests/SubtaskStateTests.swift` — ORCH-03 state machine
- [ ] `Tests/ExmenTests/DynamicSpawnTests.swift` — ORCH-04 inline-table decode, dup-id, progress clamp
- [ ] `Tests/ExmenTests/SummaryTests.swift` — ORCH-05 counts + verdict
- [ ] `Tests/ExmenTests/CascadeSkipTests.swift` — ORCH-05 cascade-skip semantics
- [ ] `Tests/ExmenTests/ConcurrencyCapTests.swift` — ORCH-06 cap honored
- [ ] `Tests/ExmenTests/TimeoutTests.swift` — ORCH-06 timeout + process death

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Process-group kill leaves no zombies | ORCH-06 | Requires live spawn of a parent that forks long-lived grandchildren; needs OS process inspection | Run an action whose subtask launches `sh -c 'sleep 300 & sleep 300'`; trigger timeout; confirm via `ps -o pid,ppid,pgid,stat` that no `sleep` survives and no `<defunct>` (zombie) entries remain |
| Live progress window updates | ORCH-03 | Visual/AppKit window behavior; survives menu close | Run a multi-subtask action; observe progress window shows colored dots, elapsed time, header % bar updating live, and survives closing the menu-bar menu |
| Aggregated popup + notification | ORCH-05 | OutputService popup/notification rendering | Run an action with a deliberate failure; confirm popup + notification show `N succeeded / M failed / K skipped` with error severity |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
