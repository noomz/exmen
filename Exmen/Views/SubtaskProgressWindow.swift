import AppKit
import SwiftUI

/// Standalone AppKit window controller hosting a SwiftUI list of live subtask
/// progress (D-09). Like `ServiceOutputWindow`, it is an independent `NSWindow`
/// that survives menu-bar popup close/open cycles (`isReleasedWhenClosed = false`).
class SubtaskProgressWindow: NSWindowController, NSWindowDelegate {

    /// Strong reference to the currently-shown window so it is not deallocated
    /// while orchestration runs. Cleared in `windowWillClose` so it can be recreated.
    static var current: SubtaskProgressWindow?

    // MARK: - Init

    init(orchestrator: SubtaskOrchestrator, title: String = "Subtask Progress") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(rootView: SubtaskProgressView(orchestrator: orchestrator))
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Presentation

    /// Build (or reuse) the shared window and bring it to the front.
    @discardableResult
    static func present(orchestrator: SubtaskOrchestrator, title: String) -> SubtaskProgressWindow {
        let controller = current ?? SubtaskProgressWindow(orchestrator: orchestrator, title: title)
        current = controller
        controller.window?.title = title
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if SubtaskProgressWindow.current === self {
            SubtaskProgressWindow.current = nil
        }
    }
}

// MARK: - SubtaskProgressView

/// SwiftUI list bound to the orchestrator's `@Published` state (ORCH-03).
/// Header shows overall completed/total percentage (D-11); each row shows a
/// Phase-8-convention status dot (D-10), name, live elapsed, a running spinner,
/// and an opt-in per-subtask progress bar when `progressPercent` is set (D-12).
struct SubtaskProgressView: View {
    @ObservedObject var orchestrator: SubtaskOrchestrator

    /// Drives live elapsed-time refresh while a run is in progress.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var completedCount: Int {
        orchestrator.subtaskStates.filter { $0.status.isTerminal }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 420, minHeight: 280)
        .onReceive(ticker) { now = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Overall progress")
                    .font(.headline)
                Spacer()
                Text("\(completedCount)/\(orchestrator.subtaskStates.count) · \(orchestrator.overallProgressPercent)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: Double(orchestrator.overallProgressPercent), total: 100)
        }
        .padding(12)
    }

    private var list: some View {
        List(orchestrator.subtaskStates) { state in
            row(for: state)
        }
    }

    @ViewBuilder
    private func row(for state: SubtaskState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.status.dotColor)
                    .frame(width: 8, height: 8)

                Text(state.name)
                    .font(.body)

                if state.status == .running {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }

                Spacer()

                Text(SubtaskState.elapsedString(elapsed(for: state)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            if let percent = state.progressPercent {
                ProgressView(value: Double(percent), total: 100)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    /// Live elapsed time. While running, recompute against the ticking `now`;
    /// once terminal, `state.elapsed` is frozen at `endedAt`.
    private func elapsed(for state: SubtaskState) -> TimeInterval {
        guard let start = state.startedAt else { return 0 }
        if let end = state.endedAt { return end.timeIntervalSince(start) }
        return now.timeIntervalSince(start)
    }
}
