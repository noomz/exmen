# Summary: 07-01 Global Config

## Completed

All tasks completed successfully.

### Task 1: Create GlobalConfig model
- Created `Exmen/Models/GlobalConfig.swift` with Codable struct containing:
  - `order: [String]?` - Action names in display order
  - `disabled: [String]?` - Action names to hide/disable
- Added `parentConfigDirectory` and `globalConfigPath` properties to ConfigLoader
- Added `loadGlobalConfig() -> GlobalConfig?` method to ConfigLoader
- Added GlobalConfig.swift to Xcode project

### Task 2: Apply ordering and filtering in ActionService
- Modified `loadActions()` to:
  - Load global config
  - Filter out disabled actions using Set for O(1) lookup
  - Sort actions based on order array (unspecified actions appear at end)

### Task 3: Watch config.toml for changes
- Added second DirectoryWatcher (`configWatcher`) for parent directory
- Both `~/.config/exmen/actions/` and `~/.config/exmen/` are now monitored
- Changes to config.toml trigger automatic reload

## Files Modified

- `Exmen/Models/GlobalConfig.swift` (new)
- `Exmen/Services/ConfigLoader.swift`
- `Exmen/Services/ActionService.swift`
- `Exmen.xcodeproj/project.pbxproj`

## Config Format

Example `~/.config/exmen/config.toml`:

```toml
# Action display order (actions not listed appear at end)
order = [
    "System Status",
    "Generate Phone Number",
    "Update Homebrew"
]

# Actions to hide (by name)
disabled = [
    "Check Disk Space"
]
```

## Verification

- [x] Build succeeds
- [x] GlobalConfig model decodes from TOML
- [x] Actions filtered by disabled array
- [x] Actions sorted by order array
- [x] File watching triggers reload on config.toml changes
