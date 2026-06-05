# Roadmap: Exmen

## Overview

A macOS menu bar app for zero-friction script execution. Solid SwiftUI
foundation, TOML config + folder discovery, script execution with flexible
output, hook system for dynamic updates, and (v1.1) managed long-running CLI
services with full PTY interaction and CLI control.

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7.1 (shipped, tag v1.0.0)
- ✅ **v1.1 Services & CLI** — Phases 8-10 (shipped 2026-03-20, tag v1.1.0)
- 🚧 **v1.2 Polish & Power** — Phases 11-14 (in progress)

## Phases

### 🚧 v1.2 Polish & Power (Phases 11-14)

- [ ] Phase 11: Subtask Orchestration (6 plans) — declarative + dynamic parallel subtasks with live feedback
- [ ] Phase 12: Global Summon — Palette + HUD (0 plans) — global hotkey, command palette, progress overlay
- [ ] Phase 13: Menu Bar UI/UX Overhaul (0 plans) — search, grouping, inline progress, visual refresh
- [ ] Phase 14: Raycast Integration (0 plans) — CLI `--json` + Raycast extension for actions/services

#### Phase 11: Subtask Orchestration

**Goal**: An action can run multiple subtasks — declared in TOML or spawned dynamically by the parent script — in parallel with dependency ordering, live per-subtask progress, and an aggregated result.
**Depends on**: Phase 10 (existing ScriptRunner, HookParser, OutputService)
**Requirements**: ORCH-01, ORCH-02, ORCH-03, ORCH-04, ORCH-05, ORCH-06
**Tech**: streaming `Process` runner (`AsyncStream`, concurrent stdout/stderr drain), `[[subtasks]]` TOML schema, wave topo-sort scheduler with cycle detection, `@MainActor SubtaskOrchestrator` (bounded concurrency + per-subtask timeout), extended `HookParser` for dynamic `EXMEN:subtask=…`.
**Success criteria**:

1. An action with `[[subtasks]]` runs them; parallel subtasks run concurrently and `depends_on` gates dependents correctly.
2. Per-subtask state (pending/running/succeeded/failed) updates live during the run.
3. A parent script emitting `EXMEN:subtask=…` spawns subtasks at runtime that run on the same engine.
4. On completion a popup + notification show an aggregated pass/fail summary.
5. Concurrency cap is honored; a timeout cancels the subtask and its child process with no zombie processes.

Plans:

- [x] 11-01-PLAN.md — Wave 0: ExmenTests target, shared scheme, red test suites for ORCH-01..06
- [x] 11-02-PLAN.md — Models: SubtaskConfig (shared static/dynamic decode), SubtaskState/Status, ActionConfig.subtasks
- [ ] 11-03-PLAN.md — Streaming SubtaskRunner + process-group kill (no zombies)
- [ ] 11-04-PLAN.md — HookParser streaming parseLine + subtask/progress keys
- [ ] 11-05-PLAN.md — SubtaskOrchestrator: wave scheduler, concurrency cap, cascade-skip, dynamic spawn, summary
- [ ] 11-06-PLAN.md — SubtaskProgressWindow + MenuContentView wiring + aggregated popup/notification

#### Phase 12: Global Summon — Palette + HUD

**Goal**: Summon Exmen from anywhere with a configurable global shortcut that opens a Spotlight-style command palette, plus an on-screen HUD overlay showing live task/subtask progress.
**Depends on**: Phase 11 (HUD binds to the orchestration progress model)
**Requirements**: SUMMON-01, SUMMON-02, SUMMON-03, SUMMON-04, SUMMON-05
**Tech**: `sindresorhus/KeyboardShortcuts` v2.4.0 (SPM, no Accessibility permission); palette = non-activating borderless `NSPanel` (`canBecomeKey=true`, `NSHostingView`, `@FocusState`, dismiss on Esc/resignKey, centered on active screen); HUD = separate non-key `NSPanel` (`ignoresMouseEvents`, `level=.statusBar`, top-center, auto-hide).
**Success criteria**:

1. The configured global shortcut opens the palette from any frontmost app (including over fullscreen).
2. Palette filters actions as you type; arrows move selection, Enter runs, Esc dismisses.
3. The shortcut is user-editable in Settings via a recorder control.
4. A HUD overlay shows live progress of running tasks/subtasks and auto-hides when all complete.

#### Phase 13: Menu Bar UI/UX Overhaul

