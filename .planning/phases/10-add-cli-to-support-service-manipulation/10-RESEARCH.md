# Phase 10: Add CLI to Support Service Manipulation - Research

**Researched:** 2026-03-20
**Domain:** Swift CLI + Unix domain socket IPC, macOS menu bar app extension
**Confidence:** HIGH

## Summary

Phase 10 extends the existing IPC system to expose service lifecycle operations over the CLI. The current `exmen` CLI tool (`exmen-cli/main.swift`) and `CommandHandler.swift` only handle three commands: `list-actions`, `run`, and `status`. Managed services — implemented fully in Phase 8 — have no CLI surface at all. They are exclusively controllable from the GUI context menu.

The work is a symmetric extension of what was already built. The pattern is crystal clear: `CommandHandler.swift` in the Exmen app daemon handles routing; `exmen-cli/main.swift` is the thin client that serializes JSON requests and prints formatted responses. Every new service command follows the exact same path: add a case to the `switch` in `CommandHandler.handleCommand`, add a handler function, extend `ResponseData` enum if new data shapes are needed, and add a corresponding case to the CLI's `main.swift`.

The primary technical consideration is that service operations (start/stop/restart) are fire-and-control — they do not wait for a result the way `run` waits for script output. The response only needs to confirm the command was dispatched. `service-status` returns the current `ServiceState` and uptime string. `list-services` returns a list of service info structs.

**Primary recommendation:** Add five new commands to `CommandHandler` and five corresponding handlers to `exmen-cli/main.swift`, following the exact existing pattern. No new dependencies, no architectural changes.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift stdlib | macOS 13+ | Language runtime | Already in project |
| Foundation | macOS 13+ | Darwin socket APIs, JSON | Already used by both sides |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ServiceManager.shared | N/A (project code) | Service lifecycle dispatch | Server side — all start/stop/restart commands route through this |
| ManagedService | N/A (project code) | State and PID access | Reading `state`, `startedAt`, `pid` for service-status response |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON protocol (current) | Plain text | JSON already in place; no reason to diverge |
| Separate ResponseData cases | Reuse existing `.output(String)` | Need structured service info — a new `.services([ServiceInfo])` and `.serviceStatus(ServiceStatusInfo)` are cleaner than encoding structs as freeform strings |

**Build command (CLI only, no new dependencies):**
```bash
swiftc -O -o .build/exmen exmen-cli/main.swift
```

## Architecture Patterns

### Existing Project Structure (relevant files)
```
Exmen/
├── Services/
│   ├── CommandHandler.swift   # IPC command router (server-side, @MainActor)
│   ├── SocketServer.swift     # Unix domain socket accept/read/write loop
│   ├── ServiceManager.swift   # start/stop/restart dispatch, services array
│   └── ManagedService.swift   # per-service state machine, PID, startedAt
├── Models/
│   ├── ServiceState.swift     # stopped/starting/running/restarting/crashed
│   └── ServiceConfig.swift    # RestartPolicy, ServiceConfig struct
exmen-cli/
└── main.swift                 # Thin CLI client (Darwin sockets + JSON)
```

### Pattern 1: Command Handler Extension (server-side)
**What:** Add new cases to the existing `switch request.command` in `CommandHandler.handleCommand`, each calling a private handler method.
**When to use:** All new service commands follow this pattern identically.
**Example (based on existing code):**
```swift
// In CommandHandler.handleCommand(_ request: Request) -> Response
case "list-services":
    return listServices()
case "start-service":
    guard let name = request.name else {
        return Response(success: false, error: "Missing 'name' parameter")
    }
    return startService(name: name)
case "stop-service":
    guard let name = request.name else {
        return Response(success: false, error: "Missing 'name' parameter")
    }
    return stopService(name: name)
case "restart-service":
    guard let name = request.name else {
        return Response(success: false, error: "Missing 'name' parameter")
    }
    return restartService(name: name)
case "service-status":
    guard let name = request.name else {
        return Response(success: false, error: "Missing 'name' parameter")
    }
    return getServiceStatus(name: name)
```

### Pattern 2: ResponseData Enum Extension (server-side)
**What:** Add new associated value cases to the `ResponseData` enum so the server can encode service-specific structs.
**When to use:** `list-services` returns an array of `ServiceInfo`; `service-status` returns a `ServiceStatusInfo`.

