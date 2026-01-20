---
phase: 03-script-execution
plan: 02
status: complete
---

# Output Handlers - Summary

## What Was Done

Implemented output handlers for clipboard, notification, and popup display, completing the script execution to output flow.

### Files Created/Modified

1. **Exmen/Services/OutputHandler.swift** (new)
   - `OutputService` singleton class for handling script output
   - `copyToClipboard(_ text: String)` - Copy text to system clipboard using NSPasteboard
   - `showNotification(title:body:isError:)` - Display macOS notifications using UserNotifications
   - `handle(_ result:config:actionName:)` - Route output based on OutputConfig
   - Requests notification permission on init

2. **Exmen/Views/PopupResultView.swift** (new)
   - SwiftUI view for displaying script results in a popup
   - Shows success/error icon based on result status
   - Monospaced output display with text selection enabled
   - Footer shows exit code and execution duration
   - Copy button to copy output to clipboard
   - Close button with Escape key shortcut

3. **Exmen/Views/MenuContentView.swift** (updated)
   - Added `@State` for `executingActionId` and `popupResult`
   - `executeAction(_ action:)` - Async script execution with loading state
   - `handleResult(_ result:for:)` - Route result to appropriate handler
   - `ActionRowView` updated with `isExecuting` and `onExecute` parameters
   - Shows loading spinner during execution
   - Dynamic frame size when popup is displayed

### Key Implementation Details

- **Clipboard handler**: Uses `NSPasteboard.general` for system clipboard access
- **Notification handler**: Uses `UNUserNotificationCenter` with critical sound for errors
- **Popup handler**: Displays result inline in the menu popup with 400x300 frame
- **Loading state**: Shows progress spinner and disables button during execution
- **Error handling**: Creates ScriptResult with error message on failure

## Verification

- [x] OutputHandler.swift exists with clipboard/notification handling
- [x] PopupResultView.swift exists for popup display
- [x] MenuContentView.swift updated with execution logic
- [x] All files added to Xcode project
- [x] Project builds successfully

## Example Flow

1. User clicks an action row
2. `executingActionId` is set, showing loading spinner
3. `ScriptRunner.shared.run()` executes the script asynchronously
4. On completion, `handleResult()` routes based on `outputConfig.handler`:
   - `.clipboard`: Copies to clipboard, shows brief notification
   - `.notification`: Shows macOS notification with output
   - `.popup`: Sets `popupResult` to display PopupResultView

## Next Steps

Phase 3 Script Execution is complete. The application now supports:
- Loading actions from TOML configuration
- Executing inline and file-based scripts
- Handling output via clipboard, notification, or popup
