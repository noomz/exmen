import AppKit
import SwiftTerm

/// An independent AppKit window controller that hosts a SwiftTerm terminal view
/// for a managed service's output.
///
/// This window is deliberately NOT part of the SwiftUI view hierarchy — it is an
/// independent NSWindow that survives menu bar popup close/open cycles.
class ServiceOutputWindow: NSWindowController, NSWindowDelegate {

    private weak var service: ManagedService?

    // MARK: - Init

    init(for service: ManagedService) {
        self.service = service

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = service.action.name + " - Output"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self

        // Set content view: terminal if available, placeholder if reconnected keep_alive service
        if let tv = service.terminalView {
            window.contentView = tv
        } else {
            window.contentView = makePlaceholderView()
        }

        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Public API

    /// Replace the window's content view with a new terminal view (e.g. after restart).
    func updateTerminalView(_ terminalView: LocalProcessTerminalView) {
        window?.contentView = terminalView
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Allow the service to recreate this window on next showOutput call
        service?.outputWindow = nil
    }

    // MARK: - Private helpers

    private func makePlaceholderView() -> NSView {
        let label = NSTextField(
            labelWithString:
                "Reconnected to running service — previous output not available.\n" +
                "New output will appear after restart."
        )
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40)
        ])

        return container
    }
}