```swift
// New structs to add to CommandHandler
struct ServiceInfo: Codable {
    let name: String
    let state: String        // ServiceState raw string
    let pid: Int32?
    let statusText: String   // ServiceState.displayText(state:startedAt:)
}

struct ServiceStatusInfo: Codable {
    let name: String
    let state: String
    let pid: Int32?
    let statusText: String
    let restartPolicy: String // from ServiceConfig.resolvedRestart.rawValue
    let keepAlive: Bool
}

// Extend ResponseData enum
enum ResponseData: Codable {
    case actions([ActionInfo])
    case output(String)
    case status(ActionStatus)
    case services([ServiceInfo])         // NEW
    case serviceStatus(ServiceStatusInfo) // NEW
    ...
}
```

**Important:** The `ResponseData` enum uses a custom `encode(to:)` and `init(from:)` that tries decoding each variant in order. Adding new cases means adding them to both encode and decode. Order in decode matters — place more specific types (objects with distinctive keys) before generic arrays.

### Pattern 3: CLI Handler Functions (client-side)
**What:** Each new command gets a `handleXxx()` function in `exmen-cli/main.swift`, following the same structure as `handleListActions`, `handleRun`, `handleStatus`.
**When to use:** All five new commands.

```swift
// Example: handleStartService
func handleStartService(name: String) {
    let client = SocketClient()
    let result = client.send(["command": "start-service", "name": name])
    switch result {
    case .success(let response):
        guard let success = response["success"] as? Bool, success else {
            if let error = response["error"] as? String {
                fputs("Error: \(error)\n", stderr)
            }
            exit(1)
        }
        print("Service '\(name)' started.")
    case .failure(let error):
        fputs("Error: \(error.message)\n", stderr)
        exit(1)
    }
}
```

### Pattern 4: Fire-and-Control vs. Fire-and-Wait
**What:** `start-service`, `stop-service`, `restart-service` dispatch the operation then immediately return a success/error. They do NOT block waiting for the service to reach a steady state.
**Why:** The operations involve async state machines (PTY setup, SIGTERM/SIGKILL timeouts, exponential backoff). Blocking the socket call would require a semaphore wait that could time out. The GUI uses the same fire-and-return approach.
**Implication:** Response for start/stop/restart is simply `{"success": true}` or `{"success": false, "error": "..."}`. No state data is returned; the caller can follow up with `service-status` if needed.

