# Exmen

## What This Is

Exmen is a macOS menu bar app that executes scripts and actions without leaving your current focused app. Instead of switching to Terminal to run quick commands, click the menu bar icon, pick an action, and it runs in the background. Open source.

## Core Value

Zero-friction execution — click menu, run action, done. As fast as possible with no context switching.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Menu bar icon that displays a list of actions when clicked
- [ ] TOML config file format for defining actions (supports inline scripts or paths to executables)
- [ ] Script folder discovery — drop scripts in a folder, exmen finds them
- [ ] Hook system for dynamic updates — scripts can push updates (title, status, thumbnail) via output, plus optional polling fallback
- [ ] Configurable output handling per action — clipboard, notification, popup, or combination

### Out of Scope

- Cloud sync — v1 is local-only, no cross-device syncing
- Plugin marketplace — no community sharing platform or plugin system
- Keyboard shortcuts — no global hotkeys to trigger actions in v1

## Context

Target users are developers and power users who frequently run small scripts (generate test data, update homebrew, check system status, etc.) and want faster access than switching to Terminal.

Example actions:
- Generate random phone number → copy to clipboard
- Run `brew update && brew upgrade` → show notification on complete
- Check disk space → display in menu bar status

## Constraints

- **Tech stack**: Swift/SwiftUI native — no Electron, no web technologies. Must feel like a native macOS app.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| TOML for config | Human-readable, supports inline scripts and complex config | — Pending |
| Script output for hooks | Scripts emit special format for real-time updates | — Pending |
| Polling as fallback | Some scripts can't push updates, polling provides alternative | — Pending |

---
*Last updated: 2026-01-20 after initialization*
