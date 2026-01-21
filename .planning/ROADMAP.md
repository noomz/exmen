# Roadmap: Exmen

## Overview

Build a macOS menu bar app for zero-friction script execution. Start with a solid SwiftUI foundation, add TOML config parsing and folder discovery, implement script execution with flexible output handling, then layer on the hook system for dynamic updates.

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Foundation** — SwiftUI menu bar app scaffold with basic UI
- [x] **Phase 2: Config & Discovery** — TOML parsing and script folder discovery
- [x] **Phase 3: Script Execution** — Run scripts with output handling
- [x] **Phase 4: Hook System** — Dynamic updates via script output and polling
- [x] **Phase 5: Auto-Hide Menu** — Hide menu on action click with per-action override
- [x] **Phase 6: IPC Server** — External communication interface for tools like sketchybar
- [x] **Phase 7: Global Config** — Central config.toml for action ordering and enable/disable
- [ ] **Phase 7.1: UI Improvements** — More compact action list and better popup layout (INSERTED)

## Phase Details

### Phase 1: Foundation
**Goal**: Working menu bar app with static action list and basic UI structure
**Depends on**: Nothing (first phase)
**Research**: Likely (macOS menu bar API)
**Research topics**: NSStatusItem/MenuBarExtra in SwiftUI, menu bar app lifecycle, proper app structure for menu bar-only apps
**Plans**: TBD

Plans:
- [x] 01-01: Xcode project setup and menu bar app scaffold
- [x] 01-02: Basic menu UI with static action list

### Phase 2: Config & Discovery
**Goal**: Load actions from TOML config files and discover scripts in designated folder
**Depends on**: Phase 1
**Research**: Likely (TOML parsing in Swift)
**Research topics**: Swift TOML libraries (TOMLKit, Yams alternatives), file system monitoring for folder changes
**Plans**: TBD

Plans:
- [x] 02-01: TOML config parsing and action model
- [x] 02-02: Script folder discovery and file watching

### Phase 3: Script Execution
**Goal**: Execute scripts and handle output (clipboard, notification, popup)
**Depends on**: Phase 2
**Research**: Unlikely (Process/shell execution is standard Swift)
**Plans**: TBD

Plans:
- [x] 03-01: Script execution engine
- [x] 03-02: Output handling (clipboard, notification, popup)

### Phase 4: Hook System
**Goal**: Scripts can push updates (title, status, thumbnail) and optional polling fallback
**Depends on**: Phase 3
**Research**: Unlikely (parsing script output, timers — established patterns)
**Plans**: TBD

Plans:
- [x] 04-01: Script output parsing for dynamic updates
- [x] 04-02: Polling fallback for status refresh

### Phase 5: Auto-Hide Menu
**Goal**: Hide menu popup when action is clicked, with per-action override option
**Depends on**: Phase 4
**Research**: Unlikely (standard SwiftUI/AppKit patterns)
**Plans**: TBD

Plans:
- [x] 05-01: Add hide_on_click config and implement menu dismissal

### Phase 6: IPC Server
**Goal**: Expose Exmen functionality to external tools (sketchybar, scripts, etc.) via IPC
**Depends on**: Phase 5
**Research**: Likely (IPC mechanisms on macOS)
**Research topics**: Unix domain sockets vs XPC vs HTTP localhost, CLI client pattern (like aerospace, yabai), message format (JSON-RPC, plain text)
**Plans**: TBD

Example use cases:
- `exmen list-actions` — List available actions
- `exmen run <action-name>` — Execute an action
- `exmen status <action-name>` — Get action status
- Integration with sketchybar for dynamic widgets

Plans:
- [x] 06-01: Socket server + command handlers
- [x] 06-02: CLI client tool

### Phase 7: Global Config
**Goal**: Add ~/.config/exmen/config.toml to control action ordering and enable/disable actions
**Depends on**: Phase 6
**Research**: Unlikely (TOML parsing already implemented)
**Plans**: TBD

Features:
- `~/.config/exmen/config.toml` for global settings
- Action ordering: specify display order of actions
- Enable/disable: toggle actions without deleting config files

Plans:
- [x] 07-01: Global config loader and action ordering

### Phase 7.1: UI Improvements (INSERTED)
**Goal**: Make action list more compact to show more items, improve popup to show full content
**Depends on**: Phase 7
**Research**: Unlikely (SwiftUI layout adjustments)
**Plans**: TBD

Issues identified:
- Action rows have excessive padding/spacing, only ~4 items visible
- Popup has wasted space, content area could be larger
- Need more compact row design while maintaining readability

Plans:
- [ ] 07.1-01: Compact action rows and improved popup layout

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete | 2026-01-20 |
| 2. Config & Discovery | 2/2 | Complete | 2026-01-20 |
| 3. Script Execution | 2/2 | Complete | 2026-01-20 |
| 4. Hook System | 2/2 | Complete | 2026-01-20 |
| 5. Auto-Hide Menu | 1/1 | Complete | 2026-01-20 |
| 6. IPC Server | 2/2 | Complete | 2026-01-21 |
| 7. Global Config | 1/1 | Complete | 2026-01-21 |
| 7.1 UI Improvements | 0/1 | Inserted | — |
