---
phase: 04-hook-system
plan: 01
status: completed
---

## Summary

Added hook system support for parsing script output for dynamic updates (title, status, badge, icon).

## What Was Built

### New Files Created

1. **HookUpdate.swift** (`Exmen/Models/HookUpdate.swift`)
   - `HookUpdate` struct: Holds dynamic update values (title, status, badge, icon)
   - `HookConfig` struct: TOML configuration for hook behavior with CodingKeys for snake_case support
   - Supports merge functionality for combining multiple updates

2. **HookParser.swift** (`Exmen/Services/HookParser.swift`)
   - Singleton service for parsing script output
   - Extracts `EXMEN:key=value` lines from output
   - Returns clean output (without hook lines) and extracted updates
   - Supports keys: title, status, badge, icon

### Modified Files

3. **ActionConfig.swift** (`Exmen/Models/ActionConfig.swift`)
   - Added `hook: HookConfig?` property for TOML configuration

4. **Action.swift** (`Exmen/Models/Action.swift`)
   - Added `hookConfig: HookConfig?` property
   - Added dynamic state properties: `dynamicTitle`, `dynamicStatus`, `dynamicBadge`, `dynamicIcon`
   - Added computed properties: `displayTitle`, `displayIcon`
   - Added `applyHookUpdate(_:)` method for applying updates

5. **project.pbxproj** (`Exmen.xcodeproj/project.pbxproj`)
   - Added HookUpdate.swift to Models group
   - Added HookParser.swift to Services group

## Hook System Format

Scripts can emit special lines to update their display:
```
EXMEN:title=New Title
EXMEN:status=Running
EXMEN:badge=3
EXMEN:icon=checkmark
```

These lines are parsed and removed from the clean output, with values applied to the action's dynamic properties.

## TOML Configuration Example

```toml
[hook]
status_script = { type = "inline", content = "echo 'EXMEN:status=OK'" }
poll_interval = 30
parse_output = true
```

## Verification

- [x] HookUpdate.swift exists with HookUpdate and HookConfig structs
- [x] HookParser.swift exists with parse() method
- [x] ActionConfig.swift has hook: HookConfig? property
- [x] Action.swift has dynamic properties and applyHookUpdate method
- [x] Files added to Xcode project
- [x] Project builds successfully

## Build Result

```
** BUILD SUCCEEDED **
```

## Next Steps

- Phase 04-02: Integrate HookParser with ScriptRunner to process hook output
- Phase 04-03: Add polling support using HookConfig.pollInterval
