# Phase 8: Long-Running CLI Services - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Manage arbitrary CLI programs as persistent services with lifecycle control (start/stop/restart), output viewing in a separate window, and full terminal interaction via PTY. Services are configured alongside existing actions using TOML with a `type = "service"` flag and dedicated `[service]` section.

</domain>

<decisions>
## Implementation Decisions

### Service config model
- Hybrid approach: services live in `~/.config/exmen/actions/` alongside regular actions
- Action TOML gets `type = "service"` in `[action]` section
- New `[service]` section for lifecycle config: `auto_start`, `restart`, `max_restarts`, `keep_alive`, `working_dir`, `env`
- Restart policies: `never`, `on-failure` (non-zero exit only), `always`
- Environment variables via `env = { KEY = "value" }` table
- Working directory via `working_dir = "~/path"`

### Menu layout
- Services and regular actions shown in separate sections with a divider
- Services section distinct from actions section (positioning TBD — Claude's discretion)

### Lifecycle controls
- Right-click / context menu on service row shows: Start, Stop, Restart, View Output
- Left-click does NOT toggle — avoids accidental start/stop

### Status indicators
- Colored dot + text status in the service row
- Colors: green = running, gray = stopped, yellow = starting/restarting, red = crashed
- Show uptime when running (e.g., "running • uptime 2h 15m")

### On app quit behavior
- Configurable per-service via `keep_alive = true/false` in `[service]` config
- `keep_alive = true`: service continues as background process after Exmen quits, reconnect on next launch
- `keep_alive = false` (default): service terminated when Exmen quits

### Auto-start
- NOT implemented in v1. User always manually starts services.
- `auto_start` config key reserved for future use

### Output viewing
- Output displayed in a separate standalone macOS window (not in-menu popup)
- Window stays open when menu closes, can be resized and positioned
- Always auto-scroll to bottom as new lines arrive
- stdout and stderr merged into one interleaved stream
- stderr lines visually distinguished (colored red)
- Buffer size: Claude's discretion (reasonable default)

### Terminal emulation
- Full PTY allocation — programs think they're running in a real terminal
- Full ANSI color and escape code support (colors, bold, underline)
- Full terminal emulation: cursor movement, screen clearing, alternate screen buffer
- Preferred library: libghostty from ghostty-org/ghostty (Zig-based, C API)
- Fallback library: SwiftTerm (pure Swift, easier to embed) if libghostty integration proves too complex
- Researcher should investigate libghostty embeddability first

### Claude's Discretion
- Output buffer size and eviction strategy
- Services section position in menu (top vs bottom)
- Terminal window default size and appearance
- How to reconnect to `keep_alive` processes on relaunch (PID file, socket, etc.)
- Error presentation for failed service starts

</decisions>

<specifics>
## Specific Ideas

- User specifically wants libghostty (from Ghostty terminal emulator) for terminal emulation — high quality, GPU-accelerated
- Context menu pattern similar to how macOS Finder handles right-click actions
- Status display should show PID and uptime when running

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ActionConfig` / `Action` models: Need extension for `type` field and service-specific config
- `ActionRowView`: Base for service row, needs context menu and status indicator additions
- `MenuContentView`: Needs separate sections logic for services vs actions
- `ScriptRunner`: NOT reusable for services (fire-and-forget with timeout) — need new `ServiceManager`
- `ConfigLoader`: Can be extended to parse `[service]` section from TOML
- `ActionService`: Manages action lifecycle, needs service-aware counterpart or extension

### Established Patterns
- Singleton services (`ActionService.shared`, `ScriptRunner.shared`) — follow same pattern for `ServiceManager`
- `@Published` properties for reactive UI updates
- `DirectoryWatcher` for config change detection — works for service configs too
- Hook system (`EXMEN:key=value`) could be reused for service status updates

### Integration Points
- `ActionConfig` TOML parsing needs new `type` and `[service]` fields
- `MenuContentView` needs split layout: services section + actions section
- `ActionRowView` needs variant for service rows (context menu, status dot)
- New `ServiceManager` service for process lifecycle (start/stop/restart/monitor)
- New `ServiceOutputWindow` for separate output viewing window
- Terminal emulation component (libghostty or SwiftTerm) embedded in output window

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-long-running-cli-services*
*Context gathered: 2026-03-11*
