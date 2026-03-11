# Phase 8: Long-Running CLI Services - Research

**Researched:** 2026-03-11
**Domain:** macOS Swift — PTY process management, terminal emulation, standalone windows, service lifecycle
**Confidence:** HIGH (core stack), MEDIUM (keep_alive reconnection pattern)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Services live in `~/.config/exmen/actions/` alongside regular actions
- Action TOML gets `type = "service"` in `[action]` section
- New `[service]` section: `auto_start`, `restart`, `max_restarts`, `keep_alive`, `working_dir`, `env`
- Restart policies: `never`, `on-failure`, `always`
- Environment variables via `env = { KEY = "value" }` table
- Working directory via `working_dir = "~/path"`
- Services and regular actions shown in separate sections with a divider
- Right-click / context menu on service row shows: Start, Stop, Restart, View Output
- Left-click does NOT toggle
- Status: colored dot + text — green=running, gray=stopped, yellow=starting/restarting, red=crashed
- Show uptime when running (e.g., "running • uptime 2h 15m")
- `keep_alive = true`: service continues as background process after Exmen quits, reconnect on next launch
- `keep_alive = false` (default): service terminated when Exmen quits
- auto_start NOT implemented in v1; key reserved
- Output in a separate standalone macOS window (not in-menu popup)
- Window stays open when menu closes, can be resized and positioned
- Always auto-scroll to bottom as new lines arrive
- stdout and stderr merged into one interleaved stream; stderr visually distinguished (colored red)
- Full PTY allocation — programs think they're running in a real terminal
- Full ANSI color and escape code support
- Full terminal emulation: cursor movement, screen clearing, alternate screen buffer
- **Preferred library: libghostty** from ghostty-org/ghostty (Zig-based, C API)
- **Fallback library: SwiftTerm** (pure Swift, easier to embed) if libghostty integration proves too complex

### Claude's Discretion

- Output buffer size and eviction strategy
- Services section position in menu (top vs bottom)
- Terminal window default size and appearance
- How to reconnect to `keep_alive` processes on relaunch (PID file, socket, etc.)
- Error presentation for failed service starts

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 8 adds managed long-running CLI services to Exmen: TOML-configured programs that start/stop on demand, display real-time PTY output in a standalone window, and support full terminal interaction. The core technical challenges are (1) PTY process management in Swift, (2) terminal emulation in a SwiftUI/AppKit window, and (3) optional keep_alive reconnection across app launches.

**libghostty (the preferred library) is not yet embeddable.** As of early 2026, `libghostty-vt`'s C API is not finalized — only a Zig API exists for testing. The timeline from its author (Mitchell Hashimoto) is "within 6 months" from mid-2025, making it unavailable for this phase. **SwiftTerm is the correct fallback and the only viable choice today.**

SwiftTerm is a mature, actively maintained (v1.11.2), pure-Swift VT100/Xterm terminal emulator with `LocalProcessTerminalView` — an AppKit `NSView` that allocates a PTY, launches a process, and handles all keyboard/mouse input and ANSI rendering. This covers all stated requirements: full PTY, ANSI colors, cursor movement, alternate screen. Exmen is NOT sandboxed (no `.entitlements` file present, no `ENABLE_APP_SANDBOX` in project), so PTY spawning works without restriction.

