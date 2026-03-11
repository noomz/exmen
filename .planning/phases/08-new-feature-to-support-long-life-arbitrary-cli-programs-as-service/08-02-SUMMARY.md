---
phase: 08-long-running-cli-services
plan: 02
subsystem: service-engine
tags: [swift, swiftterm, pty, service-lifecycle, nswindow, appkit]
dependency_graph:
  requires: [ServiceConfig, ServiceState, ManagedService-skeleton, SwiftTerm-dependency]
  provides: [ManagedService-full, ServiceManager, ServiceOutputWindow]
  affects: [Exmen.xcodeproj/project.pbxproj]
tech_stack:
  added: []
  patterns: [LocalProcessTerminalView-PTY, NSWindowController-independent, exponential-backoff-Task, MainActor-delegate-dispatch]
key_files:
  created:
    - Exmen/Services/ServiceManager.swift
    - Exmen/Views/ServiceOutputWindow.swift
  modified:
    - Exmen/Services/ManagedService.swift
    - Exmen.xcodeproj/project.pbxproj
decisions:
  - "LocalProcessTerminalViewDelegate used (not TerminalViewDelegate) — processTerminated(source: TerminalView, exitCode:) is the key callback"
  - "NSWindowDelegate conformance added to ServiceOutputWindow (override windowWillClose not valid on NSWindowController)"
  - "ServiceManager.register() matches by action.name to preserve running services on config reload"
  - "manuallyStoppping flag prevents restart logic when stop() is explicitly called"
metrics:
  duration: "~8 minutes"
  completed: "2026-03-11"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
---

# Phase 8 Plan 2: Service Engine (PTY + Manager + Output Window) Summary

Full ManagedService lifecycle with SwiftTerm LocalProcessTerminalView PTY, ServiceManager singleton with PID file persistence for keep_alive services, and ServiceOutputWindow as an independent AppKit NSWindow with ANSI color terminal rendering.

## What Was Built

### Task 1: ManagedService with SwiftTerm PTY lifecycle

`Exmen/Services/ManagedService.swift` — skeleton from Plan 01 replaced with full implementation.

**Start flow:**
1. Guard against double-start (running/starting states)
2. Create `LocalProcessTerminalView(frame: 800x500)` and set `processDelegate = self`
3. Resolve executable: absolute path used directly, otherwise `/usr/bin/env <command>`
4. Convert `[String: String]` environment to `["KEY=VALUE"]` array for SwiftTerm
5. Call `startProcess(executable:args:environment:execName:currentDirectory:)`
6. Set `state = .running`, `startedAt = Date()`, extract PID from `tv.process.shellPid`
7. Notify output window to swap terminal view if open

**Stop flow:**
1. Set `manuallyStoppping = true`, cancel pending restart backoff task
2. Call `tv.terminate()` (sends SIGTERM via LocalProcess, closes DispatchIO cleanly)
3. Schedule SIGKILL after 5 seconds if process still alive
4. State set to `.stopped` in processTerminated delegate

**Restart flow:**
- If stopped/crashed: call start() directly
- If running: set state to `.restarting`, call terminate(); processTerminated detects `.restarting` state and calls `start()`

**Restart policy with exponential backoff:**
- `.never`: stopped (exit 0) or crashed (non-zero)
- `.onFailure`: restart on non-zero exit with backoff; max_restarts enforced → crashed
- `.always`: always restart with backoff; max_restarts enforced → crashed
- Backoff delay: `min(2^(restartCount-1), 30)` seconds using `Task.sleep`
- Backoff task stored in `restartBackoffTask` for cancellation on manual stop

**Delegate conformance (`LocalProcessTerminalViewDelegate`):**
- `processTerminated` dispatched to @MainActor via `Task { @MainActor in ... }`
- `sizeChanged`, `setTerminalTitle`, `hostCurrentDirectoryUpdate` are no-ops

### Task 2: ServiceManager singleton and ServiceOutputWindow

