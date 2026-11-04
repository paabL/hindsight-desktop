import Foundation
import XCTest

@testable import HindsightCore

@MainActor
final class ProjectSyncTests: XCTestCase {
    static let approval = String(repeating: "a", count: 64)
    static let dryRun = (1...12).map { "À envoyer : doc:\($0) | sha256=" + String(repeating: "b", count: 64) }.joined(separator: "\n") + "\nPlan : " + approval + "\n" + """
        NOMAD-Companion    doc         6 documents,    5 à envoyer (29 k caractères)
        NOMAD-RL           campaign  246 documents,    0 à envoyer (0 k caractères)
        NOMAD-RL           doc        20 documents,    7 à envoyer (209 k caractères)
        source disparue : doc:NOMAD-RL:docs/companion.md
        Total : 12 documents, 238 k caractères, environ 59 k jetons à extraire ; 1 orphelins, gardés sans --prune.
        """

    private var script: String!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        script = dir.appendingPathComponent("sync.py").path
        try #"API = "http://localhost:8888/v1/default/banks/nomad-rl""#.write(toFile: script, atomically: true, encoding: .utf8)
    }

    private func make(_ runner: FakeProcessRunner, paused: String? = nil, pending: Int? = 0) -> ProjectSyncViewModel {
        let vm = ProjectSyncViewModel(settings: InMemorySettingsStore(), runner: runner, bank: { "nomad-rl" })
        vm.setScript(script)
        vm.pauseGate = { _ in paused }
        vm.pendingRetains = { _ in pending }
        return vm
    }

    func testPreviewIsReadFromTheDryRunOutput() throws {
        let p = try XCTUnwrap(ProjectSyncPreview.parse(Self.dryRun))
        XCTAssertEqual(p.toSend, 12)
        XCTAssertEqual(p.documents.count, 12)
        XCTAssertEqual(p.approval, Self.approval)
        XCTAssertNil(ProjectSyncPreview.parse("Total : 1 documents, 1 k caractères"), "un ancien aperçu sans liste ne permet pas l'envoi")
        XCTAssertEqual(p.kiloCharacters, 238)
        XCTAssertEqual(p.orphans, ["doc:NOMAD-RL:docs/companion.md"])
        XCTAssertEqual(p.groups.count, 3)
        XCTAssertEqual(p.groups[2], .init(repo: "NOMAD-RL", kind: "doc", documents: 20, toSend: 7, kiloCharacters: 209))
        XCTAssertNil(ProjectSyncPreview.parse("Traceback (most recent call last):"))
    }

    func testDryRunFirstThenSendOnlyAfterConfirmation() async throws {
        let runner = FakeProcessRunner { inv in
            ProcessOutput(status: 0, stdout: inv.arguments == ["--dry-run"] ? Self.dryRun : "Envoyé : 12 documents en 2 lots asynchrones.")
        }
        let vm = make(runner)
        await vm.requestSync()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run"]])
        XCTAssertEqual(runner.calls.first?.currentDirectory, (script as NSString).deletingLastPathComponent)
        let request = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(request.title.contains("12 documents"))
        XCTAssertTrue(request.message.contains("NOMAD-RL · doc : 7 documents"))
        XCTAssertTrue(request.message.contains("• doc:1"))
        XCTAssertFalse(request.message.contains("campaign"), "les groupes sans rien à envoyer ne sont pas listés")

        await request.perform()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run"], ["--approve", Self.approval]])
        XCTAssertTrue(vm.actionMessage?.hasPrefix("Envoyé : 12 documents") == true)
    }

    func testChangedScriptAfterPreviewCannotSend() async throws {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: Self.dryRun) }
        let vm = make(runner)
        await vm.requestSync()
        let request = try XCTUnwrap(vm.confirmation)
        try "# modified script".write(toFile: script, atomically: true, encoding: .utf8)
        await request.perform()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run"]])
        XCTAssertTrue(vm.actionMessage?.contains("changé") == true)
    }

    func testSelectedIdsAreBoundToTheApprovedSend() async throws {
        let output = "À envoyer : doc:1 | sha256=" + String(repeating: "b", count: 64) + "\nPlan : " + Self.approval + "\nTotal : 1 documents, 1 k caractères"
        let runner = FakeProcessRunner { inv in
            ProcessOutput(status: 0, stdout: inv.arguments.contains("--dry-run") ? output : "Envoyé : 1 document")
        }
        let vm = make(runner)
        await vm.requestSync(ids: ["doc:1"])
        let request = try XCTUnwrap(vm.confirmation)
        await request.perform()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run", "--select", "doc:1"], ["--select", "doc:1", "--approve", Self.approval]])
    }

    func testPendingQueueMustBeReadableAndEmptyAtConfirmation() async throws {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: Self.dryRun) }
        let vm = make(runner, pending: nil)
        await vm.requestSync()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertNil(vm.confirmation)
        vm.pendingRetains = { _ in 0 }
        await vm.requestSync()
        let request = try XCTUnwrap(vm.confirmation)
        vm.pendingRetains = { _ in 1 }
        await request.perform()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run"]])
        XCTAssertTrue(vm.actionMessage?.contains("occupée") == true)
    }

    func testPausedBankRunsNothing() async {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: Self.dryRun) }
        let vm = make(runner, paused: "La banque nomad-rl est en pause.")
        await vm.requestSync()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, "La banque nomad-rl est en pause.")
    }

    func testPauseAfterThePreviewBlocksTheSend() async throws {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: Self.dryRun) }
        let vm = make(runner)
        await vm.requestSync()
        let request = try XCTUnwrap(vm.confirmation)
        vm.pauseGate = { _ in "En pause." }
        await request.perform()
        XCTAssertEqual(runner.calls.map(\.arguments), [["--dry-run"]])
        XCTAssertEqual(vm.actionMessage, "En pause.")
    }

    func testRefusedWhileThePreviousSendIsStillProcessed() async {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: Self.dryRun) }
        let vm = make(runner, pending: 3)
        await vm.requestSync()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(vm.actionMessage?.contains("3 envois") == true)
    }

    func testScriptForAnotherBankIsNotRun() async throws {
        try #"API = "http://localhost:8888/v1/default/banks/autre""#.write(toFile: script, atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner()
        let vm = make(runner)
        await vm.requestSync()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(vm.actionMessage?.contains("n'écrit pas dans la banque") == true)
    }

    func testNothingToSendAsksNothing() async {
        let runner = FakeProcessRunner { _ in
            ProcessOutput(status: 0, stdout: "Total : 0 documents, 0 k caractères, environ 0 k jetons à extraire ; 0 orphelins, gardés sans --prune.")
        }
        let vm = make(runner)
        await vm.requestSync()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, "Rien à envoyer : la banque est à jour.")
    }
}
