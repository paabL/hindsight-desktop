import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

/// Écran Documents : sources suivies et documents de la banque réunis.
@MainActor
final class DocumentLibraryTests: XCTestCase {
    func file(_ path: String, repo: String = "repoA") -> ScannedFile {
        ScannedFile(repo: repo, path: path, url: URL(fileURLWithPath: "/tmp/\(repo)/\(path)"), size: 10, modified: Date(timeIntervalSince1970: 1_000))
    }

    func doc(_ id: String, repo: String? = "repoA", path: String?, hash: String? = nil, facts: Int = 3, meta: [String: JSONValue] = [:]) -> DocumentListItem {
        var m = meta
        if let repo { m["repo"] = .string(repo) }
        if let path { m["path"] = .string(path) }
        return DocumentListItem(id: id, contentHash: hash, updatedAt: "1970-01-01T00:30:00Z", memoryUnitCount: facts, documentMetadata: m)
    }

    func testEveryDocumentAppearsOnceWithOneClearState() async {
        let files = [file("README.md"), file("docs/old.md"), file("new.md"), file("docs/empty.md"), file("later.md")]
        let docs = [
            doc("doc:repoA:README.md", path: "README.md", hash: "h1"),
            doc("doc:repoA:docs/old.md", path: "docs/old.md", hash: "stale"),
            doc("doc:repoA:docs/empty.md", path: "docs/empty.md", hash: "h3", facts: 0),
            doc("doc:repoA:gone.md", path: "gone.md"),
            doc("doc:other:x.md", repo: "other", path: "notes/x.md"),
            doc("codex-zz-task-001", repo: nil, path: nil),
            doc("synthese-1", repo: nil, path: nil),
            doc("vide", repo: nil, path: nil, facts: 0),
        ]
        let hashes = ["README.md": "h1", "docs/old.md": "fresh", "docs/empty.md": "h3"]
        let report = FileCoverage.report(files: files, documents: docs) { hashes[$0.path] }
        let items = DocumentLibrary.build(report: report, queued: ["doc:repoA:new.md"])
        let state = Dictionary(uniqueKeysWithValues: items.map { ($0.title, $0.state) })
        XCTAssertEqual(state["README.md"], .current)
        XCTAssertEqual(state["old.md"], .modified)
        XCTAssertEqual(state["empty.md"], .noFacts)
        XCTAssertEqual(state["new.md"], .queued, "une opération l'extrait")
        XCTAssertEqual(state["later.md"], .notSent)
        XCTAssertEqual(state["gone.md"], .fileMissing)
        XCTAssertEqual(state["x.md"], .stored)
        XCTAssertEqual(state["synthese-1"], .stored)
        XCTAssertEqual(state["vide"], .noFacts)

        let placed = items.flatMap { $0.documents.map(\.id) }
        XCTAssertEqual(placed.count, Set(placed).count, "aucun document en double")
        XCTAssertEqual(Set(placed), Set(docs.map(\.id)), "aucun document oublié")
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)

        let sections = DocumentLibrary.sections(items, sort: .name)
        XCTAssertEqual(sections.map(\.group.title), ["repoA", "other", "Autres conversations", "Autres documents"])
        XCTAssertEqual(sections[0].items.map(\.title), ["empty.md", "old.md", "gone.md", "later.md", "new.md", "README.md"], "ordre du Finder, chemin compris")
        XCTAssertEqual(items.first { $0.title == "gone.md" }?.group.id, "folder:repoA", "un fichier disparu reste dans son dossier")
        XCTAssertEqual(items.first { $0.title == "x.md" }?.location, "other/notes")