**`Exmen/Services/ServiceManager.swift`:**
- `@MainActor class ServiceManager: ObservableObject` with `static let shared`
- `register(_ actions: [Action])`: matches by `action.name` to preserve running services; removes deleted configs (stops if active); adds new ones
- `showOutput(for:)`: creates `ServiceOutputWindow` if nil, calls `showWindow` + `makeKeyAndOrderFront` + `NSApp.activate`
- `handleAppWillTerminate()`: writes PID files for keep_alive services, stops others
- `reconnectKeepAliveServices()`: reads `~/.config/exmen/services/*.pid`, verifies with `kill(pid, 0)`, sets `.running` state with approximate startedAt
- PID files: plain text at `~/.config/exmen/services/{name}.pid`

**`Exmen/Views/ServiceOutputWindow.swift`:**
- `class ServiceOutputWindow: NSWindowController, NSWindowDelegate`
- Creates 800x500 titled/closable/resizable/miniaturizable NSWindow
- `window.isReleasedWhenClosed = false` — window controller retains the window
- `window.delegate = self` — receives `windowWillClose` notifications
- Content view: `service.terminalView` if available, placeholder NSTextField if nil
- `updateTerminalView()`: swaps content view for new terminal after restart
- `windowWillClose`: nils `service.outputWindow` to allow recreation on next show

**pbxproj:** ServiceManager.swift and ServiceOutputWindow.swift added to Services and Views groups respectively, with PBXBuildFile, PBXFileReference, and PBXSourcesBuildPhase entries.

## Verification

Build output: `** BUILD SUCCEEDED **` with zero errors. Pre-existing warnings in ScriptRunner.swift and CommandHandler.swift are out of scope.

Four verification criteria from plan:
1. Build succeeds — PASSED
2. `ServiceManager.shared` accessible — PASSED (static singleton)
3. ManagedService imports SwiftTerm and references LocalProcessTerminalView — PASSED
4. ServiceOutputWindow creates independent NSWindow — PASSED (NSWindowController, not SwiftUI)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] NSWindowController override does not exist for windowWillClose**
- **Found during:** Task 2 compile
- **Issue:** `override func windowWillClose` fails — NSWindowController has no such override point; windowWillClose is an NSWindowDelegate method
- **Fix:** Added `NSWindowDelegate` conformance to `ServiceOutputWindow` and set `window.delegate = self` in init; removed `override` keyword
- **Files modified:** `Exmen/Views/ServiceOutputWindow.swift`
- **Commit:** 0012877

**2. [Rule 3 - Blocking] ServiceOutputWindow.swift not in Xcode project**
- **Found during:** Task 1/2 compile (file existed on disk but not in pbxproj)
- **Issue:** New files must be registered in Exmen.xcodeproj/project.pbxproj to be compiled
- **Fix:** Added PBXBuildFile, PBXFileReference entries and group/build phase references for ServiceOutputWindow.swift and ServiceManager.swift
- **Files modified:** `Exmen.xcodeproj/project.pbxproj`
- **Commit:** 0012877

## Decisions Made

1. **`nonisolated` on delegate methods**: `LocalProcessTerminalViewDelegate` methods are called from non-isolated context. Marked `nonisolated` to satisfy Swift concurrency; the processTerminated callback dispatches to `@MainActor` via `Task { @MainActor in ... }`.

2. **`manuallyStoppping` flag pattern**: A boolean flag (set before calling `terminate()`) suppresses restart logic in the delegate. This is cleaner than passing exit context through the delegate callback, which doesn't carry intent.

3. **Restart state machine for `restart()`**: When state is `.restarting` and `manuallyStoppping` is false, `processTerminated` calls `start()` directly — avoiding a double-stop/start sequencing issue.

## Self-Check

Files created:
- Exmen/Services/ServiceManager.swift: FOUND
- Exmen/Views/ServiceOutputWindow.swift: FOUND

Files modified:
- Exmen/Services/ManagedService.swift: FOUND

Commits:
- c925117: feat(08-02): implement ManagedService with SwiftTerm PTY lifecycle — FOUND
- 0012877: feat(08-02): create ServiceManager singleton and ServiceOutputWindow — FOUND

## Self-Check: PASSED
