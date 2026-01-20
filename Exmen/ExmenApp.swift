import SwiftUI

@main
struct ExmenApp: App {
    init() {
        // Initialize the action service
        ActionService.shared.initialize()
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
