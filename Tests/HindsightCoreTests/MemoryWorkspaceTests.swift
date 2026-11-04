import Foundation
import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class MemoryWorkspaceTests: XCTestCase {
    final class Server: @unchecked Sendable { var docs: [DocumentListItem] = [] }
    struct Setup {
        let root: URL; let text: URL; let transport: MockTransport; let server: Server
        let folder: MemoryFolderViewModel; let vm: MemoryWorkspace; let runner: FakeProcessRunner
    }
    func setup() throws -> Setup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("collection/a"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let text = root.appendingPathComponent("collection/a/document.md")
        try Data("# Full original\nAll the source, including its limits.\n".utf8).write(to: text)
        let record: [String: Any] = ["id": "project:repo:note", "title": "A source", "kind": "wandb", "project": "project", "repository": "repo", "files": ["document.md": "a/document.md"], "source_updated_at": "2026-10-29T12:00:00Z"]
        try JSONSerialization.data(withJSONObject: ["version": 1, "mode": "collection_only", "records": [record], "projects": [["id": "project", "name": "Project"]]]).write(to: root.appendingPathComponent("collection/catalog.json"))
        try Data("# fixture collector".utf8).write(to: root.appendingPathComponent("collect.py"))
        try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": testBank, "excluded_document_ids": [:], "deferred_document_ids": [:]]).write(to: root.appendingPathComponent("memory-policy.json"))
        let transport = MockTransport(), server = Server()
        transport.on("GET", "\(bankPath)/documents") { _ in
            let page = ListDocumentsResponse(items: server.docs, total: server.docs.count, limit: 100, offset: 0)
            return .json(String(decoding: try! JSONEncoder().encode(page), as: UTF8.self))
        }
        transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":0,"limit":1,"offset":0,"operations":[]}"#)
        transport.on("POST", "\(bankPath)/memories", json: #"{"success":true,"bank_id":"b","items_count":1,"async":true,"operation_id":"op"}"#)
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0) }
        let folder = MemoryFolderViewModel(settings: InMemorySettingsStore(), runner: runner, home: root, python: "/example/python", discoverAutomatically: false)
        folder.choose(root)
        let vm = MemoryWorkspace(folder: folder, client: { makeClient(transport) }, bank: { testBank })
        return Setup(root: root, text: text, transport: transport, server: server, folder: folder, vm: vm, runner: runner)
    }
    func state(_ vm: MemoryWorkspace, _ id: String = "project:repo:note") -> [String: Any] {
        vm.records.first { $0["id"] as? String == id }?["memory"] as? [String: Any] ?? [:]
    }
    func installDocument(_ s: Setup, id: String, text: String) {
        s.server.docs = [DocumentListItem(id: id, contentHash: SHA256.hex(Data(text.utf8)), textLength: text.count, memoryUnitCount: 1)]
        let doc = #"{"id":"\#(id)","bank_id":"b","original_text":\#(String(data:try! JSONSerialization.data(withJSONObject:text,options:.fragmentsAllowed),encoding:.utf8)!),"content_hash":"\#(SHA256.hex(Data(text.utf8)))","created_at":"","updated_at":"","text_length":\#(text.count),"memory_unit_count":1,"tags":[]}"#
        s.transport.on("GET", "\(bankPath)/documents/\(id)", json: doc)
        s.transport.on("DELETE", "\(bankPath)/documents/\(id)", json: #"{"success":true,"message":"removed","document_id":"x","memory_units_deleted":1}"#)
    }
    func testReadingJoinsSourcesAndBankWithoutWritesOrCollection() async throws {
        let s = try setup(); let text = try String(contentsOf: s.text, encoding: .utf8)
        s.server.docs = [DocumentListItem(id: "source:project:repo:note", contentHash: SHA256.hex(Data(text.utf8))), DocumentListItem(id: "direct-note")]
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        XCTAssertEqual(state(s.vm, "bank:direct-note")["state"] as? String, "unlinked")
        XCTAssertTrue(s.runner.calls.isEmpty)
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("collection/.memory-workspace.json").path))
    }
    func testRefreshingSourcesDoesNotContactHindsightOrPrepareAnUpload() async throws {
        let s = try setup()
        await s.vm.refreshSources()
        XCTAssertEqual(s.runner.calls.count, 1)
        XCTAssertTrue(s.transport.requests.isEmpty)
        XCTAssertNil(s.vm.confirmation)
        XCTAssertNil(s.vm.error)
        XCTAssertTrue(s.vm.message?.contains("Dossier actualisé") == true)
    }
    func testPreparingCatalogueDoesNotNeedACollectorScript() async throws {
        let s = try setup()
        try FileManager.default.removeItem(at: s.root.appendingPathComponent("collect.py"))
        await s.vm.prepareSend()
        XCTAssertNotNil(s.vm.confirmation)
        XCTAssertTrue(s.runner.calls.isEmpty)
    }
    func testRefreshingSourcesWithoutASelectedBankStillWorks() async throws {
        let s = try setup()
        let vm = MemoryWorkspace(folder: s.folder, client: { makeClient(s.transport) }, bank: { nil })
        await vm.refreshSources()
        XCTAssertNil(vm.error)
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(s.runner.calls.count, 1)
        XCTAssertTrue(s.transport.requests.isEmpty)
    }

    func testPreparingExistingCatalogueRequiresApprovalWithoutCollecting() async throws {
        let s = try setup()
        await s.vm.prepareSend()
        XCTAssertTrue(s.runner.calls.isEmpty)
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
        let approval = try XCTUnwrap(s.vm.confirmation)
        XCTAssertTrue(approval.message.contains("source:project:repo:note"))
        await approval.perform()
        let req = try XCTUnwrap(s.transport.requests.first { $0.method == "POST" })
        XCTAssertEqual(req.bodyJSON?["items"]?[0]?["content"], .string(try String(contentsOf: s.text, encoding: .utf8)))
        XCTAssertEqual(req.bodyJSON?["items"]?[0]?["document_id"], .string("source:project:repo:note"))
        XCTAssertNotNil(req.bodyJSON?["operation_id"])
        XCTAssertEqual(state(s.vm)["state"] as? String, "queued")
        XCTAssertFalse(s.transport.requests.contains { $0.path.contains("consolidat") || $0.method == "DELETE" })
        XCTAssertTrue(s.runner.calls.isEmpty, "Confirming the preview must not collect either")
    }
    func testChangedTextCannotUsePreviousApproval() async throws {
        let s = try setup(); await s.vm.prepareSend(); let approval = try XCTUnwrap(s.vm.confirmation)
        try Data("changed after preview".utf8).write(to: s.text)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
        XCTAssertTrue(s.vm.error?.contains("changé") == true)
    }
    func testChangedPolicyCannotUsePreviousApproval() async throws {
        let s = try setup(); await s.vm.prepareSend(); let approval = try XCTUnwrap(s.vm.confirmation)
        let p = s.root.appendingPathComponent("memory-policy.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: p)) as? [String: Any])
        json["excluded_document_ids"] = ["source:project:repo:note": ["reason": "held"]]
        try JSONSerialization.data(withJSONObject: json).write(to: p)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }
    func testOfflineComparisonDoesNotPretendSourceIsCurrent() async throws {
        let s = try setup(); s.transport.on("GET", "\(bankPath)/documents", json: "{}", status: 503)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "unknown")
        await s.vm.prepareSend(); XCTAssertNil(s.vm.confirmation)
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }
    func testUserCanLinkAnExistingDocumentWithoutSendingIt() async throws {
        let s = try setup(); let text = try String(contentsOf: s.text, encoding: .utf8)
        installDocument(s, id: "old-note", text: text)
        await s.vm.refresh(); try s.vm.link("project:repo:note", document: "old-note")
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        XCTAssertEqual(state(s.vm)["document_id"] as? String, "old-note")
        XCTAssertFalse(s.vm.records.contains { $0["id"] as? String == "bank:old-note" })
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }
    func testRemovalIsConfirmedBackedUpAndDoesNotRemoveLocalFile() async throws {
        let s = try setup(); let text = try String(contentsOf: s.text, encoding: .utf8)
        let id = "source:project:repo:note"; installDocument(s, id: id, text: text)
        await s.vm.refresh(); s.vm.requestRemove("project:repo:note")
        XCTAssertFalse(s.transport.requests.contains { $0.method == "DELETE" })
        let approval = try XCTUnwrap(s.vm.confirmation)
        await approval.perform()
        XCTAssertTrue(s.transport.requests.contains { $0.method == "DELETE" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.text.path))
        let files = FileManager.default.enumerator(at: s.root.appendingPathComponent("archives"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        XCTAssertTrue(files.contains { $0.lastPathComponent == "document.json" })
        XCTAssertEqual(state(s.vm)["state"] as? String, "excluded")
        XCTAssertEqual(state(s.vm)["locked"] as? Bool, false)
        try s.vm.setEnabled("project:repo:note", enabled: true)
        XCTAssertEqual(state(s.vm)["enabled"] as? Bool, true)
    }
    func testFailedOrUncertainSubmissionIsNotSilentlyResent() async throws {
        let s = try setup(); s.transport.on("POST", "\(bankPath)/memories", json: "{}", status: 503)
        await s.vm.prepareSend(); await s.vm.confirmation?.perform()
        XCTAssertEqual(state(s.vm)["state"] as? String, "queued")
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }
    func testExplicitRetryKeepsTheOriginalOperationAndText() async throws {
        let s = try setup(); s.transport.on("POST", "\(bankPath)/memories", json: "{}", status: 503)
        await s.vm.prepareSend(); await s.vm.confirmation?.perform()
        let first = try XCTUnwrap(s.transport.requests.first { $0.method == "POST" })
        s.vm.requestRetry("project:repo:note")
        let retry = try XCTUnwrap(s.vm.confirmation)
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
        await retry.perform()
        let last = try XCTUnwrap(s.transport.requests.last { $0.method == "POST" })
        XCTAssertEqual(first.bodyJSON, last.bodyJSON)
    }

    func submitAndParent(_ s: Setup) async throws -> String {
        await s.vm.prepareSend(); await (try XCTUnwrap(s.vm.confirmation)).perform()
        let id = try XCTUnwrap(s.transport.requests.last { $0.method == "POST" }?.bodyJSON?["operation_id"]?.stringValue)
        s.transport.on("GET", "\(bankPath)/operations/\(id)", json: #"{"operation_id":"\#(id)","status":"completed","operation_type":"batch_retain","result_metadata":{"is_parent":true,"num_sub_batches":2},"child_operations":[]}"#)
        return id
    }
    func markRetainQueueActive(_ s: Setup) {
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":1,"offset":0,"operations":[]}"#)
    }
    func testCompletedParentKeepsSourcesQueuedUntilActualWorkFinishes() async throws {
        let s = try setup(); _ = try await submitAndParent(s); markRetainQueueActive(s)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "queued")
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }
    func testCompletedParentWithNoSavedDocumentAndDrainedQueueIsAnError() async throws {
        let s = try setup(); _ = try await submitAndParent(s)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "error")
    }
    func testFailedOperationIsNotSuccessEvenWhenDocumentTextMatches() async throws {
        let s = try setup(); let id = try await submitAndParent(s)
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        s.transport.on("GET", "\(bankPath)/operations/\(id)", json: #"{"operation_id":"\#(id)","status":"failed"}"#)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "error")
    }
    func testOldFalseFailureIsBackedUpAndRecoveredWithoutResending() async throws {
        let s = try setup(); _ = try await submitAndParent(s)
        let ledger = s.root.appendingPathComponent("collection/.memory-workspace.json")
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: ledger)) as? [String: Any])
        var bankState = try XCTUnwrap(data[testBank] as? [String: Any])
        bankState["tracking_version"] = nil; bankState["pending"] = [:]; bankState["operations"] = [:]
        bankState["failures"] = ["source:project:repo:note": "Old false failure"]
        data[testBank] = bankState; try JSONSerialization.data(withJSONObject: data).write(to: ledger)
        markRetainQueueActive(s); await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "queued")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("collection/.memory-workspace.pre-tracking-v2.json").path))
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":0,"limit":1,"offset":0,"operations":[]}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation, "Already-current sources must not appear in a new preview")
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testStoredDocumentCanBeRemovedWhenItsLocalTextIsMissing() async throws {
        let s = try setup(); let text = try String(contentsOf: s.text, encoding: .utf8)
        installDocument(s, id: "source:project:repo:note", text: text)
        try FileManager.default.removeItem(at: s.text)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["locked"] as? Bool, true)
        XCTAssertEqual(state(s.vm)["can_remove"] as? Bool, true)
        s.vm.requestRemove("project:repo:note")
        await (try XCTUnwrap(s.vm.confirmation)).perform()
        XCTAssertNil(s.vm.error)
        XCTAssertEqual(s.transport.requests.filter { $0.method == "DELETE" }.count, 1)
    }

    func testDisabledSourcesStayDisabledAcrossReloads() async throws {
        let s = try setup(); await s.vm.refresh()
        try s.vm.setEnabled(["project:repo:note"], enabled: false)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "excluded")
        await s.vm.prepareSend(); XCTAssertNil(s.vm.confirmation)
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }
    func testLegacyConversationExclusionIsNotBypassedByCatalogID() async throws {
        let s = try setup(); let url = s.root.appendingPathComponent("collection/catalog.json")
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try XCTUnwrap(catalog["records"] as? [[String: Any]])
        let uuid = "12345678-abcd-1234-abcd-123456789012"
        rows[0]["kind"] = "conversations"; rows[0]["source_id"] = "codex://" + uuid; catalog["records"] = rows
        try JSONSerialization.data(withJSONObject: catalog).write(to: url)
        try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": testBank, "excluded_document_ids": ["conversation:" + uuid: [:]], "deferred_document_ids": [:]]).write(to: s.root.appendingPathComponent("memory-policy.json"))
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "excluded")
        XCTAssertThrowsError(try s.vm.setEnabled("project:repo:note", enabled: true))
    }
    func testHistoricalGitExclusionDoesNotExcludeNewCommits() async throws {
        let s = try setup(); let url = s.root.appendingPathComponent("collection/catalog.json")
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var rows = try XCTUnwrap(catalog["records"] as? [[String: Any]])
        rows[0]["kind"] = "github"; rows[0]["context"] = ["commit": String(repeating: "a", count: 40)]; catalog["records"] = rows
        try JSONSerialization.data(withJSONObject: catalog).write(to: url)
        try Data("aaaaaaa 2026-10-01 author\nHistorical commit\n".utf8).write(to: s.root.appendingPathComponent("old-git.md"))
        try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": testBank, "excluded_document_ids": ["gitlog:repo": ["archive": "old-git.md"]], "deferred_document_ids": [:]]).write(to: s.root.appendingPathComponent("memory-policy.json"))
        await s.vm.refresh(); XCTAssertEqual(state(s.vm)["state"] as? String, "excluded")
        rows[0]["context"] = ["commit": String(repeating: "b", count: 40)]; catalog["records"] = rows
        try JSONSerialization.data(withJSONObject: catalog).write(to: url)
        await s.vm.refresh(); XCTAssertEqual(state(s.vm)["state"] as? String, "new")
    }

    func testPolicyHoldsSourcesByPathWhateverTheirUnicodeFormAndReviewComesFirst() async throws {
        let s = try setup(); let url = s.root.appendingPathComponent("collection/catalog.json")
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let base = try XCTUnwrap((catalog["records"] as? [[String: Any]])?.first)
        func record(_ id: String, _ context: [String: Any]) -> [String: Any] {
            var row = base; row["id"] = id; row["context"] = context; return row
        }
        // Chemins du catalogue décomposés (NFD), politique précomposée (NFC), et inversement.
        catalog["records"] = [
            record("project:repo:managed", ["managed_path": "notes/Caf\u{E9}.md"]),
            record("project:repo:original", ["original_path": "/Users/x/Me\u{301}moire/repo2/docs/pla\u{302}n.md"]),
            record("project:repo:moved", ["original_path": "/Users/x/Me\u{301}moire/ailleurs.md"]),
            record("project:repo:both", [:]),
            record("project:repo:removed", [:]),
            record("project:repo:free", ["managed_path": "notes/libre.md", "original_path": "/Users/x/repo2/docs/autre.md"]),
        ]
        try JSONSerialization.data(withJSONObject: catalog).write(to: url)
        let policy: [String: Any] = [
            "version": 1, "bank_id": testBank,
            "deferred_document_ids": [
                "doc:repo:notes/autre.md": ["source": ["repo": "repo", "path": "notes/Cafe\u{301}.md"]],
                "doc:old:ailleurs.md": ["original_path": "/Users/x/M\u{E9}moire/ailleurs.md"],
                "source:project:repo:both": [:],
            ],
            "excluded_document_ids": [
                "doc:repo2:docs/pl\u{E2}n.md": ["source": ["repo": "repo2", "path": "docs/pl\u{E2}n.md"]],
                "source:project:repo:both": ["origin": "workspace"],
                "source:project:repo:removed": ["origin": "workspace"],
            ],
        ]
        try JSONSerialization.data(withJSONObject: policy).write(to: s.root.appendingPathComponent("memory-policy.json"))
        await s.vm.refresh()
        let contained = "Source contenant des documents retirés ou en attente de revue"
        for id in ["project:repo:managed", "project:repo:original", "project:repo:moved"] {
            XCTAssertEqual(state(s.vm, id)["reason"] as? String, contained, id)
            XCTAssertEqual(state(s.vm, id)["locked"] as? Bool, true, id)
        }
        XCTAssertEqual(state(s.vm, "project:repo:both")["reason"] as? String, "En attente de revue")
        XCTAssertEqual(state(s.vm, "project:repo:removed")["reason"] as? String, "Retrait validé")
        XCTAssertEqual(state(s.vm, "project:repo:removed")["can_remove"] as? Bool, true)
        XCTAssertEqual(state(s.vm, "project:repo:removed")["locked"] as? Bool, false)
        XCTAssertEqual(state(s.vm, "project:repo:free")["state"] as? String, "new")
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }

    func testPathTraversalSourceCannotBeSent() async throws {
        let s = try setup(); let path = s.root.appendingPathComponent("collection/catalog.json")
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var rows = try XCTUnwrap(catalog["records"] as? [[String: Any]])
        rows[0]["files"] = ["document.md": "../../private.md"]; catalog["records"] = rows
        try JSONSerialization.data(withJSONObject: catalog).write(to: path)
        await s.vm.prepareSend()
        XCTAssertEqual(state(s.vm)["state"] as? String, "error")
        XCTAssertTrue(state(s.vm)["locked"] as? Bool == true)
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }
}
