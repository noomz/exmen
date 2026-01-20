---
phase: 04-hook-system
plan: 02
status: completed
---

## Summary

Implemented polling fallback for status updates and integrated hooks into UI.

## What Was Built

### New Files Created

1. **StatusPoller.swift** (`Exmen/Services/StatusPoller.swift`)
   - Singleton service marked with `@MainActor` for thread safety
   - Manages `Timer` instances per action for periodic polling
   - `startPolling(for:)` - Start polling for all actions with hook configs
   - `runStatusScript(for:script:)` - Execute status script and apply updates
   - `stopAll()` - Stop all active timers when reloading or shutting down

2. **ActionRowView.swift** (`Exmen/Views/ActionRowView.swift`)
   - Extracted from MenuContentView to separate file
   - Uses `action.displayTitle` and `action.displayIcon` for dynamic values
   - Shows `action.dynamicStatus` as subtitle when present
   - Displays `action.dynamicBadge` as a pill next to title

### Modified Files

3. **ActionService.swift** (`Exmen/Services/ActionService.swift`)
   - Added `applyHookUpdate(_:to:)` method to update action by ID
   - Added `processScriptResult(_:for:)` method to parse hooks and return clean output
   - Calls `StatusPoller.shared.startPolling(for:)` after loading actions
   - Stops StatusPoller in `stopWatching()`

4. **MenuContentView.swift** (`Exmen/Views/MenuContentView.swift`)
   - Removed inline ActionRowView (now in separate file)
   - Updated `popupResult` to include `cleanOutput` tuple element
   - Uses `actionService.processScriptResult()` to get clean output
   - Passes clean output to PopupResultView and OutputService

5. **PopupResultView.swift** (`Exmen/Views/PopupResultView.swift`)
   - Added `cleanOutput: String` parameter
   - Uses `cleanOutput` instead of `result.output` for display
   - Copy button copies clean output

6. **project.pbxproj** (`Exmen.xcodeproj/project.pbxproj`)
   - Added StatusPoller.swift to Services group
   - Added ActionRowView.swift to Views group

### Sample Configuration Created

7. **system-status.toml** (`~/.config/exmen/actions/system-status.toml`)
   - Demonstrates hook configuration with status_script
   - Polls every 30 seconds for CPU usage
   - Sets badge to "HIGH" when CPU > 50%
   - Sets status to current CPU percentage

## Hook System Flow

1. **On Action Load**: StatusPoller starts timers for actions with `hook.status_script`
2. **On Timer Fire**: Status script runs, output parsed for `EXMEN:key=value` lines
3. **On Updates**: `ActionService.applyHookUpdate()` updates action's dynamic properties
4. **On UI Render**: ActionRowView shows `displayTitle`, `displayIcon`, `dynamicStatus`, `dynamicBadge`
5. **On Script Run**: Output parsed, clean output (without EXMEN lines) shown to user

## TOML Configuration Example

```toml
[hook]
status_script = { type = "inline", content = "echo 'EXMEN:status=OK'" }
poll_interval = 30
parse_output = true
```

## Verification

- [x] StatusPoller.swift exists with polling logic
- [x] ActionService.swift has hook update methods
- [x] ActionRowView.swift shows dynamic properties
- [x] MenuContentView processes hooks
- [x] PopupResultView uses clean output
- [x] Sample system-status.toml created
- [x] Files added to Xcode project
- [x] Project builds successfully

## Build Result

```
** BUILD SUCCEEDED **
```

## Phase 4 Complete

This completes Phase 4 (Hook System) of the v1 roadmap. The hook system now supports:
- Dynamic property updates via `EXMEN:key=value` output format
- Periodic status polling via `status_script` and `poll_interval`
- Clean output display (hook lines stripped from user-visible output)
- UI reflects dynamic title, icon, status, and badge
