# Milestones

## v1.1 — Services & CLI

**Shipped:** 2026-03-20
**Phases:** 8-10 (3 phases) | **Plans:** 4 | **Tasks:** ~8
**Src changes:** 21 files, +2,285 / -44 (since v1.0.0)
**Git range:** dc8603b → b8d291e

### Delivered
Long-running CLI programs as managed services — PTY engine, lifecycle with
restart policies and keep-alive, dedicated menu UI with output window, and CLI
commands to script service control.

### Accomplishments
1. SwiftTerm PTY service engine — long-life CLI programs run as managed services with full terminal emulation
2. ServiceManager lifecycle — start/stop/restart, restart policies (never/on-failure/always with backoff), keep-alive persistence via PID files
3. Service UI — separate menu section with status dots, context menu (Start/Stop/Restart/View Output), standalone ANSI-color output window
4. Service config — `type = "service"` TOML + `[service]` section; app lifecycle reconnect/cleanup hooks
5. CLI service commands — list-services / start / stop / restart / service-status over Unix socket JSON IPC

### Known Deferred Items
| Category | Item | Status |
|----------|------|--------|
| verification | Phase 10 live IPC tests (list/start/stop/restart/status vs live service) | deferred — build + static verified (7/7), live run pending app+TOML |

---

## v1.0 — MVP

**Tagged:** v1.0.0 (archived retroactively at v1.1 close)
**Phases:** 1-7.1

### Delivered
Menu bar app for zero-friction script execution — TOML actions, folder
discovery with file watching, script execution with output handlers, hook
system for dynamic updates, auto-hide menu, Unix socket IPC + CLI, global
config for ordering/enable, and compact UI.

### Accomplishments
1. SwiftUI MenuBarExtra app with action list (LSUIElement, no dock icon)
2. TOML config + script folder discovery + DispatchSource directory watching
3. Script execution (Process API, 30s timeout) with clipboard/notification/popup output
4. Hook system (`EXMEN:key=value`) + status polling for dynamic menu updates
5. Unix domain socket IPC + `exmen` CLI client; global config.toml for ordering/enable
