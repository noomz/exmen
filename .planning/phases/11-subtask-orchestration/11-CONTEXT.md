# Phase 11: Subtask Orchestration - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

An action can run multiple subtasks — declared in TOML (`[[subtasks]]`) or
spawned dynamically by the parent script via the hook protocol — in parallel
with dependency ordering, live per-subtask progress in a dedicated window, and
an aggregated pass/fail summary. Honors a concurrency cap and per-subtask
timeout with clean child-process cancellation (no zombies).

Tech approach is locked by ROADMAP.md (streaming `Process` runner via
`AsyncStream`, wave topo-sort scheduler with cycle detection, `@MainActor`
`SubtaskOrchestrator`, extended `HookParser`). This context captures the
user-facing HOW decisions, not the technical implementation.

</domain>

<decisions>
## Implementation Decisions

### Subtask TOML schema (ORCH-01, ORCH-02)
- **D-01:** Subtasks declared as a `[[subtasks]]` array on the action.
- **D-02:** A subtask's command reuses the existing `ScriptConfig` model
  (inline content OR file path) — same inline-or-file pattern as actions, so
  subtasks can point at script files. **At rest there is exactly one command
  representation: an embedded `ScriptConfig`.**
  - **D-02a (refined 2026-06-05, resolves D-02↔D-05 conflict):** `cmd` is a
    *decode-time convenience alias only*, not a separate stored field. When the
    TOML provides `cmd = "make"`, the decoder normalizes it into
    `ScriptConfig(type: .inline, content: "make")`. The struct stores only the
    `ScriptConfig` — there is no `cmd: String?` property. Both static
    `[[subtasks]]` and dynamic `EXMEN:subtask=` accept either the `cmd`
    shorthand OR a full `script = { type = …, … }` table; both decode through
    the single shared `SubtaskConfig` path (D-06). This keeps the terse user
    syntax from D-05 while honoring D-02's "one command model at rest".
    Providing both `cmd` and `script` on one subtask → decode error.
- **D-03:** Required fields: `id` (used for `depends_on` references) and the
  command (via `ScriptConfig`). Optional: `name` (defaults to `id`), `timeout`
  (falls back to a default), `depends_on`.
- **D-04:** No separate run-mode key. Run mode is **implied by `depends_on`**:
  subtasks with no dependency run concurrently (wave 0); `depends_on` creates
  ordering. The scheduler derives waves from the dependency graph. One
  mechanism, no redundant `subtask_mode` config.

### Dynamic subtask spawn grammar (ORCH-04)
- **D-05:** Parent emits `EXMEN:subtask=<TOML inline table>`, e.g.
  `EXMEN:subtask={ id = "build", cmd = "make", depends_on = ["fetch"] }`.
  Chosen over JSON to avoid introducing a second config syntax — the project
  already uses TOMLDecoder, and TOML inline tables are single-line by spec
  (matches the line-based hook protocol).
- **D-06:** The dynamic value decodes into the **same `SubtaskConfig` struct**
  used by `[[subtasks]]`. Parser wraps the value as `subtask = <value>` and
  runs it through TOMLDecoder. Static and dynamic subtasks share one model and
  one validator (single decode path).
- **D-07:** A dynamically-spawned subtask **may declare `depends_on`** against
  any known id (declared or earlier-spawned). The scheduler re-computes its
  wave at runtime. An unknown `depends_on` id → error *that* subtask (not the
  whole orchestration).
- **D-08:** Duplicate id (parent re-emits an existing subtask id) → **ignored
  idempotently** and logged. Safe against scripts that re-emit in a loop.

### Live progress surface (ORCH-03)
- **D-09:** Per-subtask status shows in a **separate progress window**, reusing
  the Phase 8 `ServiceOutputWindow` pattern (standalone window, survives menu
  close). Bound to an `@Published` progress model so Phase 12 (HUD) and Phase
  13 (inline menu progress) can bind to the same model later without rework.
- **D-10:** Each subtask row shows: **colored status dot + name + running
  elapsed time**. States: pending / running / succeeded / failed / skipped.
  Mirrors the Phase 8 service-row status convention (green/gray/yellow/red).
  Running state uses an indeterminate spinner.
- **D-11:** **Orchestration-level percentage** is shown in the window header
  (aggregate `completed/total` + % bar) — always correct, free to compute.
- **D-12:** **Opt-in per-subtask percentage**: a subtask script may emit
  `EXMEN:progress=N` (0–100) to render its own progress bar. Exmen maps the
  emitting child process → its subtask id natively (Exmen spawned it). Without
  this, a subtask stays discrete (dot + spinner). Extends the hook parser.

### Failure semantics (feeds ORCH-05)
- **D-13:** When a subtask **fails**, its dependents are marked **`skipped`**
  and never run (cascades transitively to their dependents). Skipped is
  reported distinctly from failed.
- **D-14:** A failure does **NOT abort the whole orchestration**. It cascades
  only to its own dependents; unrelated independent branches keep running to
  completion. Maximizes useful work; full picture at end. (No global
  fail-fast cancel in v1.)
- **D-15:** Overall verdict = **failed if ≥1 subtask failed**. Aggregated
  summary shows counts: `N succeeded / M failed / K skipped`. Notification
  severity = error on any failure. (ORCH-05 popup + notification via existing
  `OutputService`.)

### Claude's Discretion
- Concurrency cap **default value** (suggest a small default like 4) and
  whether it's global, per-action, or both. ORCH-06 requires the cap is
  honored; the exact knob/default is the planner's call.
