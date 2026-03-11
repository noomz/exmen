---
phase: 08-long-running-cli-services
plan: 03
subsystem: ui
tags: [swift, swiftui, appkit, service-ui, context-menu, lifecycle]
dependency_graph:
  requires:
    - phase: 08-01
      provides: ServiceState, ServiceConfig, ManagedService skeleton, Action.isService
    - phase: 08-02
      provides: ManagedService full lifecycle, ServiceManager singleton, ServiceOutputWindow
  provides:
    - ServiceRowView with status dot, name, uptime, and context menu
    - MenuContentView split layout with actions above and services below divider
    - ActionService filters services out of actions and registers them with ServiceManager
    - ExmenApp app lifecycle hooks for keep_alive reconnect and termination cleanup
  affects: [complete end-to-end services feature visible and controllable from menu bar]
tech-stack:
  added: []
  patterns:
    - ObservedObject-ServiceManager-in-MenuContentView for reactive services list
    - contextMenu-only-interaction-for-ServiceRowView (no left-click toggle)
    - willTerminateNotification-in-init for pre-quit service cleanup
key-files:
  created:
    - Exmen/Views/ServiceRowView.swift
  modified:
    - Exmen/Views/MenuContentView.swift
    - Exmen/Services/ActionService.swift
    - Exmen/ExmenApp.swift
    - Exmen.xcodeproj/project.pbxproj
key-decisions:
  - "Services shown below actions (actions are primary use case, services are secondary)"
  - "Left-click on ServiceRowView does NOT toggle service — interaction is context menu only"
  - "Empty state check updated to require both actions AND services to be empty"
  - "willTerminateNotification registered in init() to ensure pre-quit cleanup fires before any quit action"
patterns-established:
  - "ServiceRowView: context-menu-only row with hover highlight but no click action"
  - "ActionService: filters isService actions before assigning to self.actions, passes them to ServiceManager"
requirements-completed: [SVC-UI, SVC-MENU, SVC-APPLIFECYCLE]
duration: ~10min
completed: 2026-03-11
---

# Phase 8 Plan 3: UI Integration and App Lifecycle Summary

**ServiceRowView with context menu (Start/Stop/Restart/View Output), MenuContentView split sections (actions above divider, services below), ActionService filtering services to ServiceManager, and ExmenApp lifecycle hooks for keep_alive reconnect and termination cleanup.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-11T16:05:00Z
- **Completed:** 2026-03-11T16:15:00Z
- **Tasks:** 2 auto + 1 checkpoint (human-verify)
- **Files modified:** 5

## Accomplishments
- ServiceRowView created with colored status dot, name+uptime VStack, hover highlight, and full context menu
- MenuContentView restructured with a separate services section below actions with Divider and "Services" label
- ActionService.loadActions() now splits regular actions from service actions and registers services with ServiceManager
- ExmenApp registers willTerminateNotification in init() and calls reconnectKeepAliveServices() on launch

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ServiceRowView and update MenuContentView with split sections** - `df07850` (feat)
2. **Task 2: Wire ActionService to ServiceManager and add app lifecycle handling** - `4f369fd` (feat)
3. **Task 3: Human verification checkpoint** - awaiting user verification

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `Exmen/Views/ServiceRowView.swift` - New service row view with status dot, name, uptime, context menu
- `Exmen/Views/MenuContentView.swift` - Added serviceManager observer, services section with divider, updated empty check
- `Exmen/Services/ActionService.swift` - Filter service-type actions, register with ServiceManager, updated log
- `Exmen/ExmenApp.swift` - Added reconnectKeepAliveServices() call and willTerminateNotification registration
- `Exmen.xcodeproj/project.pbxproj` - Added ServiceRowView.swift to PBXBuildFile, PBXFileReference, Views group, Sources phase

## Decisions Made
- Services placed below actions (actions are primary use case; services are secondary/management)
- Left-click on service row does not trigger any action — the row is informational and interaction is via right-click context menu only
- Empty state text "No actions configured" only shown when both actions AND services are empty
- willTerminateNotification registered in `init()` (not `body`) to ensure it fires before any quit action triggers

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 8 is feature-complete pending human verification (Task 3 checkpoint). The complete long-running CLI services feature is ready for end-to-end testing:
- Service TOML with `type = "service"` + `[service]` block
- Menu bar shows services below actions with colored status dots
- Right-click context menu: Start/Stop/Restart/View Output
- Standalone output window with SwiftTerm PTY terminal emulation
- App quit terminates non-keep_alive services; keep_alive services persist and reconnect

---
*Phase: 08-long-running-cli-services*
*Completed: 2026-03-11*

## Self-Check: PASSED

Files created:
- Exmen/Views/ServiceRowView.swift: FOUND

Files modified:
- Exmen/Views/MenuContentView.swift: FOUND
- Exmen/Services/ActionService.swift: FOUND
- Exmen/ExmenApp.swift: FOUND

Commits:
- df07850: feat(08-03): create ServiceRowView and update MenuContentView with split sections - FOUND
- 4f369fd: feat(08-03): wire ActionService to ServiceManager and add app lifecycle handling - FOUND
