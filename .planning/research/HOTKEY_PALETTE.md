# Hotkey + Command Palette Research (Exmen)

> Target: native Swift/SwiftUI menu bar app, `LSUIElement=true` (accessory), macOS 13+.
> Researched June 2026. Two features: (A) system-wide global hotkey, (B) Spotlight-style command palette + HUD progress overlay.

## Overview

- **Global hotkey**: Use a library, not raw API. `sindresorhus/KeyboardShortcuts` (v2.4.0) is the recommended choice — it wraps the still-functional Carbon `RegisterEventHotKey`, ships a SwiftUI recorder UI, persists to `UserDefaults`, and is **fully App Sandbox / Mac App Store compatible with no special permission**.
- **Palette window**: a subclassed `NSPanel` with `.nonactivatingPanel` + `.borderless`, `level = .floating` (or `.popUpMenu`), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, overriding `canBecomeKey`. The accessory app must briefly `NSApp.activate(...)` to receive text-input focus.
- **HUD**: same panel pattern but `becomesKeyOnlyIfNeeded`/never key, `ignoresMouseEvents = true`, positioned top-center, auto-hides.
- **Permissions**: `RegisterEventHotKey` (and thus KeyboardShortcuts) needs **no TCC permission**. `CGEventTap` and `NSEvent.addGlobalMonitorForEvents` need **Input Monitoring / Accessibility**. Prefer the former.

---

## Global Hotkey

### Options table

| Option | Status 2026 | Can consume event? | Permission needed | User-configurable UI | Notes |
|---|---|---|---|---|---|
| Carbon `RegisterEventHotKey` | Deprecated since 10.8 but **still works** in macOS 15/26 | Yes (consumes the hotkey) | **None** (no TCC prompt) | Build yourself | Sequoia bug: Option-only / Option+Shift-only combos no longer fire (FB15168205). Avoid Option-only shortcuts. |
| `NSEvent.addGlobalMonitorForEvents` | Works | **No** — observe-only, cannot block/consume the event | **Accessibility** (`AXIsProcessTrusted`) | Build yourself | Also won't fire while your own app is key; needs a *local* monitor too. Lightweight but limited. |
| `CGEventTap` | Works, Apple's "modern" recommendation | Yes (can consume/modify) | **Input Monitoring** (`CGRequestListenEventAccess`) | Build yourself | Most powerful, but triggers a TCC prompt that scares users; fragile across taps being disabled. |
| **`sindresorhus/KeyboardShortcuts`** (SPM) | **v2.4.0** (Sep 2025), actively maintained | Yes (built on RegisterEventHotKey) | **None** | **Built-in `Recorder` (AppKit + SwiftUI)** | Sandbox + MAS compatible. Recorder stores in UserDefaults, warns on conflicts, fires while NSMenu/MenuBarExtra open. **Recommended.** |
| `soffes/HotKey` (SPM) | Maintained but minimal | Yes | None | **No UI** — hardcoded shortcuts only | Good only for fixed, non-user-editable shortcuts. |

### Recommendation

Use **`sindresorhus/KeyboardShortcuts` v2.4.0**. It gives a user-configurable shortcut, a drop-in recorder, no permission prompt, and sandbox compatibility — all the manual `RegisterEventHotKey` plumbing handled. Pick `soffes/HotKey` only if the shortcut is fixed and you want zero recorder UI. Reserve `CGEventTap`/`NSEvent` global monitors for cases needing arbitrary key interception (not this app).

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePalette = Self("togglePalette",
        default: .init(.space, modifiers: [.command, .option]))
}

// AppDelegate / app init — register the handler once:
KeyboardShortcuts.onKeyUp(for: .togglePalette) { [weak self] in
    self?.paletteController.toggle()
}

// Settings view — user-editable recorder:
import SwiftUI
struct ShortcutSettings: View {
    var body: some View {
        Form { KeyboardShortcuts.Recorder("Summon palette:", name: .togglePalette) }
    }
}
```

### Permissions: request / check

- **KeyboardShortcuts path: nothing to request.** No `AXIsProcessTrusted`, no Input Monitoring. This is the main reason to prefer it.
- If you ever use `NSEvent` global monitor or `CGEventTap`:

```swift
// Accessibility (NSEvent global monitor / AX APIs)
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts) // prompts + opens System Settings pane

