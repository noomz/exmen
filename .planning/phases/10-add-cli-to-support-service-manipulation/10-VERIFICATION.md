---
phase: 10-add-cli-to-support-service-manipulation
verified: 2026-03-20T07:05:00Z
status: human_needed
score: 7/7 must-haves verified
human_verification:
  - test: "Run exmen list-services with Exmen app running and a service configured"
    expected: "Prints service name, uptime/state text, and PID if running"
    why_human: "Requires live app + service TOML; socket IPC cannot be tested statically"
  - test: "Run exmen start-service <name> on a stopped service"
    expected: "Prints 'Service '<name>' started.' and service transitions to running"
    why_human: "Requires live app and a stopped service to verify state transition"
  - test: "Run exmen stop-service <name> on a running service"
    expected: "Prints 'Service '<name>' stopped.' and process terminates"
    why_human: "Requires live app and a running service"
  - test: "Run exmen restart-service <name>"
    expected: "Prints 'Service '<name>' restarted.' without error"
    why_human: "Requires live app"
  - test: "Run exmen service-status <name>"
    expected: "Prints Service, State, optional PID, Restart policy, Keep alive fields"
    why_human: "Requires live app"
  - test: "Run exmen start-service nonexistent-name"
    expected: "Prints 'Error: Service not found: nonexistent-name' to stderr, exits with code 1"
    why_human: "Requires live socket connection"
  - test: "Run exmen start-service <name> on an already-running service"
    expected: "Prints 'Error: Service '<name>' is already running' to stderr, exits with code 1"
    why_human: "Requires live app and a running service"
  - test: "Run exmen stop-service <name> on a stopped service"
    expected: "Prints 'Error: Service '<name>' is not running' to stderr, exits with code 1"
    why_human: "Requires live app and a stopped service"
---

# Phase 10: Add CLI to Support Service Manipulation — Verification Report

