import Foundation

/// Unix domain socket server for IPC communication
/// Allows external tools to query and control Exmen
@MainActor
class SocketServer {
    static let shared = SocketServer()

    private var serverSocket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var isRunning = false
    private var clientSockets: [Int32] = []

    /// Socket file path
    var socketPath: String {
        let configDir = NSString(string: "~/.config/exmen").expandingTildeInPath
        return "\(configDir)/exmen.sock"
    }

    private init() {}

    /// Start the socket server
    func start() {
        guard !isRunning else {
            print("SocketServer: Already running")
            return
        }

        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("SocketServer: Failed to create socket: \(errno)")
            return
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy path to sun_path
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            pathBytes.withUnsafeBufferPointer { pathBuffer in
                let dst = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                let copyLen = min(pathBuffer.count, maxLen - 1)
                memcpy(dst, pathBuffer.baseAddress!, copyLen)
                dst[copyLen] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("SocketServer: Failed to bind: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Listen for connections
        guard listen(serverSocket, 5) == 0 else {
            print("SocketServer: Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Capture socket for use in closures
        let socket = serverSocket

        // Set up dispatch source for accepting connections
        readSource = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .global())
        readSource?.setEventHandler { [weak self] in
            Self.acceptConnection(serverSocket: socket, server: self)
        }
        readSource?.setCancelHandler {
            close(socket)
        }
        readSource?.resume()

        isRunning = true
        print("SocketServer: Listening on \(socketPath)")
    }

    /// Stop the socket server
    func stop() {
        guard isRunning else { return }

        readSource?.cancel()
        readSource = nil

        // Close all client sockets
        for clientSocket in clientSockets {
            close(clientSocket)
        }
        clientSockets.removeAll()

        // Server socket is closed by cancelHandler
        serverSocket = -1

        // Remove socket file
        unlink(socketPath)

        isRunning = false
        print("SocketServer: Stopped")
    }

    /// Accept incoming connection (runs on background queue)
    private nonisolated static func acceptConnection(serverSocket: Int32, server: SocketServer?) {
        var clientAddr = sockaddr_un()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(serverSocket, sockaddrPtr, &clientAddrLen)
            }
        }

        guard clientSocket >= 0 else {
            print("SocketServer: Failed to accept connection: \(errno)")
            return
        }

        DispatchQueue.main.async {
            server?.clientSockets.append(clientSocket)
        }

        // Handle client in background
        handleClient(clientSocket, server: server)
    }

    /// Handle a client connection (runs on background queue)
    private nonisolated static func handleClient(_ clientSocket: Int32, server: SocketServer?) {
        defer {
            close(clientSocket)
            DispatchQueue.main.async {
                server?.clientSockets.removeAll { $0 == clientSocket }
            }
        }

        // Read request
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count - 1)

        guard bytesRead > 0 else {
            return
        }

        buffer[bytesRead] = 0
        let requestString = String(cString: buffer)

        // Process command and get response
        let response: String
        if let requestData = requestString.data(using: .utf8) {
            // Call command handler on main thread
            let semaphore = DispatchSemaphore(value: 0)
            var result = ""

            DispatchQueue.main.async {
                result = CommandHandler.shared.handle(requestData)
                semaphore.signal()
            }

            semaphore.wait()
            response = result
        } else {
            response = "{\"success\":false,\"error\":\"Invalid request\"}"
        }

        // Send response
        let responseData = response.utf8CString
        _ = responseData.withUnsafeBufferPointer { buffer in
            write(clientSocket, buffer.baseAddress!, buffer.count - 1) // -1 to exclude null terminator
        }
    }
}
