---
phase: 11-subtask-orchestration
plan: "04"
subsystem: services
tags: [hookparser, streaming, parseLine, progress, dynamic-spawn, orch-04]
provides:
  - "HookParser.parseLine(_:) streaming single-line entry point"
  - "HookLineEvent enum: subtask / progress / invalidProgress / legacyHook / unknown"
  - "EXMEN:subtask= raw inline-table passthrough; EXMEN:progress=N validation"
affects:
  - 11-05-orchestrator
key-files:
  created:
    - Exmen/Services/HookLineEvent.swift
  modified: []
---

## What shipped

`HookParser.parseLine(_:)` (static, in `HookLineEvent.swift` as a `HookParser`
extension) parsing a single line into a typed `HookLineEvent`: `.subtask(rawValue:)`
passes the raw inline table verbatim to `SubtaskConfig.decodeInlineTable` (D-06),
`.progress(Int)` for 0–100, `.legacyHook` for title/status/badge/icon, `.unknown`
otherwise, and `nil` for non-`EXMEN:` lines. The batch `parse(_:)` single-action
path is untouched.

## Key decisions / deviations

- **Implemented during the Wave 1 executor overrun** (committed under 11-02), then
  integrated onto main during accept-and-integrate recovery.
- **Out-of-range progress → `.invalidProgress`, not clamp.** The plan prose (D-12/A4)
  said "clamp," but the committed `DynamicSpawnTests` (lines 81–91) assert that
  `progress=150` / `-5` are NOT `.progress`. The committed test contract is the
  source of truth, so reject-not-clamp stands. The orchestrator ignores
  `.invalidProgress` (leaves the bar at its last value).
- **Location**: lives in `HookLineEvent.swift` (extension), not inside
  `HookParser.swift` as the plan suggested — functionally equivalent, same `@testable` API.

## Verification

- `xcodebuild test -only-testing:ExmenTests/DynamicSpawnTests` green (both subtask forms,
  progress clamp-range assertions, legacy/nil cases).

## Self-Check: PASSED