**Goal**: Refresh the menu with search/filter, grouped sections, inline live progress, and a polished visual design.
**Depends on**: Phase 11 (inline progress binds to the orchestration/run progress model)
**Requirements**: UIUX-01, UIUX-02, UIUX-03, UIUX-04
**Tech**: SwiftUI search field + filtering over actions/services; section grouping (category metadata from TOML/global config); inline spinner/progress in `ActionRowView`/`ServiceRowView`; visual refresh (icons, spacing, color, light/dark, status dots).
**Success criteria**:

1. Typing in the menu filters actions and services live.
2. Actions display grouped into sections/categories.
3. Running actions/subtasks show inline progress (spinner/bar) in the menu.
4. The menu reflects the refreshed visual design in both light and dark mode.

#### Phase 14: Raycast Integration

**Goal**: A Raycast extension lists Exmen actions and services and runs/controls them via the existing CLI, with async toast feedback — backed by complete, stable CLI `--json` output.
**Depends on**: Phase 10 (CLI/IPC); independent of 11-13
**Requirements**: RAYCAST-01, RAYCAST-02, RAYCAST-03, RAYCAST-04, RAYCAST-05
**Tech**: extend `exmen` CLI with `--json` for `list-actions`/`status` (services already JSON); Raycast extension (`@raycast/api` 1.104.x + `@raycast/utils` 2.x) with two view commands (Actions, Services) using `useExec` for lists and `execa` for mutations, parsing the `success/data/error` envelope; animated Toast + `revalidate()`; `exmenPath` preference; bundled in repo as importable local extension with README.
**Success criteria**:

1. The CLI returns valid JSON with a stable envelope for list-actions/list-services/status.
2. The Raycast extension lists actions and runs a selected action.
3. The extension lists services and can start/stop/restart them.
4. Mutations show a toast and the list refreshes to the new state.
5. The extension lives in the repo with setup docs and works as an imported local extension.

<details>
<summary>✅ v1.0 MVP (Phases 1-7.1) — SHIPPED (tag v1.0.0)</summary>

- [x] Phase 1: Foundation (2/2 plans) — SwiftUI menu bar scaffold + basic UI
- [x] Phase 2: Config & Discovery (2/2 plans) — TOML parsing + folder discovery/watching
- [x] Phase 3: Script Execution (2/2 plans) — run scripts + output handling
- [x] Phase 4: Hook System (2/2 plans) — dynamic updates + polling fallback
- [x] Phase 5: Auto-Hide Menu (1/1 plan) — hide on click + per-action override
- [x] Phase 6: IPC Server (2/2 plans) — Unix socket server + CLI client
- [x] Phase 7: Global Config (1/1 plan) — config.toml ordering + enable/disable
- [x] Phase 7.1: UI Improvements (1/1 plan) — compact rows + better popup (INSERTED)

Full details: see MILESTONES.md (v1.0 archived retroactively at v1.1 close)

</details>

<details>
<summary>✅ v1.1 Services & CLI (Phases 8-10) — SHIPPED 2026-03-20 (tag v1.1.0)</summary>

- [x] Phase 8: Long-Running CLI Services (3/3 plans) — SwiftTerm PTY service engine, lifecycle, UI
- [x] Phase 9: Service Context Menu (0 plans) — satisfied by Phase 8
- [x] Phase 10: CLI Service Manipulation (1/1 plan) — list/start/stop/restart/status commands

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Foundation | v1.0 | 2/2 | Complete | 2026-01-20 |
| 2. Config & Discovery | v1.0 | 2/2 | Complete | 2026-01-20 |
| 3. Script Execution | v1.0 | 2/2 | Complete | 2026-01-20 |
| 4. Hook System | v1.0 | 2/2 | Complete | 2026-01-20 |
| 5. Auto-Hide Menu | v1.0 | 1/1 | Complete | 2026-01-20 |
| 6. IPC Server | v1.0 | 2/2 | Complete | 2026-01-21 |
| 7. Global Config | v1.0 | 1/1 | Complete | 2026-01-21 |
| 7.1 UI Improvements | v1.0 | 1/1 | Complete | 2026-01-21 |
| 8. Long-Running Services | v1.1 | 3/3 | Complete | 2026-03-11 |
| 9. Service Context Menu | v1.1 | 0/0 | Complete | 2026-03-20 |
| 10. CLI Service Manipulation | v1.1 | 1/1 | Complete | 2026-03-20 |
| 11. Subtask Orchestration | v1.2 | 2/6 | In Progress|  |
| 12. Global Summon — Palette + HUD | v1.2 | 0/0 | Not started | — |
| 13. Menu Bar UI/UX Overhaul | v1.2 | 0/0 | Not started | — |
| 14. Raycast Integration | v1.2 | 0/0 | Not started | — |
