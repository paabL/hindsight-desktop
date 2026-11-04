import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

@MainActor
final class FileCoverageTests: XCTestCase {
    func file(_ path: String, repo: String = "repoA", modified: Date = Date(timeIntervalSince1970: 1_000)) -> ScannedFile {
        ScannedFile(repo: repo, path: path, url: URL(fileURLWithPath: "/tmp/\(repo)/\(path)"), size: 10, modified: modified)
    }

    func doc(_ id: String, repo: String? = "repoA", path: String?, hash: String? = nil, facts: Int = 3, updated: String = "1970-01-01T00:30:00Z")
        -> DocumentListItem
    {
        var meta: [String: JSONValue] = [:]
        if let repo { meta["repo"] = .string(repo) }
        if let path { meta["path"] = .string(path) }
        return DocumentListItem(id: id, contentHash: hash, updatedAt: updated, memoryUnitCount: facts, documentMetadata: meta)
    }

    func testRulesMatchSyncScript() async {
        XCTAssertEqual(FileCoverage.documentID(repo: "NOMAD-RC5-minimal", path: "docs/validity.md"), "doc:NOMAD-RC5-minimal:docs/validity.md")
        XCTAssertEqual(FileCoverage.strategy(for: "docs/campaigns.md"), "campaign")
        XCTAssertEqual(FileCoverage.strategy(for: "rapports/20261018-bilan/rapport.html"), "report")
        XCTAssertEqual(FileCoverage.strategy(for: "board/project.md"), "board")
        XCTAssertEqual(FileCoverage.strategy(for: "papers/ppo.PDF"), "paper")
        XCTAssertEqual(FileCoverage.tags(repo: "r", path: "README.md"), ["source:doc", "repo:r"])
        XCTAssertTrue(FileCoverage.isDocument("a/b.docx"))
        XCTAssertFalse(FileCoverage.isDocument("NOMAD/env.py"))
    }

    func testStatusesOrphansAndUnfiled() async {
        let files = [
            file("README.md"), file("docs/old.md"), file("docs/empty.md"), file("new.md"),
            file("paper.pdf", modified: Date(timeIntervalSince1970: 5_000)), file("report.pdf"),
            file("docs/campaigns.md", modified: Date(timeIntervalSince1970: 1_000)),
        ]
        let docs = [
            doc("doc:repoA:README.md", path: "README.md", hash: "h-readme"),
            doc("doc:repoA:docs/old.md", path: "docs/old.md", hash: "stale"),
            doc("doc:repoA:docs/empty.md", path: "docs/empty.md", hash: "h-empty", facts: 0),
            doc("paper:repoA:paper.pdf", path: "paper.pdf"),
            doc("paper:repoA:report.pdf", path: "report.pdf"),
            doc("campaign:repoA:a", path: "docs/campaigns.md"), doc("campaign:repoA:b", path: "docs/campaigns.md"),
            doc("doc:repoA:gone.md", path: "gone.md"),
            doc("doc:other:x.md", repo: "other", path: "x.md"),
            doc("codex-1-task-001", repo: nil, path: nil),
        ]
        let hashes = ["README.md": "h-readme", "docs/old.md": "fresh", "docs/empty.md": "h-empty"]
        let r = FileCoverage.report(files: files, documents: docs) { hashes[$0.path] }
        let status = Dictionary(uniqueKeysWithValues: r.entries.map { ($0.file.path, $0.status) })
        XCTAssertEqual(status["README.md"], .current)
        XCTAssertEqual(status["docs/old.md"], .modified, "empreinte différente de celle envoyée")
        XCTAssertEqual(status["docs/empty.md"], .noFacts)
        XCTAssertEqual(status["new.md"], .missing)
        XCTAssertEqual(status["paper.pdf"], .modified, "binaire modifié après l'envoi")
        XCTAssertEqual(status["report.pdf"], .current)
        XCTAssertEqual(status["docs/campaigns.md"], .current)
        let campaigns = r.entries.first { $0.file.path == "docs/campaigns.md" }!
        XCTAssertTrue(campaigns.isSplit)
        XCTAssertFalse(campaigns.canSend, "sync.py envoie le journal entrée par entrée")
        XCTAssertEqual(r.orphans.map(\.id), ["doc:repoA:gone.md"], "seuls les dépôts analysés ont des orphelins")
        XCTAssertEqual(r.unfiled, 1)
        XCTAssertEqual(r.count(.missing), 1)
    }

