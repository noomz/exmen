import SwiftUI

/// View for displaying script result in a popup
struct PopupResultView: View {
    let actionName: String
    let result: ScriptResult
    let cleanOutput: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                Text(actionName)
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Output content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !cleanOutput.isEmpty {
                        Text(cleanOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !result.error.isEmpty {
                        Text(result.error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if cleanOutput.isEmpty && result.error.isEmpty {
                        Text("No output")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("Exit code: \(result.exitCode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text(String(format: "%.2fs", result.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    OutputService.shared.copyToClipboard(cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                Button("Close") {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(12)
        }
        .frame(width: 400, height: 300)
    }
}
