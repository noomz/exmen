# Phase 1: Foundation - Research

**Researched:** 2026-01-20
**Domain:** SwiftUI macOS menu bar app development
**Confidence:** HIGH

<research_summary>
## Summary

Researched the SwiftUI ecosystem for building a macOS menu bar-only app. The standard approach since macOS 13 Ventura uses SwiftUI's native `MenuBarExtra` scene, replacing the older AppKit `NSStatusItem` approach. MenuBarExtra provides two styles: `.menu` (dropdown menu) and `.window` (popover-like panel with custom SwiftUI views).

Key finding: MenuBarExtra is the right choice for Exmen since we're targeting modern macOS and want SwiftUI throughout. However, MenuBarExtra has known limitations around settings windows, menu refresh events, and runloop blocking. For advanced needs, the MenuBarExtraAccess library provides additional control.

**Primary recommendation:** Use pure SwiftUI with `MenuBarExtra` in `.window` style for maximum flexibility. Set `LSUIElement = YES` to hide dock icon. Include explicit quit button in UI.
</research_summary>

<standard_stack>
## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | 5.0+ | UI framework | Native Apple framework, declarative UI |
| MenuBarExtra | macOS 13+ | Menu bar scene | Native SwiftUI scene for menu bar apps |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MenuBarExtraAccess | latest | Enhanced MenuBarExtra control | If need programmatic show/hide or NSStatusItem access |
| Combine | built-in | Reactive updates | State management and async operations |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| MenuBarExtra | NSStatusItem (AppKit) | More control, but requires AppDelegate bridging, older API |
| .window style | .menu style | Menu style is simpler but less flexible for custom UI |

**Installation:**
```swift
// No external packages needed for basic menu bar app
// Optional: MenuBarExtraAccess if more control needed
.package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.0.0")
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```
Exmen/
├── ExmenApp.swift           # @main entry, MenuBarExtra scene
├── Views/
│   ├── MenuContentView.swift  # Main menu content shown in popover
│   └── ActionRowView.swift    # Individual action item view
├── Models/
│   └── Action.swift           # Action data model
├── ViewModels/
│   └── ActionViewModel.swift  # State management for actions
└── Info.plist                 # LSUIElement = YES
```

### Pattern 1: Pure SwiftUI MenuBarExtra
**What:** Use MenuBarExtra as the only scene, no WindowGroup
**When to use:** Menu bar-only apps with no main window
**Example:**
```swift
// Source: https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
@main
struct ExmenApp: App {
    var body: some Scene {
        MenuBarExtra("Exmen", systemImage: "terminal") {
            ContentView()
                .frame(width: 300, height: 400)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Pattern 2: Menu Bar Icon with Custom Image
**What:** Use custom icon instead of SF Symbol
**When to use:** Branded app icon in menu bar
**Example:**
```swift
// Source: https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
MenuBarExtra {
    ContentView()
} label: {
    let image: NSImage = {
        let img = NSImage(named: "MenuBarIcon")!
        let ratio = img.size.height / img.size.width
        img.size.height = 18
        img.size.width = 18 / ratio
        return img
    }()
    Image(nsImage: image)
}
```

### Pattern 3: Quit Button in Menu
**What:** Explicit quit mechanism since no dock icon
**When to use:** All menu bar-only apps
**Example:**
```swift
// Source: https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
Button("Quit Exmen") {
    NSApp.terminate(nil)
}
.keyboardShortcut("q", modifiers: .command)
```

### Anti-Patterns to Avoid
- **Using WindowGroup with MenuBarExtra:** Can cause termination bugs when Window and MenuBarExtra combined
- **Forgetting quit button:** Users have no way to exit app without dock icon
- **Not setting LSUIElement:** App will appear in dock unnecessarily
- **Using .menu style for complex UI:** The .menu style limits you to basic menu items only
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Menu bar presence | Custom NSStatusItem wrapper | MenuBarExtra | Native SwiftUI, handles lifecycle |
| Dock icon hiding | Runtime activation policy changes | LSUIElement in Info.plist | System-level, reliable |
| Menu popup window | Custom NSPanel/NSWindow | .menuBarExtraStyle(.window) | Native behavior, proper positioning |
| App termination | Custom shutdown logic | NSApp.terminate(nil) | Standard macOS pattern |
| Icon resizing | Manual CGImage manipulation | NSImage with size adjustment | Proper menu bar sizing |

**Key insight:** Menu bar apps are deceptively simple-looking but have complex lifecycle requirements. MenuBarExtra handles window positioning, click detection, and activation policy automatically. Fighting the framework leads to subtle bugs.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Settings Window Won't Open
**What goes wrong:** SettingsLink doesn't work in MenuBarExtra, settings window appears behind other apps
**Why it happens:** Menu bar apps use `.accessory` activation policy, macOS doesn't allow windows to become key without dock icon
**How to avoid:** Use workarounds: temporarily change activation policy, or use a floating panel
**Warning signs:** Settings click does nothing, or window appears but not focused
**Source:** [Peter Steinberger's 5-Hour Journey](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)

### Pitfall 2: Menu Content Doesn't Update
**What goes wrong:** With `.menu` style, menu items don't refresh when state changes
**Why it happens:** SwiftUI doesn't re-render menu body when opened (unlike AppKit's removeAllItems pattern)
**How to avoid:** Use `.window` style which properly observes state, or use MenuBarExtraAccess
**Warning signs:** Stale data in menu, changes not reflected until app restart
**Source:** [FB13683957](https://github.com/feedback-assistant/reports/issues/477)

### Pitfall 3: Runloop Blocking with .menu Style
**What goes wrong:** `isPresented` binding doesn't work, can't programmatically close menu
**Why it happens:** The .menu style blocks the runloop while open
**How to avoid:** Use `.window` style for interactive content
**Warning signs:** Bindings not firing, setting isPresented to false has no effect

### Pitfall 4: No Quit Mechanism
**What goes wrong:** Users can't quit the app
**Why it happens:** LSUIElement hides dock icon, so no right-click quit option
**How to avoid:** Always include a Quit button in your menu UI
**Warning signs:** Users force-quitting via Activity Monitor, complaints about "stuck" app
</common_pitfalls>

<code_examples>
## Code Examples

### Basic Menu Bar App Structure
```swift
// Source: https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
import SwiftUI

@main
struct ExmenApp: App {
    var body: some Scene {
        MenuBarExtra("Exmen", systemImage: "terminal") {
            MenuContentView()
                .frame(width: 320, height: 400)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Menu Content with Actions List and Quit
```swift
// Source: Community pattern
struct MenuContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Exmen")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Actions list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        ActionRow(action: action)
                    }
                }
                .padding()
            }