// Input Monitoring (CGEventTap)
if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
```

Both deep-link to System Settings ▸ Privacy & Security ▸ Accessibility / Input Monitoring. The user must toggle manually; the prompt cannot grant it directly.

---

## Command Palette Window

Subclass `NSPanel`. The accessory (`LSUIElement`) app shows it, makes it key, and accepts typing.

```swift
final class PalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating              // use .popUpMenu to also float over the Dock/menu bar
        hidesOnDeactivate = false      // we manage dismissal ourselves
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        // Show on every Space + over other apps' fullscreen spaces:
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = NSHostingView(rootView: PaletteView())
    }

    // Borderless windows are NOT key by default — required for text input:
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Dismiss on Escape (cancelOperation) and on losing key:
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func resignKey() { super.resignKey(); orderOut(nil) }
}
```

### Showing it from an accessory app (becoming key + focus)

An `LSUIElement` app is `.accessory` by default; its windows will not reliably become key/accept first-responder text input unless the app is activated first.

```swift
func showPalette() {
    centerOnActiveScreen()
    // Accessory apps must activate to receive keyboard focus for typing:
    NSApp.activate(ignoringOtherApps: true)   // macOS 14+: NSApp.activate()
    panel.makeKeyAndOrderFront(nil)
}
```

> If you must keep policy `.accessory` and still type, the `NSApp.activate` + `canBecomeKey=true` combo is the reliable recipe. Some apps temporarily switch `NSApp.setActivationPolicy(.regular)` while the palette is open and back to `.accessory` on close — only needed if focus still misbehaves.

### SwiftUI: focus the search field, dismiss on Escape

```swift
struct PaletteView: View {
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($searchFocused)
                .onExitCommand { NSApp.keyWindow?.orderOut(nil) } // Escape
            // …filtered results list…
        }
        .padding()
        .background(.ultraThinMaterial)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }
}
```

- `@FocusState` + `.onAppear` (deferred to next runloop) gives the field first responder so typing works immediately.
- `.onExitCommand` handles Escape inside SwiftUI; the panel's `cancelOperation` is the AppKit backstop.
- Dismiss-on-focus-loss is handled by the panel's `resignKey()` override above.

### Centering on the active screen (multi-monitor)

```swift
func centerOnActiveScreen() {
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main ?? NSScreen.screens.first!
    let vf = screen.visibleFrame
    let size = panel.frame.size
    let origin = NSPoint(
        x: vf.midX - size.width / 2,
        y: vf.midY - size.height / 2 + vf.height * 0.08) // bias slightly above center, Spotlight-style
    panel.setFrameOrigin(origin)
}
```

Pick the screen under the mouse (or with the focused window) rather than `NSScreen.main`, so the palette appears where the user is looking on multi-monitor setups.

---

## HUD Overlay

Non-activating, focus-never-stealing, optionally click-through progress panel pinned top-center.

```swift
final class HUDPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        level = .statusBar                 // above .floating; sits near menu bar layer
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear; isOpaque = false; hasShadow = true
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true          // click-through; toggle off if HUD needs a Cancel button
        contentView = NSHostingView(rootView: HUDView())
    }
    override var canBecomeKey: Bool { false }   // never steals focus
}

