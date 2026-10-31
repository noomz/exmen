import AppKit
import SwiftUI

struct AppVersion {
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

struct SettingsView: View {
    private let version = AppVersion()

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Exmen")
                .font(.title2)
            Text("Version \(version.version) (\(version.build))")
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 200)
    }
}

final class SettingsWindow: NSWindowController {
    private(set) static var existing: SettingsWindow?
    static let shared: SettingsWindow = {
        let controller = SettingsWindow()
        existing = controller
        return controller
    }()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func present() {
        window?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

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
