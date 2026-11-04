import Foundation
import XCTest
@testable import HindsightCore

@MainActor
final class LLMConnectionsTests: XCTestCase {
    private let context = LLMConnectionContext(isLocalServer: true, codexHome: "/tmp/hs-account")

    private func make(_ runner: any ProcessRunning) -> LLMConnections {
        LLMConnections(runner: runner, locate: { "/test/" + $0 })
    }

    func testRefreshOnlyChecksOAuthAndUsesTheServersCredentialStore() async {
        let runner = FakeProcessRunner { invocation in
            if invocation.executable.hasSuffix("claude") {
                return ProcessOutput(status: 0, stdout: #"{"loggedIn":true,"authMethod":"claude.ai","email":"private@example.com"}"#)
            }
            return ProcessOutput(status: 0, stderr: "Logged in using ChatGPT")
        }
        let connections = make(runner)
        await connections.refresh(context)
        XCTAssertEqual(connections.status(.claude), .connected)
        XCTAssertEqual(connections.status(.chatGPT), .connected)
        XCTAssertEqual(connections.status(.hindsightCloud), .signedOut)
        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertTrue(runner.calls.allSatisfy { $0.arguments.contains("status") && !$0.inheritEnvironment })
        let codex = runner.calls.first { $0.executable.hasSuffix("codex") }!
        XCTAssertEqual(codex.environment["CODEX_HOME"], context.codexHome)
        XCTAssertTrue(codex.arguments.contains("cli_auth_credentials_store=\"file\""))
        XCTAssertFalse(connections.status(.claude).summary.contains("private@"))
    }

    func testAPIKeysAreNotPresentedAsOAuthSessions() async {
        let runner = FakeProcessRunner { invocation in
            invocation.executable.hasSuffix("claude")
                ? ProcessOutput(status: 0, stdout: #"{"loggedIn":true,"authMethod":"api_key"}"#)
                : ProcessOutput(status: 0, stderr: "Logged in using an API key - sk-private")
        }
        let connections = make(runner)
        await connections.refresh(context)
        XCTAssertEqual(connections.status(.claude), .signedOut)
        XCTAssertEqual(connections.status(.chatGPT), .signedOut)
        XCTAssertFalse(connections.status(.chatGPT).summary.contains("sk-private"))
    }

    func testRemoteServerNeverReadsOrStartsALocalAccountSession() async {
        let runner = FakeProcessRunner()
        let connections = make(runner)
        let remote = LLMConnectionContext(isLocalServer: false, codexHome: "/tmp/hs-account")
        await connections.refresh(remote)
        connections.connect(.claude, context: remote)
        XCTAssertTrue(runner.calls.isEmpty)
        guard case .unavailable = connections.status(.claude) else { return XCTFail("local account offered for remote server") }
    }

    func testUnknownDynamicCodexDirectoryCannotFallBackToAnotherAccount() async {
        let runner = FakeProcessRunner()
        let connections = make(runner)
        connections.connect(.chatGPT, context: LLMConnectionContext(isLocalServer: true, codexHome: nil))
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertNil(connections.activeAccount)
        guard case .unavailable = connections.status(.chatGPT) else { return XCTFail("unresolved directory allowed") }
        XCTAssertEqual(LLMConnectionContext.credentialsDirectory("$HOME/.codex-team", home: "/Users/test"), "/Users/test/.codex-team")
        XCTAssertEqual(LLMConnectionContext.credentialsDirectory("${HOME}/.codex", home: "/Users/test"), "/Users/test/.codex")
        XCTAssertNil(LLMConnectionContext.credentialsDirectory("$(resolve-profile)"))
        XCTAssertNil(LLMConnectionContext.credentialsDirectory("$PROFILE_HOME/.codex"))
    }

    func testExplicitLoginIsFollowedByAnIndependentSessionCheck() async {
        let runner = FakeProcessRunner { invocation in
            invocation.arguments.contains("status")
                ? ProcessOutput(status: 0, stderr: "Logged in using ChatGPT")
                : ProcessOutput(status: 0, stdout: "success")
        }
        let connections = make(runner)
        XCTAssertTrue(runner.calls.isEmpty)
        connections.connect(.chatGPT, context: context)
        for _ in 0..<1000 where connections.activeAccount != nil { await Task.yield() }
        XCTAssertNil(connections.activeAccount)
        XCTAssertEqual(connections.status(.chatGPT), .connected)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertFalse(runner.calls[0].arguments.contains("status"))
        XCTAssertTrue(runner.calls[1].arguments.contains("status"))
    }

    func testSuccessExitCodeWithoutAnOAuthSessionDoesNotReportConnected() async {
        let connections = make(FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: "ok") })
        connections.connect(.claude, context: context)
        for _ in 0..<1000 where connections.activeAccount != nil { await Task.yield() }
        XCTAssertNotEqual(connections.status(.claude), .connected)
        XCTAssertNil(connections.authorizationURL)
    }

