---
status: partial
phase: 11-subtask-orchestration
source:
  - 11-01-SUMMARY.md
  - 11-02-SUMMARY.md
  - 11-03-SUMMARY.md
  - 11-04-SUMMARY.md
  - 11-05-SUMMARY.md
  - 11-06-SUMMARY.md
started: 2026-07-31T00:00:00Z
updated: 2026-07-31T09:00:00Z
resume: .planning/phases/11-subtask-orchestration/11-RESUME.md
---

## Current Test

number: 5
name: Dynamic Subtask Spawn (ORCH-04)
expected: |
  Click "Subtask Dynamic Demo" in the Exmen menu. Rows "Dynamic One" and
  "Dynamic Two" appear at runtime; the repeated id "dyn1" adds no second row.
awaiting: user response
blocked_on: human — requires a menu-bar click; osascript has no assistive access
fixture: ~/.config/exmen/actions/subtask-dynamic-demo.toml (added 2026-07-31, safe to delete)

## Tests

### 1. Cold Start — Build and Launch
expected: Quit any running Exmen instance. Build fresh (`xcodebuild build -scheme Exmen -destination 'platform=macOS' EXCLUDED_SOURCE_FILE_NAMES="*.metal"`) and launch. Menu bar icon appears, existing non-subtask actions still list and execute normally (no regression from Phase 11).
result: pass
source: automated
evidence: |
  - `xcodebuild build -scheme Exmen -configuration Release` → ** BUILD SUCCEEDED **
  - `xcodebuild test -scheme Exmen` → 84/84 tests passed, ** TEST SUCCEEDED **
  - Fresh Release build launched; process alive, IPC socket bound.
  - `list-actions` over the Unix socket returns 13 actions including "Subtask Demo".
  - config.toml `order` respected: Generate Thai ID, Generate Phone Number,
    Update Coding Agent, System Status, Check Disk Space, Update Homebrew, then unlisted.
note: |
  Observed during teardown (NOT a Phase 11 defect — SocketServer is Phase 6 code,
  untouched by Phase 11): quitting and immediately relaunching Exmen left the IPC
  socket unusable — the client connected but the app never accepted, then subsequent
  connects returned ECONNREFUSED while the app held the bound fd. Deleting
  ~/.config/exmen/exmen.sock before launch cleared it. Filed as an observation only.

### 2. Declarative Subtasks Run (ORCH-01)
expected: An action TOML declaring `[[subtasks]]` with `id`, `name`, `cmd` runs all subtasks when clicked — not the single-action ScriptRunner path. A progress window opens listing every declared subtask by name.
result: pass
evidence: |
  User ran "Subtask Demo" from the menu. Window titled "Subtask Demo — Subtasks" opened
  listing all four declared subtasks by their TOML `name`: Fetch, Lint (fails),
  Build (skipped — depends on lint), Slow (timeout/zombie check). Screenshot confirmed.

### 3. Parallel Execution + depends_on Ordering (ORCH-02)
expected: Independent subtasks start concurrently (their dots go green/running at the same time). A subtask with `depends_on = ["a"]` does not start until `a` finishes. Wave order is respected.
result: pass
evidence: |
  Wave 0 (Fetch 2s, Lint 1s, Slow 2s) all completed with independent elapsed times.
  "Build" declares depends_on = ["lint"]; lint exited 1, so Build never started —
  0s elapsed, gray/skipped dot. Dependency gating and cascade-skip (D-13/D-14) both hold.

### 4. Live Progress Window (ORCH-03)
expected: While running, the progress window shows per-subtask colored status dots (gray pending/skipped, green running/succeeded, red failed), live-ticking elapsed time, a spinner on running rows, and a header bar with overall completed/total %. The window survives closing the menu-bar menu.
result: pass
evidence: |
  Screenshot of the completed run shows the Phase-8 dot convention exactly:
  green = Fetch (succeeded), red = Lint and Slow (failed), gray = Build (skipped).
  Per-row elapsed rendered (2s / 1s / 0s / 2s). Header shows "Overall progress" with
  a bar and "4/4 · 100%" (D-11). Window is standalone and outlived the menu-bar popover.
note: |
  Verified from the terminal (final) state. Live per-second ticking and the running-row
  spinner were not directly witnessed by the tester in this pass.

### 5. Dynamic Subtask Spawn (ORCH-04)
expected: A parent subtask whose script emits `EXMEN:subtask={id="dyn1", name="Dynamic", cmd="echo hi"}` on stdout causes a new subtask row to appear in the progress window at runtime and run on the same engine. Emitting the same id twice does not duplicate the row.
result: [pending]

