import Foundation

/// Global configuration for Exmen
/// Loaded from ~/.config/exmen/config.toml
struct GlobalConfig: Codable {
    /// Action names in display order (actions not listed appear at end)
    var order: [String]?

    /// Action names to hide/disable
    var disabled: [String]?
}
