import XCTest
@testable import Exmen

// ORCH-01: [[subtasks]] parses into [SubtaskConfig]; required id + ScriptConfig embed;
//          optional name/timeout/depends_on defaults applied.
// Decision: D-01 (subtasks array), D-02 (ScriptConfig reuse), D-03 (required fields + defaults)

final class SubtaskConfigTests: XCTestCase {

    // MARK: - ORCH-01: TOML decode [[subtasks]] into [SubtaskConfig]

    func testDecodeSubtasksArrayInlineScript() throws {
        // A minimal inline-script subtask must decode successfully
        let toml = """
        name = "TestAction"
        [[subtasks]]
        id = "build"
        [subtasks.script]
        type = "inline"
        content = "make all"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let subtasks = try XCTUnwrap(config.subtasks)
        XCTAssertEqual(subtasks.count, 1)
        let sub = subtasks[0]
        XCTAssertEqual(sub.id, "build")
        XCTAssertEqual(sub.script.type, .inline)
        XCTAssertEqual(sub.script.content, "make all")
    }

    func testDecodeSubtasksArrayFileScript() throws {
        // A file-script subtask must decode successfully
        let toml = """
        name = "TestAction"
        [[subtasks]]
        id = "deploy"
        [subtasks.script]
        type = "file"
        path = "~/scripts/deploy.sh"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let subtasks = try XCTUnwrap(config.subtasks)
        XCTAssertEqual(subtasks.count, 1)
        XCTAssertEqual(subtasks[0].script.type, .file)
        XCTAssertEqual(subtasks[0].script.path, "~/scripts/deploy.sh")
    }

    func testDecodeMultipleSubtasks() throws {
        let toml = """
        name = "Pipeline"
        [[subtasks]]
        id = "fetch"
        [subtasks.script]
        type = "inline"
        content = "git fetch"

        [[subtasks]]
        id = "build"
        depends_on = ["fetch"]
        [subtasks.script]
        type = "inline"
        content = "make"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let subtasks = try XCTUnwrap(config.subtasks)
        XCTAssertEqual(subtasks.count, 2)
        XCTAssertEqual(subtasks[0].id, "fetch")
        XCTAssertEqual(subtasks[1].id, "build")
        XCTAssertEqual(subtasks[1].depends_on, ["fetch"])
    }

    // MARK: - ORCH-01: resolvedName defaults to id

    func testResolvedNameDefaultsToId() throws {
        // When name is absent, resolvedName == id
        let config = SubtaskConfig(
            id: "compile",
            name: nil,
            script: ScriptConfig(type: .inline, content: "cc main.c", path: nil),
            timeout: nil,
            depends_on: nil
        )
        XCTAssertEqual(config.resolvedName, "compile")
    }

    func testResolvedNameUsesExplicitName() throws {
        let config = SubtaskConfig(
            id: "compile",
            name: "Compile Sources",
            script: ScriptConfig(type: .inline, content: "cc main.c", path: nil),
            timeout: nil,
            depends_on: nil
        )
        XCTAssertEqual(config.resolvedName, "Compile Sources")
    }

    // MARK: - ORCH-01: resolvedTimeout defaults to SubtaskConfig.defaultTimeout

    func testResolvedTimeoutDefaultsToConstant() throws {
        let config = SubtaskConfig(
            id: "step",
            name: nil,
            script: ScriptConfig(type: .inline, content: "echo hi", path: nil),
            timeout: nil,
            depends_on: nil
        )
        XCTAssertEqual(config.resolvedTimeout, SubtaskConfig.defaultTimeout, accuracy: 0.001)
    }

    func testResolvedTimeoutUsesExplicitValue() throws {
        let config = SubtaskConfig(
            id: "long-step",
            name: nil,
            script: ScriptConfig(type: .inline, content: "sleep 5", path: nil),
            timeout: 120.0,
            depends_on: nil
        )
        XCTAssertEqual(config.resolvedTimeout, 120.0, accuracy: 0.001)
    }

    // MARK: - ORCH-01: resolvedScript convenience

    func testResolvedScriptInline() throws {
        let config = SubtaskConfig(
            id: "step",
            name: nil,
            script: ScriptConfig(type: .inline, content: "echo hello", path: nil),
            timeout: nil,
            depends_on: nil
        )
        XCTAssertEqual(config.resolvedScript, "echo hello")
    }

    // MARK: - ORCH-01: decodeInlineTable parses bare inline-table string

    func testDecodeInlineTable() throws {
        // D-06: decodeInlineTable wraps and decodes
        let inline = #"{ id = "fetch", script = { type = "inline", content = "git fetch" } }"#
        let config = try SubtaskConfig.decodeInlineTable(inline)
        XCTAssertEqual(config.id, "fetch")
        XCTAssertEqual(config.script.type, .inline)
        XCTAssertEqual(config.script.content, "git fetch")
    }

    func testDecodeInlineTableWithOptionalFields() throws {
        let inline = #"{ id = "build", name = "Build", script = { type = "inline", content = "make" }, timeout = 30.0, depends_on = ["fetch"] }"#
        let config = try SubtaskConfig.decodeInlineTable(inline)
        XCTAssertEqual(config.id, "build")
        XCTAssertEqual(config.name, "Build")
        XCTAssertEqual(config.timeout, 30.0)
        XCTAssertEqual(config.depends_on, ["fetch"])
    }

    // MARK: - ORCH-01: ActionConfig.subtasks is nil for plain actions

    func testSubtasksNilForPlainAction() throws {
        let toml = """
        name = "Simple"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        XCTAssertNil(config.subtasks)
    }
}
