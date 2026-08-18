import AppKit
import SwiftUI

/// Standalone AppKit window controller hosting a SwiftUI script-result view.
///
/// Like `SubtaskProgressWindow` and `ServiceOutputWindow`, it is an independent
/// `NSWindow` so the menu-bar window can stay available while a result is shown.
class ActionResultWindow: NSWindowController, NSWindowDelegate {
    /// Strong reference to the currently-shown window so it is not deallocated.
    /// Cleared in `windowWillClose` so it can be recreated.
    static var current: ActionResultWindow?

    private var hostingView: NSHostingView<PopupResultView>?

    // MARK: - Init

    init(title: String, result: ScriptResult, cleanOutput: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        let hosting = NSHostingView(
            rootView: PopupResultView(
                result: result,
                cleanOutput: cleanOutput,
                onDismiss: { [weak self] in self?.close() }
            )
        )
        // Default sizingOptions include intrinsicContentSize, so a long dump
        // becomes the window's ideal size instead of scrolling.
        hosting.sizingOptions = [.minSize]
        hostingView = hosting
        window.contentView = hosting
        window.contentMinSize = NSSize(width: 420, height: 240)
        window.setContentSize(NSSize(width: 450, height: 320))
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Public API

    /// Show the latest result in one shared window. A new result replaces the
    /// content of the current window instead of spawning a new window.
    @discardableResult
    static func present(
        title: String,
        result: ScriptResult,
        cleanOutput: String
    ) -> ActionResultWindow {
        let controller: ActionResultWindow
        if let existing = current {
            existing.update(title: title, result: result, cleanOutput: cleanOutput)
            controller = existing
        } else {
            controller = ActionResultWindow(title: title, result: result, cleanOutput: cleanOutput)
            current = controller
        }

        // Do not NSApp.activate: hide_on_click defaults true and a long run
        // would steal focus from whatever the user switched to.
        controller.window?.deminiaturize(nil)
        if NSApp.isActive {
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            controller.window?.orderFrontRegardless()
        }
        return controller
    }

    func update(title: String, result: ScriptResult, cleanOutput: String) {
        window?.title = title
        hostingView?.rootView = PopupResultView(
            result: result,
            cleanOutput: cleanOutput,
            onDismiss: { [weak self] in self?.close() }
        )
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if ActionResultWindow.current === self {
            ActionResultWindow.current = nil
        }
    }
}