    func testHTMLLosesEmbeddedImagesOnly() async {
        let html = #"<p>Texte</p><img src="data:image/png;base64,iVBORw0KGgo=AAAA"><a href="figure.png">f</a>"#
        XCTAssertEqual(FileCoverage.strippingDataURIs(html), #"<p>Texte</p><img src=""><a href="figure.png">f</a>"#)
        let u = FileCoverage.upload(file("rapports/r/rapport.html"), data: Data(html.utf8))
        XCTAssertFalse(String(decoding: u.file.data, as: UTF8.self).contains("base64"))
        XCTAssertEqual(u.metadata.documentId, "report:repoA:rapports/r/rapport.html")
        XCTAssertEqual(u.metadata.metadata, ["repo": "repoA", "path": "rapports/r/rapport.html"])
        XCTAssertEqual(u.file.mimeType, "text/html")
    }

    func testFileBatchesRespectServerLimits() async {
        let f = { (n: Int) in (file: UploadFile(filename: "f", mimeType: "application/pdf", data: Data(count: n)), metadata: FileRetainMetadata()) }
        let batches = FileCoverageViewModel.fileBatches([f(4), f(4), f(4), f(20), f(1)], limit: 2, bytes: 10)
        XCTAssertEqual(batches.map(\.count), [2, 1, 1, 1])
    }

    /// Dossier `repoA` (README en mémoire, une note, un PDF, un script) et faux serveur.
    func fixture() throws -> (repo: URL, transport: MockTransport) {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID().uuidString)").appendingPathComponent("repoA")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("docs"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let readme = Data("# Titre\n".utf8)
        try readme.write(to: repo.appendingPathComponent("README.md"))
        try Data("brouillon\n".utf8).write(to: repo.appendingPathComponent("docs/notes.md"))
        try Data("%PDF-1.4".utf8).write(to: repo.appendingPathComponent("docs/article.pdf"))
        try Data("print(1)".utf8).write(to: repo.appendingPathComponent("script.py"))
        let t = MockTransport()
        let docs = #"{"items":[{"id":"doc:repoA:README.md","bank_id":"b","content_hash":"\#(SHA256.hex(readme))","created_at":"","updated_at":"2026-10-20T10:00:00Z","text_length":8,"memory_unit_count":2,"document_metadata":{"repo":"repoA","path":"README.md"},"tags":[]}],"total":1,"limit":500,"offset":0}"#
        t.on("GET", "\(bankPath)/documents", json: docs)
        t.on("POST", "\(bankPath)/memories", json: #"{"success":true,"bank_id":"b","items_count":1,"async":true,"operation_id":"op1"}"#)
        t.on("POST", "\(bankPath)/files/retain", json: #"{"operation_ids":["op2"]}"#)
        t.on("DELETE", "\(bankPath)/documents/doc:repoA:README.md", json: #"{"success":true,"message":"","document_id":"doc:repoA:README.md","memory_units_deleted":2}"#)
        t.on("GET", "\(bankPath)/llm-requests", json: #"{"bank_id":"b","total":2,"limit":500,"offset":0,"items":[{"id":"1","status":"success","provider":"gemini","model":"gemini-3.8-flash","input_tokens":1000000,"output_tokens":0,"llm_info":{},"metadata":{}},{"id":"2","status":"success","provider":"claude-code","model":"claude-sonnet","input_tokens":10,"output_tokens":10,"llm_info":{},"metadata":{}}]}"#)
        return (repo, t)
    }

    func testScansFolderComparesAndSendsAfterConfirmation() async throws {
        let (repo, t) = try fixture()
        let settings = InMemorySettingsStore()
        let vm = FileCoverageViewModel(settings: settings, client: { makeClient(t) }, bank: { testBank })
        // Sans `.git`, un dossier choisi est analysé tel quel : son nom sert de dépôt.
        await vm.addRoots([repo])
        XCTAssertEqual(vm.roots, [CoverageRoot(path: repo.path)])
        XCTAssertNotNil(settings.string(forKey: "coverageRoots.\(testBank)"), "dossiers mémorisés par banque")
        let report = try XCTUnwrap(vm.state.value)
        XCTAssertEqual(report.entries.map(\.file.path), ["README.md", "docs/article.pdf", "docs/notes.md"], "le code n'est pas un document")
        XCTAssertEqual(report.entries.map(\.status), [.current, .missing, .missing])

        vm.selectVisible()
        XCTAssertEqual(vm.selection.count, 2, "un fichier à jour n'est pas envoyable")
        await vm.requestSend()
        let confirmation = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(t.requests.allSatisfy { $0.method == "GET" }, "rien n'est envoyé avant confirmation")
        XCTAssertTrue(confirmation.message.contains("fournir la source TeX ou Markdown"))
        await confirmation.perform()

        let retain = try XCTUnwrap(t.requests.first { $0.path == "\(bankPath)/memories" }?.bodyJSON)
        XCTAssertEqual(retain["items"]?[0]?["document_id"], .string("doc:repoA:docs/notes.md"))
        XCTAssertEqual(retain["items"]?[0]?["observation_scopes"], .string("shared"))
        XCTAssertEqual(retain["items"]?[0]?["metadata"]?["path"], .string("docs/notes.md"))
        XCTAssertFalse(t.requests.contains { $0.path == "\(bankPath)/files/retain" }, "aucun PDF n'est transmis")
        XCTAssertTrue(vm.selection.isEmpty)
        XCTAssertEqual(vm.actionMessage?.hasPrefix("1/1 fichier(s)"), true)
    }

    func testCommonPolicyBlocksAndIsRecheckedBeforeSend() async throws {
        let (repo, t) = try fixture()
        let url = repo.appendingPathComponent("memory-policy.json")
        func writePolicy(excluded: [String: Any] = [:], deferred: [String: Any] = [:]) throws {
            try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": testBank, "excluded_document_ids": excluded, "deferred_document_ids": deferred]).write(to: url)
        }
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        vm.memoryPolicyURL = { url }
        await vm.addRoots([repo])
        vm.selectVisible()
        try writePolicy(excluded: ["doc:repoA:docs/notes.md": [:]])
        await vm.requestSend()
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(vm.actionMessage?.contains("archivée ou en attente") == true)
        let source = ["source": ["repo": "repoA", "path": "docs/notes.md"]]
        try writePolicy(excluded: ["historical-id-without-bank-document": source])
        await vm.requestSend()
        XCTAssertNil(vm.confirmation, "le chemin bloque aussi une ancienne identité absente de la banque")
        try writePolicy()
        await vm.requestSend()
        let confirmation = try XCTUnwrap(vm.confirmation)
        try writePolicy(deferred: ["historical-id-without-bank-document": source])
        await confirmation.perform()
        XCTAssertTrue(t.requests.allSatisfy { $0.method == "GET" }, "une modification de la politique bloque aussi la confirmation déjà ouverte")
        try Data("invalide".utf8).write(to: url)
        await vm.requestSend()
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(vm.actionMessage?.contains("inaccessible") == true)
        vm.memoryPolicyURL = { nil }
        await vm.requestSend()
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(vm.actionMessage?.contains("Choisissez le dossier mémoire") == true)
    }

    func testAllFilesOptionAndAutomaticSyncBlocked() async throws {
        let (repo, t) = try fixture()
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        await vm.addRoots([repo])
        await vm.setAllFiles(true, for: vm.roots[0])
        XCTAssertTrue(vm.state.value!.entries.contains { $0.file.path == "script.py" && $0.status == .missing })
        vm.requestAutoSync(true, for: vm.roots[0])
        XCTAssertFalse(vm.roots[0].autoSync)
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(vm.actionMessage?.contains("validez chaque envoi") == true)
        await vm.autoSyncOnce()
        XCTAssertFalse(t.requests.contains { $0.method == "POST" })
    }

    func testRealCostAndRemovalNeedConfirmation() async throws {
        let (repo, t) = try fixture()
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        vm.priceBook = { .defaults }
        await vm.addRoots([repo])
        let readme = vm.state.value!.entries.first { $0.file.path == "README.md" }!
        await vm.select(readme.id)
        let cost = try XCTUnwrap(vm.cost.value)
        XCTAssertEqual(cost.calls, 2)
        XCTAssertEqual(cost.dollars, 0.3, accuracy: 1e-9, "1 M de jetons d'entrée Gemini Flash au tarif par défaut")
        XCTAssertEqual(cost.unpriced, 1, "l'abonnement n'est pas compté en dollars")
        XCTAssertEqual(t.requests.last { $0.path.hasSuffix("/llm-requests") }?.queryValue("document_id"), "doc:repoA:README.md")

        vm.toggle(readme.id)
        vm.requestRemoveSelection()
        XCTAssertFalse(t.requests.contains { $0.method == "DELETE" })
        await vm.confirmation!.perform()
        XCTAssertTrue(t.requests.contains { $0.method == "DELETE" && $0.path.hasSuffix("README.md") })
    }

    func testConversationsMatchedBySessionNotByPath() async {
        var codex = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.codex/sessions/s1.jsonl")))
        codex.meta = CodexSessionMeta(id: "s1")
        codex.meta?.cwd = "/w/NOMAD-RC5-minimal"
        codex.firstUserText = "Optimise le MPC"
        var claude = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.claude/projects/p/s2.jsonl")))
        claude.meta = CodexSessionMeta(id: "s2")
        var auto = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.codex/sessions/s3.jsonl")))
        auto.meta = CodexSessionMeta(id: "s3")
        auto.meta?.threadSource = "subagent"
        let docs = [
            doc("codex-s1-task-001", repo: nil, path: nil), doc("codex-s1-task-002", repo: nil, path: nil, facts: 4),
            DocumentListItem(id: "conversation-x", memoryUnitCount: 1, documentMetadata: ["session_id": .string("s2")]),
            doc("codex-zz-task-001", repo: nil, path: nil),
        ]
        XCTAssertEqual(FileCoverage.sessionID(docs[0]), "s1")
        let r = FileCoverage.report(files: [], sessions: [codex, claude, auto], documents: docs) { _ in nil }
        XCTAssertEqual(r.entries.count, 2, "les sous-agents et revues automatiques sont ignorés")
        let c = r.entries.first { $0.session?.meta?.id == "s1" }!
        XCTAssertEqual(c.documents.count, 2)
        XCTAssertEqual(c.facts, 7)
        XCTAssertEqual(c.file.repo, "Conversations Codex")
        XCTAssertTrue(c.file.path.hasPrefix("NOMAD-RC5-minimal · Optimise le MPC"))
        XCTAssertFalse(c.canSend, "une conversation s'envoie par « Importer »")
        XCTAssertEqual(r.entries.first { $0.session?.meta?.id == "s2" }?.documents.map(\.id), ["conversation-x"])
        XCTAssertEqual(r.unfiled, 1, "session inconnue : document sans source analysée")
    }
}
