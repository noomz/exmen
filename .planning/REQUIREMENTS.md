# Requirements: Exmen v1.2 — Polish & Power

Scoped requirements for milestone v1.2. REQ-IDs continue per category.

## v1.2 Requirements

### Subtask Orchestration (ORCH)

- [x] **ORCH-01**: User can define an action with multiple subtasks in TOML (`[[subtasks]]` with id, name, cmd, optional timeout)
- [x] **ORCH-02**: User can set a run mode (parallel/sequential) and `depends_on` per subtask; Exmen schedules waves and runs independent subtasks concurrently
- [x] **ORCH-03**: User sees live per-subtask status (pending/running/succeeded/failed) while an orchestration runs
- [x] **ORCH-04**: A parent script can spawn subtasks dynamically at runtime via the hook protocol (`EXMEN:subtask=…`)
- [x] **ORCH-05**: User gets an aggregated pass/fail summary via output handlers (popup + notification) when orchestration completes
- [x] **ORCH-06**: Orchestration honors a concurrency cap and per-subtask timeout, and cancels child processes cleanly (no zombies)

### On-Screen Summon (SUMMON)

- [ ] **SUMMON-01**: User can summon Exmen via a global keyboard shortcut from any frontmost app
- [ ] **SUMMON-02**: User can configure the summon shortcut in Settings (recorder UI)
- [ ] **SUMMON-03**: Summon opens a centered, Spotlight-style command palette to search and run actions
- [ ] **SUMMON-04**: Palette supports keyboard navigation (type to filter, arrow keys, Enter to run, Esc to dismiss)
- [ ] **SUMMON-05**: A HUD overlay shows live running task/subtask progress on-screen and auto-hides on completion

### Raycast Integration (RAYCAST)

- [ ] **RAYCAST-01**: User can list Exmen actions in Raycast and run a selected action
- [ ] **RAYCAST-02**: User can list Exmen services in Raycast and start/stop/restart them
- [ ] **RAYCAST-03**: Raycast shows async feedback (toast) and refreshes state after a run/mutation
- [ ] **RAYCAST-04**: The `exmen` CLI exposes stable `--json` output for all list/status commands the extension consumes
- [ ] **RAYCAST-05**: The extension is bundled in the repo as a local/importable extension with setup docs

### Menu Bar UI/UX (UIUX)

- [ ] **UIUX-01**: User can type to search/filter actions and services in the menu
- [ ] **UIUX-02**: User can group actions into sections/categories
- [ ] **UIUX-03**: Menu shows inline live progress (spinner/bar) for running actions/subtasks
- [ ] **UIUX-04**: Menu reflects a refreshed visual design (icons, spacing, color, light/dark, status visuals)

## Future Requirements (deferred)

- Result feedback channel for dynamic subtasks (child→parent via `EXMEN_RESULT_FIFO`) — deferred until a concrete use case needs it
- Raycast Store submission (icon/screenshots/CHANGELOG + review) — after local extension UX is stable
- Palette: fuzzy ranking / recent-actions, run services from palette — post-v1.2

## Out of Scope

- Cloud sync — local-only (carried from v1.0)
- Plugin marketplace — no community sharing platform (carried from v1.0)
- Arbitrary global hotkeys per-action (only the summon shortcut is global) — keeps permission model simple

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| ORCH-01 | 11 | Complete |
| ORCH-02 | 11 | Complete |
| ORCH-03 | 11 | Complete |
| ORCH-04 | 11 | Complete |
| ORCH-05 | 11 | Complete |
| ORCH-06 | 11 | Complete |
| SUMMON-01 | 12 | Pending |
| SUMMON-02 | 12 | Pending |
| SUMMON-03 | 12 | Pending |
| SUMMON-04 | 12 | Pending |
| SUMMON-05 | 12 | Pending |
| UIUX-01 | 13 | Pending |
| UIUX-02 | 13 | Pending |
| UIUX-03 | 13 | Pending |
| UIUX-04 | 13 | Pending |
| RAYCAST-01 | 14 | Pending |
| RAYCAST-02 | 14 | Pending |
| RAYCAST-03 | 14 | Pending |
| RAYCAST-04 | 14 | Pending |
| RAYCAST-05 | 14 | Pending |
