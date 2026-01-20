import SwiftUI

@main
struct ExmenApp: App {
    init() {
        // Initialize the action service
        ActionService.shared.initialize()
    }

    var body: some Scene {
        MenuBarExtra("Exmen", systemImage: "terminal.fill") {
            MenuContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