        XCTAssertEqual(items.filter(LibraryScope.toSend.includes).map(\.title).sorted(), ["later.md", "old.md"])
        XCTAssertEqual(items.filter(LibraryScope.toCheck.includes).map(\.title).sorted(), ["empty.md", "gone.md", "vide"])
        XCTAssertEqual(items.filter(LibraryScope.queued.includes).map(\.title), ["new.md"])
        XCTAssertEqual(items.filter(LibraryScope.inMemory.includes).count, 8)
    }

    func testConversationsWithTheSameTitleStayDistinct() async {
        func session(_ id: String) -> CodexSessionSummary {
            var s = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/x/.codex/sessions/\(id).jsonl")))
            s.meta = CodexSessionMeta(id: id)
            s.firstUserText = "Corrige le test"
            return s
        }
        let report = FileCoverage.report(files: [], sessions: [session("a"), session("b")], documents: [doc("codex-a-task-001", repo: nil, path: nil)]) { _ in nil }
        let items = DocumentLibrary.build(report: report)
        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertEqual(Set(items.map(\.title)), ["Corrige le test"])
        XCTAssertEqual(items.first { !$0.documents.isEmpty }?.state, .current)
        XCTAssertTrue(items.allSatisfy { !$0.canSend }, "Les conversations restent consultables sans import natif")
        XCTAssertTrue(items.allSatisfy { $0.sourceURL?.pathExtension == "jsonl" })
        XCTAssertEqual(items[0].group.title, "Conversations Codex")
        XCTAssertFalse(FileCoverageViewModel.isSelectable(report.entries[1]), "Une conversation absente de la banque ne peut pas être envoyée ici")
        XCTAssertTrue(FileCoverageViewModel.isSelectable(report.entries[0]), "Un document existant peut toujours être sélectionné pour retrait")
    }

    /// Dossier `repoA` avec une note absente de la banque ; faux serveur dont les documents évoluent.
    func fixture() throws -> (repo: URL, transport: MockTransport, documents: Lock<String>) {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)").appendingPathComponent("repoA")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        try Data("note\n".utf8).write(to: repo.appendingPathComponent("note.md"))
        let t = MockTransport()
        let documents = Lock(#"{"items":[],"total":0,"limit":500,"offset":0}"#)
        t.on("GET", "\(bankPath)/documents") { _ in .json(documents.value) }
        t.on("POST", "\(bankPath)/memories", json: #"{"success":true,"bank_id":"b","items_count":1,"async":true,"operation_id":"op1"}"#)
        t.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":1,"limit":100,"offset":0,"operations":[]}"#)
        t.on("GET", "\(bankPath)/llm-requests", json: #"{"bank_id":"b","total":0,"limit":500,"offset":0,"items":[]}"#)
        return (repo, t, documents)
    }

    func testSentItemStaysQueuedUntilItsDocumentIsWritten() async throws {
        let (repo, t, documents) = try fixture()
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        await vm.addRoots([repo])
        XCTAssertEqual(vm.library.map(\.state), [.notSent])
        vm.selection = [vm.library[0].id]
        await vm.requestSend()
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.library.first?.state, .queued, "envoyée, pas encore extraite")
        XCTAssertEqual(vm.count(.queued), 1)

        let hash = SHA256.hex(Data("note\n".utf8))
        let later = HSDate.format(Date().addingTimeInterval(60))
        documents.value = #"{"items":[{"id":"doc:repoA:note.md","bank_id":"b","content_hash":"\#(hash)","created_at":"","updated_at":"\#(later)","text_length":5,"memory_unit_count":2,"document_metadata":{"repo":"repoA","path":"note.md"},"tags":["repo:repoA"]}],"total":1,"limit":500,"offset":0}"#
        await vm.refreshMemory()
        XCTAssertEqual(vm.library.first?.state, .current)
        XCTAssertEqual(vm.library.first?.facts, 2)
        XCTAssertEqual(vm.availableTags.first?.tag, "repo:repoA")

        vm.tagFilter = ["autre"]
        XCTAssertTrue(vm.visibleItems.isEmpty)
        vm.tagFilter = []
        vm.search = "NOTE"
        XCTAssertEqual(vm.visibleItems.count, 1, "recherche insensible à la casse")
        XCTAssertEqual(vm.item(containing: "doc:repoA:note.md")?.title, "note.md")
    }

    func testSwitchingBankNeverShowsTheOtherBanksItems() async throws {
        let (repo, t, _) = try fixture()
        let other = "autre-banque"
        t.on("GET", "/v1/default/banks/\(other)/documents", json: #"{"items":[{"id":"x","bank_id":"autre","created_at":"","updated_at":"2026-10-20T10:00:00Z","text_length":1,"memory_unit_count":1,"tags":[]}],"total":1,"limit":500,"offset":0}"#)
        let bank = Lock(testBank)
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { bank.value })
        await vm.addRoots([repo])
        vm.selection = [vm.library[0].id]
        bank.value = other
        await vm.loadIfNeeded()
        XCTAssertEqual(vm.library.map(\.title), ["x"], "les dossiers suivis sont propres à chaque banque")
        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testReprocessedDocumentIsQueuedAndOnlyItIsReread() async throws {
        let (repo, t, documents) = try fixture()
        let hash = SHA256.hex(Data("note\n".utf8))
        func doc(facts: Int, updated: String) -> String {
            #"{"items":[{"id":"doc:repoA:note.md","bank_id":"b","content_hash":"\#(hash)","created_at":"","updated_at":"\#(updated)","text_length":5,"memory_unit_count":\#(facts),"document_metadata":{"repo":"repoA","path":"note.md"},"tags":[]}],"total":1,"limit":500,"offset":0}"#
        }
        documents.value = doc(facts: 0, updated: "2026-10-20T10:00:00Z")
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        await vm.addRoots([repo])
        XCTAssertEqual(vm.library.first?.state, .noFacts)
        vm.markQueued("doc:repoA:note.md")
        XCTAssertEqual(vm.library.first?.state, .queued, "retraité : en file tout de suite")

        t.reset()
        documents.value = doc(facts: 4, updated: HSDate.format(Date().addingTimeInterval(60)))
        await vm.refreshQueued()
        let reads = t.requests.filter { $0.path.hasSuffix("/documents") }
        XCTAssertFalse(reads.isEmpty)
        XCTAssertTrue(reads.allSatisfy { $0.queryValue("q") == "doc:repoA:note.md" }, "seul le document en file est relu")
        XCTAssertEqual(vm.library.first?.state, .current)
        XCTAssertEqual(vm.library.first?.facts, 4)
    }

    func testCostFallsBackOnLocalHistoryWhenServerTracesExpired() async throws {
        let (repo, t, documents) = try fixture()
        documents.value = #"{"items":[{"id":"doc:repoA:note.md","bank_id":"b","created_at":"","updated_at":"2026-10-20T10:00:00Z","text_length":5,"memory_unit_count":2,"document_metadata":{"repo":"repoA","path":"note.md"},"tags":[]}],"total":1,"limit":500,"offset":0}"#
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        vm.historicalCost = { bank, ids in
            bank == testBank && ids == ["doc:repoA:note.md"] ? FileCoverageViewModel.Cost(calls: 4, tokens: TokenCount(input: 9_000), dollars: 0.02, unpriced: 0, documentsRead: 1) : nil
        }
        await vm.addRoots([repo])
        await vm.select(vm.library[0].id)
        XCTAssertEqual(vm.cost.value?.calls, 4, "le serveur n'a plus de traces : l'historique local prend le relais")
        XCTAssertEqual(vm.focusedItem?.title, "note.md")
    }
}
