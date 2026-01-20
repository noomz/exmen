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
- [ ] **Phase 5: Auto-Hide Menu** — Hide menu on action click with per-action override

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
- [ ] 05-01: Add hide_on_click config and implement menu dismissal

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete | 2026-01-20 |
| 2. Config & Discovery | 2/2 | Complete | 2026-01-20 |
| 3. Script Execution | 2/2 | Complete | 2026-01-20 |
| 4. Hook System | 2/2 | Complete | 2026-01-20 |
| 5. Auto-Hide Menu | 0/1 | Planned | — |