### 6. Per-Subtask Progress Bar (D-12)
expected: A subtask emitting `EXMEN:progress=45` on stdout shows a determinate progress bar filled to 45% on its row. Subtasks that emit no progress line show no bar. Out-of-range values (`150`, `-5`) are ignored — the bar stays at its last value.
result: pass
evidence: |
  "Fetch" emits EXMEN:progress=50 then EXMEN:progress=100 and is the only row rendering
  a determinate bar — shown filled at 100%. Lint, Build and Slow emit no progress line
  and render no bar, confirming the bar is opt-in per D-12.
note: Out-of-range rejection (150 / -5) is covered by DynamicSpawnTests, not re-tested manually.

### 7. Aggregated Summary — Popup + Notification (ORCH-05)
expected: Run an action with a deliberately failing subtask (e.g. `cmd = "exit 1"`). On completion a popup AND a macOS notification appear showing `N succeeded / M failed / K skipped`, flagged with error severity. A subtask depending on the failed one is reported as skipped, not failed (cascade skip).
result: pass
evidence: |
  Tester confirmed the popup and the macOS notification both appeared on completion of
  the Subtask Demo run (1 succeeded / 2 failed / 1 skipped). Cascade-skip reporting is
  corroborated by Test 3 — "Build" was reported skipped, not failed, after lint exited 1.

### 8. Timeout Kills Process Group — No Zombies (ORCH-06)
expected: Run an action whose subtask is `sh -c 'sleep 300 & sleep 300'` with `timeout = 5`. After ~5s the subtask goes red/failed. Then `ps -o pid,ppid,pgid,stat -ax | grep sleep` shows no surviving `sleep` processes and no `<defunct>` (zombie) entries. Concurrency cap is honored — no more than `max_concurrent` subtasks run at once.
result: pass
source: automated
evidence: |
  "Slow (timeout/zombie check)" runs `sleep 300 & sleep 300` with timeout = 2.0.
  Screenshot: red/failed dot at 2s — the timeout fired and mapped to the failed state.
  Immediately after, checked from the terminal:
    - `ps -ax -o pid,ppid,pgid,stat,etime,command | grep sleep` → NONE
    - defunct/zombie scan → NONE
    - `pgrep -P <exmen pid>` → no children
  The backgrounded grandchild `sleep` did not survive: process-group kill (ORCH-06) holds.

### 9. Run a Subtask Action via CLI / IPC
expected: `exmen run "Subtask Demo"` executes the action's subtasks through SubtaskOrchestrator, the same engine the menu uses, and returns an aggregated result.
result: issue
reported: "IPC returns {\"error\":\"Action has no script: Subtask Demo\",\"success\":false}. The action is listed by list-actions but cannot be run over the socket."
severity: major
source: automated
evidence: |
  Sent {"command":"run","name":"Subtask Demo"} to ~/.config/exmen/exmen.sock against the
  fresh Release build. Response: {"error":"Action has no script: Subtask Demo","success":false}.
  Root cause is visible in source: CommandHandler.runAction (Exmen/Services/CommandHandler.swift:187-194)
  guards on `action.scriptConfig` and returns early; it has no `action.subtasks` branch.
  Phase 11 (11-06) added the orchestrator branch only to MenuContentView.executeAction
  (Exmen/Views/MenuContentView.swift:103-106), leaving the IPC path on the old single-script path.

## Summary

total: 9
passed: 7
issues: 1
pending: 1
skipped: 0

## Gaps

- gap_id: G-11-9
  truth: "An action declaring [[subtasks]] runs through SubtaskOrchestrator when invoked over the IPC socket, the same as when clicked in the menu."
  status: resolved
  resolved_at: 2026-07-31
  fix: |
    CommandHandler.runAction now branches on `action.subtasks` into runSubtaskAction,
    mirroring MenuContentView.executeAction. Fire-and-return semantics: `handle` runs
    on the main thread and SubtaskOrchestrator.run hops to the main actor on every
    state update, so blocking for completion there would deadlock the orchestration
    being awaited. A new `orchestration-status` command exposes live state, and the
    CLI's `exmen run <name> --wait` polls it to completion.
    A run already in flight returns success ("Already running: …"), never an error.
  verified: |
    - `run "Subtask Demo"` → 0.147s, {"success":true,"message":"Started: Subtask Demo (4 subtasks)"}
    - duplicate `run` while in flight → success=true, "Already running: Subtask Demo (0/4 subtasks complete)"
    - `orchestration-status` mid-run → isRunning=true, 0/4, 0%
    - `xcodebuild build` green (app + CLI), `xcodebuild test` 84/84 green
  verified_cli: |
    Against a clean single instance, using a correctly-built CLI (see G-11-11):
    - `exmen run "Generate Phone Number"` → "0800007732", exit 0 (plain path, no regression)
    - `exmen run "Subtask Demo"` → "Started: Subtask Demo (4 subtasks)", exit 0, 0.085s
    - duplicate `run` while in flight → "Already running: Subtask Demo", exit 0
    - `exmen orchestration-status` → "running — 0/4 subtasks complete (0%)"
    - `exmen run "Subtask Demo" --wait` → ticks 0/4 → 1/4 → 4/4, prints
      "1 succeeded, 2 failed, 1 skipped", **exit 1** (non-zero on failure)
    - after completion: "idle — last run: 1 succeeded, 2 failed, 1 skipped"
    Summary matches the menu-triggered run exactly.