    func testCancellationIgnoresLateLoginOutputAndCompletion() async {
        let runner = SuspendedOAuthRunner()
        let connections = make(runner)
        connections.connect(.chatGPT, context: context)
        for _ in 0..<1000 {
            if await runner.started { break }
            await Task.yield()
        }
        connections.cancel()
        await runner.finish()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(connections.activeAccount)
        XCTAssertNil(connections.authorizationURL)
        XCTAssertEqual(connections.status(.chatGPT), .unchecked, "annuler n'est pas se déconnecter")
    }

    func testImmediateCancellationDoesNotStartTheLoginClient() async {
        let runner = FakeProcessRunner()
        let connections = make(runner)
        connections.connect(.chatGPT, context: context)
        connections.cancel()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(connections.status(.chatGPT), .unchecked)
    }

    func testInvalidatingAStatusCheckDoesNotLeaveTheInterfaceCheckingForever() async {
        let runner = SuspendedOAuthRunner()
        let connections = make(runner)
        let task = Task { await connections.refresh(context) }
        for _ in 0..<1000 {
            if await runner.started { break }
            await Task.yield()
        }
        connections.cancel()
        XCTAssertFalse(connections.isRefreshing)
        await runner.finish()
        await task.value
        XCTAssertEqual(connections.status(.claude), .unchecked)
    }

    func testOnlyTrustedAuthorizationURLsAreExposed() async {
        XCTAssertEqual(LLMConnections.authorizationURL(in: "Open https://auth.openai.com/oauth/authorize?state=abc", account: .chatGPT)?.host, "auth.openai.com")
        XCTAssertNil(LLMConnections.authorizationURL(in: "https://auth.openai.com.evil.test/oauth/authorize", account: .chatGPT))
        XCTAssertNil(LLMConnections.authorizationURL(in: "https://user@auth.openai.com/oauth/authorize", account: .chatGPT))
        XCTAssertNil(LLMConnections.authorizationURL(in: "https://auth.openai.com/token?secret=value", account: .chatGPT))
        XCTAssertNil(LLMConnections.authorizationURL(in: "https://claude.ai/oauth/authorize", account: .chatGPT))
        XCTAssertEqual(LLMConnections.authorizationURL(in: "https://claude.ai/oauth/authorize?state=abc", account: .claude)?.host, "claude.ai")
        let cloud = "Browser didn't open? Use this link:\n\n  https://ui.hindsight.vectorize.io/connect/desktop?port=5123&state=abc&source=hindsight_cli&host=mac\n"
        XCTAssertEqual(LLMConnections.authorizationURL(in: cloud, account: .hindsightCloud)?.path, "/connect/desktop")
        XCTAssertNil(LLMConnections.authorizationURL(in: "Revoke it any time at https://ui.hindsight.vectorize.io/api-keys", account: .hindsightCloud))
        XCTAssertNil(LLMConnections.authorizationURL(in: "https://ui.hindsight.vectorize.io.evil.test/connect/desktop", account: .hindsightCloud))
    }

