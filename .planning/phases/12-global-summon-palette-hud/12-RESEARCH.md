# Phase 12: Global Summon — Palette + HUD - Research

**Researched:** 2026-08-05
**Domain:** macOS global hotkeys, SwiftUI settings, AppKit panels, shared execution progress
**Confidence:** HIGH for project architecture; MEDIUM for final visual tuning (requires human smoke test)

---

<phase_scope>
## Phase Scope

Phase 12 makes existing Exmen actions globally accessible without opening the menu-bar popover. A configurable system-wide shortcut opens a keyboard-first command palette; actions started from either the palette or menu publish one shared execution state to an on-screen HUD.

This phase does not redesign the menu (Phase 13), add service search/control to the palette, or add Raycast integration (Phase 14).
</phase_scope>

<requirements>
## Requirements

| ID | Required outcome | Planning implication |
|---|---|---|
| SUMMON-01 | Global shortcut works from any frontmost app | Register a Carbon event hot key at app startup; do not rely on local NSEvent monitors or Accessibility permission |
| SUMMON-02 | Recorder UI in Settings | Add a SwiftUI Settings scene, native key-event recorder, durable shortcut store, conflict/error feedback |
| SUMMON-03 | Centered Spotlight-style palette searches and runs actions | Use a reusable AppKit NSPanel hosting SwiftUI; consume ActionService and a shared executor |
| SUMMON-04 | Type/filter, arrows, Enter, Esc | Keep filtering/selection logic testable outside NSPanel; make the panel key-capable and explicitly handle commands |
| SUMMON-05 | Live progress HUD, automatic dismissal | Publish a single execution session model for both scripts and orchestrations; drive a non-activating overlay from it |
</requirements>

<existing_architecture>
## Existing Architecture Findings

- `ExmenApp` owns startup and the `MenuBarExtra`, but there is no Settings scene or global shortcut registration.
- `ActionService.shared` is `@MainActor`, publishes the current ordered/non-disabled `[Action]`, and reloads automatically when TOML changes.
- `MenuContentView.executeAction` currently owns script/orchestration branching, notifications, popup results, and its private `executingActionId`. The palette and HUD cannot safely duplicate this logic; it must move into a shared observable executor.
- `SubtaskOrchestrator.shared` already publishes `subtaskStates`, `isRunning`, `overallProgressPercent`, and `completionSummary`. It deliberately is not class-level `@MainActor`; callers perform explicit main-actor mutations.
- `SubtaskProgressWindow` and `ServiceOutputWindow` establish the project pattern for independent AppKit windows hosting SwiftUI content.
- The Xcode test target is `Tests/ExmenTests` and runs through the `Exmen` scheme. `Package.swift` has no test target.
- Deployment is macOS 13. APIs introduced after macOS 13 (for example `SettingsLink`) cannot be the only path to Settings.
</existing_architecture>

<recommended_architecture>
## Recommended Architecture

### 1. One execution path

Introduce an `@MainActor ActionExecutor` shared service. Both `MenuContentView` and the palette call it. It owns the current `ExecutionSession`, rejects a second launch while one is active, routes scripts through `ScriptRunner`, routes orchestration actions through `SubtaskOrchestrator.shared`, and preserves existing popup/notification behavior.

The session model carries action identity, start time, status, optional determinate progress, detail text, and terminal result. Single scripts use indeterminate progress; orchestrations mirror `overallProgressPercent` and per-subtask state. A shared model prevents menu, palette, and HUD from disagreeing about what is running.

### 2. Native hotkey without a new package

Use Carbon `RegisterEventHotKey`/`UnregisterEventHotKey`. This API remains appropriate for menu-bar utilities, works while another app is frontmost, and does not require Accessibility permission. Wrap Carbon behind `GlobalHotKeyManager` so registration, replacement, conflicts, and cleanup are isolated and testable at the shortcut-model/store boundary.

Persist a codable `KeyboardShortcut` (virtual key code plus normalized modifiers) in `UserDefaults`; application UI preferences belong there rather than rewriting user-authored TOML. Default to Option-Space. Settings must show registration errors and retain the last valid registered shortcut if replacement fails.

### 3. AppKit panel with SwiftUI content

Use an `NSPanel` subclass that can become key, with a SwiftUI `CommandPaletteView` in an `NSHostingController`. Capture the previously frontmost application, activate Exmen only long enough to receive keyboard input, center the panel on the active screen, and restore focus when dismissed. Repeated hotkey presses toggle rather than create duplicate panels.

Filtering should be deterministic and testable: case/diacritic-insensitive matching over action name and description; prefix/name matches rank ahead of description-only matches; original ActionService order is the stable tie-breaker. Exclude `isService` entries because starting/stopping managed services is outside SUMMON scope.

### 4. Non-activating HUD

Use a separate borderless AppKit window with `ignoresMouseEvents = true`, floating above normal windows without stealing focus. Its SwiftUI view observes `ActionExecutor`. Show immediately on `.running`, display indeterminate progress for scripts or determinate overall/subtask progress for orchestrations, show terminal success/failure briefly, then order out automatically. A generation/token guard must prevent an old hide timer from hiding a newer run.
</recommended_architecture>

<failure_modes>
## Failure Modes to Plan Explicitly

- **Shortcut conflict or invalid recording:** surface the Carbon status in Settings; do not silently leave the app without a working shortcut.
- **Modifier-only/repeat events:** recorder ignores modifier-only events and key repeats; Escape cancels recording; Delete clears or restores the default according to explicit UI copy.
- **Hotkey lifecycle leaks:** unregister before replacement and on manager teardown; install the Carbon event handler once.
- **Duplicate execution:** shared executor rejects launches while a session is active and exposes that state to disable menu/palette rows.
- **Focus theft:** HUD never activates Exmen; palette restores the prior frontmost app when dismissed.
- **Empty or changing action list:** palette renders an empty state and updates when ActionService reloads; selection clamps after every filter update.
- **Stale timers:** HUD hide work is cancelled or generation-checked whenever a new session starts.
- **Orchestration failure:** failed/skipped counts remain visible and terminal failure controls HUD styling and notification severity.
</failure_modes>

<verification_strategy>
## Verification Strategy

Automated tests cover shortcut normalization/persistence, filtering/ranking/selection clamping, executor session transitions and busy rejection, and HUD presentation state/timer generation behavior. Run the full Xcode test target after each structural unit.

Global registration, cross-app focus, recorder ergonomics, panel placement, and overlay appearance require a final manual macOS smoke test because CI/unit tests cannot prove system-wide keyboard delivery or visual behavior.
</verification_strategy>

<plan_shape>
## Plan Shape

1. **12-01 Shared action execution state** — centralize menu/palette execution and publish progress.
2. **12-02 Global shortcut and Settings recorder** — durable shortcut, Carbon manager, Settings UI.
3. **12-03 Spotlight-style command palette** — panel, filtering, keyboard navigation, execution wiring.
4. **12-04 Live progress HUD and integration closeout** — overlay, timer safety, full automated and manual verification.

The plans are deliberately sequential because each consumes shared app wiring and project-file entries from the previous plan; parallel execution would create unnecessary conflicts in `ExmenApp.swift`, `MenuContentView.swift`, and `project.pbxproj`.
</plan_shape>