**Primary recommendation:** Use SwiftTerm v1.11.2 via Swift Package Manager. Build `ServiceManager` (singleton, `@MainActor`, `@Published`) following existing patterns. Standalone output window via `NSWindowController` hosting an `NSViewRepresentable`-wrapped `LocalProcessTerminalView`. For `keep_alive`, write a JSON PID file to `~/.config/exmen/services/{name}.pid` and reconnect via process adoption (signal 0 liveness check + re-open PTY file descriptors is not possible for already-running processes — see Open Questions).

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm | 1.11.2 | PTY allocation, VT100/Xterm emulation, keyboard/mouse input | Only pure-Swift terminal emulator; used in commercial SSH clients; handles UTF/Unicode/grapheme clusters; `LocalProcessTerminalView` ships PTY integration out of the box |
| Foundation.Process | Built-in | Process lifecycle for non-PTY use | Already used in project for ScriptRunner |
| AppKit NSWindowController | Built-in | Standalone resizable output window | NSWindow survives menu close, supports resize/position persistence |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TOMLDecoder | Already in project | Parse `[service]` section additions | Already used for ActionConfig parsing |
| Foundation.FileManager | Built-in | PID file read/write for keep_alive reconnection | When `keep_alive = true` |
| Darwin libc (kill, getpgid) | Built-in | PID liveness check (signal 0) | Checking if keep_alive process is still running on relaunch |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftTerm | libghostty | libghostty not embeddable yet (C API unfinished as of early 2026); use SwiftTerm now, migrate later if desired |
| SwiftTerm | Hand-rolled ANSI parser + NSTextView | Enormous complexity: cursor positioning, alternate screen, 256-color, mouse events — months of work |
| NSWindowController | SwiftUI WindowGroup + openWindow | NSWindowController gives direct NSWindow access needed to embed NSView (SwiftTerm is AppKit-based); SwiftUI WindowGroup can't easily host arbitrary NSViews |

**Installation:**
```
In Xcode: File > Add Package Dependencies
URL: https://github.com/migueldeicaza/SwiftTerm
Version: Up to Next Major from 1.11.2
```

Or in `Package.swift` if project ever migrates:
```swift
.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.11.2")
```

---

## Architecture Patterns

### Recommended Project Structure

```
Exmen/
├── Models/
│   ├── ActionConfig.swift       # Extend: add type field + ServiceConfig
│   ├── Action.swift             # Extend: add serviceConfig, serviceState
│   └── ServiceState.swift       # NEW: enum (stopped/starting/running/crashed) + uptime/pid
├── Services/
│   ├── ServiceManager.swift     # NEW: singleton, owns all ManagedService instances
│   ├── ManagedService.swift     # NEW: one per service — Process, PTY, restart logic, output buffer
│   └── ActionService.swift      # Extend: split loading into actions vs services
├── Views/
│   ├── MenuContentView.swift    # Extend: two sections (services + actions), divider
│   ├── ServiceRowView.swift     # NEW: status dot, name, uptime, context menu
│   └── ServiceOutputWindow.swift # NEW: NSWindowController + LocalProcessTerminalView host
└── [existing files unchanged]
```

### Pattern 1: Extending ActionConfig for Services

**What:** Add `type` discriminator and optional `[service]` block to existing TOML model
**When to use:** All service config parsing

```swift
// Source: existing ActionConfig.swift pattern + CONTEXT.md spec
enum ActionType: String, Codable {
    case action   // default — existing behavior
    case service  // long-running managed service
}

struct ServiceConfig: Codable {
    let command: String            // The executable/script to run
    let args: [String]?           // Optional arguments
    let restart: RestartPolicy?   // never | on-failure | always
    let max_restarts: Int?        // default: 3
    let keep_alive: Bool?         // default: false
    let working_dir: String?      // expands ~
    let env: [String: String]?    // additional env vars

    var resolvedRestart: RestartPolicy { restart ?? .never }
    var resolvedMaxRestarts: Int { max_restarts ?? 3 }
    var resolvedKeepAlive: Bool { keep_alive ?? false }
}

enum RestartPolicy: String, Codable {
    case never = "never"
    case onFailure = "on-failure"
    case always = "always"
}

// Extend ActionConfig:
struct ActionConfig: Codable {
    // ... existing fields ...
    let type: ActionType?          // nil == .action for backward compat
    let service: ServiceConfig?    // Only present when type == .service

    var resolvedType: ActionType { type ?? .action }
}
```

