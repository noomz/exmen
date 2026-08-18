import SwiftUI

struct MenuContentView: View {
    @ObservedObject private var actionService = ActionService.shared
    @ObservedObject private var serviceManager = ServiceManager.shared
    @State private var executingActionId: UUID?
    @AppStorage("exmen.showHiddenItems") private var showHiddenItems = false

    private var displayedActions: [Action] {
        showHiddenItems
            ? actionService.actions
            : actionService.actions.filter { !$0.isHidden }
    }

    private var displayedServices: [ManagedService] {
        showHiddenItems
            ? serviceManager.services
            : serviceManager.services.filter { !$0.action.isHidden }
    }

    private var hiddenCount: Int {
        actionService.actions.filter(\.isHidden).count
            + serviceManager.services.filter { $0.action.isHidden }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.accentColor)
                Text("Exmen")
                    .font(.headline)
                Spacer()
                Button(action: {
                    actionService.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reload actions")
            }
            .padding()

            Divider()

            // Actions list
            if actionService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedActions.isEmpty && displayedServices.isEmpty {
                Text(hiddenCount > 0 ? "No visible actions" : "No actions configured")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // Actions section — regular (non-service) actions
                        ForEach(displayedActions) { action in
                            ActionRowView(
                                action: action,
                                isExecuting: executingActionId == action.id,
                                onExecute: { executeAction(action) }
                            )
                        }

                        // Services section — shown below actions when services are configured
                        if !displayedServices.isEmpty {
                            Divider()
                                .padding(.vertical, 4)

                            HStack {
                                Text("Services")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)

                            ForEach(displayedServices) { service in
                                ServiceRowView(service: service)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }

            Divider()

            HStack {
                Toggle(isOn: $showHiddenItems) {
                    Text(hiddenCount > 0 ? "Show hidden (\(hiddenCount))" : "Show hidden")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Reveal actions and services hidden by [when] conditions")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Footer
            HStack {
                Text("v1.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 280, height: 400)
    }

    private func executeAction(_ action: Action) {
        // Results are shown in ActionResultWindow, so the extra can close now.
        if action.hideOnClick {
            dismissMenuExtraWindow()
        }

        // Phase 11: actions declaring [[subtasks]] run through the orchestrator (D-01),
        // not ScriptRunner. The single-action path below is unchanged.
        if let subtasks = action.subtasks, !subtasks.isEmpty {
            executeSubtaskAction(action, subtasks: subtasks)
            return
        }

        guard let scriptConfig = action.scriptConfig else {
            print("No script config for action: \(action.name)")
            return
        }

        executingActionId = action.id

        Task {
            do {
                let result = try await ScriptRunner.shared.run(scriptConfig)

                await MainActor.run {
                    executingActionId = nil
                    handleResult(result, for: action)
                }
            } catch {
                await MainActor.run {
                    executingActionId = nil
                    let errorResult = ScriptResult(
                        output: "",
                        error: error.localizedDescription,
                        exitCode: -1,
                        duration: 0
                    )
                    handleResult(errorResult, for: action)
                }
            }
        }
    }

    /// Phase 11: open the live progress window and run the orchestrator (ORCH-03),
    /// then deliver the aggregated summary on completion (ORCH-05/D-15).
    private func executeSubtaskAction(_ action: Action, subtasks: [SubtaskConfig]) {
        let orchestrator = SubtaskOrchestrator.shared
        SubtaskProgressWindow.present(orchestrator: orchestrator, title: "\(action.name) — Subtasks")

        Task {
            try? await orchestrator.run(subtasks: subtasks)
            await MainActor.run { deliverSummary(for: action) }
        }
    }

    /// Deliver the orchestration outcome as a popup + notification with error
    /// severity when any subtask failed (ORCH-05/D-15).
    private func deliverSummary(for action: Action) {
        guard let summary = SubtaskOrchestrator.shared.completionSummary else { return }

        OutputService.shared.showNotification(
            title: action.name,
            body: summary.summaryLine,
            isError: summary.verdictFailed
        )

        let result = ScriptResult(
            output: summary.summaryLine,
            error: summary.verdictFailed ? "One or more subtasks failed" : "",
            exitCode: summary.verdictFailed ? 1 : 0,
            duration: 0
        )
        ActionResultWindow.present(
            title: action.name,
            result: result,
            cleanOutput: summary.summaryLine
        )
    }

    private func handleResult(_ result: ScriptResult, for action: Action) {
        // Process hooks and get clean output
        let (cleanOutput, _) = actionService.processScriptResult(result, for: action)

        switch action.outputConfig.handler {
        case .clipboard:
            OutputService.shared.copyToClipboard(cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            if result.isSuccess {
                OutputService.shared.showNotification(
                    title: action.name,
                    body: "Copied to clipboard",
                    isError: false
                )
            }
        case .notification:
            OutputService.shared.showNotification(
                title: action.name,
                body: cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                isError: !result.isSuccess
            )
        case .popup:
            ActionResultWindow.present(
                title: action.name,
                result: result,
                cleanOutput: cleanOutput
            )
        }
    }

    /// Close the MenuBarExtra panel only. Standalone result/progress/output
    /// windows are regular NSWindows and must stay open.
    private func dismissMenuExtraWindow() {
        let standalone: [NSWindow] = [
            ActionResultWindow.current?.window,
            SubtaskProgressWindow.current?.window
        ].compactMap { $0 } + ServiceManager.shared.services.compactMap { $0.outputWindow?.window }

        func isStandalone(_ window: NSWindow) -> Bool {
            standalone.contains { $0 === window }
        }

        if let key = NSApp.keyWindow, !isStandalone(key) {
            key.close()
            return
        }

        for window in NSApp.windows where window.isVisible && !isStandalone(window) {
            let className = String(describing: type(of: window))
            let looksLikeMenuExtra =
                window is NSPanel
                || window.styleMask.contains(.nonactivatingPanel)
                || className.contains("StatusBar")
                || className.contains("MenuBarExtra")
            if looksLikeMenuExtra {
                window.close()
                return
            }
        }
    }
}

#Preview {
    MenuContentView()
}
