import Foundation
import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor QueueReadMeasurement: HTTPTransport {
    let mock: MockTransport
    private var inFlight = 0
    private(set) var peak = 0
    init(_ mock: MockTransport) { self.mock = mock }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path.contains("/operations/") == true else { return try await mock.send(request) }
        inFlight += 1
        peak = max(peak, inFlight)
        defer { inFlight -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        return try await mock.send(request)
    }
}

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
        let folder = MemoryFolderViewModel(runner: runner, python: "/example/python")
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
        XCTAssertTrue(s.vm.message?.contains("Sources collectées") == true)
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
    func testFolderOfAnotherBankIsBrowsableButNeverSentOrLinked() async throws {
        let s = try setup()
        try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": "other-bank", "excluded_document_ids": [:], "deferred_document_ids": [:]]).write(to: s.root.appendingPathComponent("memory-policy.json"))
        s.server.docs = [DocumentListItem(id: "direct-note")]
        s.vm.prime()
        XCTAssertEqual(state(s.vm)["state"] as? String, "other_bank")
        await s.vm.refresh()
        XCTAssertEqual(s.vm.boundBank, "other-bank")
        XCTAssertTrue(s.vm.bankMismatch)
        XCTAssertEqual(state(s.vm)["state"] as? String, "other_bank")
        XCTAssertEqual(state(s.vm)["enabled"] as? Bool, false)
        XCTAssertEqual(state(s.vm)["locked"] as? Bool, true)
        XCTAssertFalse(s.vm.records.contains { ($0["id"] as? String)?.hasPrefix("bank:") == true }, "The selected bank's documents have nothing to link in another bank's catalog")
        XCTAssertThrowsError(try s.vm.setEnabled("project:repo:note", enabled: true))
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertTrue(s.vm.error?.contains("other-bank") == true)
        XCTAssertFalse(s.transport.requests.contains { $0.method != "GET" })
    }
    func testFirstUploadLinksAnUnboundFolderToItsBank() async throws {
        let s = try setup()
        let policyURL = s.root.appendingPathComponent("memory-policy.json")
        try FileManager.default.removeItem(at: policyURL)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.boundBank)
        let approval = try XCTUnwrap(s.vm.confirmation)
        XCTAssertTrue(approval.message.contains("Ce dossier sera rattaché à « \(testBank) »"))
        await approval.perform()
        XCTAssertNotNil(s.transport.requests.first { $0.method == "POST" })
        let policy = try JSONSerialization.jsonObject(with: Data(contentsOf: policyURL)) as? [String: Any]
        XCTAssertEqual(policy?["bank_id"] as? String, testBank)
        XCTAssertEqual(s.vm.boundBank, testBank)
        XCTAssertFalse(s.vm.bankMismatch)
    }
    func testChangedTextCannotUsePreviousApproval() async throws {
        let s = try setup(); await s.vm.prepareSend(); let approval = try XCTUnwrap(s.vm.confirmation)
        try Data("changed after preview".utf8).write(to: s.text)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
        XCTAssertTrue(s.vm.error?.contains("changé") == true)
    }
    func testPrimingDisplaysManifestWithoutReadingSourcesOrClaimingAComparison() async throws {
        let s = try setup()
        try FileManager.default.removeItem(at: s.text)
        s.vm.prime()
        XCTAssertEqual(s.vm.records.count, 1)
        XCTAssertEqual(state(s.vm)["state"] as? String, "unknown")
        XCTAssertEqual(state(s.vm)["locked"] as? Bool, true)
        XCTAssertEqual(state(s.vm)["enabled"] as? Bool, false)
        XCTAssertEqual(state(s.vm)["hash"] as? String, "")
        XCTAssertNil(s.vm.error)
        XCTAssertTrue(s.transport.requests.isEmpty)
        XCTAssertTrue(s.runner.calls.isEmpty)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "error")
    }
    func testCachedSourceDetectsSameSizeEditWithRestoredModificationDate() async throws {
        let s = try setup()
        await s.vm.refresh()
        let original = try String(contentsOf: s.text, encoding: .utf8)
        let oldHash = state(s.vm)["hash"] as? String
        let modified = try s.text.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let changed = original.replacingOccurrences(of: "Full", with: "True")
        try Data(changed.utf8).write(to: s.text)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: s.text.path)
        await s.vm.refresh()
        XCTAssertNotEqual(state(s.vm)["hash"] as? String, oldHash)
        XCTAssertEqual(state(s.vm)["hash"] as? String, SHA256.hex(Data(changed.utf8)))
        XCTAssertTrue(s.runner.calls.isEmpty)
    }
    func testCachedSourceDoesNotFollowReplacementSymlinkOutsideCollection() async throws {
        let s = try setup()
        await s.vm.refresh()
        let outside = s.root.appendingPathComponent("private.md")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.removeItem(at: s.text)
        try FileManager.default.createSymbolicLink(at: s.text, withDestinationURL: outside)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "error")
        XCTAssertEqual(state(s.vm)["locked"] as? Bool, true)
        XCTAssertEqual(state(s.vm)["hash"] as? String, "")
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
    }
    func testServerChangeDoesNotReuseDocumentsFromThePreviousServer() async throws {
        let s = try setup()
        s.server.docs = [DocumentListItem(id: "only-on-first")]
        var activeClient = makeClient(s.transport)
        let workspace = MemoryWorkspace(folder: s.folder, client: { activeClient }, bank: { testBank })
        await workspace.refresh()
        XCTAssertTrue(workspace.records.contains { $0["id"] as? String == "bank:only-on-first" })
        let offline = MockTransport()
        offline.on("GET", "\(bankPath)/documents", json: "{}", status: 503)
        activeClient = HindsightClient(baseURL: URL(string: "http://localhost:9999")!, transport: offline)
        await workspace.refresh()
        XCTAssertFalse(workspace.records.contains { $0["id"] as? String == "bank:only-on-first" })
        XCTAssertEqual(state(workspace)["state"] as? String, "unknown")
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
        XCTAssertEqual(state(s.vm)["state"] as? String, "failed")
    }
    func testFailedOperationIsNotSuccessEvenWhenDocumentTextMatches() async throws {
        let s = try setup(); let id = try await submitAndParent(s)
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        s.transport.on("GET", "\(bankPath)/operations/\(id)", json: #"{"operation_id":"\#(id)","status":"failed"}"#)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "failed")
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
        XCTAssertEqual(state(s.vm, "project:repo:removed")["can_remove"] as? Bool, false, "Nothing stored: there is nothing to remove from memory")
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

    private func saveTracking(_ s: Setup, _ state: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: [testBank: state])
            .write(to: s.root.appendingPathComponent("collection/.memory-workspace.json"))
    }

    func testHistoricalQueueRowsDoNotBlockWhenTheirActualOperationsHaveCompleted() async throws {
        let s = try setup()
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":100,"offset":0,"operations":[{"id":"old-task","operation_id":"finished","task_type":"retain","items_count":1,"status":"processing","created_at":""}]}"#)
        s.transport.on("GET", "\(bankPath)/operations/finished", json: #"{"operation_id":"finished","status":"processing","operation_type":"retain"}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertTrue(s.vm.error?.contains("encore en cours") == true)
        s.transport.on("GET", "\(bankPath)/operations/finished", json: #"{"operation_id":"finished","status":"completed","operation_type":"retain","error_message":"Old transient failure"}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.error)
        XCTAssertNotNil(s.vm.confirmation)
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }

    func testQueueVerificationPaginatesPastHistoricalRowsAndStillBlocksRealWork() async throws {
        let s = try setup()
        let rows = (0..<101).map { OperationResponse(id: "op-\($0)", taskType: "retain", itemsCount: 1, createdAt: "", status: "processing") }
        s.transport.on("GET", "\(bankPath)/operations") { request in
            let offset = Int(request.queryValue("offset") ?? "0") ?? 0
            let page = OperationsListResponse(bankId: testBank, total: rows.count, limit: 100, offset: offset, operations: Array(rows.dropFirst(offset).prefix(100)))
            return .json(String(decoding: try! JSONEncoder().encode(page), as: UTF8.self))
        }
        s.transport.on("GET", "\(bankPath)/operations/*") { request in
            let id = (request.path as NSString).lastPathComponent
            return .json(#"{"operation_id":"\#(id)","operation_type":"retain","status":"\#(id == "op-100" ? "pending" : "completed")"}"#)
        }
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertTrue(s.vm.error?.contains("encore en cours") == true)
        XCTAssertTrue(s.transport.requests.contains { $0.queryValue("offset") == "100" })
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testHistoricalTasksSharingAParentAreNotAnIncompleteQueue() async throws {
        let s = try setup()
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":2,"limit":100,"offset":0,"operations":[{"id":"task-one","operation_id":"parent","task_type":"retain","items_count":1,"status":"processing","created_at":""},{"id":"task-two","operation_id":"parent","task_type":"retain","items_count":1,"status":"processing","created_at":""}]}"#)
        s.transport.on("GET", "\(bankPath)/operations/parent", json: #"{"operation_id":"parent","operation_type":"batch_retain","status":"completed"}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.error)
        XCTAssertNotNil(s.vm.confirmation)
        XCTAssertEqual(s.transport.requests.filter { $0.path.hasSuffix("/operations/parent") }.count, 1)
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }

    func testHistoricalQueueVerificationUsesBoundedConcurrentReads() async throws {
        let s = try setup()
        let rows = (0..<12).map { OperationResponse(id: "historical-\($0)", taskType: "retain", itemsCount: 1, createdAt: "", status: "processing") }
        s.transport.on("GET", "\(bankPath)/operations") { _ in
            .json(String(decoding: try! JSONEncoder().encode(OperationsListResponse(bankId: testBank, total: rows.count, limit: 100, offset: 0, operations: rows)), as: UTF8.self))
        }
        s.transport.on("GET", "\(bankPath)/operations/*") { request in
            .json(#"{"operation_id":"\#((request.path as NSString).lastPathComponent)","operation_type":"retain","status":"completed"}"#)
        }
        let measured = QueueReadMeasurement(s.transport)
        let client = HindsightClient(transport: measured)
        let vm = MemoryWorkspace(folder: s.folder, client: { client }, bank: { testBank })
        await vm.prepareSend()
        XCTAssertNil(vm.error)
        XCTAssertNotNil(vm.confirmation)
        let peak = await measured.peak
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertEqual(s.transport.requests.filter { $0.path.contains("/operations/") }.count, 12)
    }

    func testUnreadableOrIncompleteQueueRemainsFailClosed() async throws {
        let s = try setup()
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":100,"offset":0,"operations":[]}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertNotNil(s.vm.error)
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":100,"offset":0,"operations":[{"id":"unknown","task_type":"retain","items_count":1,"status":"pending","created_at":""}]}"#)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertNotNil(s.vm.error)
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testCompletedParentDoesNotStayQueuedBecauseOfHistoricalTaskRows() async throws {
        let s = try setup(); let id = try await submitAndParent(s)
        s.transport.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":100,"offset":0,"operations":[{"id":"\#(id)","task_type":"batch_retain","items_count":1,"status":"processing","created_at":""}]}"#)
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "failed", "A drained queue without the expected saved text needs fresh approval, not an endless queued state")
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testRefreshClearsMessagesFromACompletedSubmission() async throws {
        let s = try setup(); _ = try await submitAndParent(s)
        XCTAssertNotNil(s.vm.message)
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        await s.vm.refresh()
        XCTAssertEqual(state(s.vm)["state"] as? String, "current")
        XCTAssertNil(s.vm.message)
        XCTAssertNil(s.vm.error)
    }

    func testMalformedTrackingCannotSilentlyDropPendingAndResend() async throws {
        let s = try setup()
        try saveTracking(s, ["pending": ["source:project:repo:note": 42], "operations": [:]])
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertNotNil(s.vm.error)
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testIncompleteOrForeignServerTrackingCannotBeReplayedIntoTheCurrentBank() async throws {
        let s = try setup()
        let cases: [[String: Any]] = [
            ["pending": [:], "operations": ["source:project:repo:note": UUID().uuidString]],
            ["server_url": "https://another-fixture.invalid", "pending": [:], "operations": [:]],
        ]
        for tracking in cases {
            try saveTracking(s, tracking)
            await s.vm.prepareSend()
            XCTAssertNil(s.vm.confirmation)
            XCTAssertNotNil(s.vm.error)
        }
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testDuplicateCatalogIDsCannotCrashPreviewOrSendDuplicateDocuments() async throws {
        let s = try setup(); let path = s.root.appendingPathComponent("collection/catalog.json")
        var catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        let row = try XCTUnwrap((catalog["records"] as? [[String: Any]])?.first)
        catalog["records"] = [row, row]
        try JSONSerialization.data(withJSONObject: catalog).write(to: path)
        await s.vm.prepareSend()
        XCTAssertNil(s.vm.confirmation)
        XCTAssertTrue(s.vm.error?.contains("dupliqués") == true)
        XCTAssertTrue(s.vm.records.isEmpty)
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testUploadApprovalIsBoundToTheOriginalServerAndCannotBePerformedTwice() async throws {
        let s = try setup(); var activeClient = makeClient(s.transport)
        let vm = MemoryWorkspace(folder: s.folder, client: { activeClient }, bank: { testBank })
        await vm.prepareSend(); let approval = try XCTUnwrap(vm.confirmation)
        activeClient = HindsightClient(baseURL: URL(string: "http://localhost:9999")!, transport: s.transport)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
        XCTAssertTrue(vm.error?.contains("contexte") == true)
        activeClient = makeClient(s.transport)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" }, "An old confirmation is consumed even when validation refuses it")
        await vm.prepareSend(); let current = try XCTUnwrap(vm.confirmation)
        await current.perform(); await current.perform()
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testRetryApprovalCannotReplayAReconciledOrForeignServerBatch() async throws {
        let s = try setup(); var activeClient = makeClient(s.transport)
        let vm = MemoryWorkspace(folder: s.folder, client: { activeClient }, bank: { testBank })
        await vm.prepareSend(); await (try XCTUnwrap(vm.confirmation)).perform()
        vm.requestRetry("project:repo:note"); let retry = try XCTUnwrap(vm.confirmation)
        try saveTracking(s, ["tracking_version": 2, "pending": [:], "operations": [:]])
        await retry.perform()
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
        XCTAssertNotNil(vm.error)
        activeClient = HindsightClient(baseURL: URL(string: "http://localhost:9999")!, transport: s.transport)
        vm.requestRetry("project:repo:note")
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testRemovalRechecksPendingTrackingAfterTheConfirmationWasShown() async throws {
        let s = try setup(); let text = try String(contentsOf: s.text, encoding: .utf8)
        let target = "source:project:repo:note"
        installDocument(s, id: target, text: text)
        await s.vm.refresh(); s.vm.requestRemove("project:repo:note")
        let approval = try XCTUnwrap(s.vm.confirmation)
        try saveTracking(s, ["tracking_version": 2, "pending": [target: SHA256.hex(Data(text.utf8))], "operations": [target: UUID().uuidString]])
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "DELETE" })
        XCTAssertTrue(s.vm.error?.contains("fin du traitement") == true)
    }

    func testRemovalApprovalDoesNotDeleteFromANewServer() async throws {
        let s = try setup(); var activeClient = makeClient(s.transport)
        installDocument(s, id: "source:project:repo:note", text: try String(contentsOf: s.text, encoding: .utf8))
        let vm = MemoryWorkspace(folder: s.folder, client: { activeClient }, bank: { testBank })
        await vm.refresh(); vm.requestRemove("project:repo:note")
        let approval = try XCTUnwrap(vm.confirmation)
        activeClient = HindsightClient(baseURL: URL(string: "http://localhost:9999")!, transport: s.transport)
        await approval.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "DELETE" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("archives").path))
    }

    func testImportRechecksSelectedFilesAndFolderAndConsumesApproval() async throws {
        let s = try setup()
        s.folder.requestImport(paths: [s.text.path], project: "fixture")
        let changed = try XCTUnwrap(s.folder.confirmation)
        try Data("# Changed after the preview".utf8).write(to: s.text)
        await changed.perform()
        XCTAssertTrue(s.runner.calls.isEmpty)
        XCTAssertTrue(s.folder.error?.contains("changé") == true)
        s.folder.requestImport(paths: [s.text.path], project: "fixture")
        let moved = try XCTUnwrap(s.folder.confirmation)
        let other = try setup()
        s.folder.choose(other.root)
        await moved.perform()
        XCTAssertTrue(s.runner.calls.isEmpty)
        s.folder.choose(s.root)
        s.folder.requestImport(paths: [s.text.path], project: "fixture")
        let valid = try XCTUnwrap(s.folder.confirmation)
        await valid.perform(); await valid.perform()
        XCTAssertEqual(s.runner.calls.count, 1)
    }

    func testImportCannotFollowASymlinkSubstitutedAfterPreview() async throws {
        let s = try setup()
        s.folder.requestImport(paths: [s.text.path], project: "fixture")
        let approval = try XCTUnwrap(s.folder.confirmation)
        let other = s.root.appendingPathComponent("other.md")
        try Data("# Not selected".utf8).write(to: other)
        try FileManager.default.removeItem(at: s.text)
        try FileManager.default.createSymbolicLink(at: s.text, withDestinationURL: other)
        await approval.perform()
        XCTAssertTrue(s.runner.calls.isEmpty)
        XCTAssertNotNil(s.folder.error)
    }

    private actor RequestGate: HTTPTransport {
        let transport: MockTransport
        private var path: String?
        private var releaseRequest: CheckedContinuation<Void, Never>?
        private var entered: CheckedContinuation<Void, Never>?
        init(_ transport: MockTransport) { self.transport = transport }
        func holdNext(_ path: String) { self.path = path }
        func waitUntilHeld() async {
            if releaseRequest != nil { return }
            await withCheckedContinuation { entered = $0 }
        }
        func release() { releaseRequest?.resume(); releaseRequest = nil }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            if request.url?.path == path {
                path = nil
                await withCheckedContinuation { continuation in
                    releaseRequest = continuation
                    entered?.resume(); entered = nil
                }
            }
            return try await transport.send(request)
        }
    }

    func testServerChangeDuringQueueVerificationCannotRedirectAnApprovedUpload() async throws {
        let s = try setup(); let gate = RequestGate(s.transport)
        var activeClient = HindsightClient(baseURL: makeClient(s.transport).baseURL, transport: gate)
        let vm = MemoryWorkspace(folder: s.folder, client: { activeClient }, bank: { testBank })
        await vm.prepareSend(); let approval = try XCTUnwrap(vm.confirmation)
        await gate.holdNext("\(bankPath)/operations")
        let task = Task { await approval.perform() }
        await gate.waitUntilHeld()
        activeClient = HindsightClient(baseURL: URL(string: "http://localhost:9999")!, transport: s.transport)
        await gate.release(); await task.value
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
    }

    func testRapidConfirmationsOfTwoPreviewsCannotSubmitTheSameSourceTwice() async throws {
        let s = try setup(); let gate = RequestGate(s.transport)
        let api = HindsightClient(baseURL: makeClient(s.transport).baseURL, transport: gate)
        let vm = MemoryWorkspace(folder: s.folder, client: { api }, bank: { testBank })
        await vm.prepareSend(); let first = try XCTUnwrap(vm.confirmation)
        await vm.prepareSend(); let second = try XCTUnwrap(vm.confirmation)
        await gate.holdNext("\(bankPath)/operations")
        let running = Task { await first.perform() }
        await gate.waitUntilHeld()
        await second.perform()
        XCTAssertFalse(s.transport.requests.contains { $0.method == "POST" })
        await gate.release(); await running.value
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testRetryApprovalCannotBypassAPolicyChangedAfterItsPreview() async throws {
        let s = try setup()
        await s.vm.prepareSend(); await (try XCTUnwrap(s.vm.confirmation)).perform()
        s.vm.requestRetry("project:repo:note"); let retry = try XCTUnwrap(s.vm.confirmation)
        let url = s.root.appendingPathComponent("memory-policy.json")
        var policy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        policy["deferred_document_ids"] = ["source:project:repo:note": ["reason": "Needs review"]]
        try JSONSerialization.data(withJSONObject: policy).write(to: url)
        await retry.perform()
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
        XCTAssertTrue(s.vm.error?.contains("politique") == true)
    }

    func testLateStoredTextIsDiscardedAfterABankChange() async throws {
        let s = try setup(); let target = "source:project:repo:note"
        installDocument(s, id: target, text: try String(contentsOf: s.text, encoding: .utf8))
        let gate = RequestGate(s.transport)
        let api = HindsightClient(baseURL: makeClient(s.transport).baseURL, transport: gate)
        var selectedBank: String? = testBank
        let vm = MemoryWorkspace(folder: s.folder, client: { api }, bank: { selectedBank })
        await vm.refresh()
        await gate.holdNext("\(bankPath)/documents/\(target)")
        let task = Task { try await vm.storedText("project:repo:note") }
        await gate.waitUntilHeld(); selectedBank = "another"
        await gate.release()
        do { _ = try await task.value; XCTFail("A late private document must not escape into the new context") }
        catch { XCTAssertTrue(error.localizedDescription.contains("contexte")) }
    }

    func testOutOfOrderFolderRefreshCannotReplaceTheNewFoldersCatalog() async throws {
        let s = try setup(), other = try setup(); let gate = RequestGate(s.transport)
        let api = HindsightClient(baseURL: makeClient(s.transport).baseURL, transport: gate)
        let vm = MemoryWorkspace(folder: s.folder, client: { api }, bank: { testBank })
        await gate.holdNext("\(bankPath)/documents")
        let slow = Task { await vm.refresh() }
        await gate.waitUntilHeld()
        try Data("# Second folder source".utf8).write(to: other.text)
        s.folder.choose(other.root)
        await vm.refresh()
        let current = state(vm)["hash"] as? String
        await gate.release(); await slow.value
        XCTAssertEqual(state(vm)["hash"] as? String, current)
        XCTAssertEqual(current, SHA256.hex(Data("# Second folder source".utf8)))
        XCTAssertTrue(s.transport.requests.allSatisfy { $0.method == "GET" })
    }

    func testLateTrackingRecoveryCannotRestorePendingIntoANewerRefresh() async throws {
        let s = try setup(); let operation = try await submitAndParent(s)
        let target = "source:project:repo:note"
        try saveTracking(s, ["tracking_version": 1, "pending": [:], "operations": [:], "failures": [target: "Old false failure"]])
        let gate = RequestGate(s.transport)
        let api = HindsightClient(baseURL: makeClient(s.transport).baseURL, transport: gate)
        let vm = MemoryWorkspace(folder: s.folder, client: { api }, bank: { testBank })
        await gate.holdNext("\(bankPath)/operations/\(operation)")
        let old = Task { await vm.refresh() }
        await gate.waitUntilHeld()
        try saveTracking(s, ["tracking_version": 2, "enabled": ["project:repo:note": false], "pending": [:], "operations": [:], "failures": [:]])
        await vm.refresh()
        await gate.release(); await old.value
        XCTAssertEqual(state(vm)["state"] as? String, "excluded")
        installDocument(s, id: target, text: try String(contentsOf: s.text, encoding: .utf8))
        await vm.refresh()
        vm.requestRemove("project:repo:note")
        XCTAssertNotNil(vm.confirmation, "A superseded recovery must not resurrect an old pending blocker")
        XCTAssertEqual(s.transport.requests.filter { $0.method == "POST" }.count, 1)
    }
}
