# Phase 11 — Resume Notes

**Paused:** 2026-07-31
**Session:** UAT of Phase 11 (subtask orchestration) via `/gsd-verify-work 11`
**State:** 7/9 UAT tests pass · 2 gaps fixed · 1 gap open · 1 test blocked on a human

---

## Where things stand

`11-UAT.md` is the source of truth (`status: partial`). Summary:

| # | Test | Result |
|---|------|--------|
| 1 | Cold start — build & launch | pass (automated) |
| 2 | Declarative subtasks run (ORCH-01) | pass |
| 3 | Parallel + depends_on ordering (ORCH-02) | pass |
| 4 | Live progress window (ORCH-03) | pass |
| 5 | **Dynamic subtask spawn (ORCH-04)** | **pending — needs a menu click** |
| 6 | Per-subtask progress bar (D-12) | pass |
| 7 | Aggregated popup + notification (ORCH-05) | pass |
| 8 | Timeout kills process group, no zombies (ORCH-06) | pass (automated) |
| 9 | Run a subtask action via CLI/IPC | issue → **fixed**, verified |

Gaps: **G-11-9 resolved**, **G-11-10 resolved**, **G-11-11 open**.

---

## Pick up here

### 1. Test 5 — the only outstanding UAT item

Requires a human; `osascript` has no assistive access on this machine (`-25211`).

Click **"Subtask Dynamic Demo"** in the Exmen menu and confirm:
- rows "Dynamic One" and "Dynamic Two" appear *at runtime* (ORCH-04 / D-05)
- the repeated id `dyn1` does **not** add a second row (D-08 idempotency)

Fixture: `~/.config/exmen/actions/subtask-dynamic-demo.toml` — added during this session
purely for the test. Safe to delete.

### 2. G-11-11 — the CLI has no build

`exmen-cli/main.swift` is in no build system:
- `grep -c exmen-cli Exmen.xcodeproj/project.pbxproj` → `0`
- `Package.swift:12-19` declares one `executableTarget` named `Exmen` at `path: "Exmen"` — the GUI app
- no Makefile, no build script, no README instructions

**The trap that cost this session hours:** `swift build` emits `.build/debug/Exmen` (the GUI
app), and on a case-insensitive filesystem that answers to `.build/debug/exmen`. Running it
launches a SECOND app instance which unlinks and rebinds the IPC socket, orphaning the real
one. It presents as random socket flakiness (hangs, then `ECONNREFUSED`) and as a
`UNUserNotificationCenter` abort at `OutputHandler.swift:58` (unbundled launches cannot use it).

Fix: add an SPM `executableTarget` for `exmen-cli/`, with a product name that does **not**
collide case-insensitively with `Exmen`.

### 3. `~/.local/bin/exmen` is stale — decision needed

Untouched, dated **2026-03-20**. It predates the G-11-9 work, so `--wait`,
`orchestration-status`, and subtask runs are NOT available in the user's shell yet.
Deliberately not overwritten. Rebuild with:

```
swiftc -O exmen-cli/main.swift -o ~/.local/bin/exmen
```

### 4. Unruled design question

The progress window header reads `4/4 · 100%` with a full bar even when only 1 of 4
subtasks succeeded (1 failed, 1 skipped, 1 timed out). Spec-correct per D-11
(`completed/total`), but reads as success. Candidate for Phase 13's visual refresh.
User was asked, has not ruled.

---

## Code changed this session (UNCOMMITTED)

| File | Change |
|------|--------|
| `Exmen/Services/CommandHandler.swift` | G-11-9: `runAction` branches on `action.subtasks` into new `runSubtaskAction`; new `OrchestrationStatusInfo` + `.orchestration` ResponseData case; new `orchestration-status` command; `deliverSummary` for CLI-triggered runs; `Request.wait` field |
| `Exmen/Services/SocketServer.swift` | G-11-10: `acceptConnection` → `acceptPendingConnections` with an accept drain loop; O_NONBLOCK listener; O_NONBLOCK cleared per accepted socket; per-client global queue; backlog 5 → 64 |
| `exmen-cli/main.swift` | `run <name> --wait` (polls to completion, exits non-zero on failure); `orchestration-status [--json]`; usage/examples updated |
| `.planning/phases/11-subtask-orchestration/11-UAT.md` | new — full UAT record |
| `.planning/phases/11-subtask-orchestration/11-RESUME.md` | new — this file |

Outside the repo: `~/.config/exmen/actions/subtask-dynamic-demo.toml` (test fixture).

**Nothing has been committed.** The working tree also carries pre-existing noise: a tracked
`build/` tree with many modified artifacts, a deleted `Exmen-v1.1.0.zip`, and an untracked
`Exmen-v1.1.1.zip`. Any commit should select paths explicitly.

---

## Verification evidence (all re-run clean at pause time)

- `xcodebuild build -scheme Exmen -configuration Release` → BUILD SUCCEEDED
- `xcodebuild test -scheme Exmen` → **84/84**, TEST SUCCEEDED
- `exmen run "Generate Phone Number"` → `0800003243`, exit 0 (plain path, no regression)
- `exmen run "Subtask Demo"` → `Started: Subtask Demo (4 subtasks)`, exit 0, 0.127s
- duplicate run mid-flight → `Already running: Subtask Demo`, exit 0 (idempotent, not an error)
- `exmen run "Subtask Demo" --wait` → 0/4 → 1/4 → 4/4, `1 succeeded, 2 failed, 1 skipped`, **exit 1**
- `exmen orchestration-status` → `idle — last run: 1 succeeded, 2 failed, 1 skipped`
- socket: **40 sequential** → 40 ok / 0 fail; **25 concurrent** → 25 ok / 0 fail; still responsive
  (previously wedged permanently at ~4 connections)
- zombies: no surviving `sleep`, no `<defunct>`

---

## How to test this app without tripping over yourself

1. Launch **only** via `open -a <path>/Exmen.app` — never the binary directly
   (`.../Contents/MacOS/Exmen`), which aborts in `UNUserNotificationCenter`.
2. Never run `.build/debug/exmen` — it is the GUI app, not the CLI (see G-11-11).
3. Before each test round, confirm exactly one instance:
   `lsof -U | grep -c exmen.sock` → must be `1`. More than one means instances are
   fighting over the socket and every result is suspect.
4. To reset: quit, `pkill -x Exmen`, `rm -f ~/.config/exmen/exmen.sock`, relaunch.

---

## Blocked / not done

- Test 5 (ORCH-04 dynamic spawn) — needs a human click
- G-11-11 — CLI build target not created (scope call not yet made)
- `~/.local/bin/exmen` not rebuilt (deliberate — user's binary, not overwritten)
- Nothing committed
- Phase 11 `VERIFICATION.md` still missing, so the phase remains `executed`, not `complete`.
  `/gsd-progress` will keep routing to `/gsd-execute-phase 11` until it exists.
