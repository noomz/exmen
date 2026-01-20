import Foundation
import AppKit
import UserNotifications

/// Service for handling script output
class OutputService {
    static let shared = OutputService()

    private init() {
        // Request notification permissions
        requestNotificationPermission()
    }

    /// Handle script result based on output config
    func handle(_ result: ScriptResult, config: OutputConfig, actionName: String) {
        let output = result.trimmedOutput

        switch config.handler {
        case .clipboard:
            copyToClipboard(output)
        case .notification:
            showNotification(title: actionName, body: output, isError: !result.isSuccess)
        case .popup:
            // Popup is handled by the view layer
            break
        }
    }

    /// Copy text to system clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Show macOS notification
    func showNotification(title: String, body: String, isError: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = isError ? "\(title) - Error" : title
        content.body = body.isEmpty ? (isError ? "Script failed" : "Completed") : body
        content.sound = isError ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            }
        }
    }

    /// Request notification permission
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