**Phase Goal:** Extend the exmen CLI tool with five new commands (list-services, start-service, stop-service, restart-service, service-status) to enable scripting and automation of managed services
**Verified:** 2026-03-20T07:05:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can list all registered services with state and uptime via CLI | VERIFIED | `case "list-services"` in CommandHandler.swift:144; `handleListServices(json:)` in main.swift:257; `listServices()` queries `ServiceManager.shared.services` and returns `ServiceInfo` array |
| 2 | User can start a stopped service by name via CLI | VERIFIED | `case "start-service"` in CommandHandler.swift:146; `handleStartService(name:)` in main.swift:302; `startService(name:)` calls `ServiceManager.shared.start(service)` at line 276 |
| 3 | User can stop a running service by name via CLI | VERIFIED | `case "stop-service"` in CommandHandler.swift:153; `handleStopService(name:)` in main.swift:322; `stopService(name:)` calls `ServiceManager.shared.stop(service)` at line 287 |
| 4 | User can restart a service by name via CLI | VERIFIED | `case "restart-service"` in CommandHandler.swift:157; `handleRestartService(name:)` in main.swift:342; `restartService(name:)` calls `ServiceManager.shared.restart(service)` at line 295 |
| 5 | User can get detailed status of a service by name via CLI | VERIFIED | `case "service-status"` in CommandHandler.swift:161; `handleServiceStatus(name:)` in main.swift:362; `getServiceStatus(name:)` returns `ServiceStatusInfo` with state, pid, statusText, restartPolicy, keepAlive |
| 6 | User gets a clear error when targeting a nonexistent service | VERIFIED | All four mutating handlers have `guard let service = findService(name: name) else { return Response(success: false, error: "Service not found: \(name)") }`; CLI handlers call `fputs("Error: ...")` and `exit(1)` |
| 7 | User gets a clear error when starting an already-running service or stopping an already-stopped one | VERIFIED | `startService`: `guard !service.state.isActive else { return Response(success: false, error: "Service '\(name)' is already running") }`; `stopService`: `guard service.state == .running || service.state == .starting else { return Response(success: false, error: "Service '\(name)' is not running") }` |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Exmen/Services/CommandHandler.swift` | Server-side handlers for all five service commands | VERIFIED | 314 lines; contains all five `case` branches, `ServiceInfo`, `ServiceStatusInfo`, `findService`, `listServices`, `startService`, `stopService`, `restartService`, `getServiceStatus`, `ServiceState.rawStringValue` extension |
| `exmen-cli/main.swift` | CLI handlers and command dispatch for all five new service commands | VERIFIED | 467 lines; contains all five handler functions, updated `printUsage()` with "Service Commands:" section, dispatch `switch` with all five `case` branches |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `exmen-cli/main.swift` | `Exmen/Services/CommandHandler.swift` | JSON over Unix domain socket | WIRED | CLI sends `["command": "list-services"]` etc via `SocketClient.send()`; `SocketServer.swift:168` routes all incoming data to `CommandHandler.shared.handle()` |
| `Exmen/Services/CommandHandler.swift` | `Exmen/Services/ServiceManager.swift` | `ServiceManager.shared` calls | WIRED | `ServiceManager.shared.services` (lines 252, 258), `ServiceManager.shared.start()` (line 276), `ServiceManager.shared.stop()` (line 287), `ServiceManager.shared.restart()` (line 295) all verified present |

---

### Requirements Coverage

No separate REQUIREMENTS.md exists in this project. Requirement IDs are referenced only in ROADMAP.md. The six IDs from the PLAN frontmatter map to verified behavior as follows:

| Requirement | Source Plan | Behavior | Status | Evidence |
|-------------|------------|----------|--------|----------|
| SVC-CLI-LIST | 10-01-PLAN.md | `list-services` command lists all services with state and uptime | SATISFIED | `case "list-services"` → `listServices()` → `ServiceManager.shared.services.map { ServiceInfo(...) }` |
| SVC-CLI-START | 10-01-PLAN.md | `start-service <name>` starts a stopped service | SATISFIED | `case "start-service"` → `startService(name:)` → `ServiceManager.shared.start(service)` |
| SVC-CLI-STOP | 10-01-PLAN.md | `stop-service <name>` stops a running service | SATISFIED | `case "stop-service"` → `stopService(name:)` → `ServiceManager.shared.stop(service)` |
| SVC-CLI-RESTART | 10-01-PLAN.md | `restart-service <name>` restarts any service | SATISFIED | `case "restart-service"` → `restartService(name:)` → `ServiceManager.shared.restart(service)` |
| SVC-CLI-STATUS | 10-01-PLAN.md | `service-status <name>` returns detailed status | SATISFIED | `case "service-status"` → `getServiceStatus(name:)` → `ServiceStatusInfo` with restartPolicy, keepAlive |
| SVC-CLI-ERR | 10-01-PLAN.md | Clear errors for not-found and invalid-state operations | SATISFIED | "Service not found: \(name)" in all four handlers; "already running" and "is not running" guards; CLI exits with code 1 on all error paths |

No orphaned requirements found — all six IDs are claimed by 10-01-PLAN.md and all have verified implementations.

---

### Anti-Patterns Found

No TODO/FIXME/placeholder comments found in either modified file. No empty implementations or stub return values. All handler functions make real socket calls and all server handlers interact with `ServiceManager.shared`.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

---

### Human Verification Required

#### 1. list-services end-to-end

**Test:** With Exmen app running and at least one service defined in TOML, run `exmen list-services`
**Expected:** Prints one line per service showing name, uptime/state text, and PID (if running). Run with `--json` flag and confirm raw JSON is emitted.
**Why human:** Requires live Unix domain socket at `~/.config/exmen/exmen.sock` and a configured service

#### 2. start-service on a stopped service

**Test:** Run `exmen start-service "<name>"` on a service currently in stopped state
**Expected:** Prints `Service '<name>' started.` — confirm the status dot in the menu bar turns green
**Why human:** State transition is visual and requires a live running service configuration

#### 3. stop-service on a running service

**Test:** Run `exmen stop-service "<name>"` on a service currently in running state
**Expected:** Prints `Service '<name>' stopped.` and the service process terminates (verify with `ps`)
**Why human:** Process lifecycle cannot be verified statically

#### 4. restart-service

**Test:** Run `exmen restart-service "<name>"` in any service state
**Expected:** Prints `Service '<name>' restarted.` — service PID changes to a new value
**Why human:** PID change verification requires live execution

#### 5. service-status output format

**Test:** Run `exmen service-status "<name>"` on a running service
**Expected:** Prints Service, State (with uptime), PID, Restart policy, and Keep alive fields in readable format
**Why human:** Output format correctness is a human judgment; field values require live data

#### 6. Error: nonexistent service

**Test:** Run `exmen start-service "does-not-exist"`
**Expected:** Output to stderr: `Error: Service not found: does-not-exist` — exit code 1 (verify with `echo $?`)
**Why human:** Requires live socket connection

#### 7. Error: already running

**Test:** Run `exmen start-service "<name>"` on a service already in running state
**Expected:** Output to stderr: `Error: Service '<name>' is already running` — exit code 1
**Why human:** Requires live app with a running service

#### 8. Error: not running

**Test:** Run `exmen stop-service "<name>"` on a service in stopped state
**Expected:** Output to stderr: `Error: Service '<name>' is not running` — exit code 1
**Why human:** Requires live app with a stopped service

---

### Gaps Summary

No gaps. All seven observable truths are verified by actual code. Both artifacts exist and are substantive (not stubs). Both key links are wired: the CLI sends correct JSON payloads over the socket, the socket server routes all data to `CommandHandler.shared.handle()`, and `CommandHandler` delegates to `ServiceManager.shared` for all state mutations.

The SUMMARY-reported commits (`d5e33d1`, `0905ac3`) exist in the repository and correspond to the expected changes.

The only remaining items are live integration tests that require the Exmen app to be running with a service configured — these cannot be verified statically.

---

_Verified: 2026-03-20T07:05:00Z_
_Verifier: Claude (gsd-verifier)_