### Anti-Patterns to Avoid
- **Duplicating the SocketClient code:** `exmen-cli/main.swift` already has `SocketClient` — add new handlers in the same file, do not create a second socket wrapper.
- **Blocking start/stop in the socket handler:** `start()`, `stop()`, `restart()` on `ManagedService` are synchronous @MainActor methods that return immediately and let state transitions happen asynchronously. Do not wrap them in a semaphore wait.
- **Encoding ServiceState directly:** `ServiceState` is not `Codable` (it's a SwiftUI-dependent enum). Convert to a `String` (e.g., `"\(service.state)"` or a simple switch) before serializing.
- **Attempting to open the output window from CLI:** `showOutput(for:)` calls `NSApp.activate` — it requires AppKit and will not work from the socket response path. `service-status` can report whether a window is open via a flag if desired, but opening it from CLI is out of scope.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Service lookup by name | Custom lookup logic | Extend `findAction(name:)` pattern already in CommandHandler | Pattern is case-insensitive, already proven |
| State serialization | Custom state string encoding | Simple `switch service.state { case .running: return "running" ... }` or interpolation | ServiceState is not Codable; a small helper method is all that's needed |
| Socket communication | New socket library | Existing `SocketClient` in exmen-cli/main.swift | Darwin APIs already abstracted |
| Command routing | New dispatcher | Extend `handleCommand(_ request:)` switch in CommandHandler | Consistent with all existing commands |

**Key insight:** This phase is purely additive. Both files (`CommandHandler.swift` and `exmen-cli/main.swift`) have clear extension points with no refactoring required.

## Common Pitfalls

### Pitfall 1: ServiceState is not Codable
**What goes wrong:** Attempting to directly encode `ServiceState` in a `Codable` struct fails — `ServiceState` imports SwiftUI (for `Color`) and is not a `Codable` type.
**Why it happens:** Phase 8 designed `ServiceState` as a view-model enum, not a data transfer type.
**How to avoid:** Convert to `String` before encoding. Use `ServiceState.displayText(state:startedAt:)` for the human-readable status and a raw string (`"running"`, `"stopped"`, etc.) for the machine-readable state field.
**Warning signs:** Compiler error "Type 'ServiceState' does not conform to protocol 'Encodable'".

### Pitfall 2: ResponseData Decode Order
**What goes wrong:** If `services([ServiceInfo])` is placed before `actions([ActionInfo])` in the decode try-sequence, and both are arrays of dicts, the decoder may successfully decode `services` as `actions` or vice versa.
**Why it happens:** The existing `ResponseData.init(from:)` uses sequential `try?` attempts without discriminator fields.
**How to avoid:** Add `ServiceInfo` and `ActionInfo` with at least one distinct key (e.g., `ServiceInfo` has `state` and `pid`; `ActionInfo` has `icon` and `description`). Place the more specific decode attempt first, or use a wrapper with a type discriminator field.
**Recommended approach:** Give each new Codable struct at least one unique required field that won't be present in the others, so the decoder can disambiguate.

### Pitfall 3: @MainActor Dispatch for Service Operations
**What goes wrong:** `ServiceManager.start/stop/restart` are @MainActor methods. Calling them from a background queue (where `handleClient` in SocketServer runs) without `DispatchQueue.main.async` will trigger a concurrency warning or crash.
**Why it happens:** `SocketServer.handleClient` runs on a background DispatchQueue; `CommandHandler.handle` is called via `DispatchQueue.main.async` with a semaphore (see `SocketServer.swift` lines 162–173). This is already handled for existing commands — service commands automatically benefit from the same dispatch.
**How to avoid:** No extra work needed — the existing `DispatchQueue.main.async { result = CommandHandler.shared.handle(requestData); semaphore.signal() }` in `SocketServer.handleClient` means all CommandHandler code already runs on MainActor.

### Pitfall 4: Service Not Found vs. Operation Not Applicable
**What goes wrong:** Returning a generic "Service not found" error when the service exists but is already in the target state (e.g., `start-service` on a running service) gives a confusing error.
**Why it happens:** `ManagedService.start()` has a guard: `guard state != .running && state != .starting else { return }`. It silently no-ops. The CommandHandler wrapper would see no error but the service wasn't changed.
**How to avoid:** Check service state before calling `start()`/`stop()` in the CommandHandler and return a meaningful error: `"Service 'name' is already running"` or `"Service 'name' is not running"`. Mirror what the GUI already disables via `.disabled(service.state.isActive)`.

### Pitfall 5: CLI help text and usage patterns
**What goes wrong:** Forgetting to update `printUsage()` in `exmen-cli/main.swift` after adding new commands — users see old help.
**Why it happens:** The usage string is a hardcoded multi-line string; easy to miss.
**How to avoid:** Update `printUsage()` and the `switch command` dispatch block in the same commit as the new handlers.

## Code Examples

Verified patterns from existing source:

### Finding a Service by Name (mirrors existing findAction)
```swift
// Source: CommandHandler.swift findAction() pattern
private func findService(name: String) -> ManagedService? {
    ServiceManager.shared.services.first { $0.action.name.lowercased() == name.lowercased() }
}
```

### ServiceState to String (server-side, avoids Codable issue)
```swift
// Source: ServiceState.swift + ServiceRowView pattern
extension ServiceState {
    var rawStringValue: String {
        switch self {
        case .stopped:    return "stopped"
        case .starting:   return "starting"
        case .running:    return "running"
        case .restarting: return "restarting"
        case .crashed:    return "crashed"
        }
    }
}
```

### list-services Server Handler
```swift
private func listServices() -> Response {
    let infos = ServiceManager.shared.services.map { svc in
        ServiceInfo(
            name: svc.action.name,
            state: svc.state.rawStringValue,
            pid: svc.pid,
            statusText: ServiceState.displayText(state: svc.state, startedAt: svc.startedAt)
        )
    }
    return Response(success: true, data: .services(infos))
}
```

### start-service Server Handler (fire-and-control pattern)
```swift
private func startService(name: String) -> Response {
    guard let service = findService(name: name) else {
        return Response(success: false, error: "Service not found: \(name)")
    }
    guard !service.state.isActive else {
        return Response(success: false, error: "Service '\(name)' is already running")
    }
    ServiceManager.shared.start(service)
    return Response(success: true)
}
```

### list-services CLI Handler
```swift
func handleListServices(json: Bool) {
    let client = SocketClient()
    let result = client.send(["command": "list-services"])
    switch result {
    case .success(let response):
        if json {
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
            return
        }
        guard let success = response["success"] as? Bool, success else {
            if let error = response["error"] as? String { fputs("Error: \(error)\n", stderr) }
            exit(1)
        }
        if let services = response["data"] as? [[String: Any]] {
            for svc in services {
                let name = svc["name"] as? String ?? "Unknown"
                let statusText = svc["statusText"] as? String ?? "unknown"
                print("\(name)  \(statusText)")
            }
        }
    case .failure(let error):
        fputs("Error: \(error.message)\n", stderr)
        exit(1)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GUI-only service control | GUI context menu (Phase 8) | 2026-03-11 | Context menu Start/Stop/Restart/View Output exists but no CLI |
| No service CLI | Need to add in Phase 10 | This phase | Enables scripting, sketchybar integration, headless testing |

**Deprecated/outdated:**
- Nothing. The IPC pattern (JSON over Unix socket) is unchanged since Phase 6.

## Open Questions

1. **Should `service-status` include the service config details (command, restart policy)?**
   - What we know: `ServiceStatusInfo` can include `restartPolicy` and `keepAlive` from `ServiceConfig`
   - What's unclear: Whether the user wants all config fields or just runtime state
   - Recommendation: Include `restartPolicy` and `keepAlive` only; the TOML file is the authoritative config source

2. **Should `list-services` also show services from config that have never been started?**
   - What we know: `ServiceManager.shared.services` is populated after config load regardless of whether the service has been started
   - What's unclear: Whether `.stopped` services should be shown (they would have state "stopped")
   - Recommendation: Yes, show all registered services including stopped ones — mirrors how `list-actions` shows all actions

3. **Exit codes for error states**
   - What we know: Current CLI uses `exit(1)` for all errors, `exit(0)` for success
   - What's unclear: Whether distinct exit codes per error type would be useful for scripts
   - Recommendation: Keep `exit(1)` for all failures — consistent with current behavior; can be enhanced later

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None (no test target in Package.swift or Xcode project) |
| Config file | None |
| Quick run command | Manual: `swiftc -O -o .build/exmen exmen-cli/main.swift && .build/exmen list-services` |
| Full suite command | Manual end-to-end: build + run Exmen app + test each CLI command |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SVC-CLI-LIST | `exmen list-services` returns all services with state | smoke | `.build/exmen list-services` | ❌ Wave 0 (build first) |
| SVC-CLI-START | `exmen start-service <name>` starts a stopped service | smoke | `.build/exmen start-service "my-svc"` | ❌ Wave 0 (build first) |
| SVC-CLI-STOP | `exmen stop-service <name>` stops a running service | smoke | `.build/exmen stop-service "my-svc"` | ❌ Wave 0 (build first) |
| SVC-CLI-RESTART | `exmen restart-service <name>` restarts a service | smoke | `.build/exmen restart-service "my-svc"` | ❌ Wave 0 (build first) |
| SVC-CLI-STATUS | `exmen service-status <name>` returns detailed status | smoke | `.build/exmen service-status "my-svc"` | ❌ Wave 0 (build first) |
| SVC-CLI-ERR | Unknown service name returns error, exit(1) | smoke | `.build/exmen start-service "nonexistent"; echo $?` | ❌ Wave 0 (build first) |

### Sampling Rate
- **Per task commit:** `swiftc -O -o .build/exmen exmen-cli/main.swift` (compile check — catches server-side JSON contract issues indirectly via response parsing)
- **Per wave merge:** Full manual smoke test with running Exmen app
- **Phase gate:** All six behaviors above verified manually before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Build CLI binary: `swiftc -O -o .build/exmen exmen-cli/main.swift` — required before any smoke test
- [ ] Running Exmen app with at least one `type = "service"` TOML configured — prerequisite for functional tests

*(No automated test framework exists in this project. All verification is manual compilation + smoke testing against the running app.)*

## Sources

### Primary (HIGH confidence)
- Direct source code inspection: `Exmen/Services/CommandHandler.swift` — exact command routing pattern
- Direct source code inspection: `exmen-cli/main.swift` — exact CLI handler pattern
- Direct source code inspection: `Exmen/Services/ServiceManager.swift` — start/stop/restart API surface
- Direct source code inspection: `Exmen/Models/ManagedService.swift` — state fields, lifecycle methods
- Direct source code inspection: `Exmen/Models/ServiceState.swift` — enum cases and displayText helper
- Direct source code inspection: `Exmen/Services/SocketServer.swift` — background queue + MainActor dispatch pattern

### Secondary (MEDIUM confidence)
- `.planning/phases/08-*/` PLAN and SUMMARY files — implementation decisions from Phase 8

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — entire implementation uses existing in-project patterns, zero new dependencies
- Architecture: HIGH — both files examined in full; extension points are explicit and unambiguous
- Pitfalls: HIGH — identified from direct code inspection (ResponseData decode order, ServiceState non-Codable, existing guard conditions)

**Research date:** 2026-03-20
**Valid until:** Stable — no external dependencies involved; valid until the codebase changes significantly