- Aggregated summary **popup/notification exact layout** (per-subtask line
  format, duration display, ordering).
- Per-subtask **timeout default value** and the cancellation mechanism details
  (process-group kill to avoid zombies — ORCH-06).
- Progress window default size, appearance, and whether it auto-closes on
  completion.
- Whether `EXMEN:progress=N` is rejected/clamped outside 0–100.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/ROADMAP.md` §"Phase 11: Subtask Orchestration" — goal, locked tech
  (AsyncStream runner, wave topo-sort + cycle detection, `@MainActor`
  orchestrator, extended HookParser), 5 success criteria.
- `.planning/REQUIREMENTS.md` — ORCH-01 … ORCH-06 acceptance text.

### Existing code to extend/reuse (Phase 8 precedent)
- `Exmen/Services/ScriptRunner.swift` — current fire-and-forget runner
  (`withCheckedThrowingContinuation`, buffers full output, single timeout,
  `terminate()` on timeout, NSLock double-resume guard). NOT streaming — the
  new subtask runner must stream (`AsyncStream`) for live progress.
- `Exmen/Services/HookParser.swift` — current `EXMEN:key=value` parser
  (keys: title/status/badge/icon; parses AFTER full output). Must extend for
  `EXMEN:subtask=` (inline-table) and `EXMEN:progress=` and parse the stream
  live, not post-hoc.
- `Exmen/Services/OutputHandler.swift` (`OutputService`) — clipboard /
  notification / popup handlers. Reuse for ORCH-05 aggregated summary.
- `Exmen/Models/ActionConfig.swift` — `ActionConfig`, `ScriptConfig`,
  `OutputConfig`. Add `subtasks: [SubtaskConfig]?`; `SubtaskConfig` embeds a
  `ScriptConfig` for its command.
- `Exmen/Models/HookUpdate.swift` — `HookUpdate` struct + `HookConfig`. Pattern
  for new subtask/progress hook payloads.
- `Exmen/Views/ServiceOutputWindow.swift` — window pattern to reuse for the
  progress window.
- `Exmen/Services/ServiceManager.swift` / `Exmen/Services/ActionService.swift`
  — `@MainActor` singleton + `@Published` patterns for the new
  `SubtaskOrchestrator`.
- `.planning/phases/08-new-feature-to-support-long-life-arbitrary-cli-programs-as-service/08-CONTEXT.md`
  — prior decisions: status-dot color convention, separate-window output,
  clean process lifecycle.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ScriptConfig` (inline/file + `resolvedContent()`): embed directly in
  `SubtaskConfig` for the subtask command (D-02).
- `ServiceOutputWindow`: window scaffold for the progress window (D-09).
- `OutputService`: aggregated summary delivery — notification + popup (D-15).
- Phase 8 status-dot colors (green=running, gray=stopped/pending,
  yellow=starting, red=crashed/failed): reuse the convention (D-10).
- `@MainActor` + `@Published` singleton pattern (`ActionService`,
  `ServiceManager`): blueprint for `SubtaskOrchestrator`.

### Established Patterns
- Hook protocol `EXMEN:key=value` — extend with `subtask=` and `progress=`
  keys; new branch when the value starts with `{` (TOML inline table).
- TOMLDecoder for all config — dynamic subtask uses the SAME decode path
  (D-06), no JSON.
- `ScriptRunner` is the anti-pattern reference: it buffers output and is
  fire-and-forget. The subtask runner must stream stdout/stderr concurrently
  via `AsyncStream` to drive live status + per-subtask progress.

### Integration Points
- `ActionConfig` gains `subtasks: [SubtaskConfig]?`; `ConfigLoader` parses it.
- New `SubtaskOrchestrator` (`@MainActor`, `@Published` progress model): wave
  topo-sort scheduler, bounded concurrency, per-subtask timeout, cascade-skip
  on dependency failure (D-13/D-14), child-process-group kill on
  timeout/cancel (ORCH-06).
- New streaming subtask runner feeding the orchestrator (replaces
  `ScriptRunner` for this path).
- `HookParser` streaming extension feeds dynamic spawn (D-05–D-08) and
  per-subtask progress (D-12) into the orchestrator live.
- Progress window view binds to the orchestrator's `@Published` model (D-09).
- On completion, orchestrator hands the aggregate to `OutputService` (D-15).

</code_context>

<specifics>
## Specific Ideas

- Dynamic spawn syntax the user explicitly wanted: a TOML **inline table** as
  the hook value, e.g. `EXMEN:subtask={ id = "build", cmd = "make" }` — to keep
  one config language and unify static/dynamic decode.
- Progress window should feel like the Phase 8 service output window (familiar,
  standalone, survives menu close).
- Skipped ≠ failed: the summary must distinguish cascade-skipped subtasks from
  genuinely failed ones.

</specifics>

<deferred>
## Deferred Ideas

- **Global fail-fast / abort-on-first-failure mode** — considered and rejected
  for v1 (D-14 runs independent branches to completion). Could be a future
  opt-in per-action policy.
- **Per-subtask live output tail** in the progress window — considered; chose
  dot+name+elapsed for v1 (D-10). Richer streaming output is a later UI
  enhancement (overlaps Phase 13 menu overhaul / future).
- HUD overlay and inline menu progress are explicitly **Phase 12 and Phase 13**
  — Phase 11 only provides the `@Published` model they will bind to.

</deferred>

---

*Phase: 11-subtask-orchestration*
*Context gathered: 2026-06-05*
