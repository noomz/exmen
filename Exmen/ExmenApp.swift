import AppKit
import ServiceManagement
import SwiftUI

struct AppVersion {
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?
    @Published private(set) var isChanging = false
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () async throws -> Void

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () async throws -> Void = { try await SMAppService.mainApp.unregister() }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }

    func refresh() {
        status = readStatus()
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        errorMessage = nil
        do {
            if enabled {
                try register()
            } else {
                try await unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

struct SettingsView: View {
    private let version = AppVersion()
    @StateObject private var loginItem = LoginItemSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch on startup", isOn: Binding(
                get: { loginItem.status == .enabled || loginItem.status == .requiresApproval },
                set: { enabled in Task { await loginItem.setEnabled(enabled) } }
            ))
            .disabled(loginItem.isChanging)
            if loginItem.status == .requiresApproval {
                Text("Approve Exmen in Login Items to launch on startup.")
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = loginItem.errorMessage {
                Text(error).foregroundStyle(.red)
                if loginItem.status != .requiresApproval {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Exmen").font(.headline)
                    Text("Version \(version.version) (\(version.build))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 400, height: 220, alignment: .topLeading)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if notification.object as? NSWindow === SettingsWindow.existing?.window {
                loginItem.refresh()
            }
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
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
