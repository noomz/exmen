import Foundation

// MARK: - Socket Client

class SocketClient {
    let socketPath: String

    init(socketPath: String = NSString(string: "~/.config/exmen/exmen.sock").expandingTildeInPath) {
        self.socketPath = socketPath
    }

    func send(_ request: [String: Any]) -> Result<[String: Any], SocketError> {
        // Create socket
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            return .failure(.socketCreationFailed)
        }
        defer { close(sock) }

        // Prepare address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

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

        // Connect
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            if errno == ENOENT {
                return .failure(.socketNotFound)
            }
            if errno == ECONNREFUSED || errno == 61 {
                return .failure(.connectionRefused)
            }
            return .failure(.connectionFailed(errno))
        }

        // Send request
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestString = String(data: requestData, encoding: .utf8) else {
            return .failure(.serializationFailed)
        }

        let requestBytes = requestString.utf8CString
        _ = requestBytes.withUnsafeBufferPointer { buffer in
            write(sock, buffer.baseAddress!, buffer.count - 1)
        }

        // Read response
        var responseBuffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(sock, &responseBuffer, responseBuffer.count - 1)

        guard bytesRead > 0 else {
            return .failure(.noResponse)
        }

        responseBuffer[bytesRead] = 0
        let responseString = String(cString: responseBuffer)

        guard let responseData = responseString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return .failure(.invalidResponse(responseString))
        }

        return .success(json)
    }
}

enum SocketError: Error {
    case socketCreationFailed
    case socketNotFound
    case connectionRefused
    case connectionFailed(Int32)
    case serializationFailed
    case noResponse
    case invalidResponse(String)

    var message: String {
        switch self {
        case .socketCreationFailed:
            return "Failed to create socket"
        case .socketNotFound:
            return "Exmen is not running (socket not found)"
        case .connectionRefused:
            return "Exmen is not running (connection refused)"
        case .connectionFailed(let errno):
            return "Could not connect to Exmen (errno: \(errno))"
        case .serializationFailed:
            return "Failed to serialize request"
        case .noResponse:
            return "No response from Exmen"
        case .invalidResponse(let raw):
            return "Invalid response: \(raw)"
        }
    }
}

// MARK: - Command Line Interface

func printUsage() {
    let usage = """
    Usage: exmen <command> [options]

    Commands:
      list-actions          List all available actions
      run <name>            Run an action by name
      status <name>         Get status of an action

    Options:
      --json                Output raw JSON (for list-actions)
      --help, -h            Show this help message

    Examples:
      exmen list-actions
      exmen list-actions --json
      exmen run "Generate Phone Number"
      exmen status "System Status"
    """
    print(usage)
}

func handleListActions(json: Bool) {
    let client = SocketClient()
    let result = client.send(["command": "list-actions"])

    switch result {
    case .success(let response):
        if json {
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
            return
        }

        guard let success = response["success"] as? Bool, success else {
            if let error = response["error"] as? String {
                fputs("Error: \(error)\n", stderr)
            }
            exit(1)
        }

        if let actions = response["data"] as? [[String: Any]] {
            for action in actions {
                let name = action["name"] as? String ?? "Unknown"
                let icon = action["icon"] as? String ?? ""
                let desc = action["description"] as? String ?? ""
                let status = action["status"] as? String

                var output = "\(name)"
                if !icon.isEmpty {
                    output = "[\(icon)] \(output)"
                }
                if let status = status {
                    output += " (\(status))"
                }
                if !desc.isEmpty {
                    output += "\n    \(desc)"
                }
                print(output)
            }
        }

    case .failure(let error):
        fputs("Error: \(error.message)\n", stderr)
        exit(1)
    }
}

func handleRun(name: String) {
    let client = SocketClient()
    let result = client.send(["command": "run", "name": name])

    switch result {
    case .success(let response):
        guard let success = response["success"] as? Bool, success else {
            if let error = response["error"] as? String {
                fputs("Error: \(error)\n", stderr)
            }
            exit(1)
        }

        if let output = response["data"] as? String {
            print(output)
        }

    case .failure(let error):
        fputs("Error: \(error.message)\n", stderr)
        exit(1)
    }
}

func handleStatus(name: String) {
    let client = SocketClient()
    let result = client.send(["command": "status", "name": name])

    switch result {
    case .success(let response):
        guard let success = response["success"] as? Bool, success else {
            if let error = response["error"] as? String {
                fputs("Error: \(error)\n", stderr)
            }
            exit(1)
        }

        if let status = response["data"] as? [String: Any] {
            let name = status["name"] as? String ?? "Unknown"
            print("Action: \(name)")

            if let title = status["dynamicTitle"] as? String {
                print("Title: \(title)")
            }
            if let statusText = status["dynamicStatus"] as? String {
                print("Status: \(statusText)")
            }
            if let badge = status["dynamicBadge"] as? String {
                print("Badge: \(badge)")
            }
            if let icon = status["dynamicIcon"] as? String {
                print("Icon: \(icon)")
            }
        }

    case .failure(let error):
        fputs("Error: \(error.message)\n", stderr)
        exit(1)
    }
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(0)
}

let command = args[0]

switch command {
case "list-actions":
    let json = args.contains("--json")
    handleListActions(json: json)

case "run":
    guard args.count >= 2 else {
        fputs("Error: Missing action name\nUsage: exmen run <name>\n", stderr)
        exit(1)
    }
    let name = args[1]
    handleRun(name: name)

case "status":
    guard args.count >= 2 else {
        fputs("Error: Missing action name\nUsage: exmen status <name>\n", stderr)
        exit(1)
    }
    let name = args[1]
    handleStatus(name: name)

default:
    fputs("Unknown command: \(command)\n", stderr)
    printUsage()
    exit(1)
}
