# Roadmap: Exmen

## Overview

A macOS menu bar app for zero-friction script execution. Solid SwiftUI
foundation, TOML config + folder discovery, script execution with flexible
output, hook system for dynamic updates, and (v1.1) managed long-running CLI
services with full PTY interaction and CLI control.

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7.1 (shipped, tag v1.0.0)
- ✅ **v1.1 Services & CLI** — Phases 8-10 (shipped 2026-03-20, tag v1.1.0)

## Phases

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
