---
phase: 11-subtask-orchestration
plan: "06"
subsystem: views
tags: [nswindow, swiftui, progress-window, menu-wiring, notification, orch-03, orch-05]
provides:
  - "SubtaskProgressWindow: standalone NSWindow + SwiftUI list bound to the orchestrator (D-09)"
  - "Live status dot + name + elapsed + spinner + opt-in per-subtask bar (D-10/D-12)"
  - "Overall completed/total % header (D-11)"
  - "MenuContentView orchestration branch + aggregated popup/notification summary (ORCH-05/D-15)"
  - "Action.subtasks passthrough (D-01)"
key-files:
  created:
    - Exmen/Views/SubtaskProgressWindow.swift
  modified:
    - Exmen/Views/MenuContentView.swift
    - Exmen/Models/Action.swift
    - Exmen/Services/SubtaskOrchestrator.swift
    - Exmen.xcodeproj/project.pbxproj
---

## What shipped

`SubtaskProgressWindow` — a standalone `NSWindowController` (`isReleasedWhenClosed =
false`, retained via a static `current`, cleared in `windowWillClose`) hosting
`SubtaskProgressView`, a SwiftUI list bound via `@ObservedObject` to
`SubtaskOrchestrator`. Header shows the overall % bar + completed/total (D-11); each
row renders a Phase-8-convention status dot (D-10), name, live elapsed (1s ticker),
a running spinner, and a determinate bar only when `progressPercent` is set (D-12).

`MenuContentView.executeAction` now branches: actions declaring `[[subtasks]]` (D-01)
open the window, run `SubtaskOrchestrator.shared`, and on completion deliver the
aggregated `OrchestrationSummary` as a popup + macOS notification with error severity
on any failure (ORCH-05/D-15). The single-action `ScriptRunner` path is unchanged.

## Verification

- `xcodebuild build` green; `xcodebuild test` 84/84 green.
- **Pending human-verify (Task 3, blocking)**: visual window behavior, popup +
  notification summary, and zombie-free teardown on timeout — the manual-only
  ORCH-03/05/06 verifications per 11-VALIDATION.md.

## Self-Check: PASSED (automated); human-verify checkpoint OPEN
