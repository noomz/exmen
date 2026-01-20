import SwiftUI

struct MenuContentView: View {
    @ObservedObject private var actionService = ActionService.shared
    @State private var executingActionId: UUID?
    @State private var popupResult: (action: Action, result: ScriptResult, cleanOutput: String)?

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

            // Actions list or popup
            if let popup = popupResult {
                PopupResultView(
                    actionName: popup.action.name,
                    result: popup.result,
                    cleanOutput: popup.cleanOutput,
                    onDismiss: { popupResult = nil }
                )
            } else if actionService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if actionService.actions.isEmpty {
                Text("No actions configured")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(actionService.actions) { action in
                            ActionRowView(
                                action: action,
                                isExecuting: executingActionId == action.id,
                                onExecute: { executeAction(action) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("v1.0")
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
        .frame(width: popupResult != nil ? 400 : 280, height: popupResult != nil ? 350 : 320)
    }

    private func executeAction(_ action: Action) {
        guard let scriptConfig = action.scriptConfig else {
            print("No script config for action: \(action.name)")
            return
        }

        executingActionId = action.id

        // Hide menu on click if enabled and not showing popup
        if action.hideOnClick && action.outputConfig.handler != .popup {
            NSApp.keyWindow?.close()
        }

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
            popupResult = (action, result, cleanOutput)
        }
    }
}

#Preview {
    MenuContentView()
}