func showHUD() {
    guard let vf = NSScreen.main?.visibleFrame else { return }
    let s = hud.frame.size
    hud.setFrameOrigin(NSPoint(x: vf.midX - s.width/2, y: vf.maxY - s.height - 24)) // top-center
    hud.orderFrontRegardless()             // show without activating the app
}
```

- `orderFrontRegardless()` (not `makeKeyAndOrderFront`) keeps the user's current app key.
- `canBecomeKey = false` + `.nonactivatingPanel` guarantees no focus theft.
- `ignoresMouseEvents = true` makes it click-through; set `false` only when the HUD shows an interactive control.
- Auto-hide via a `Task`/timer that calls `hud.orderOut(nil)` after completion, optionally with a fade using `animator().alphaValue = 0`.

---

## SwiftUI Integration

- Host both panels with `NSHostingView` (or `NSHostingController`); panels are AppKit, content is SwiftUI.
- App shell: `MenuBarExtra` (macOS 13+) for the status item; manage panels via an `NSWindowController`/`@Observable` controller, not SwiftUI `WindowGroup` (you need precise level/collectionBehavior control SwiftUI scenes don't expose).
- Focus: `@FocusState` for the search field; defer setting it to the next runloop tick in `.onAppear` so the panel is key first.
- Escape: `.onExitCommand` in SwiftUI + `cancelOperation(_:)` on the panel.
- Pass an `@Observable` view model (progress, results) into both `NSHostingView`s so live HUD progress updates render automatically.

---

## Pitfalls

1. **Accessory activation policy**: `LSUIElement` windows often can't become key for text input until `NSApp.activate(ignoringOtherApps:)` runs. Always activate before `makeKeyAndOrderFront` for the palette. The HUD must do the opposite — `orderFrontRegardless()`, never activate.
2. **Borderless = not key by default**: must override `canBecomeKey`/`canBecomeMain` to `true`, or the search field silently won't accept typing.
3. **Fullscreen Spaces**: without `.fullScreenAuxiliary` the panel won't appear over another app's fullscreen window; without `.canJoinAllSpaces` it vanishes when the user switches Space. Use `level = .popUpMenu` if it must sit above the menu bar.
4. **Sequoia hotkey regression**: `RegisterEventHotKey` ignores Option-only and Option+Shift-only modifier combos on macOS 15+ (FB15168205). Default to ⌘-based combos; KeyboardShortcuts inherits this limitation.
5. **`NSEvent` global monitor caveats**: cannot consume the event (the keystroke still reaches the focused app), doesn't fire when your own app is key (add a local monitor too), and needs Accessibility. This is why a `RegisterEventHotKey`-based lib is preferred for a true hotkey.
6. **App Sandbox + global hotkeys**: `RegisterEventHotKey`/KeyboardShortcuts work sandboxed with **no entitlement and no TCC prompt**. `CGEventTap` works sandboxed only since 10.15 and requires the Input Monitoring grant — a worse UX. Choosing KeyboardShortcuts avoids sandbox/entitlement friction entirely.
7. **Notarization**: none of these APIs require special entitlements, so notarization is unaffected. If you add Accessibility/Input-Monitoring TCC usage, the grant survives notarized signed builds but resets if the binary's code signature/identity changes — sign stably.
8. **`hidesOnDeactivate` vs manual dismiss**: convenient but it also hides the palette whenever any app deactivates yours (e.g. a system alert), which can feel abrupt. Prefer explicit `resignKey()` dismissal so you control timing; don't combine both blindly.
9. **HUD over palette ordering**: give HUD a higher `level` (`.statusBar`) than the palette (`.floating`) so progress shows on top; otherwise the palette can cover it.

---

## Recommendation

1. **Hotkey**: adopt `sindresorhus/KeyboardShortcuts` v2.4.0 via SPM. Define a `KeyboardShortcuts.Name`, register `onKeyUp`, expose `KeyboardShortcuts.Recorder` in Settings. No permission prompt, sandbox-safe.
2. **Palette**: subclass `NSPanel` (`.nonactivatingPanel`+`.borderless`, `level=.floating`/`.popUpMenu`, `collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]`, `canBecomeKey=true`). Show with `NSApp.activate` + `makeKeyAndOrderFront`; host `PaletteView` via `NSHostingView`; focus via `@FocusState`; dismiss on `cancelOperation`/`resignKey`. Center on the screen under the cursor.
3. **HUD**: separate `NSPanel`, `canBecomeKey=false`, `ignoresMouseEvents=true`, `level=.statusBar`, shown with `orderFrontRegardless()` at top-center, auto-hide on completion.
4. Manage both panels with an `@Observable` controller and a `MenuBarExtra` shell; avoid SwiftUI `WindowGroup` for these.

## Sources

- https://github.com/sindresorhus/KeyboardShortcuts and https://github.com/sindresorhus/KeyboardShortcuts/releases (v2.4.0)
- https://github.com/soffes/HotKey
- https://developer.apple.com/forums/thread/735223 (Apple DTS on RegisterEventHotKey vs CGEventTap + permissions)
- https://github.com/feedback-assistant/reports/issues/552 (FB15168205 Sequoia Option-modifier regression)
- https://cindori.com/developer/floating-panel (FloatingPanel NSPanel subclass pattern)
- https://fazm.ai/blog/swiftui-floating-panel and https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
- https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac
