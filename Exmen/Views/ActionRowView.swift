import SwiftUI

struct ActionRowView: View {
    let action: Action
    let isExecuting: Bool
    let onExecute: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onExecute) {
            HStack(spacing: 8) {
                // Icon or loading spinner
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16)
                } else {
                    Image(systemName: action.displayIcon)
                        .font(.caption)
                        .frame(width: 16)
                        .foregroundColor(.accentColor)
                }

                // Title and description/status
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(action.displayTitle)
                            .font(.callout)

                        // Badge if present
                        if let badge = action.dynamicBadge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }

                    // Status or description
                    if let status = action.dynamicStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    } else if !action.description.isEmpty {
                        Text(action.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Play icon on hover
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(isHovered && !isExecuting ? 1 : 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
