---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Completed 08-02-PLAN.md
last_updated: "2026-03-11T09:08:35.136Z"
last_activity: 2026-01-21 — Completed 07.1-01-PLAN.md
progress:
  total_phases: 9
  completed_phases: 8
  total_plans: 16
  completed_plans: 15
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Zero-friction execution — click menu, run action, done.
**Current focus:** v1.1 Complete with IPC!

## Current Position

Phase: 8 of 8 (Not planned)
Plan: None yet
Status: Phase 8 needs planning
Last activity: 2026-01-21 — Completed 07.1-01-PLAN.md

Progress: ██████████ 100%

**Next Phase:** Milestone complete

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 2 | — | — |
| 2. Config & Discovery | 2 | — | — |
| 3. Script Execution | 2 | — | — |
| 4. Hook System | 2 | — | — |
| 5. Auto-Hide Menu | 1 | — | — |
| 6. IPC Server | 2 | — | — |
| 7. Global Config | 1 | — | — |

**Recent Trend:**
- Last 5 plans: 05-01, 06-01, 06-02, 07-01
- Trend: —
| Phase 08 P02 | 8min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
All key decisions for v1:

- SwiftUI MenuBarExtra with .window style (macOS 13+)
- LSUIElement=true to hide dock icon
- Quit button with Cmd+Q shortcut
- TOMLDecoder for TOML parsing (pure Swift)
- DispatchSource for directory watching (0.5s debounce)
- Config path: ~/.config/exmen/actions/
- Swift Process API for script execution (30s timeout)
- OutputService for clipboard/notification/popup handling
- Hook format: EXMEN:key=value in script output
- StatusPoller with Timer for periodic status updates
- Menu auto-hide on action click (default: true, configurable via hide_on_click)
- Unix domain socket for IPC (~/.config/exmen/exmen.sock)
- JSON protocol for CLI communication
- [Phase 08]: SwiftTerm 1.11.2 added as SPM dependency (libghostty C API not yet embeddable as of 2026)
- [Phase 08]: ActionConfig.script made optional to support service TOMLs (backward compatible)
- [Phase 08]: RestartPolicy uses String raw values (on-failure) matching TOML spec directly
- [Phase 08]: LocalProcessTerminalViewDelegate used for PTY process exit — processTerminated(source: TerminalView, exitCode:) dispatched to @MainActor
- [Phase 08]: ServiceManager.register() matches by action.name to preserve running services on config reload
- [Phase 08]: ServiceOutputWindow uses NSWindowDelegate (not NSWindowController override) for windowWillClose

### Roadmap Evolution

- Phase 7 added: Global config for action ordering and enable/disable
- Phase 7.1 inserted after Phase 7: UI Improvements (URGENT) — compact action list, better popup layout
- Phase 8 added: Long-running CLI services with start/stop, output viewing, and TTY interaction

### Deferred Issues

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-11T09:08:35.132Z
Stopped at: Completed 08-02-PLAN.md
Resume file: None

## v1.1 Features Complete

- [x] Menu bar icon with action list
- [x] TOML config for actions (inline/file scripts)
- [x] Script folder discovery (~/.config/exmen/actions/)
- [x] Directory watching for auto-reload
- [x] Script execution with timeout
- [x] Output handlers: clipboard, notification, popup
- [x] Hook system: EXMEN:key=value parsing
- [x] Status polling with configurable interval
- [x] Dynamic UI updates (title, status, badge, icon)
- [x] Menu auto-hide on action click (configurable)
- [x] IPC via Unix domain socket
- [x] CLI tool (exmen) for external integration
- [x] Global config.toml for action ordering and enable/disable
