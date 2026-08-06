# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Exmen -- native macOS menu bar app (Swift/SwiftUI/AppKit) for zero-friction script execution. Actions are defined in TOML files under `~/.config/exmen/actions/`, discovered automatically, and run via click. Includes a managed-services subsystem (long-running processes with PTY interaction) and a CLI tool (`exmen`) that talks to the running app over a Unix domain socket.

## Build & test

The GUI app and its tests build through Xcode; there is no SPM test target.

```bash
# Build the app (Debug)
xcodebuild -project Exmen.xcodeproj -scheme Exmen -configuration Debug build

# Run all tests (ExmenTests target, via the Exmen scheme)
xcodebuild test -project Exmen.xcodeproj -scheme Exmen -destination 'platform=macOS'

# Run a single test class or method
xcodebuild test -project Exmen.xcodeproj -scheme Exmen -destination 'platform=macOS' \
  -only-testing:ExmenTests/SubtaskConfigTests/testDecodeSubtasksArrayInlineScript
```

`swift build` / `swift test` also work against `Package.swift`, but that manifest declares only the `Exmen` executable target (the GUI app) -- **it has no test target**, so `swift test` finds nothing, and `swift build` produces `.build/debug/exmen`, which is the GUI binary, not the CLI.

### CLI (`exmen-cli/`)

`exmen-cli/main.swift` is **not wired into any build system** (not in `Package.swift`, not an Xcode target) -- it has historically been compiled ad hoc:

```bash
swiftc -O exmen-cli/main.swift -o <output-path>
```

Never output it to `.build/debug/exmen` or otherwise let it collide with the SPM-built GUI binary of the same name -- running the GUI binary in place of the CLI silently binds/steals the same IPC socket (`~/.config/exmen/exmen.sock`) as a real running Exmen.app, which looks like flaky socket behavior. Prefer a scratch path (e.g. `/tmp/exmen` or `~/.local/bin/exmen`) when building the CLI for manual testing.

### Release build

```bash
xcodebuild -project Exmen.xcodeproj -scheme Exmen -configuration Release build
```

## Architecture

### Actions (core execution path)

`ConfigLoader` parses TOML files from `~/.config/exmen/actions/*.toml` into `ActionConfig` -> `Action` models. `ActionService` owns the in-memory action list and is watched by `DirectoryWatcher`, which triggers reloads on filesystem changes. `MenuContentView`/`ActionRowView` render the list; clicking runs `ScriptRunner`, and the result flows through `OutputHandler` (clipboard/notification/popup). `HookParser` extracts `EXMEN:title=`/`status=`/`badge=`/`icon=` lines emitted by scripts for live display updates; `StatusPoller` provides a polling fallback (`[hook.status_script]` + `poll_interval`).

### Managed services

A TOML action with `type = "service"` and a `[service]` block (instead of `[script]`) is a long-running process. `ManagedService` owns one process's PTY lifecycle (via SwiftTerm) -- start/stop/restart, restart policy (`never`/`on-failure`/`always`) with exponential backoff, `keep_alive` reconnection across app restarts. `ServiceManager` is the registry of all services, matched by `action.name` across config reloads. `ServiceRowView`/`ServiceOutputWindow` provide the menu UI and live terminal output window.

Constraints that are easy to violate and expensive to debug:

- **`[service].command` must run in the foreground.** Exmen supervises exactly the process it forks. A launcher script that backgrounds a daemon (`nohup ... &`) and exits looks like a process that died instantly, and tearing down its PTY on the next start kills the detached daemon too. Point `command` at the daemon itself. `ManagedService.reportFailure` emits this hint whenever a service exits within `immediateExitThreshold`.
- **`restartCount` must not be reset by `start()`.** Automatic restarts go through `start()`, so resetting there makes `max_restarts` unreachable and turns any instantly-exiting command into an unbounded respawn loop. It is reset only by an explicit user start/restart (`resetRestartBudget`) or after the process stays up for `healthyUptimeThreshold`.
- **`stop()` must be valid from every state**, notably `.restarting` and `.crashed` -- that is when a user needs it most, and it is the only thing that cancels a pending restart backoff. Same rule for the `stop-service` IPC command.
- **Exited children must be reaped.** SwiftTerm only calls `waitpid()` from its PTY read loop, which stops running once we terminate the process ourselves; `ManagedService.reapChild` polls `waitpid(..., WNOHANG)` so stop/restart cycles do not leak `<defunct>` entries.
- **Working directory defaults to `$HOME`, not `/`.** A bundled `.app` runs with cwd `/`; programs keeping state relative to cwd cannot write there and die at startup with no visible cause. See `ServiceConfig.resolvedWorkingDir` and `ScriptRunner`.
- **Hook status strings are matched negative-first** in `ServiceState.dotColor` -- `"not running"` contains `"running"`, so matching positives first paints a dead service green.

### Subtask orchestration (v1.2, in progress)

An action can declare `[[subtasks]]` (parsed into `SubtaskConfig`) instead of a single script. `SubtaskOrchestrator` (`Exmen/Services/SubtaskOrchestrator.swift`) is a wave topo-sort scheduler with bounded concurrency: it resolves `depends_on` into execution waves, runs each subtask through `SubtaskRunner` (per-subtask timeout, hook-line parsing via `HookParser.parseLine`, cascade-skip when a dependency fails), and publishes live progress (`@Published subtaskStates`, `isRunning`, `overallProgressPercent`) consumed by `SubtaskProgressWindow`. It is deliberately not `@MainActor` at the class level (state mutation is dispatched to the main actor explicitly) so `@Published` state can be read synchronously from nonisolated test contexts -- see the doc comment at the top of `SubtaskOrchestrator.swift` before changing its actor isolation.

### IPC (socket + CLI)

`SocketServer` (`Exmen/Services/SocketServer.swift`) listens on a Unix domain socket at `~/.config/exmen/exmen.sock`, accepts connections on a background queue (non-blocking accept loop -- see the comment on `acceptPendingConnections` about draining the whole backlog, not just one connection per event), and hops each request to the main actor via `CommandHandler.shared.handle(_:)`, which decodes a JSON `Request { command, name, wait }` and dispatches by `command` string (`list-actions`, `run`, `status`, `orchestration-status`, `list-services`, `start-service`, `stop-service`, `restart-service`, `service-status`). `exmen-cli/main.swift` is the thin client: it builds the same JSON request shape, connects via its own `SocketClient`, and prints the formatted response (supports `--json`).

Orchestrated (`[[subtasks]]`) actions run **fire-and-return** over IPC: `CommandHandler.runSubtaskAction` starts the orchestrator and returns immediately rather than blocking, because `handle` itself runs on the main thread that the orchestrator needs for its own state updates -- blocking there would deadlock. A caller that wants the result polls `orchestration-status` (`exmen run --wait` does this loop for you).

### Config locations

- `~/.config/exmen/config.toml` -- global config (`order`, `disabled`)
- `~/.config/exmen/actions/*.toml` -- one file per action or service
- `~/.config/exmen/exmen.sock` -- IPC socket (created by the running app)

Repo-local examples live in `.config/exmen/` (copy to `~/.config/exmen/` to try them).

## Project planning docs

`.planning/` holds GSD-workflow planning artifacts (`PROJECT.md`, `ROADMAP.md`, per-phase `PLAN.md`/`SUMMARY.md`/`RESEARCH.md`/`VERIFICATION.md`). `PROJECT.md` is the most useful single file for current milestone state, active requirements, and key architectural decisions with rationale -- check it before making cross-cutting changes.
