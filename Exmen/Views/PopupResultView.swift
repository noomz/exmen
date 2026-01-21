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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            Divider()

            // Output content
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !cleanOutput.isEmpty {
                        Text(cleanOutput)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !result.error.isEmpty {
                        Text(result.error)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if cleanOutput.isEmpty && result.error.isEmpty {
                        Text("No output")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(10)
            }

            Divider()

            // Footer
            HStack {
                Text("Exit: \(result.exitCode)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2fs", result.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    OutputService.shared.copyToClipboard(cleanOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .font(.caption)
                Button("Close") {
                    onDismiss()
                }
                .font(.caption)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(8)
        }
        .frame(width: 450, height: 400)
    }
}