- gap_id: G-11-10
  truth: "The IPC socket keeps accepting connections indefinitely, however many clients connect."
  status: resolved
  resolved_at: 2026-07-31
  fix: |
    SocketServer.acceptConnection became acceptPendingConnections: it now drains
    accept() in a loop until EWOULDBLOCK instead of taking one connection per
    source event, the listening socket is O_NONBLOCK so the loop can terminate,
    O_NONBLOCK is cleared on each accepted socket (Darwin propagates it, and
    handleClient does a blocking read), each client is served on its own global
    queue rather than blocking the source handler on a semaphore, and the listen
    backlog went from 5 to 64.
  verified: |
    - 40 back-to-back sequential connections: 40 ok, 0 fail
    - 25 simultaneous connections: 25 ok, 0 fail
    - server still responsive afterwards
    Previously wedged permanently at ~4 connections.
  reason: |
    Discovered while verifying G-11-9. After roughly three rapid sequential connections
    the app stops accepting entirely: clients connect and hang with no reply, then every
    later connect returns ECONNREFUSED (listen backlog is 5 and full) while the app still
    holds the bound fd. Reproduced with exactly ONE app instance running, so it is not an
    instance collision. `sample` shows the main thread idle in its run loop and NO thread
    in accept/handleClient — the connections are simply never picked up. The app never recovers.
  severity: major
  test: 9
  artifacts:
    - Exmen/Services/SocketServer.swift:80-88
    - Exmen/Services/SocketServer.swift:117-138
  missing:
    - "Drain loop: the read-source handler accepts exactly one connection per event, but a connection left pending in the backlog does not re-trigger the source"
    - "Non-blocking listening socket so the drain loop can terminate on EWOULDBLOCK"
    - "Per-client handling off the source's own queue — handleClient currently blocks the source handler on a semaphore while it waits for the main thread"
  note: |
    Pre-existing Phase 6 code, untouched by Phase 11. Was blocking Phase 14 (Raycast),
    which drives this socket for every list and mutation.

- gap_id: G-11-11
  truth: "The exmen CLI has a reproducible build, and building it produces the CLI."
  status: failed
  reason: |
    `exmen-cli/main.swift` is in NO build system: `grep -c exmen-cli` over
    Exmen.xcodeproj/project.pbxproj returns 0, and Package.swift declares a single
    executableTarget named "Exmen" at path "Exmen" — the GUI app. There is no Makefile
    and no build script. The installed binary at ~/.local/bin/exmen is dated
    2026-03-20 (Phase 10) and was evidently produced ad-hoc with swiftc.
    Worse, `swift build` emits .build/debug/Exmen — the GUI app — and on a
    case-insensitive filesystem that answers to `.build/debug/exmen`. Running it
    silently launches a SECOND app instance, which unlinks and rebinds the IPC socket,
    orphaning the real instance. That masqueraded as socket flakiness for a long stretch
    of this session, and it is also what triggered the UNUserNotificationCenter abort
    (an unbundled launch cannot use UNUserNotificationCenter — see the crash at
    OutputHandler.swift:58).
  severity: major
  test: 9
  artifacts:
    - Package.swift:12-19
    - exmen-cli/main.swift
  missing:
    - "An SPM executableTarget (or Xcode target) for exmen-cli so the CLI has a real build"
    - "A distinct product name — a target whose binary collides case-insensitively with the app binary is a trap"
    - "Install/build docs: README documents CLI usage but never how to build it"
  note: |
    The G-11-9 CLI verification above used a manually compiled binary
    (`swiftc -O exmen-cli/main.swift -o <scratch>/exmen`) written to a scratch path.
    The user's installed ~/.local/bin/exmen is UNTOUCHED and still predates these
    changes — it needs rebuilding once this gap is closed.
  reason: "User reported: IPC `run` returns \"Action has no script: Subtask Demo\" — CommandHandler.runAction has no subtasks branch, so subtask actions are listable but unrunnable from the CLI."
  severity: major
  test: 9
  artifacts:
    - Exmen/Services/CommandHandler.swift:187-194
    - Exmen/Views/MenuContentView.swift:103-106
  missing:
    - "Subtask branch in CommandHandler.runAction mirroring MenuContentView.executeAction"
    - "IPC response shape for an aggregated OrchestrationSummary"