**TOML example:**
```toml
[action]
name = "Dev Server"
icon = "server.rack"
type = "service"

[service]
command = "npm"
args = ["run", "dev"]
working_dir = "~/Projects/myapp"
restart = "on-failure"
max_restarts = 5
keep_alive = false
env = { NODE_ENV = "development" }
```

### Pattern 2: ServiceManager Singleton

**What:** Single `@MainActor` `ObservableObject` that owns all `ManagedService` instances
**When to use:** All service lifecycle operations

```swift
// Source: follows ActionService.shared / ScriptRunner.shared pattern
@MainActor
class ServiceManager: ObservableObject {
    static let shared = ServiceManager()

    @Published var services: [ManagedService] = []

    func start(_ service: ManagedService) { ... }
    func stop(_ service: ManagedService) { ... }
    func restart(_ service: ManagedService) { ... }
    func showOutput(for service: ManagedService) { ... }

    // Called by ActionService on load
    func register(_ configs: [Action]) { ... }

    // App termination handler — stop all non-keep_alive services
    func handleAppWillTerminate() { ... }

    private init() {}
}
```

### Pattern 3: ManagedService with PTY via SwiftTerm

**What:** One `ManagedService` per configured service; owns `LocalProcessTerminalView` lifecycle
**When to use:** Per-service process management

```swift
// Source: SwiftTerm LocalProcessTerminalView API
import SwiftTerm

class ManagedService: ObservableObject, Identifiable {
    let id: UUID
    let action: Action            // source config

    @Published var state: ServiceState = .stopped
    @Published var pid: Int32?
    @Published var startedAt: Date?

    private var terminalView: LocalProcessTerminalView?
    private var outputWindow: ServiceOutputWindow?
    private var restartCount = 0

    func start() {
        state = .starting
        let view = LocalProcessTerminalView(frame: .zero)
        view.startProcess(
            executable: resolvedExecutable,
            args: resolvedArgs,
            environment: resolvedEnvironment,
            execName: action.name
        )
        // terminalView.delegate = self  (for process exit notification)
        terminalView = view
        state = .running
        startedAt = Date()
    }

    func stop() {
        terminalView?.getTerminal().kill()   // sends SIGTERM to child process group
        state = .stopped
    }
}
```

**Key SwiftTerm API (verified from docs/search):**
- `LocalProcessTerminalView(frame:)` — creates NSView with embedded PTY
- `startProcess(executable:args:environment:execName:)` — launches process in PTY
- `LocalProcessTerminalViewDelegate.processTerminated(_:exitCode:)` — called on process exit
- Terminal view handles all keyboard input automatically (it IS the responder)
- `getTerminal().kill()` / `process?.terminate()` for stopping

### Pattern 4: Standalone Output Window

**What:** NSWindowController wrapping LocalProcessTerminalView in an NSWindow
**When to use:** "View Output" action from context menu

```swift
// Source: NSWindowController pattern for AppKit NSView embedding
class ServiceOutputWindow: NSWindowController {
    let terminalView: LocalProcessTerminalView

    init(for service: ManagedService) {
        self.terminalView = service.terminalView ?? LocalProcessTerminalView(frame: .zero)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = service.action.name
        window.contentView = terminalView
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// Usage in ServiceManager:
func showOutput(for service: ManagedService) {
    if service.outputWindow == nil {
        service.outputWindow = ServiceOutputWindow(for: service)
    }
    service.outputWindow?.showWindow(nil)
    service.outputWindow?.window?.makeKeyAndOrderFront(nil)
}
```

**Key: window stays alive** even after menu closes because NSWindowController retains it independently of the menu bar popover.

### Pattern 5: ServiceRowView with Context Menu

**What:** SwiftUI view for service row with colored status dot and right-click context menu
**When to use:** Each service entry in MenuContentView services section

