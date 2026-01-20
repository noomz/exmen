import Foundation

/// Watches a directory for file system changes
class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let callback: () -> Void

    // Debounce to avoid multiple rapid callbacks
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    init(path: String, debounceInterval: TimeInterval = 0.5, callback: @escaping () -> Void) {
        self.path = NSString(string: path).expandingTildeInPath
        self.debounceInterval = debounceInterval
        self.callback = callback
    }

    /// Start watching the directory
    func start() -> Bool {
        // Open file descriptor for the directory
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("DirectoryWatcher: Failed to open \(path)")
            return false
        }

        // Create dispatch source
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.handleEvent()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source?.resume()
        print("DirectoryWatcher: Started watching \(path)")
        return true
    }

    /// Stop watching
    func stop() {
        debounceWorkItem?.cancel()
        source?.cancel()
        source = nil
    }

    /// Handle file system event with debouncing
    private func handleEvent() {
        // Cancel any pending callback
        debounceWorkItem?.cancel()

        // Schedule new callback after debounce interval
        let workItem = DispatchWorkItem { [weak self] in
            self?.callback()
        }
        debounceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    deinit {
        stop()
    }
}
