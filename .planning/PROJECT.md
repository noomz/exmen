# Exmen

## What This Is

Exmen is a macOS menu bar app that executes scripts and actions without leaving your current focused app. Instead of switching to Terminal to run quick commands, click the menu bar icon, pick an action, and it runs in the background. As of v1.1 it also manages long-running CLI programs as services with full PTY terminal interaction. Open source.

## Core Value

Zero-friction execution — click menu, run action, done. As fast as possible with no context switching.

## Current State

**Shipped:** v1.1 (2026-03-20, tag v1.1.0)

- v1.0 MVP: menu bar app, TOML actions, folder discovery, script execution, output handlers, hook system, auto-hide menu, Unix socket IPC + CLI, global config (Phases 1-7.1)
- v1.1 Services & CLI: managed long-running services via SwiftTerm PTY, lifecycle with restart policies + keep-alive, dedicated menu UI with output window, CLI service commands (Phases 8-10)

Codebase: ~2,991 LOC Swift across Exmen app + exmen-cli. Tech stack: Swift/SwiftUI, AppKit, SwiftTerm 1.11.2 (PTY), TOMLDecoder, Unix domain sockets.

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

### Active

(None — planning next milestone)

### Out of Scope

- Cloud sync — local-only, no cross-device syncing
- Plugin marketplace — no community sharing platform or plugin system
- Keyboard shortcuts — no global hotkeys to trigger actions

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

---
*Last updated: 2026-03-20 after v1.1 milestone*
