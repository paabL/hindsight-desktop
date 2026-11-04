import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class DocumentsViewModelTests: XCTestCase {
    func make(_ t: MockTransport) -> DocumentsViewModel {
        let c = makeClient(t)
        return DocumentsViewModel(client: c, bank: testBank, attachmentLoader: AttachmentLoader(client: c))
    }

    func testReloadAndPaging() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.total, 4)
        XCTAssertTrue(vm.canLoadMore)
        await vm.loadMore()
        XCTAssertEqual(vm.items.count, 4)
        XCTAssertFalse(vm.canLoadMore)
        let offsets = t.requests.filter { $0.path.hasSuffix("/documents") }.map { $0.queryValue("offset") }
        XCTAssertEqual(offsets, ["0", "3"])
    }

    func testNaturalSortOrdersTaskNumbers() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        await vm.loadAll()
        vm.sort = .nameAscending
        XCTAssertEqual(vm.sortedItems.map(\.id), ["codex-abc-task-001", "codex-abc-task-002", "codex-abc-task-010", "notes-misc"])
        vm.sort = .mostFacts
        XCTAssertEqual(vm.sortedItems.first?.id, "codex-abc-task-001")
        vm.sort = .longest
        XCTAssertEqual(vm.sortedItems.first?.id, "codex-abc-task-001")
        vm.sort = .oldestFirst
        XCTAssertEqual(vm.sortedItems.first?.id, "notes-misc")
    }

    func testTagFilterAndSearchAreSentToServer() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        vm.query = "task-00"
        vm.toggleTag("source:codex")
        vm.toggleTag("task:002")
        await vm.reload()
        let r = t.requests.last!
        XCTAssertEqual(r.queryValue("q"), "task-00")
        XCTAssertEqual(r.query["tags"], ["source:codex", "task:002"])
        XCTAssertEqual(r.queryValue("tags_match"), "all_strict")
        vm.toggleTag("task:002")
        XCTAssertEqual(vm.selectedTags, ["source:codex"])
    }

    func testAvailableTagsAreCountedAcrossLoadedDocuments() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        let tags = vm.availableTags
        XCTAssertEqual(tags.first?.count, 3)  // à égalité, ordre alphabétique
        XCTAssertEqual(tags.map(\.tag).prefix(2), ["session:abc", "source:codex"])
        XCTAssertEqual(tags.first { $0.tag == "task:002" }?.count, 1)
    }

    func testOpenReusesReaderAndFocusesChunk() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        let r1 = vm.open(documentID: "codex-abc-task-002", chunkID: "codex-abc-task-002_1")
        for _ in 0..<50 where r1.state.value == nil { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(r1.state.value)
        XCTAssertEqual(r1.focusedChunkID, "codex-abc-task-002_1")
        let r2 = vm.open(documentID: "codex-abc-task-002", chunkID: "codex-abc-task-002_0")
        XCTAssertTrue(r1 === r2)
        XCTAssertEqual(r2.focusedChunkID, "codex-abc-task-002_0")
    }

    /// Lecteur ouvert depuis l'écran Documents (vue compacte) : sur un serveur 1.1.0, il a la portée et l'historique.
    func testReaderOpenedFromDocumentsHasScopeAndHistoryOn110() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "\(bankPath)/documents/codex-abc-task-002/history", json: #"{"document_id":"codex-abc-task-002","items":[{"document_id":"codex-abc-task-002","kind":"consolidation","facts_added":0,"facts_removed":0}],"total":1,"limit":50,"offset":0}"#)
        let vm = make(t)
        vm.serverIs110 = true
        let r = vm.open(documentID: "codex-abc-task-002")
        for _ in 0..<50 where r.history == nil { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(r.serverIs110, "le menu de portée suit la version du serveur")
        XCTAssertEqual(r.history?.map(\.kind), ["consolidation"])
    }

    func testTaskNumberParsing() async {
        let vm = make(MockTransport())
        XCTAssertEqual(vm.taskNumber(of: "codex-abc-task-012"), 12)
        XCTAssertNil(vm.taskNumber(of: "notes"))
        XCTAssertTrue(vm.isTaskDocument("codex-abc-task-012"))
        XCTAssertFalse(vm.isTaskDocument("notes-misc"))
    }

    func testErrorStateOnFailure() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/documents", json: #"{"detail":"boom"}"#, status: 500)
        let vm = make(t)
        await vm.reload()
        XCTAssertTrue(vm.state.errorMessage?.contains("HTTP 500") == true)
    }
}
