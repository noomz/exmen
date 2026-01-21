# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-20)

**Core value:** Zero-friction execution — click menu, run action, done.
**Current focus:** v1.1 Complete with IPC!

## Current Position

Phase: 7.1 (Inserted)
Plan: 07.1-01 not started
Status: Phase 7.1 UI Improvements inserted
Last activity: 2026-01-21 — Phase 7.1 inserted

Progress: █████████░ 93%

**Next Phase:** Phase 7.1: UI Improvements

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

### Roadmap Evolution

- Phase 7 added: Global config for action ordering and enable/disable
- Phase 7.1 inserted after Phase 7: UI Improvements (URGENT) — compact action list, better popup layout

### Deferred Issues

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-01-21
Stopped at: Phase 7 complete
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
