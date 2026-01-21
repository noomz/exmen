import SwiftUI

@main
struct ExmenApp: App {
    init() {
        // Initialize the action service
        ActionService.shared.initialize()

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
