# Exmen

## What This Is

Exmen is a macOS menu bar app that executes scripts and actions without leaving your current focused app. Instead of switching to Terminal to run quick commands, click the menu bar icon, pick an action, and it runs in the background. As of v1.1 it also manages long-running CLI programs as services with full PTY terminal interaction. Open source.

## Core Value

Zero-friction execution — click menu, run action, done. As fast as possible with no context switching.

## Current State

**In progress:** v1.2 Polish & Power (Phase 11 complete 2026-08-05; Phase 12 next)

- v1.0 MVP: menu bar app, TOML actions, folder discovery, script execution, output handlers, hook system, auto-hide menu, Unix socket IPC + CLI, global config (Phases 1-7.1)
- v1.1 Services & CLI: managed long-running services via SwiftTerm PTY, lifecycle with restart policies + keep-alive, dedicated menu UI with output window, CLI service commands (Phases 8-10)
- v1.2 Phase 11: declarative and dynamic subtask orchestration, live progress window, aggregate output summary, timeout/process-group cleanup, IPC status + `run --wait`

Codebase: ~2,991 LOC Swift across Exmen app + exmen-cli. Tech stack: Swift/SwiftUI, AppKit, SwiftTerm 1.11.2 (PTY), TOMLDecoder, Unix domain sockets.

## Current Milestone: v1.2 Polish & Power

**Goal:** Make Exmen faster to reach and more capable per task — parallel subtask orchestration with live feedback, instant on-screen summon, Raycast integration, and a refreshed menu UI.

**Target features:**
- Parallel subtask orchestration — declarative (`[[subtasks]]` TOML with run mode + `depends_on`) and dynamic (parent script spawns subtasks via hook protocol), with async per-subtask progress and result aggregation
- On-screen summon — global hotkey opens a Spotlight-style command palette plus a HUD progress overlay
- Raycast integration — TS extension listing/running actions and services via the existing `exmen` CLI / socket IPC
- Menu bar UI/UX overhaul — search/filter, grouping/sections, inline live progress, visual refresh

**Milestone tech decisions (from research):**
- Subtasks: app-spawned streaming runner (`AsyncStream`), wave topo-sort scheduler, `@MainActor` orchestrator
- Hotkey: `sindresorhus/KeyboardShortcuts` v2.4.0 (no Accessibility permission, sandbox-safe)
- Palette/HUD: non-activating borderless `NSPanel` (palette becomes key; HUD non-key, click-through)
- Raycast: full extension (`@raycast/api` 1.104.x), `useExec`/`execa`, parse `--json` envelope, bundle local-first

## Requirements

### Validated

- ✓ Menu bar icon with action list — v1.0
- ✓ TOML config format (inline scripts or executable paths) — v1.0
- ✓ Script folder discovery with file watching — v1.0
- ✓ Hook system for dynamic updates + polling fallback — v1.0
- ✓ Configurable output handling (clipboard/notification/popup) — v1.0
- ✓ Unix socket IPC + CLI client — v1.0
- ✓ Global config for action ordering + enable/disable — v1.0
- ✓ Long-running CLI services with PTY interaction — v1.1
- ✓ Service lifecycle (start/stop/restart, restart policies, keep-alive) — v1.1
- ✓ CLI service control (list/start/stop/restart/status) — v1.1
- ✓ Parallel subtask orchestration with live feedback — v1.2 Phase 11 (2026-08-05)

### Active (v1.2)

- [ ] On-screen summon: global hotkey + command palette + HUD overlay — SUMMON-*
- [ ] Raycast integration via CLI — RAYCAST-*
- [ ] Menu bar UI/UX overhaul (search, grouping, inline progress, visuals) — UIUX-*

### Out of Scope

- Cloud sync — local-only, no cross-device syncing
- Plugin marketplace — no community sharing platform or plugin system
- Arbitrary per-action global hotkeys — only Phase 12 summon shortcut is global

## Context

Target users are developers and power users who frequently run small scripts (generate test data, update homebrew, check system status, etc.) and want faster access than switching to Terminal. v1.1 broadens the audience to those running persistent dev processes (servers, watchers, tunnels) wanting managed control from the menu bar and scriptable CLI.

Example actions:
- Generate random phone number → copy to clipboard
- Run `brew update && brew upgrade` → show notification on complete
- Check disk space → display in menu bar status

Example services (v1.1):
- Dev server / file watcher with restart-on-failure
- Long-running tunnel with keep_alive

## Constraints

- **Tech stack**: Swift/SwiftUI native — no Electron, no web technologies. Must feel like a native macOS app.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| TOML for config | Human-readable, supports inline scripts and complex config | ✓ Good |
| Script output for hooks | Scripts emit special format for real-time updates | ✓ Good |
| Polling as fallback | Some scripts can't push updates | ✓ Good |
| Unix domain socket for IPC | Lightweight CLI integration (aerospace/yabai pattern) | ✓ Good |
| SwiftTerm 1.11.2 for PTY | libghostty C API not embeddable as of 2026 | ✓ Good |
| ActionConfig.script optional | Backward-compatible support for service TOMLs | ✓ Good |
| ServiceManager matches by action.name on reload | Preserve running services across config reload | ✓ Good |
| Services below actions in menu | Actions primary use case, services secondary | ✓ Good |
| ResponseData ordered decode disambiguation | Distinguish service vs action IPC responses without a type tag | ⚠️ Revisit (a type discriminator would be cleaner) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-05 — Phase 11 complete; Phase 12 next*