```swift
// Source: SwiftUI .contextMenu modifier — macOS 13+
struct ServiceRowView: View {
    @ObservedObject var service: ManagedService

    var body: some View {
        HStack(spacing: 8) {
            // Colored status dot
            Circle()
                .fill(service.state.dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(service.action.name).font(.callout)
                Text(service.state.displayText).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contextMenu {
            Button("Start")   { ServiceManager.shared.start(service) }
                .disabled(service.state == .running || service.state == .starting)
            Button("Stop")    { ServiceManager.shared.stop(service) }
                .disabled(service.state == .stopped || service.state == .crashed)
            Button("Restart") { ServiceManager.shared.restart(service) }
            Divider()
            Button("View Output") { ServiceManager.shared.showOutput(for: service) }
        }
    }
}

// ServiceState computed properties:
extension ServiceState {
    var dotColor: Color {
        switch self {
        case .running:    return .green
        case .stopped:    return .gray
        case .starting, .restarting: return .yellow
        case .crashed:    return .red
        }
    }
    var displayText: String { /* "running • uptime 2h 15m" or "stopped" etc */ }
}
```

### Pattern 6: keep_alive PID File Strategy

**What:** Write PID to `~/.config/exmen/services/{name}.pid` on start; check on relaunch
**When to use:** Services with `keep_alive = true`

```swift
// Source: standard Unix PID file pattern (MEDIUM confidence — Claude's discretion)
let pidDir = URL(fileURLWithPath: NSString(string: "~/.config/exmen/services").expandingTildeInPath)

func writePIDFile(name: String, pid: Int32) {
    let url = pidDir.appendingPathComponent("\(name).pid")
    try? "\(pid)".write(to: url, atomically: true, encoding: .utf8)
}

func checkPIDAlive(name: String) -> Int32? {
    guard let pidStr = try? String(contentsOf: pidDir.appendingPathComponent("\(name).pid")),
          let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    // kill(pid, 0) returns 0 if process exists and we have permission
    return kill(pid, 0) == 0 ? pid : nil
}
```

**Important limitation:** For `keep_alive` services, when Exmen relaunches and finds a living PID, it can display the running status (green dot + PID), but **cannot reattach the PTY output stream** — PTY file descriptors are not inheritable across unrelated processes. The output window will be empty on reconnect; new output will appear only after that point. This is the correct behavior to document in the UI ("Reconnected to running service — previous output unavailable").

### Anti-Patterns to Avoid

- **Using `forkpty()` directly in Swift**: Unsafe — `forkpty` does `fork()` without `exec` and Swift runtime is not fork-safe. SwiftTerm handles PTY allocation internally via `posix_openpt` + `posix_spawn` equivalent patterns.
- **Using Pipe/Pipe for interactive programs**: Programs that check `isatty()` will disable interactive prompts (password prompts, readline, etc.). Must use PTY for real terminal behavior.
- **Reusing ScriptRunner**: ScriptRunner is fire-and-forget with timeout. Services need continuous streaming, restart logic, and PTY — a completely different execution model.
- **SwiftUI WindowGroup for terminal window**: SwiftUI WindowGroup can't cleanly host AppKit `NSView` subclasses like `LocalProcessTerminalView`; use `NSWindowController` directly.
- **Storing terminalView in @Published**: `LocalProcessTerminalView` is a reference-type `NSView`; store as regular `var`, not `@Published` to avoid SwiftUI observation issues.
- **Killing process with SIGKILL immediately**: Always try SIGTERM first (gives process a chance to clean up); SIGKILL as fallback after timeout.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PTY allocation + VT100 emulation | Custom ANSI parser + NSTextView renderer | SwiftTerm LocalProcessTerminalView | Cursor movement, alternate screen, 256-color, Kitty graphics, Unicode, grapheme clusters — months of work |
| Terminal keyboard input routing | Manual NSEvent handling | SwiftTerm TerminalView (handles it) | Ctrl+C, arrow keys, escape sequences require precise terminal protocol handling |
| ANSI color rendering | NSAttributedString with regex | SwiftTerm TerminalView (renders it) | Color pairs, bold, underline, blink, reverse video interact with terminal state |

