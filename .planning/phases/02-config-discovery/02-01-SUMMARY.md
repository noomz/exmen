---
phase: 02-config-discovery
plan: 01
type: summary
status: completed
---

# Phase 02-01 Summary: Config Discovery - TOML Models & Loader

## Objective
Add TOMLDecoder dependency and create config models for loading actions from TOML files.

## Completed Tasks

### Task 1: Add TOMLDecoder Swift Package dependency
- **Files created:** `Package.swift`
- **Changes:**
  - Created Package.swift with TOMLDecoder dependency (https://github.com/dduan/TOMLDecoder, version 0.4.0+)
  - Updated Xcode project (`Exmen.xcodeproj/project.pbxproj`) to include:
    - XCRemoteSwiftPackageReference for TOMLDecoder
    - XCSwiftPackageProductDependency linking TOMLDecoder to the Exmen target
    - TOMLDecoder added to Frameworks build phase
  - Package resolved to version 0.4.3

### Task 2: Create ActionConfig Codable models
- **File created:** `Exmen/Models/ActionConfig.swift`
- **Components:**
  - `ScriptType` enum: `inline` (embedded script) and `file` (external script path)
  - `OutputHandler` enum: `clipboard`, `notification`, `popup`
  - `ScriptConfig` struct: Codable config with `type`, `content`, `path`, and `resolvedContent()` method
  - `OutputConfig` struct: Codable config with `handler` property
  - `ActionConfig` struct: Full TOML structure with `name`, `icon`, `description`, `script`, `output`

### Task 3: Create ConfigLoader service
- **File created:** `Exmen/Services/ConfigLoader.swift`
- **Directory created:** `Exmen/Services/`
- **Features:**
  - `ConfigLoader` singleton class with shared instance
  - Default config directory: `~/.config/exmen/actions/`
  - `loadAllConfigs()`: Loads all .toml files from config directory
  - `loadConfig(from:)`: Loads a single ActionConfig from a TOML file path
  - `ensureConfigDirectory()`: Creates config directory if needed
  - Proper tilde expansion using `NSString(string:).expandingTildeInPath`
  - `ConfigError` enum for error handling

### Task 4: Update Action model
- **File modified:** `Exmen/Models/Action.swift`
- **Changes:**
  - Added `scriptConfig: ScriptConfig?` property
  - Added `outputConfig: OutputConfig` property
  - Updated initializer with new parameters and defaults
  - Added `init(from: ActionConfig)` initializer for TOML-based initialization
  - Maintained backward compatibility with static sample actions

## Files Modified/Created
| File | Status |
|------|--------|
| `Package.swift` | Created |
| `Exmen.xcodeproj/project.pbxproj` | Modified |
| `Exmen/Models/ActionConfig.swift` | Created |
| `Exmen/Models/Action.swift` | Modified |
| `Exmen/Services/ConfigLoader.swift` | Created |

## Build Verification
- Package dependencies resolved successfully (TOMLDecoder 0.4.3)
- Project builds successfully with `xcodebuild -project Exmen.xcodeproj -scheme Exmen build`
- All Swift files compile without errors

## Architecture Notes
- Config path uses `~/.config/exmen/actions/` following XDG conventions
- Supports both inline scripts (content in TOML) and external script files
- Output handlers support clipboard, notification, and popup display modes
- Action model maintains backward compatibility with existing static samples

## Next Steps (for 02-02-PLAN)
- Integrate ConfigLoader with the app startup
- Load actions from TOML files and display in menu
- Create sample TOML config files for testing
