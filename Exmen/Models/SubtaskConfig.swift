import Foundation
import TOMLDecoder

/// Single-command subtask configuration decoded from TOML `[[subtasks]]` or
/// a dynamic `EXMEN:subtask=` inline table.
///
/// D-02 / D-02a: At rest there is exactly ONE command representation — an embedded
/// `ScriptConfig`. The `cmd = "…"` shorthand is a decode-time alias only; it is
/// normalized into a `ScriptConfig(type: .inline, …)` during `init(from:)` and is
/// NOT stored as a separate property.
struct SubtaskConfig: Codable {
    let id: String
    let name: String?
    let script: ScriptConfig       // D-02: single command representation at rest
    let timeout: TimeInterval?
    let depends_on: [String]?

    // MARK: - Computed defaults (D-03)

    /// Subtask display name. Defaults to `id` when `name` is omitted.
    var resolvedName: String { name ?? id }

    /// Effective timeout. Defaults to `SubtaskConfig.defaultTimeout` when omitted.
    var resolvedTimeout: TimeInterval { timeout ?? SubtaskConfig.defaultTimeout }

    /// Script content string for execution (convenience over `script.resolvedContent()`).
    var resolvedScript: String { script.resolvedContent() ?? "" }

    /// Default per-subtask timeout (Claude's Discretion: 60 s).
    static let defaultTimeout: TimeInterval = 60

    // MARK: - Custom Codable (D-02a: cmd is a decode-time alias, not stored)

    private enum CodingKeys: String, CodingKey {
        case id, name, script, cmd, timeout, depends_on
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id         = try container.decode(String.self, forKey: .id)
        name       = try container.decodeIfPresent(String.self, forKey: .name)
        timeout    = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
        depends_on = try container.decodeIfPresent([String].self, forKey: .depends_on)

        let cmdValue    = try container.decodeIfPresent(String.self, forKey: .cmd)
        let scriptValue = try container.decodeIfPresent(ScriptConfig.self, forKey: .script)

        switch (cmdValue, scriptValue) {
        case (.some, .some):
            // Both present → ambiguous; reject
            let ctx = DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "subtask '\(id)': specify either cmd or script, not both"
            )
            throw DecodingError.dataCorrupted(ctx)
        case (.none, .none):
            // Neither present → no command; reject
            let ctx = DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "subtask '\(id)': must specify cmd or script"
            )
            throw DecodingError.dataCorrupted(ctx)
        case (.some(let cmd), .none):
            // cmd shorthand → normalise to inline ScriptConfig
            script = ScriptConfig(type: .inline, content: cmd, path: nil)
        case (.none, .some(let s)):
            script = s
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(script, forKey: .script)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(depends_on, forKey: .depends_on)
        // Note: cmd is intentionally NOT encoded — only script is the at-rest form
    }

    // MARK: - Memberwise init (used by tests and orchestrator)

    init(id: String, name: String?, script: ScriptConfig,
         timeout: TimeInterval?, depends_on: [String]?) {
        self.id = id
        self.name = name
        self.script = script
        self.timeout = timeout
        self.depends_on = depends_on
    }

    // MARK: - Dynamic inline-table decode path (D-06)

    /// Decodes a raw TOML inline-table string (e.g. from `EXMEN:subtask=…`) into a
    /// `SubtaskConfig` by wrapping it as a one-key document and running through
    /// the standard decoder — the same `init(from:)` normalizes `cmd` here too.
    ///
    /// - Parameter rawValue: bare inline-table value, e.g.
    ///   `{ id = "build", cmd = "make", depends_on = ["fetch"] }`
    static func decodeInlineTable(_ rawValue: String) throws -> SubtaskConfig {
        let toml = "subtask = \(rawValue)"
        struct Root: Decodable { let subtask: SubtaskConfig }
        return try TOMLDecoder().decode(Root.self, from: toml).subtask
    }
}
