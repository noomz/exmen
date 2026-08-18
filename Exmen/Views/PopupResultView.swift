import SwiftUI

/// View for displaying script result in a popup
struct PopupResultView: View {
    let result: ScriptResult
    let cleanOutput: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                    .font(.caption)
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
                .buttonStyle(.bordered)
                .font(.caption)
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(8)
        }
        .frame(minWidth: 420, idealWidth: 450, minHeight: 240, idealHeight: 320)
    }
}
