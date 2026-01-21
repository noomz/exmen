# Phase 06-02 Summary: CLI Tool

## Completed
- Created exmen-cli/main.swift - Command-line tool for IPC
- Implements Unix socket client using Darwin APIs
- Full command support: list-actions, run, status

## Usage

```bash
# Build
swiftc -O -o .build/exmen exmen-cli/main.swift

# Install (optional)
cp .build/exmen /usr/local/bin/

# Commands
exmen list-actions          # Pretty-print all actions
exmen list-actions --json   # JSON output
exmen run "Action Name"     # Execute action, print output
exmen status "Action Name"  # Show dynamic status info
```

## Error Handling
- Socket not found: "Exmen is not running (socket not found)"
- Connection refused: "Exmen is not running (connection refused)"
- Invalid commands: Helpful usage message

## Integration Examples

### Sketchybar
```bash
# In sketchybar config
exmen status "System Status" | grep Status | cut -d: -f2
```

### Alfred/Raycast
```bash
exmen run "Generate Phone Number"
```

## Commits
- 1eaf186: feat(06-02): add CLI tool for IPC communication
