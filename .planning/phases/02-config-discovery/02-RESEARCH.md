# Phase 2: Config & Discovery - Research

**Researched:** 2026-01-20
**Domain:** TOML parsing in Swift, file system monitoring
**Confidence:** HIGH

<research_summary>
## Summary

Researched TOML parsing libraries and file system monitoring for the config and discovery phase. Two main TOML options exist: TOMLDecoder (pure Swift, excellent performance) and TOMLKit (toml++ wrapper). For file watching, macOS provides FSEvents API and DispatchSource for simpler use cases.

**Primary recommendation:** Use TOMLDecoder for TOML parsing (pure Swift, faster than C, Codable support). Use DispatchSource for folder monitoring (simpler than FSEvents, sufficient for watching a single directory).
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| TOMLDecoder | 0.4+ | TOML parsing | Pure Swift, Codable, faster than C (Jan 2026) |
| DispatchSource | built-in | File watching | Native macOS, no dependencies |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| FileManager | built-in | File operations | Directory listing, file existence |
| Combine | built-in | Reactive updates | Publishing config changes |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| TOMLDecoder | TOMLKit | TOMLKit wraps C++ toml++, more dependencies |
| TOMLDecoder | swift-toml | Less community adoption |
| DispatchSource | FSWatcher | External dependency for simple use case |
| DispatchSource | FSEvents | Lower level, more complex API |

**Installation:**
```swift
// Package.swift dependencies
.package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0")
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Config Structure
```
~/.config/exmen/
├── config.toml          # Main config (optional)
└── actions/             # Script folder
    ├── phone.toml       # Action with inline script
    ├── brew-update.toml # Action pointing to external script
    └── scripts/         # Optional subfolder for scripts
        └── update-brew.sh
```

### Pattern 1: TOML Action Config
**What:** Define actions in TOML with Codable structs
**When to use:** All action definitions
**Example:**
```toml
# ~/.config/exmen/actions/phone.toml
name = "Generate Phone Number"
icon = "phone"
description = "Generate random Thai phone number"

[script]
type = "inline"
content = """
#!/bin/bash
echo "08$(shuf -i 10000000-99999999 -n 1)"
"""

[output]
handler = "clipboard"  # or "notification", "popup"
```

```swift
// Swift Codable struct
struct ActionConfig: Codable {
    let name: String
    let icon: String?
    let description: String?
    let script: ScriptConfig
    let output: OutputConfig?
}

struct ScriptConfig: Codable {
    let type: ScriptType  // "inline" or "file"
    let content: String?  // for inline
    let path: String?     // for file reference
}

struct OutputConfig: Codable {
    let handler: String   // "clipboard", "notification", "popup"
}
```

### Pattern 2: Directory Watching with DispatchSource
**What:** Monitor scripts folder for changes
**When to use:** Auto-reload actions when files change
**Example:**
```swift
// Source: Apple documentation + community patterns
class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

### Pattern 3: Action Loading Service
**What:** Central service to load and manage actions
**When to use:** App initialization and config changes
**Example:**
```swift
class ActionService: ObservableObject {
    @Published var actions: [Action] = []
    private var watcher: DirectoryWatcher?

    func loadActions() {
        let actionsPath = "~/.config/exmen/actions"
        let expandedPath = NSString(string: actionsPath).expandingTildeInPath

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: expandedPath) else {
            return
        }

        actions = files
            .filter { $0.hasSuffix(".toml") }
            .compactMap { loadAction(from: expandedPath + "/" + $0) }
    }

    private func loadAction(from path: String) -> Action? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let decoder = TOMLDecoder()
        guard let config = try? decoder.decode(ActionConfig.self, from: content) else {
            return nil
        }

        return Action(from: config)
    }
}
```

### Anti-Patterns to Avoid
- **Polling for file changes:** Use DispatchSource instead of timers
- **Blocking main thread on file I/O:** Load configs asynchronously
- **Hard-coded config paths:** Use expandingTildeInPath for ~ support
- **No error handling for malformed TOML:** Gracefully skip invalid configs
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TOML parsing | Custom parser | TOMLDecoder | Spec-compliant, Codable support |
| File watching | Timer-based polling | DispatchSource | Efficient, event-driven |
| Path expansion | Manual string replace | NSString.expandingTildeInPath | Handles edge cases |
| Directory listing | Shell commands | FileManager.contentsOfDirectory | Native, safer |
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Tilde Path Not Expanded
**What goes wrong:** FileManager can't find ~/.config/exmen
**Why it happens:** FileManager doesn't expand ~ automatically
**How to avoid:** Always use NSString(string:).expandingTildeInPath
**Warning signs:** "No such file or directory" for paths starting with ~

