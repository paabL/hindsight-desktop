import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import HindsightCore

private func coverageResponse<T: Encodable>(_ value: T) -> MockResponse {
    MockResponse(body: try! JSONEncoder().encode(value))
}

private func coverageDocuments(_ items: [DocumentListItem]) -> MockResponse {
    coverageResponse(ListDocumentsResponse(items: items, total: items.count, limit: 500, offset: 0))
}

private func coverageDocument(_ name: String = "note.md", facts: Int = 1) -> DocumentListItem {
    DocumentListItem(id: "doc:repoA:\(name)", updatedAt: "2000-01-01T00:00:00Z", memoryUnitCount: facts,
                     documentMetadata: ["repo": .string("repoA"), "path": .string(name)])
}

/// One suspended response, without wall-clock response delays or a real server.
private actor CoverageHTTPGate: HTTPTransport {
    let mock: MockTransport
    private var predicate: (@Sendable (URLRequest) -> Bool)?
    private var response: MockResponse?
    private var held: CheckedContinuation<Void, Never>?

    init(_ mock: MockTransport) { self.mock = mock }

    func arm(response: MockResponse? = nil, matching predicate: @escaping @Sendable (URLRequest) -> Bool) {
        self.predicate = predicate
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if predicate?(request) == true {
            predicate = nil
            let response = response
            await withCheckedContinuation { held = $0 }
            if let response {
                return (response.body, HTTPURLResponse(url: request.url!, statusCode: response.status,
                                                      httpVersion: nil, headerFields: response.headers)!)
            }
        }
        return try await mock.send(request)
    }

    func waitForHold() async throws {
        for _ in 0..<2_000 {
            if held != nil { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw HindsightError.refused("Coverage test did not reach its suspended request")
    }

    func release() { held?.resume(); held = nil }
}

private actor CoverageScanGate: ProcessRunning {
    private var shouldHold = true
    private var held: CheckedContinuation<Void, Never>?

    func run(_ invocation: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { held = $0 }
        }
        return ProcessOutput(status: 0, stdout: "note.md\0")
    }

    func waitForHold() async throws {
        for _ in 0..<2_000 {
            if held != nil { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw HindsightError.refused("Coverage test did not reach its suspended scan")
    }

    func release() { held?.resume(); held = nil }
}

@MainActor
private final class CoverageContextBox {
    var client: HindsightClient
    var bank: String? = testBank
    init(_ client: HindsightClient) { self.client = client }
}

@MainActor
final class CoverageStateStressTests: XCTestCase {
    private struct Environment {
        let repo: URL
        let mock: MockTransport
        let gate: CoverageHTTPGate
        let box: CoverageContextBox
        let settings: InMemorySettingsStore
        let documents: Lock<[DocumentListItem]>
        let vm: FileCoverageViewModel
        var file: URL { repo.appendingPathComponent("note.md") }
    }

    private func fixture(documents initial: [DocumentListItem] = []) async throws -> Environment {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-state-\(UUID().uuidString)")
        let repo = parent.appendingPathComponent("repoA")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Data("note\n".utf8).write(to: repo.appendingPathComponent("note.md"))
        let mock = MockTransport(), gate = CoverageHTTPGate(mock), documents = Lock(initial)
        mock.on("GET", bankPath + "/documents") { _ in coverageDocuments(documents.value) }
        mock.on("GET", bankPath + "/operations", json: #"{"bank_id":"b","total":0,"limit":100,"offset":0,"operations":[]}"#)
        mock.on("POST", bankPath + "/memories") { request in
            let count = request.bodyJSON?["items"]?.arrayValue?.count ?? 1
            return coverageResponse(RetainResponse(success: true, bankId: testBank, itemsCount: count, async: true, operationId: "op"))
        }
        mock.on("POST", bankPath + "/files/retain", json: #"{"operation_ids":["op-file"]}"#)
        mock.on("DELETE", bankPath + "/documents/*") { request in
            let id = String(request.path.split(separator: "/").last!)
            documents.value.removeAll { $0.id == id }
            return coverageResponse(DeleteDocumentResponse(success: true, message: "", documentId: id, memoryUnitsDeleted: 1))
        }
        mock.on("GET", bankPath + "/llm-requests", json: #"{"bank_id":"b","total":0,"limit":500,"offset":0,"items":[]}"#)
        let box = CoverageContextBox(HindsightClient(baseURL: URL(string: "https://first.example.test")!, transport: gate))
        let settings = InMemorySettingsStore()
        let vm = FileCoverageViewModel(settings: settings, client: { box.client }, bank: { box.bank })
        addTeardownBlock {
            await gate.release()
            try? FileManager.default.removeItem(at: parent)
        }
        await vm.addRoots([repo])
        return Environment(repo: repo, mock: mock, gate: gate, box: box, settings: settings, documents: documents, vm: vm)
    }

    private func sendConfirmation(_ e: Environment) async throws -> ConfirmationRequest {
        e.vm.selectVisible()
        await e.vm.requestSend()
        return try XCTUnwrap(e.vm.confirmation)
    }

    private func writes(_ e: Environment) -> [RecordedRequest] { e.mock.requests.filter { $0.method != "GET" } }

    func testReversedReloadCannotReplaceTheLatestReport() async throws {
        let e = try await fixture(documents: [coverageDocument(facts: 1)])
        await e.gate.arm(response: coverageDocuments([coverageDocument(facts: 2)])) { $0.url?.path.hasSuffix("/documents") == true }
        let old = Task { await e.vm.reload() }
        try await e.gate.waitForHold()
        e.documents.value = [coverageDocument(facts: 7)]
        await e.vm.reload()
        await e.gate.release(); await old.value
        XCTAssertEqual(e.vm.state.value?.entries.first?.facts, 7)
        XCTAssertFalse(e.vm.isRefreshing)
        XCTAssertNil(e.vm.progress)
    }

    func testOldRootScanCannotPublishFilesForAReplacedRoot() async throws {
        let e = try await fixture()
        let other = e.repo.deletingLastPathComponent().appendingPathComponent("repoB")
        for repo in [e.repo, other] {
            try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try Data("note\n".utf8).write(to: repo.appendingPathComponent("note.md"))
        }
        let scan = CoverageScanGate()
        addTeardownBlock { await scan.release() }
        let vm = FileCoverageViewModel(settings: e.settings, scanner: FileCoverageScanner(runner: scan), client: { e.box.client }, bank: { e.box.bank })
        let old = Task { await vm.reload() }
        try await scan.waitForHold()
        let json = try JSONEncoder().encode([CoverageRoot(path: other.path)])
        e.settings.set(String(decoding: json, as: UTF8.self), forKey: "coverageRoots.\(testBank)")
        await vm.reload()
        await scan.release(); await old.value
        XCTAssertEqual(vm.state.value?.entries.map(\.file.repo), ["repoB"])
        XCTAssertEqual(vm.roots.map(\.path), [other.path])
    }

    func testSameBankOnAnotherServerInvalidatesCachedReportAndQueue() async throws {
        let e = try await fixture(documents: [coverageDocument(facts: 1)])
        e.vm.markQueued("doc:repoA:note.md")
        e.vm.selection = [e.vm.library[0].id]
        await e.gate.arm(response: coverageDocuments([coverageDocument(facts: 2)])) { $0.url?.path.hasSuffix("/documents") == true }
        let old = Task { await e.vm.refreshMemory() }
        try await e.gate.waitForHold()
        e.box.client = HindsightClient(baseURL: URL(string: "https://second.example.test")!, transport: e.gate)
        e.documents.value = [coverageDocument(facts: 9)]
        await e.vm.loadIfNeeded()
        await e.gate.release(); await old.value
        XCTAssertEqual(e.vm.state.value?.entries.first?.facts, 9)
        XCTAssertTrue(e.vm.queuedIDs.isEmpty)
        XCTAssertTrue(e.vm.selection.isEmpty)
    }

    func testLateFailureDoesNotReplaceLatestSuccess() async throws {
        let e = try await fixture()
        await e.gate.arm(response: .json(#"{"detail":"old failure"}"#, status: 503)) { $0.url?.path.hasSuffix("/documents") == true }
        let old = Task { await e.vm.refreshMemory() }
        try await e.gate.waitForHold()
        await e.vm.refreshMemory()
        await e.gate.release(); await old.value
        XCTAssertNotNil(e.vm.state.value)
        XCTAssertNil(e.vm.state.errorMessage)
        XCTAssertNil(e.vm.actionMessage)
    }

    func testOldReadCannotClearNewServersLoadingIndicator() async throws {
        let e = try await fixture()
        await e.gate.arm(response: coverageDocuments([])) { $0.url?.path.hasSuffix("/documents") == true }
        let old = Task { await e.vm.refreshMemory() }
        try await e.gate.waitForHold()
        let nextGate = CoverageHTTPGate(e.mock)
        addTeardownBlock { await nextGate.release() }
        await nextGate.arm(response: coverageDocuments([coverageDocument(facts: 8)])) { $0.url?.path.hasSuffix("/documents") == true }
        e.box.client = HindsightClient(baseURL: URL(string: "https://second.example.test")!, transport: nextGate)
        let next = Task { await e.vm.reload() }
        try await nextGate.waitForHold()
        await e.gate.release(); await old.value
        XCTAssertTrue(e.vm.isRefreshing)
        XCTAssertTrue(e.vm.state.isLoading)
        XCTAssertTrue(e.vm.library.isEmpty)
        await nextGate.release(); await next.value
        XCTAssertFalse(e.vm.isRefreshing)
        XCTAssertEqual(e.vm.state.value?.entries.first?.facts, 8)
    }

    func testCancelledInitialReadCanBeRetried() async throws {
        let e = try await fixture()
        e.vm.invalidateContext()
        await e.gate.arm(response: coverageDocuments([])) { $0.url?.path.hasSuffix("/documents") == true }
        let cancelled = Task { await e.vm.reload() }
        try await e.gate.waitForHold()
        cancelled.cancel()
        await e.gate.release(); await cancelled.value
        XCTAssertFalse(e.vm.state.isLoading)
        XCTAssertFalse(e.vm.isRefreshing)
        await e.vm.loadIfNeeded()
        XCTAssertNotNil(e.vm.state.value)
    }

    func testHashCacheDetectsSameSizeEditWithRestoredModificationDate() async throws {
        var doc = coverageDocument()
        doc.contentHash = SHA256.hex(Data("note\n".utf8))
        let e = try await fixture(documents: [doc])
        XCTAssertEqual(e.vm.state.value?.entries.first?.status, .current)
        let modified = try e.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try Data("EDIT\n".utf8).write(to: e.file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: e.file.path)
        await e.vm.refreshMemory()
        XCTAssertEqual(e.vm.state.value?.entries.first?.status, .modified)
    }

    func testLateQueuedRefreshCannotReplaceNewerFullRead() async throws {
        let e = try await fixture(documents: [coverageDocument(facts: 1)])
        e.vm.markQueued("doc:repoA:note.md")
        await e.gate.arm(response: coverageDocuments([coverageDocument(facts: 2)])) {
            $0.url?.path.hasSuffix("/documents") == true && $0.url?.query?.contains("q=") == true
        }
        let old = Task { await e.vm.refreshQueued() }
        try await e.gate.waitForHold()
        e.documents.value = [coverageDocument(facts: 8)]
        await e.vm.refreshMemory()
        await e.gate.release(); await old.value
        XCTAssertEqual(e.vm.state.value?.entries.first?.facts, 8)
    }

    func testInvalidatedReadCannotPublishAfterServerRoundTrip() async throws {
        let e = try await fixture()
        await e.gate.arm(response: coverageDocuments([coverageDocument(facts: 2)])) { $0.url?.path.hasSuffix("/documents") == true }
        let old = Task { await e.vm.reload() }
        try await e.gate.waitForHold()
        e.vm.invalidateContext()
        await e.vm.reload()
        await e.gate.release(); await old.value
        XCTAssertEqual(e.vm.state.value?.entries.first?.facts, 0)
        XCTAssertFalse(e.vm.isRefreshing)
    }

    func testSendConfirmationCannotMoveToAnotherServer() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        e.box.client = HindsightClient(baseURL: URL(string: "https://second.example.test")!, transport: e.gate)
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
        XCTAssertTrue(e.vm.actionMessage?.contains("changé") == true)
    }

    func testChangedAuthorizationAlsoInvalidatesApproval() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        e.box.client = HindsightClient(baseURL: e.box.client.baseURL, transport: e.gate, authorization: "Bearer synthetic-other-account")
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testSelectionRoundTripCannotReuseApproval() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        let original = e.vm.selection
        e.vm.clearSelection()
        e.vm.selection = original
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
        XCTAssertNil(e.vm.confirmation)
    }

    func testNewApprovalSupersedesSavedOldConfirmation() async throws {
        let e = try await fixture(), first = try await sendConfirmation(e)
        await e.vm.requestSend()
        let second = try XCTUnwrap(e.vm.confirmation)
        await first.perform()
        XCTAssertTrue(writes(e).isEmpty)
        // The bridge clears the displayed confirmation before executing its saved action.
        e.vm.confirmation = nil
        await second.perform()
        XCTAssertEqual(writes(e).count, 1)
    }

    func testSameSizeEditWithRestoredModificationDateIsRejected() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        let modified = try e.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try Data("EDIT\n".utf8).write(to: e.file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: e.file.path)
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
        XCTAssertTrue(e.vm.actionMessage?.contains("modifié ou remplacé") == true)
    }

    func testReplacingFileWithSameBytesIsRejected() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        try Data("note\n".utf8).write(to: e.file, options: .atomic)
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testReplacingSourceWithSymlinkIsRejected() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        let outside = e.repo.deletingLastPathComponent().appendingPathComponent("outside.md")
        try Data("not approved\n".utf8).write(to: outside)
        try FileManager.default.removeItem(at: e.file)
        try FileManager.default.createSymbolicLink(at: e.file, withDestinationURL: outside)
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testRootChangeInvalidatesReviewedUpload() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        await e.vm.removeRoot(e.vm.roots[0])
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testOneHundredRepeatedConfirmationsAndControlsWriteOnlyOnce() async throws {
        let e = try await fixture(), confirmation = try await sendConfirmation(e)
        await e.gate.arm { $0.httpMethod == "POST" }
        let sending = Task { await confirmation.perform() }
        try await e.gate.waitForHold()
        for _ in 0..<100 {
            await confirmation.perform()
            await e.vm.requestSend()
            e.vm.requestRemoveSelection()
        }
        XCTAssertNil(e.vm.confirmation)
        await e.gate.release(); await sending.value
        await confirmation.perform()
        XCTAssertEqual(writes(e).filter { $0.method == "POST" }.count, 1)
        XCTAssertTrue(writes(e).allSatisfy { $0.method == "POST" })
        XCTAssertNil(e.vm.sending)
    }

    func testRetainRefusalIsNotReportedAsSuccessfulSend() async throws {
        let e = try await fixture()
        e.mock.on("POST", bankPath + "/memories") { _ in
            coverageResponse(RetainResponse(success: false, bankId: testBank, itemsCount: 0, async: true))
        }
        let confirmation = try await sendConfirmation(e)
        await confirmation.perform()
        XCTAssertTrue(e.vm.actionMessage?.hasPrefix("0/1 fichier(s)") == true)
        XCTAssertTrue(e.vm.actionMessage?.contains("refusé") == true)
        XCTAssertTrue(e.vm.queuedIDs.isEmpty)
    }

    func testContextChangeStopsRemainingApprovedBatches() async throws {
        let e = try await fixture()
        for i in 0..<10 { try Data("synthetic \(i)\n".utf8).write(to: e.repo.appendingPathComponent("extra-\(i).md")) }
        await e.vm.reload()
        let confirmation = try await sendConfirmation(e)
        await e.gate.arm { $0.httpMethod == "POST" }
        let sending = Task { await confirmation.perform() }
        try await e.gate.waitForHold()
        e.vm.invalidateContext()
        await e.gate.release(); await sending.value
        XCTAssertEqual(writes(e).filter { $0.method == "POST" }.count, 1)
        XCTAssertTrue(e.vm.selection.isEmpty)
        XCTAssertTrue(e.vm.queuedIDs.isEmpty)
        XCTAssertNil(e.vm.sending)
    }

    func testRemovalStopsWhenServerChangesDuringVerification() async throws {
        let e = try await fixture(documents: [coverageDocument()])
        e.vm.selection = [e.vm.library[0].id]
        e.vm.requestRemoveSelection()
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        await e.gate.arm { $0.url?.path.hasSuffix("/documents") == true }
        let removing = Task { await confirmation.perform() }
        try await e.gate.waitForHold()
        for _ in 0..<100 { await confirmation.perform() }
        e.box.client = HindsightClient(baseURL: URL(string: "https://second.example.test")!, transport: e.gate)
        await e.gate.release(); await removing.value
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testRemovalRejectsDocumentChangedAfterReview() async throws {
        let e = try await fixture(documents: [coverageDocument()])
        e.vm.selection = [e.vm.library[0].id]
        e.vm.requestRemoveSelection()
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        e.documents.value = [coverageDocument(facts: 10)]
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
        XCTAssertTrue(e.vm.actionMessage?.contains("changé depuis") == true)
    }

    func testRestoredOrphanSourceRequiresNewReview() async throws {
        let e = try await fixture(documents: [coverageDocument("gone.md")])
        e.vm.requestRemoveOrphans()
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        try Data("restored\n".utf8).write(to: e.repo.appendingPathComponent("gone.md"))
        await confirmation.perform()
        XCTAssertTrue(writes(e).isEmpty)
        XCTAssertTrue(e.vm.actionMessage?.contains("source a été retrouvé") == true)
    }

    func testDuplicateDocumentsAndRepeatedRemoveConfirmationDeleteOnlyOnce() async throws {
        let doc = coverageDocument(), e = try await fixture(documents: [doc])
        e.vm.requestRemove([doc, doc], what: "selected document")
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        await e.gate.arm { $0.httpMethod == "DELETE" }
        let removing = Task { await confirmation.perform() }
        try await e.gate.waitForHold()
        for _ in 0..<100 {
            await confirmation.perform()
            await e.vm.requestSend()
            e.vm.requestRemove([doc], what: "duplicate control")
        }
        await e.gate.release(); await removing.value
        XCTAssertEqual(writes(e).filter { $0.method == "DELETE" }.count, 1)
        XCTAssertTrue(e.documents.value.isEmpty)
    }

    func testDeleteRefusalDoesNotAnnounceSuccessfulRemoval() async throws {
        let e = try await fixture(documents: [coverageDocument()])
        e.mock.on("DELETE", bankPath + "/documents/*") { _ in
            coverageResponse(DeleteDocumentResponse(success: false, message: "not deleted", documentId: "doc:repoA:note.md", memoryUnitsDeleted: 0))
        }
        e.vm.selection = [e.vm.library[0].id]
        e.vm.requestRemoveSelection()
        await e.vm.confirmation!.perform()
        XCTAssertTrue(e.vm.actionMessage?.hasPrefix("0/1 document(s)") == true)
        XCTAssertTrue(e.vm.actionMessage?.contains("not deleted") == true)
        XCTAssertFalse(e.documents.value.isEmpty)
    }

    func testExplicitInvalidationConsumesSendAndRemoveApprovals() async throws {
        let e = try await fixture(documents: [coverageDocument()])
        let sending = try await sendConfirmation(e)
        e.vm.invalidateContext()
        await e.vm.reload()
        await sending.perform()
        XCTAssertTrue(writes(e).isEmpty)
        e.vm.selection = [e.vm.library[0].id]
        e.vm.requestRemoveSelection()
        let removing = try XCTUnwrap(e.vm.confirmation)
        e.vm.invalidateContext()
        await e.vm.reload()
        await removing.perform()
        XCTAssertTrue(writes(e).isEmpty)
    }

    func testOldCostResultCannotReappearAfterSameItemIsReselected() async throws {
        let e = try await fixture(documents: [coverageDocument()])
        let id = e.vm.library[0].id
        let oldPage = #"{"bank_id":"b","total":1,"limit":500,"offset":0,"items":[{"id":"old","status":"success","provider":"local","model":"old","input_tokens":100,"output_tokens":1,"llm_info":{},"metadata":{}}]}"#
        await e.gate.arm(response: .json(oldPage)) { $0.url?.path.hasSuffix("/llm-requests") == true }
        let old = Task { await e.vm.select(id) }
        try await e.gate.waitForHold()
        await e.vm.select(nil)
        await e.vm.select(id)
        await e.gate.release(); await old.value
        XCTAssertEqual(e.vm.cost.value?.calls, 0)
    }
}
