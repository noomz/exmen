import SwiftUI

struct ActionRowView: View {
    let action: Action
    let isExecuting: Bool
    let onExecute: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onExecute) {
            HStack(spacing: 12) {
                // Icon or loading spinner
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20)
                } else {
                    Image(systemName: action.displayIcon)
                        .frame(width: 20)
                        .foregroundColor(.accentColor)
                }

                // Title and description/status
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(action.displayTitle)
                            .font(.body)

                        // Badge if present
                        if let badge = action.dynamicBadge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    // Status or description
                    if let status = action.dynamicStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else if !action.description.isEmpty {
                        Text(action.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Play icon on hover
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isHovered && !isExecuting ? 1 : 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
