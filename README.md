# Exmen

A macOS menu bar app for zero-friction script execution. Click, run, done.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## What is Exmen?

Exmen lives in your menu bar and lets you run scripts without switching to Terminal. Define actions in simple TOML files, click to execute, and get results via clipboard, notification, or popup.

**Core value:** Zero-friction execution — click menu, run action, done.

## Features

- **Menu Bar App** — Always accessible, never in the way
- **TOML Configuration** — Human-readable action definitions
- **Auto-Discovery** — Drop a `.toml` file, it appears instantly
- **Multiple Output Handlers**
  - `clipboard` — Copy output to clipboard
  - `notification` — Show macOS notification
  - `popup` — Display in a result window
- **Hook System** — Scripts can update their display dynamically
- **Status Polling** — Periodic status updates for monitoring actions

## Installation

### Build from Source

```bash
git clone https://github.com/noomz/exmen.git
cd exmen
xcodebuild -project Exmen.xcodeproj -scheme Exmen -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Exmen-*/Build/Products/Release/Exmen.app`

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building)

## Configuration

Actions are defined in TOML files located at `~/.config/exmen/actions/`

### Basic Action

```toml
name = "Generate Phone Number"
icon = "phone"
description = "Generate random phone number"

[script]
type = "inline"
content = """
#!/bin/bash
echo "08$(shuf -i 10000000-99999999 -n 1)"
"""

[output]
handler = "clipboard"
```

### Action with External Script

```toml
name = "Update Homebrew"
icon = "arrow.clockwise"
description = "Run brew update && upgrade"

[script]
type = "file"
path = "~/.config/exmen/scripts/update-brew.sh"

[output]
handler = "popup"
```

### Action with Hooks (Dynamic Updates)

```toml
name = "System Status"
icon = "cpu"
description = "Monitor CPU usage"

[script]
type = "inline"
content = """
#!/bin/bash
echo "CPU: $(top -l 1 | grep 'CPU usage' | awk '{print $3}')"
"""

[output]
handler = "notification"

[hook]
poll_interval = 30
parse_output = true

[hook.status_script]
type = "inline"
content = """
#!/bin/bash
cpu=$(top -l 1 | grep "CPU usage" | awk '{print $3}')
echo "EXMEN:status=CPU: $cpu"
"""
```

## Hook System

Scripts can emit special lines to update their action's display:

```
EXMEN:title=New Title
EXMEN:status=Current status text
EXMEN:badge=NEW
EXMEN:icon=star.fill
```

These lines are parsed and removed from the output. The action's UI updates accordingly.

## Configuration Reference

### Action Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Display name |
| `icon` | string | No | SF Symbol name (default: "terminal") |
| `description` | string | No | Shown below the name |

### Script Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `script.type` | string | Yes | `"inline"` or `"file"` |
| `script.content` | string | For inline | The script content |
| `script.path` | string | For file | Path to script file |

### Output Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `output.handler` | string | No | `"clipboard"`, `"notification"`, or `"popup"` (default: "clipboard") |

### Hook Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `hook.poll_interval` | int | No | Seconds between status script runs (default: 60) |
| `hook.parse_output` | bool | No | Parse EXMEN: lines from output (default: true) |
| `hook.status_script` | object | No | Script config for status updates |

## Project Structure

```
Exmen/
├── ExmenApp.swift           # App entry point
├── Models/
│   ├── Action.swift         # Action model
│   ├── ActionConfig.swift   # TOML config models
│   ├── HookUpdate.swift     # Hook system models
│   └── ScriptResult.swift   # Execution result
├── Views/
│   ├── MenuContentView.swift
│   ├── ActionRowView.swift
│   └── PopupResultView.swift
├── Services/
│   ├── ActionService.swift   # Action management
│   ├── ConfigLoader.swift    # TOML loading
│   ├── DirectoryWatcher.swift
│   ├── ScriptRunner.swift    # Script execution
│   ├── OutputService.swift   # Output handling
│   ├── HookParser.swift
│   └── StatusPoller.swift
└── Assets.xcassets/
    └── AppIcon.appiconset/
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