**Key insight:** Terminal emulation is deceptively complex. SwiftTerm is tested in production SSH clients (Secure Shellfish, La Terminal, CodeEdit). Even rendering "simple" ANSI output correctly requires a proper terminal state machine.

---

## Common Pitfalls

### Pitfall 1: Sandbox Would Block PTY
**What goes wrong:** `posix_openpt()` and `grantpt()` fail silently or with EPERM in sandboxed apps
**Why it happens:** App Sandbox restricts process spawning
**How to avoid:** Exmen has NO sandbox (verified — no `.entitlements` file, no `ENABLE_APP_SANDBOX` in pbxproj). SwiftTerm `LocalProcessTerminalView.startProcess()` works without any entitlements in non-sandboxed apps.
**Warning signs:** If sandbox is ever added (e.g., for Mac App Store distribution), PTY will break entirely

### Pitfall 2: Menu Close Destroys Window
**What goes wrong:** If output window is owned by a SwiftUI popover or the menu view, closing the menu dismisses the window
**Why it happens:** SwiftUI MenuBarExtra `.window` style owns all child windows
**How to avoid:** Output window must be owned by `ServiceManager` (or an `NSWindowController` held by `ServiceManager`), NOT by any SwiftUI view hierarchy. `NSWindowController.showWindow(nil)` creates an independent `NSWindow` with its own lifecycle.
**Warning signs:** Window disappears when clicking away from menu

### Pitfall 3: Double-Termination Crash (same as ScriptRunner race)
**What goes wrong:** Restart logic and termination handler both call `stop()` → double deallocation or invalid state
**Why it happens:** `processTerminated` delegate fires on background thread; restart timer also fires
**How to avoid:** Use an actor or `@MainActor` + state guard: only transition from running→stopped if currently running. Check `state != .stopped` before any termination action.
**Warning signs:** `EXC_BREAKPOINT` or `BAD_ACCESS` on process termination

### Pitfall 4: Restart Loop (max_restarts not enforced)
**What goes wrong:** Service with `restart = "always"` crashes immediately and hammers restarts continuously
**Why it happens:** No backoff or restart count check
**How to avoid:** Track `restartCount`; after `max_restarts` exceeded, transition to `.crashed` state and stop restarting. Also implement exponential backoff: `min(2^n, 30)` seconds.
**Warning signs:** High CPU, log spam, state flicker in UI

### Pitfall 5: PID File Stale on Crash
**What goes wrong:** Exmen crashes (not orderly quit); keep_alive PID file not cleaned up; next launch sees stale PID
**Why it happens:** PID cleanup requires `applicationWillTerminate` handler
**How to avoid:** On relaunch, always validate PID with `kill(pid, 0)`. If PID is dead (returns `ESRCH`), treat as stopped. Register `applicationWillTerminate` notification to clean up non-keep_alive PID files.
**Warning signs:** Service shows "running" status with a PID that belongs to a different process

### Pitfall 6: Terminal Window Loses Input Focus
**What goes wrong:** User clicks menu bar icon while terminal window is focused; terminal loses keyboard input after menu closes
**Why it happens:** Menu bar popover takes over key window
**How to avoid:** After menu closes (`menuBarExtraStyle(.window)` window dismiss), call `outputWindow?.window?.makeKeyAndOrderFront(nil)` if a terminal window was focused. Track "last focused terminal window" in ServiceManager.
**Warning signs:** Arrow keys stop working in terminal after clicking menu bar

---

## Code Examples

Verified patterns from official sources and existing codebase:

### Starting a PTY process with SwiftTerm

```swift
// Source: SwiftTerm LocalProcessTerminalView API
import SwiftTerm

let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))

// Set delegate to receive process lifecycle events
terminalView.processDelegate = self

// Launch process inside PTY
terminalView.startProcess(
    executable: "/usr/bin/env",
    args: ["python3", "-m", "http.server", "8080"],
    environment: ["PATH": "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin", "TERM": "xterm-256color"],
    execName: "python3"
)

// To stop:
terminalView.process?.terminate()  // sends SIGTERM
```

