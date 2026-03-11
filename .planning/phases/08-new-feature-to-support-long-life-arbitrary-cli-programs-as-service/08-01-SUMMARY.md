---
phase: 08-long-running-cli-services
plan: 01
subsystem: models-and-foundation
tags: [swift, spm, data-models, service-lifecycle, swiftterm]
dependency_graph:
  requires: []
  provides: [ActionType, RestartPolicy, ServiceConfig, ServiceState, ManagedService-skeleton, SwiftTerm-dependency]
  affects: [ActionConfig, Action, Exmen.xcodeproj/project.pbxproj, Package.swift]
tech_stack:
  added: [SwiftTerm 1.11.2]
  patterns: [ObservableObject-skeleton, optional-discriminator-field, resolved-computed-properties]
key_files:
  created:
    - Exmen/Models/ServiceConfig.swift
    - Exmen/Models/ServiceState.swift
    - Exmen/Services/ManagedService.swift
  modified:
    - Exmen/Models/ActionConfig.swift
    - Exmen/Models/Action.swift
    - Exmen.xcodeproj/project.pbxproj
    - Package.swift
decisions:
  - "SwiftTerm 1.11.2 added as SPM dependency (preferred over libghostty which lacks embeddable C API)"
  - "ActionConfig.script made optional for service backward compatibility (services use [service].command)"
  - "RestartPolicy uses String raw values matching TOML spec (on-failure with hyphen)"
  - "ManagedService deliberately minimal — Plan 02 adds PTY/SwiftTerm integration"
metrics:
  duration: "~5 minutes"
  completed: "2026-03-11"
  tasks_completed: 2
  files_created: 3
  files_modified: 4
---

# Phase 8 Plan 1: Service Foundation Models Summary

SwiftTerm 1.11.2 SPM dependency added; ActionType/RestartPolicy/ServiceConfig/ServiceState types created; ActionConfig and Action extended for service support; ManagedService ObservableObject skeleton established for Plan 02 to build against.

## What Was Built

### Task 1: SwiftTerm SPM dependency + service type contracts

Added SwiftTerm 1.11.2 as a dependency in `Package.swift` and `Exmen.xcodeproj/project.pbxproj`. Created two new model files:

**`Exmen/Models/ServiceConfig.swift`** provides:
- `enum ActionType: String, Codable` — `action` (default) and `service`
- `enum RestartPolicy: String, Codable` — `never`, `on-failure`, `always` (raw values match TOML spec exactly)
- `struct ServiceConfig: Codable` — `command`, `args`, `restart`, `max_restarts`, `keep_alive`, `working_dir`, `env` fields with resolved computed properties
- `resolvedEnvironment` merges parent process env + Homebrew PATH + `TERM=xterm-256color` + service-specific vars

**`Exmen/Models/ServiceState.swift`** provides:
- `enum ServiceState: Equatable` — `stopped`, `starting`, `running`, `restarting`, `crashed`
- `dotColor: Color` — green/gray/yellow/red for each state
- `isActive: Bool` — true for running, starting, restarting
- `static func displayText(state:startedAt:)` — formats "running - uptime 2h 15m" using `DateComponentsFormatter`

### Task 2: ActionConfig/Action extension + ManagedService skeleton

**`ActionConfig.swift`** changes:
- `script: ScriptConfig` made optional (`script: ScriptConfig?`) — services use `[service].command` instead
- Added `type: ActionType?` and `service: ServiceConfig?` fields
- Added `resolvedType: ActionType` (nil defaults to `.action`) and `isService: Bool` computed properties
- All existing action TOMLs remain fully backward compatible (missing `type` and `service` fields decode as nil)

**`Action.swift`** changes:
- Added `serviceConfig: ServiceConfig?` and `isService: Bool` properties
- `init(from config: ActionConfig)` populates new fields from config
- Memberwise init includes `serviceConfig: ServiceConfig? = nil, isService: Bool = false` defaults

**`ManagedService.swift`** — deliberate skeleton:
- `@MainActor class ManagedService: ObservableObject, Identifiable`
- `@Published var state: ServiceState`, `@Published var pid: Int32?`, `@Published var startedAt: Date?`
- `var restartCount = 0` — Plan 02 increments this during restart logic
- No SwiftTerm import yet — Plan 02 adds PTY integration

## Verification

Build output: `** BUILD SUCCEEDED **` with zero errors. Pre-existing warnings in ScriptRunner.swift (Swift 6 concurrency) and CommandHandler.swift (nil coalescing) are out of scope and pre-date this plan.

## Deviations from Plan

None — plan executed exactly as written.

## Decisions Made

1. **SwiftTerm in Package.swift**: Both `Package.swift` and `Exmen.xcodeproj/project.pbxproj` needed updating since the project uses both (Xcode uses the pbxproj, CLI builds use Package.swift). Both kept in sync.

2. **RestartPolicy raw values**: Used `case onFailure = "on-failure"` directly as the raw value rather than custom CodingKeys — Swift `RawRepresentable` conformance for `Codable` enums uses the raw value for encoding/decoding, which handles the hyphen correctly without additional boilerplate.

3. **ManagedService imports**: Only `Foundation` and `SwiftUI` — `SwiftTerm` import deferred to Plan 02 per spec to keep this plan's scope clean.

## Self-Check

Files created:
- Exmen/Models/ServiceConfig.swift: FOUND
- Exmen/Models/ServiceState.swift: FOUND
- Exmen/Services/ManagedService.swift: FOUND

Commits:
- a073064: feat(08-01): add SwiftTerm SPM dependency and service type contracts — FOUND
- ffe265a: feat(08-01): extend ActionConfig/Action for services and add ManagedService skeleton — FOUND

## Self-Check: PASSED
