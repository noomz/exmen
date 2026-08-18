import XCTest
@testable import Exmen

/// Optional `[when]` on actions/services: hide unless every specified
/// command / file / env check passes. Unspecified fields are ignored.
final class WhenConfigTests: XCTestCase {

    // MARK: - TOML decode

    func testWhenIsNilWhenOmitted() throws {
        let toml = """
        name = "Plain"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        XCTAssertNil(config.when)
    }

    func testDecodeWhenCommandFileEnv() throws {
        let toml = """
        name = "K8s"
        [when]
        command = "kubectl"
        file = "~/.kube/config"
        env = "KUBECONFIG"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let when = try XCTUnwrap(config.when)
        XCTAssertEqual(when.command, "kubectl")
        XCTAssertEqual(when.file, "~/.kube/config")
        XCTAssertEqual(when.env, "KUBECONFIG")
    }

    func testDecodeWhenOnService() throws {
        let toml = """
        name = "Proxy"
        type = "service"
        [when]
        command = "playwright_mcp_proxy"
        [service]
        command = "playwright_mcp_proxy"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        XCTAssertTrue(config.isService)
        XCTAssertEqual(config.when?.command, "playwright_mcp_proxy")
    }

    func testEmptyWhenTableDecodes() throws {
        let toml = """
        name = "EmptyWhen"
        [when]
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let when = try XCTUnwrap(config.when)
        XCTAssertNil(when.command)
        XCTAssertNil(when.file)
        XCTAssertNil(when.env)
        XCTAssertTrue(when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        ).isSatisfied)
    }

    // MARK: - command

    func testCommandOnPathIsSatisfied() {
        let when = WhenConfig(command: "kubectl", file: nil, env: nil)
        let result = when.evaluate(
            path: "/opt/bin:/usr/bin",
            environment: [:],
            fileExists: { $0 == "/opt/bin/kubectl" },
            isExecutable: { $0 == "/opt/bin/kubectl" }
        )
        XCTAssertTrue(result.isSatisfied)
        XCTAssertTrue(result.reasons.isEmpty)
    }

    func testCommandMissingIsUnsatisfied() {
        let when = WhenConfig(command: "kubectl", file: nil, env: nil)
        let result = when.evaluate(
            path: "/opt/bin:/usr/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(result.reasons, ["kubectl not found"])
    }

    func testCommandExistsButNotExecutableIsUnsatisfied() {
        let when = WhenConfig(command: "kubectl", file: nil, env: nil)
        let result = when.evaluate(
            path: "/opt/bin",
            environment: [:],
            fileExists: { $0 == "/opt/bin/kubectl" },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(result.isSatisfied)
    }

    func testAbsoluteCommandPath() {
        let when = WhenConfig(command: "/usr/local/bin/kubectl", file: nil, env: nil)
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { $0 == "/usr/local/bin/kubectl" },
            isExecutable: { $0 == "/usr/local/bin/kubectl" }
        )
        XCTAssertTrue(result.isSatisfied)
    }

    func testTildeCommandPath() {
        let when = WhenConfig(command: "~/bin/kubectl", file: nil, env: nil)
        let expanded = (when.command! as NSString).expandingTildeInPath
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { $0 == expanded },
            isExecutable: { $0 == expanded }
        )
        XCTAssertTrue(result.isSatisfied)
        XCTAssertTrue(expanded.hasPrefix("/"), "tilde should expand to an absolute path")
    }

    func testBlankCommandIsIgnored() {
        let when = WhenConfig(command: "  ", file: nil, env: nil)
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertTrue(result.isSatisfied)
    }

    // MARK: - file

    func testFileExistsIsSatisfied() {
        let when = WhenConfig(command: nil, file: "/tmp/exmen-when-exists", env: nil)
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { $0 == "/tmp/exmen-when-exists" },
            isExecutable: { _ in false }
        )
        XCTAssertTrue(result.isSatisfied)
    }

    func testFileMissingIsUnsatisfied() {
        let when = WhenConfig(command: nil, file: "~/.kube/config", env: nil)
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(result.reasons, ["missing ~/.kube/config"])
    }

    func testFileTildeIsExpandedBeforeCheck() {
        let when = WhenConfig(command: nil, file: "~/.kube/config", env: nil)
        let expanded = ("~/.kube/config" as NSString).expandingTildeInPath
        var checked: [String] = []
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { path in
                checked.append(path)
                return path == expanded
            },
            isExecutable: { _ in false }
        )
        XCTAssertTrue(result.isSatisfied)
        XCTAssertEqual(checked, [expanded])
    }

    // MARK: - env

    func testEnvSetIsSatisfied() {
        let when = WhenConfig(command: nil, file: nil, env: "KUBECONFIG")
        let result = when.evaluate(
            path: "/usr/bin",
            environment: ["KUBECONFIG": "/tmp/kube"],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertTrue(result.isSatisfied)
    }

    func testEnvMissingIsUnsatisfied() {
        let when = WhenConfig(command: nil, file: nil, env: "KUBECONFIG")
        let result = when.evaluate(
            path: "/usr/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(result.reasons, ["$KUBECONFIG not set"])
    }

    func testEnvEmptyIsUnsatisfied() {
        let when = WhenConfig(command: nil, file: nil, env: "KUBECONFIG")
        let result = when.evaluate(
            path: "/usr/bin",
            environment: ["KUBECONFIG": "   "],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(result.isSatisfied)
    }

    // MARK: - AND

    func testAllSpecifiedConditionsMustPass() {
        let when = WhenConfig(command: "kubectl", file: "~/.kube/config", env: "KUBECONFIG")
        let kube = ("~/.kube/config" as NSString).expandingTildeInPath
        let passing = when.evaluate(
            path: "/opt/bin",
            environment: ["KUBECONFIG": "/tmp/kube"],
            fileExists: { $0 == "/opt/bin/kubectl" || $0 == kube },
            isExecutable: { $0 == "/opt/bin/kubectl" }
        )
        XCTAssertTrue(passing.isSatisfied)

        let missingCommand = when.evaluate(
            path: "/opt/bin",
            environment: ["KUBECONFIG": "/tmp/kube"],
            fileExists: { $0 == kube },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(missingCommand.isSatisfied)
        XCTAssertEqual(missingCommand.reasons, ["kubectl not found"])

        let allMissing = when.evaluate(
            path: "/opt/bin",
            environment: [:],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertFalse(allMissing.isSatisfied)
        XCTAssertEqual(allMissing.reasons, [
            "kubectl not found",
            "missing ~/.kube/config",
            "$KUBECONFIG not set",
        ])
        XCTAssertEqual(
            allMissing.reasonCaption,
            "kubectl not found, missing ~/.kube/config, $KUBECONFIG not set"
        )
    }

    // MARK: - Action mapping

    func testActionFromConfigWithNoWhenIsVisible() throws {
        let toml = """
        name = "Always"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let action = Action(from: config)
        XCTAssertFalse(action.isHidden)
        XCTAssertNil(action.hiddenReason)
    }

    func testActionFromConfigHidesMissingCommand() throws {
        let toml = """
        name = "Missing CLI"
        [when]
        command = "definitely-not-a-real-exmen-cli-zzz"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let action = Action(from: config)
        XCTAssertTrue(action.isHidden)
        XCTAssertEqual(action.hiddenReason, "definitely-not-a-real-exmen-cli-zzz not found")
    }

    func testActionFromConfigShowsExistingCommand() throws {
        let toml = """
        name = "True"
        [when]
        command = "true"
        [script]
        type = "inline"
        content = "echo hi"
        """
        let config = try TOMLDecoder().decode(ActionConfig.self, from: toml)
        let action = Action(from: config)
        XCTAssertFalse(action.isHidden)
        XCTAssertNil(action.hiddenReason)
    }
}
