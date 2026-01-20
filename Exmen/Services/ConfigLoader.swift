import Foundation
import TOMLDecoder

/// Errors that can occur when loading configs
enum ConfigError: Error {
    case directoryNotFound(String)
    case invalidTOML(String, Error)
    case noActionsFound
}

/// Service to load action configs from TOML files
class ConfigLoader {
    static let shared = ConfigLoader()

    /// Default config directory
    let configDirectory: String

    init(configDirectory: String = "~/.config/exmen/actions") {
        self.configDirectory = NSString(string: configDirectory).expandingTildeInPath
    }

    /// Load all action configs from the config directory
    func loadAllConfigs() -> [ActionConfig] {
        let fileManager = FileManager.default

        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("Config directory not found: \(configDirectory)")
            return []
        }

        // Get all .toml files
        guard let files = try? fileManager.contentsOfDirectory(atPath: configDirectory) else {
            return []
        }

        let tomlFiles = files.filter { $0.hasSuffix(".toml") }

        // Load each config
        return tomlFiles.compactMap { filename in
            let path = (configDirectory as NSString).appendingPathComponent(filename)
            return loadConfig(from: path)
        }
    }

    /// Load a single action config from a TOML file
    func loadConfig(from path: String) -> ActionConfig? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            print("Failed to read file: \(path)")
            return nil
        }

        do {
            let decoder = TOMLDecoder()
            return try decoder.decode(ActionConfig.self, from: content)
        } catch {
            print("Failed to parse TOML at \(path): \(error)")
            return nil
        }
    }

    /// Ensure config directory exists, create if needed
    func ensureConfigDirectory() -> Bool {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configDirectory) {
            do {
                try fileManager.createDirectory(
                    atPath: configDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                return true
            } catch {
                print("Failed to create config directory: \(error)")
                return false
            }
        }
        return true
    }
}