### LocalProcessTerminalView delegate for process exit

```swift
// Source: SwiftTerm LocalProcessTerminalViewDelegate
extension ManagedService: LocalProcessTerminalViewDelegate {
    func processTerminated(_ source: LocalProcessTerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.pid = nil
            let exitedNormally = exitCode == 0

            switch self.config.resolvedRestart {
            case .never:
                self.state = exitedNormally ? .stopped : .crashed
            case .onFailure where !exitedNormally:
                self.attemptRestart()
            case .always:
                self.attemptRestart()
            default:
                self.state = .stopped
            }
        }
    }
}
```

### Context menu on service row (SwiftUI macOS)

```swift
// Source: SwiftUI .contextMenu — macOS 13+ (deployment target confirmed as 13.0)
.contextMenu {
    Button("Start")   { ... }.disabled(service.state.isActive)
    Button("Stop")    { ... }.disabled(!service.state.isActive)
    Button("Restart") { ... }
    Divider()
    Button("View Output") { ... }
}
```

### Uptime formatting

```swift
// Source: standard Swift DateComponentsFormatter
func formatUptime(since startedAt: Date) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: startedAt, to: Date()) ?? "—"
}
```

### PID liveness check (Darwin)

```swift
// Source: Darwin POSIX kill(2) man page
import Darwin

func isProcessAlive(_ pid: Int32) -> Bool {
    return kill(pid, 0) == 0 || errno == EPERM
}
```

### Environment resolution for service processes

```swift
// Source: existing ScriptRunner.swift pattern + ServiceConfig spec
var resolvedEnvironment: [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    env["TERM"] = "xterm-256color"   // Required for full color support
    // Merge service-specific env on top
    for (key, value) in config.service?.env ?? [:] {
        env[key] = value
    }
    return env
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| libghostty (preferred) | SwiftTerm (fallback, now primary) | 2026 — libghostty C API not yet available | Use SwiftTerm now; migration path to libghostty is possible later since both expose an NSView |
| Hand-rolled ANSI parser | SwiftTerm | n/a | SwiftTerm is the only mature pure-Swift option |
| NSWindowController (AppKit) | Hybrid NSWindowController + SwiftUI content | macOS 13+ | Use NSWindowController to host NSView (SwiftTerm); SwiftUI for chrome/controls around it |

**Deprecated/outdated:**
- `forkpty()` direct call: Unsafe in Swift; SwiftTerm handles PTY internally
- `daemon()` C API: Deprecated on macOS; use launchd or PID file approach for keep_alive

---

## Open Questions

1. **keep_alive PTY reattachment**
   - What we know: PTY file descriptors cannot be inherited by an unrelated process after the original parent quits. There is no standard macOS API to reattach a PTY to a new process.
   - What's unclear: Whether a socket-based proxy (like `dtach` on Linux) could be launched alongside the service process for reconnection.
   - Recommendation: For v1, keep_alive shows process as running (green dot, PID, uptime) but output window is empty on reconnect with a notice "Reconnected to running service — previous output not available." This is honest and correct. A `dtach`-style proxy is a v2 enhancement.

2. **libghostty migration path**
   - What we know: libghostty-vt C API is coming "within 6 months" from mid-2025 (possibly Q1 2026 range, but unconfirmed).
   - What's unclear: Exact API surface; whether it will provide a full view or just VT parsing.
   - Recommendation: Build with SwiftTerm. Both SwiftTerm and libghostty present as NSView-based. When libghostty ships and stabilizes, the swap is contained within `ManagedService` / `ServiceOutputWindow`.

3. **Output buffer size and eviction**
   - What we know: No constraint from user; Claude's discretion
   - Recommendation: Buffer last 10,000 lines (ring buffer). At 10,001 lines, evict oldest 1,000 (batch eviction is cheaper than single-line eviction). SwiftTerm itself has internal scrollback; the buffer here is for persistence when window is closed and reopened.

4. **Services section position in menu**
   - What we know: Positioning TBD — Claude's discretion
   - Recommendation: Services section at the **bottom**, above the footer divider and Quit button. Rationale: actions are primary use case; services are secondary/management. Bottom placement avoids shifting the actions list position as services are added/removed.

---

## Validation Architecture

> No automated test infrastructure exists for this project. It is a native macOS SwiftUI/AppKit app built and validated through Xcode. There is no `pytest.ini`, `jest.config`, or equivalent. No test files exist. All testing is manual (build, run, interact).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None — manual testing via Xcode Run |
| Config file | None |
| Quick run command | `xcodebuild -scheme Exmen -configuration Debug build 2>&1 | tail -5` |
| Full suite command | Manual: build + launch + exercise all service states |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| — | Service TOML parses correctly | manual | build succeeds + launch + config loads | ❌ Wave 0 |
| — | Start/stop via context menu | manual | visual inspection | ❌ Wave 0 |
| — | Status dot updates correctly | manual | visual inspection | ❌ Wave 0 |
| — | PTY programs get terminal (test: `tput colors`) | manual | run service, check output | ❌ Wave 0 |
| — | Output window stays open when menu closes | manual | visual inspection | ❌ Wave 0 |
| — | Restart policy enforced | manual | crash service, observe | ❌ Wave 0 |
| — | keep_alive = false terminates on quit | manual | quit app, check `ps` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild -scheme Exmen -configuration Debug build 2>&1 | grep -E "error:|BUILD"` (compile check only)
- **Per wave merge:** Full manual smoke test: launch app, configure test service, start/stop/restart, view output
- **Phase gate:** All behaviors above pass before `/gsd:verify-work`

