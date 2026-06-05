# Phase 11: Subtask Orchestration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 11-subtask-orchestration
**Areas discussed:** Subtask TOML schema, Dynamic spawn grammar, Live progress surface, Failure semantics

---

## Subtask TOML schema

### Command form
| Option | Description | Selected |
|--------|-------------|----------|
| Reuse ScriptConfig (inline/file) | Same inline-or-file-path model as actions; lets subtasks point at script files | ✓ |
| Inline cmd string only | `cmd = "..."` one-liner; no file-path support | |

### Run mode location
| Option | Description | Selected |
|--------|-------------|----------|
| Implied by depends_on | No mode key; scheduler derives waves from dependency graph | ✓ |
| Top-level mode key | `subtask_mode = "parallel"\|"sequential"` on action | |

### Required vs optional fields
| Option | Description | Selected |
|--------|-------------|----------|
| id + cmd required; name/timeout/depends_on optional | name defaults to id, timeout default fallback | ✓ |
| id + name + cmd all required | Force explicit display name | |

**User's choice:** ScriptConfig command, depends_on-implied run mode, id+cmd required.
**Notes:** Keeps subtask config consistent with existing action TOML.

---

## Dynamic spawn grammar

### Value format
| Option | Description | Selected |
|--------|-------------|----------|
| JSON payload | `EXMEN:subtask={"id":...}` | |
| Delimited positional | `EXMEN:subtask=id\|name\|cmd` | |
| TOML inline table (user-proposed) | `EXMEN:subtask={ id = "build", cmd = "make" }` — same decode path as `[[subtasks]]` | ✓ |

### Dynamic depends_on
| Option | Description | Selected |
|--------|-------------|----------|
| Yes — reference any known id | Scheduler re-computes wave; unknown id errors that subtask | ✓ |
| No — always immediate | No deps; spawned into running pool | |

### Duplicate id handling
| Option | Description | Selected |
|--------|-------------|----------|
| Ignore duplicate (idempotent) | Dropped + logged; safe against re-emit loops | ✓ |
| Error the orchestration | Hard error | |

**User's choice:** TOML inline table (asked "can it be nested toml structure?" — confirmed yes, unifies static/dynamic decode into one SubtaskConfig), dynamic depends_on allowed, duplicate id ignored.
**Notes:** Avoids introducing JSON as a second config syntax; TOML inline tables are single-line by spec, matching the line-based hook protocol.

---

## Live progress surface

### Surface
| Option | Description | Selected |
|--------|-------------|----------|
| Separate progress window | Reuse ServiceOutputWindow pattern; @Published model survives Phase 12/13 | ✓ |
| Menu-only inline | Risks rework (Phase 13 overhaul); invisible when menu closed | |
| Popup at end only | Violates ORCH-03 (live status required) | |

### Row detail
| Option | Description | Selected |
|--------|-------------|----------|
| Status dot + name + elapsed | Mirrors Phase 8 service-row convention | ✓ |
| + live output tail | Streaming last-line per subtask; heavier UI | |

### Percentage support (follow-up question)
| Option | Description | Selected |
|--------|-------------|----------|
| Orchestration % only | Aggregate completed/total + % bar | |
| Orchestration % + opt-in per-subtask % | Plus subtask self-reports `EXMEN:progress=N` | ✓ |
| No % at all | Counts only | |

**User's choice:** Separate progress window, dot+name+elapsed rows, orchestration % bar + opt-in per-subtask % via hook.
**Notes:** User asked whether progress would support percentage. Clarified orchestration % is free (completed/total); per-subtask % requires script self-reporting. User chose to support both.

---

## Failure semantics

### Failed dependency → dependents
| Option | Description | Selected |
|--------|-------------|----------|
| Skip dependents (cascade) | Marked skipped, transitive; reported distinctly | ✓ |
| Run dependents anyway | depends_on orders timing only | |

### Abort on failure?
| Option | Description | Selected |
|--------|-------------|----------|
| Run all independent branches | Failure cascades only to own dependents | ✓ |
| Abort on first failure | Fail-fast cancel all running/pending | |

### Overall verdict
| Option | Description | Selected |
|--------|-------------|----------|
| Fail if any failed; note skipped | N succeeded / M failed / K skipped; error notification | ✓ |
| Succeed unless all failed | Lenient | |

**User's choice:** Cascade-skip dependents, run independent branches to completion, overall fails if any failed.
**Notes:** Skipped distinguished from failed in summary; no global fail-fast in v1.

---

## Claude's Discretion

- Concurrency cap default value + scope (global/per-action/both) — ORCH-06 requires cap honored, exact knob left to planner.
- Aggregated summary popup/notification exact layout.
- Per-subtask timeout default + cancellation mechanism details (process-group kill, no zombies).
- Progress window default size/appearance/auto-close.
- `EXMEN:progress=N` clamping/validation outside 0–100.

## Deferred Ideas

- Global fail-fast / abort-on-first-failure mode — rejected for v1, possible future per-action policy.
- Per-subtask live output tail in progress window — deferred (chose dot+elapsed for v1).
- HUD overlay (Phase 12) and inline menu progress (Phase 13) — out of Phase 11 scope; Phase 11 provides the @Published model they bind to.
