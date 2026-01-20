---
phase: 02-config-discovery
plan: 02
status: completed
completed_at: 2026-01-20
---

# Plan 02-02: Directory Watching and ActionService - Summary

## Objective
Implemented directory watching and ActionService to auto-reload actions when config files change, making the app reactive to config changes without requiring restart.

## Tasks Completed

### Task 1: Create DirectoryWatcher class
**File:** `Exmen/Services/DirectoryWatcher.swift`

Created a directory watcher using DispatchSource with:
- File system event monitoring (.write, .delete, .rename, .extend, .attrib)
- Debouncing mechanism (0.5s default) to avoid excessive reloads
- Proper cleanup in cancel handler to avoid file descriptor leaks
- Weak self references to prevent retain cycles

### Task 2: Create ActionService with ObservableObject
**File:** `Exmen/Services/ActionService.swift`

Created the main service that manages actions:
- `@MainActor` for thread safety with UI
- `@Published` properties: `actions`, `isLoading`, `lastError`
- Singleton pattern via `ActionService.shared`
- Auto-loads from TOML configs on initialization
- Falls back to sample actions if no configs found
- Watches config directory for changes

### Task 3: Update MenuContentView to use ActionService
**File:** `Exmen/Views/MenuContentView.swift`

Updated the view to:
- Use `@ObservedObject` for reactive UI updates
- Added refresh button in header
- Added loading state with ProgressView
- Added empty state message
- Added error display in footer

### Task 4: Update ExmenApp to initialize ActionService
**File:** `Exmen/ExmenApp.swift`

Added initialization call in app's `init()`:
```swift
init() {
    ActionService.shared.initialize()
}
```

### Task 5: Create sample TOML config files
**Location:** `~/.config/exmen/actions/`

Created 3 sample config files:
- `generate-phone.toml` - Generate random Thai phone number (clipboard output)
- `disk-space.toml` - Show available disk space (notification output)
- `brew-update.toml` - Run brew update && upgrade (popup output)

## Files Changed
- Created: `Exmen/Services/DirectoryWatcher.swift`
- Created: `Exmen/Services/ActionService.swift`
- Modified: `Exmen/Views/MenuContentView.swift`
- Modified: `Exmen/ExmenApp.swift`
- Modified: `Exmen.xcodeproj/project.pbxproj` (added new source files)
- Created: `~/.config/exmen/actions/generate-phone.toml`
- Created: `~/.config/exmen/actions/disk-space.toml`
- Created: `~/.config/exmen/actions/brew-update.toml`

## Verification
- [x] DirectoryWatcher.swift exists with debouncing
- [x] ActionService.swift exists with ObservableObject
- [x] MenuContentView.swift uses ActionService
- [x] ExmenApp.swift initializes ActionService
- [x] Sample TOML files exist in ~/.config/exmen/actions/
- [x] Project builds successfully

## Build Result
```
** BUILD SUCCEEDED **
```

## Key Patterns Used
1. **DispatchSource** for efficient directory monitoring without polling
2. **Debouncing** to batch rapid file system events
3. **ObservableObject/Published** for reactive SwiftUI binding
4. **Singleton pattern** for centralized action management
5. **Weak self** references in closures to prevent memory leaks

## Ready for Next Phase
Phase 2 (Config & Discovery) is now complete. The app can:
- Load action configs from TOML files on startup
- Watch for config file changes and auto-reload
- Fall back to sample actions when no configs exist
- Manually refresh via UI button

Next: Phase 3 - Script Execution