### Wave 0 Gaps

- No test infrastructure to create — project has none and none is appropriate for this domain
- All validation is manual; ensure each plan includes specific manual verification steps

---

## Sources

### Primary (HIGH confidence)
- [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — LocalProcessTerminalView API, PTY integration, sandbox requirements, v1.11.2
- [Swift Package Index: SwiftTerm](https://swiftpackageindex.com/migueldeicaza/SwiftTerm) — version, platform support
- Existing Exmen codebase — ActionConfig, Action, ActionService patterns, sandbox status, deployment target (macOS 13.0), Swift 5.0

### Secondary (MEDIUM confidence)
- [Libghostty Is Coming — Mitchell Hashimoto](https://mitchellh.com/writing/libghostty-is-coming) — confirmed libghostty C API not ready as of mid-2025; timeline "within 6 months"
- [Apple Developer Forums: Swift Process with PTY](https://developer.apple.com/forums/thread/688534) — confirmed forkpty unsafe in Swift; SwiftTerm recommended
- [Apple Developer Forums: forkpty from sandboxed app](https://developer.apple.com/forums/thread/685544) — confirmed PTY blocked in sandboxed apps
- [SwiftUI macOS window management](https://nilcoalescing.com/blog/ProgrammaticallyOpenANewWindowInSwiftUIOnMacOS/) — NSWindowController pattern for AppKit NSView hosting

### Tertiary (LOW confidence)
- General Unix PID file pattern for keep_alive reconnection — standard technique, not Swift-specific sources found

---

## Metadata

**Confidence breakdown:**
- Standard stack (SwiftTerm): HIGH — actively maintained, official API docs, production usage confirmed
- libghostty status: HIGH — confirmed not embeddable from author's own blog post
- Architecture patterns: HIGH — based on existing codebase conventions + verified SwiftTerm API
- keep_alive reconnection: MEDIUM — standard Unix PID file pattern is well-known; PTY reattachment limitation is a confirmed constraint
- Pitfalls: HIGH — sandbox status verified in codebase; PTY safety verified from official Apple forums

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (libghostty status may change; all other findings are stable)