            Divider()

            // Footer with quit
            HStack {
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(8)
        }
    }
}
```

### Info.plist Configuration
```xml
<!-- Add to Info.plist to hide dock icon -->
<key>LSUIElement</key>
<true/>
```

Or in Xcode: Target → Info → Add "Application is agent (UIElement)" = YES
</code_examples>

<sota_updates>
## State of the Art (2024-2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSStatusItem + AppDelegate | MenuBarExtra scene | macOS 13 (2022) | Pure SwiftUI possible |
| Manual NSPopover | .menuBarExtraStyle(.window) | macOS 13 (2022) | Automatic window management |
| NSMenu for menu items | .menuBarExtraStyle(.menu) | macOS 13 (2022) | SwiftUI menus directly |

**New tools/patterns to consider:**
- **MenuBarExtraAccess:** Adds programmatic control Apple omitted (show/hide bindings, NSStatusItem access)
- **SwiftUI 5.0 improvements:** Better state management, though menu bar issues persist

**Deprecated/outdated:**
- **Manual NSStatusItem setup:** Still works but unnecessary complexity for new apps targeting macOS 13+
- **AppDelegate for menu bar:** Can be avoided with pure SwiftUI MenuBarExtra
</sota_updates>

<open_questions>
## Open Questions

1. **Settings window handling**
   - What we know: SettingsLink is buggy with MenuBarExtra, workarounds exist
   - What's unclear: Will Apple fix this in future macOS?
   - Recommendation: For v1, avoid Settings scene. If needed later, use activation policy workaround

2. **Menu refresh on open**
   - What we know: .menu style doesn't refresh, .window style does
   - What's unclear: Performance implications of .window style for simple menus
   - Recommendation: Use .window style for Exmen since we need dynamic action lists
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [Nil Coalescing Blog - Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) - February 2025, comprehensive tutorial
- [Apple Developer Documentation - MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) - Official API reference
- [Sarunw - Create a mac menu bar app in SwiftUI](https://sarunw.com/posts/swiftui-menu-bar-app/) - Step-by-step guide

### Secondary (MEDIUM confidence)
- [Peter Steinberger - Showing Settings from macOS Menu Bar Items](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) - June 2025, settings workarounds
- [MenuBarExtraAccess GitHub](https://github.com/orchetect/MenuBarExtraAccess) - Library for enhanced control
- [Feedback Assistant Reports](https://github.com/feedback-assistant/reports/issues/475) - Known issues FB13683950, FB13683957

### Tertiary (LOW confidence - needs validation)
- None - all findings verified
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: SwiftUI MenuBarExtra
- Ecosystem: MenuBarExtraAccess, AppKit bridging patterns
- Patterns: Menu bar app structure, window vs menu style
- Pitfalls: Settings windows, menu refresh, quit mechanism

**Confidence breakdown:**
- Standard stack: HIGH - official Apple APIs
- Architecture: HIGH - from official tutorials and widely-used patterns
- Pitfalls: HIGH - documented in Feedback Assistant and developer blogs
- Code examples: HIGH - from official sources and verified tutorials

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (30 days - SwiftUI MenuBarExtra API stable)
</metadata>

---

*Phase: 01-foundation*
*Research completed: 2026-01-20*
*Ready for planning: yes*