    func testHindsightCloudStatusIsReadFromTheCLIWithoutTheKey() {
        let signedIn = """
            Credential file: /Users/test/.hindsight/cloud/credentials.json
            Organization: Atelier (org_123)
            Key: hsk_…abcd
            """
        XCTAssertEqual(LLMConnections.cloudStatus(ProcessOutput(status: 0, stdout: signedIn)), .signedInTo("Atelier"))
        XCTAssertEqual(LLMConnections.cloudStatus(ProcessOutput(status: 0, stdout: "Organization: (unknown) (?)\n")), .signedInTo("Hindsight Cloud"))
        XCTAssertEqual(
            LLMConnections.cloudStatus(ProcessOutput(status: 0, stdout: "Not signed in (no /x/credentials.json). Run `hindsight-admin cloud login`.\n")),
            .signedOut)
        XCTAssertEqual(
            LLMConnections.cloudStatus(ProcessOutput(status: 2, stderr: "Error: No such command 'cloud'.")), .unavailable("Serveur Hindsight 1.2.0 requis."))
        guard case .failed = LLMConnections.cloudStatus(ProcessOutput(status: 1, stderr: "boom")) else { return XCTFail("échec présenté comme une déconnexion") }
    }

    func testHindsightCloudUsesTheServersAdminAndCanSignOut() async {
        let signedIn = Switch(true)
        let runner = FakeProcessRunner { invocation in
            switch invocation.arguments {
            case ["cloud", "status"]:
                return ProcessOutput(status: 0, stdout: signedIn.value ? "Organization: Atelier (org_1)\n" : "Not signed in (no x). Run `hindsight-admin cloud login`.\n")
            case ["cloud", "logout"]:
                signedIn.value = false
                return ProcessOutput(status: 0, stdout: "Signed out; removed x.")
            default:
                return ProcessOutput(status: 0)
            }
        }
        let connections = make(runner)
        let admin = "/srv/venv/bin/hindsight-admin"
        let context = LLMConnectionContext(isLocalServer: true, codexHome: "/tmp/hs-account", hindsightAdmin: admin)
        await connections.refresh(context)
        XCTAssertEqual(connections.status(.hindsightCloud), .signedInTo("Atelier"))
        XCTAssertEqual(connections.status(.hindsightCloud).summary, "Connecté à Atelier")
        XCTAssertTrue(connections.status(.hindsightCloud).isConnected)
        XCTAssertFalse(runner.calls.contains { $0.executable == "/test/hindsight-admin" }, "celui du serveur du script, pas celui du PATH")
        XCTAssertTrue(runner.calls.filter { $0.executable == admin }.allSatisfy { !$0.inheritEnvironment })

        await connections.disconnect(.claude, context: context)
        await connections.disconnect(.hindsightCloud, context: context)
        XCTAssertEqual(connections.status(.hindsightCloud), .signedOut)
        XCTAssertEqual(runner.calls.filter { $0.executable == admin }.map(\.arguments), [["cloud", "status"], ["cloud", "logout"], ["cloud", "status"]])
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("logout") && $0.executable != admin })
    }

    func testHindsightAdminIsFoundNextToTheScriptsServer() {
        let script = ["#!/bin/zsh", #"ROOT="$HOME/.hindsight""#, "PORT=8888", #"exec "$ROOT/venv/bin/hindsight-api" --host 127.0.0.1 --port "$PORT""#]
        XCTAssertEqual(LLMConnectionContext.hindsightAdmin(scriptLines: script, home: "/Users/test"), "/Users/test/.hindsight/venv/bin/hindsight-admin")
        XCTAssertEqual(LLMConnectionContext.hindsightAdmin(scriptLines: ["exec ~/srv/bin/hindsight-api"], home: "/Users/test"), "/Users/test/srv/bin/hindsight-admin")
        XCTAssertNil(LLMConnectionContext.hindsightAdmin(scriptLines: [#"exec "$(pick-venv)/bin/hindsight-api""#], home: "/Users/test"))
        XCTAssertNil(LLMConnectionContext.hindsightAdmin(scriptLines: [#"exec "$UNKNOWN/bin/hindsight-api""#], home: "/Users/test"))
        XCTAssertNil(LLMConnectionContext.hindsightAdmin(scriptLines: ["exec ./start-embedding2-api.sh 8888"], home: "/Users/test"))
    }
}

private actor SuspendedOAuthRunner: ProcessRunning {
    private(set) var started = false
    private var continuation: CheckedContinuation<ProcessOutput, Never>?
    func run(_ invocation: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }
    func finish() {
        continuation?.resume(returning: ProcessOutput(status: 0, stderr: "Logged in using ChatGPT"))
        continuation = nil
    }
}
