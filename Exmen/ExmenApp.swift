import SwiftUI

@main
struct ExmenApp: App {
    init() {
        // Prevent macOS from automatically terminating the app
        // when there are no visible windows (menu bar apps have none)
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app must remain running")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Initialize the action service (also registers services with ServiceManager)
        ActionService.shared.initialize()

        // Reconnect to any keep_alive services that survived a previous app quit
        ServiceManager.shared.reconnectKeepAliveServices()

        // Register for app termination to clean up non-keep_alive services
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            ServiceManager.shared.handleAppWillTerminate()
        }

        // Start the IPC socket server
        SocketServer.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
