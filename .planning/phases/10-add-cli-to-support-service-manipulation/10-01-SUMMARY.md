---
phase: 10-add-cli-to-support-service-manipulation
plan: "01"
subsystem: cli-ipc
tags: [cli, services, ipc, socket, command-handler]
dependency_graph:
  requires:
    - "Phase 6: IPC Unix domain socket and JSON protocol"
    - "Phase 8: ManagedService, ServiceManager, ServiceState infrastructure"
  provides:
    - "CLI commands: list-services, start-service, stop-service, restart-service, service-status"
    - "Server-side routing for all five service commands via CommandHandler"
  affects:
    - "exmen-cli binary (standalone compile)"
    - "Exmen.app IPC command surface"
tech_stack:
  added: []
  patterns:
    - "ServiceState.rawStringValue extension for JSON serialization"
    - "ResponseData enum disambiguation via ordered decode attempts"
    - "Codable structs (ServiceInfo, ServiceStatusInfo) for typed IPC responses"
key_files:
  created: []
  modified:
    - "Exmen/Services/CommandHandler.swift"
    - "exmen-cli/main.swift"
decisions:
  - "ResponseData decode order: ServiceStatusInfo before ActionStatus (unique restartPolicy key prevents ambiguity); [ServiceInfo] before [ActionInfo] (pid field distinguishes them)"
  - "ServiceState.rawStringValue added as extension outside CommandHandler to keep enum definition in Models/ clean"
  - "startService guard uses !service.state.isActive (covers running+starting+restarting); stopService uses explicit .running || .starting check matching ManagedService.stop() guard"
metrics:
  duration: "8 minutes"
  completed: "2026-03-20T06:33:43Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 10 Plan 01: CLI Service Manipulation Commands Summary

Five new CLI commands wired end-to-end: list-services, start-service, stop-service, restart-service, and service-status, using the existing Unix socket/JSON IPC path.

## What Was Built

### Task 1: Server-side command handlers (CommandHandler.swift)

- `ServiceState.rawStringValue` extension — serializes enum to lowercase string for JSON responses
- `ServiceInfo` struct — name, state, pid, statusText for list output
- `ServiceStatusInfo` struct — adds restartPolicy and keepAlive for detailed status
- `ResponseData` extended with `.services([ServiceInfo])` and `.serviceStatus(ServiceStatusInfo)` cases
- `encode(to:)` and `init(from:)` updated with correct disambiguation order
- `handleCommand` switch extended with five new cases
- `findService(name:)` helper — case-insensitive lookup via `ServiceManager.shared.services`
- Five private handler methods: `listServices()`, `startService(name:)`, `stopService(name:)`, `restartService(name:)`, `getServiceStatus(name:)`

### Task 2: CLI client commands (exmen-cli/main.swift)

- `printUsage()` updated with "Service Commands:" section and new examples
- Five handler functions: `handleListServices(json:)`, `handleStartService(name:)`, `handleStopService(name:)`, `handleRestartService(name:)`, `handleServiceStatus(name:)`
- `handleListServices` supports `--json` flag (raw JSON output) and human-readable list with optional PID display
- `handleServiceStatus` prints service name, state/uptime, PID (if running), restart policy, keep-alive flag
- Command dispatch switch extended with five new cases

## Error Handling

| Scenario | Error |
|---|---|
| Service name not found | "Service not found: \(name)" |
| start-service on active service | "Service '\(name)' is already running" |
| stop-service on inactive service | "Service '\(name)' is not running" |
| restart-service — no guard | always succeeds (restart handles all states) |
| Missing name parameter | "Missing 'name' parameter" |

## Deviations from Plan

None — plan executed exactly as written.

## Verification

- `xcodebuild -scheme Exmen -configuration Release build` — BUILD SUCCEEDED
- `swiftc -O -o .build/exmen exmen-cli/main.swift` — compiled without errors
- `.build/exmen --help` — shows "Service Commands:" section with all five commands

## Commits

- `d5e33d1` — feat(10-01): add service command handlers to CommandHandler.swift
- `0905ac3` — feat(10-01): add service commands to CLI client (exmen-cli/main.swift)

## Self-Check: PASSED