### Pitfall 2: DispatchSource File Descriptor Leak
**What goes wrong:** File descriptors exhausted over time
**Why it happens:** Not closing fd when canceling source
**How to avoid:** Set cancelHandler that calls close(fd)
**Warning signs:** "Too many open files" error

### Pitfall 3: TOML Decode Errors Silent
**What goes wrong:** Actions don't load but no error shown
**Why it happens:** try? swallows decode errors
**How to avoid:** Log decode errors, show count of failed loads
**Warning signs:** Fewer actions than TOML files

### Pitfall 4: Watching Wrong Directory Level
**What goes wrong:** Changes in subdirectories not detected
**Why it happens:** DispatchSource only watches single directory
**How to avoid:** Either flatten structure or use FSEvents for recursive
**Warning signs:** New files in subfolders not picked up
</common_pitfalls>

<code_examples>
## Code Examples

### TOML Action Config File
```toml
# Example: ~/.config/exmen/actions/generate-phone.toml
name = "Generate Phone Number"
icon = "phone"
description = "Generate random Thai phone number"

[script]
type = "inline"
content = """
#!/bin/bash
echo "08$(shuf -i 10000000-99999999 -n 1)"
"""

[output]
handler = "clipboard"
```

### TOML Config with External Script
```toml
# Example: ~/.config/exmen/actions/brew-update.toml
name = "Update Homebrew"
icon = "arrow.clockwise"
description = "Run brew update && upgrade"

[script]
type = "file"
path = "~/.config/exmen/scripts/update-brew.sh"

[output]
handler = "notification"
```

### Swift Codable Models
```swift
import Foundation
import TOMLDecoder

enum ScriptType: String, Codable {
    case inline
    case file
}

enum OutputHandler: String, Codable {
    case clipboard
    case notification
    case popup
}

struct ScriptConfig: Codable {
    let type: ScriptType
    let content: String?
    let path: String?
}

struct OutputConfig: Codable {
    let handler: OutputHandler
}

struct ActionConfig: Codable {
    let name: String
    let icon: String?
    let description: String?
    let script: ScriptConfig
    let output: OutputConfig?
}

// Load from TOML
func loadActionConfig(from tomlString: String) throws -> ActionConfig {
    let decoder = TOMLDecoder()
    return try decoder.decode(ActionConfig.self, from: tomlString)
}
```

### Directory Watcher Implementation
```swift
import Foundation

class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private let callback: () -> Void

    init?(path: String, callback: @escaping () -> Void) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fd = open(expandedPath, O_EVTONLY)
        guard fd >= 0 else { return nil }

        self.fileDescriptor = fd
        self.callback = callback
    }

    func start() {
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.callback()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor {
                close(fd)
            }
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
```
</code_examples>

<sources>
## Sources

### Primary (HIGH confidence)
- [TOMLDecoder GitHub](https://github.com/dduan/TOMLDecoder) - Pure Swift TOML parser
- [TOMLDecoder 0.4 Performance](https://duan.ca/2025/12/10/TOMLDecoder-0.4.1/) - 800% faster than previous versions
- [TOMLDecoder Faster Than C](https://duan.ca/2026/01/01/TOMLDecoder-Is-Faster-Than-C/) - January 2026 benchmarks
- [Apple File System Events](https://developer.apple.com/documentation/coreservices/file_system_events) - Official docs

### Secondary (MEDIUM confidence)
- [TOMLKit GitHub](https://github.com/LebJe/TOMLKit) - Alternative TOML library
- [FSWatcher GitHub](https://github.com/okooo5km/FSWatcher) - Swift file watcher library
- [Apple Developer Forums - FSEvents](https://developer.apple.com/forums/thread/115387) - FSEvents guidance
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: TOMLDecoder, DispatchSource
- Ecosystem: FileManager, Combine
- Patterns: Config loading, directory watching
- Pitfalls: Path expansion, file descriptor management

**Confidence breakdown:**
- TOML libraries: HIGH - recent benchmarks, active maintenance
- File watching: HIGH - native macOS APIs
- Architecture patterns: HIGH - standard Swift patterns

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (30 days)
</metadata>

---

*Phase: 02-config-discovery*
*Research completed: 2026-01-20*
*Ready for planning: yes*
