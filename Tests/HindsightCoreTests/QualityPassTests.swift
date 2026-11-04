import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

// Passe qualité : régressions des bugs relevés en relecture.

@MainActor
final class HermesReadingTests: XCTestCase {
    static let structured = "\u{0}json:" + #"[{"type":"text","text":"Regarde ça"},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgo="}}]"#

    func testHexColumnsAreDecoded() async {
        let hex = Data(Self.structured.utf8).map { String(format: "%02X", $0) }.joined()
        XCTAssertEqual(HermesReader.unhex(hex), Self.structured)
        XCTAssertNil(HermesReader.unhex("ABC"), "longueur impaire")
        XCTAssertEqual(HermesReader.text(["content_hex": .string(hex)], "content"), Self.structured)
        XCTAssertEqual(HermesReader.text(["content": "brut"], "content"), "brut", "lignes de test sans hexadécimal")

        let rows: [[String: JSONValue]] = [
            ["id": 1, "role": "user", "content_hex": .string(hex), "timestamp": 1_790_000_001],
            ["id": 2, "role": "assistant", "content_hex": .string("4F4B"), "timestamp": 1_790_000_002],
        ]
        let conv = HermesReader.conversation(session: ["id": "s1", "source": "cli"], messages: rows)
        let users = conv.events.compactMap { e -> [CodexBlock]? in if case .user(_, _, let b) = e { return b } else { return nil } }
        XCTAssertEqual(users.first?.count, 2, "texte + image du contenu structuré")
        XCTAssertTrue(conv.events.contains { if case .assistant(_, _, "OK", _) = $0 { return true } else { return false } })
    }

    func testTruncatedStructuredPreviewKeepsText() async {
        let truncated = String(Self.structured.prefix(60))
        XCTAssertEqual(HermesReader.textFragments(truncated), "Regarde ça")
        let row: [String: JSONValue] = ["id": "s1", "source": "cli", "first_user_hex": .string(Data(truncated.utf8).map { String(format: "%02x", $0) }.joined())]
        XCTAssertEqual(HermesReader.summary(row, db: URL(fileURLWithPath: "/tmp/state.db"), modified: Date()).firstUserText, "Regarde ça")
    }

    func testDatabaseIsOpenedImmutableWhenNoJournalExists() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("état 1.db")
        try Data().write(to: db)
        let arg = HermesReader.databaseArgument(db)
        XCTAssertTrue(arg.hasPrefix("file:") && arg.hasSuffix("?immutable=1&mode=ro"), arg)
        XCTAssertEqual(URLComponents(string: arg)?.path, db.path, "le chemin décodé est conservé, en Unicode composé ou décomposé")
        XCTAssertTrue(arg.contains("%20") && !arg.contains(" "), "espaces encodés : \(arg)")
        try Data().write(to: URL(fileURLWithPath: db.path + "-wal"))
        XCTAssertEqual(HermesReader.databaseArgument(db), db.path, "journal présent : ouverture classique, rien n'est créé")
    }

    /// Bout en bout avec le vrai sqlite3 : un contenu préfixé d'un octet nul doit arriver entier.
    func testStructuredContentSurvivesSqlite3() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: HermesReader.sqlite3), "sqlite3 absent")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("state.db")
        let hex = Data(Self.structured.utf8).map { String(format: "%02X", $0) }.joined()
        let sql = """
            CREATE TABLE sessions (id TEXT, source TEXT, title TEXT, started_at REAL);
            CREATE TABLE messages (id INTEGER, session_id TEXT, role TEXT, content TEXT, timestamp REAL, active INTEGER, compacted INTEGER);
            INSERT INTO sessions VALUES ('s1', 'cli', 'Essai', 1790000000);
            INSERT INTO messages VALUES (1, 's1', 'user', CAST(X'\(hex)' AS TEXT), 1790000001, 1, 0);
            INSERT INTO messages VALUES (2, 's1', 'assistant', 'Vu.', 1790000002, 1, 0);
            """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: HermesReader.sqlite3)
        p.arguments = [db.path, sql]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)

        let summaries = HermesReader.summaries(database: db)
        XCTAssertEqual(summaries.first?.firstUserText, "Regarde ça")
        let conv = try HermesReader.parse(CodexFile(database: db, session: "s1", modified: Date()))
        let users = conv.events.compactMap { e -> [CodexBlock]? in if case .user(_, _, let b) = e { return b } else { return nil } }
        XCTAssertEqual(users.first?.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path + "-wal"), "aucun fichier créé à côté de la base")
    }
}

@MainActor
final class ClaudeCodeCommandTests: XCTestCase {
    func testSessionSourceNeedsNoFileRead() async {
        let claude = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.claude/projects/p/s.jsonl")))
        XCTAssertEqual(claude.source, .claudeCode)
        let hermes = CodexSessionSummary(file: CodexFile(database: URL(fileURLWithPath: "/tmp/state.db"), session: "s", modified: Date()))
        XCTAssertEqual(hermes.source, .hermes)
        XCTAssertEqual(CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.codex/sessions/s.jsonl"))).source, .codex)
    }
}

@MainActor
final class QualityUsageTests: XCTestCase {
    func testOpus4PricePatternsMatchRealModelIDs() async {
        let b = PriceBook.defaults
        XCTAssertEqual(b.price(for: "claude-opus-4-20250514")?.input, 15)
        XCTAssertEqual(b.price(for: "claude-opus-4-1-20250805")?.input, 15)
        XCTAssertEqual(b.price(for: "claude-opus-4-5-20251101")?.input, 5)
    }

    func testUsageRecordDecodesOlderLedgerAndFiltersByTimestamp() async throws {
        let old = #"{"id":"a","bank":"b","day":"2026-10-19","operation":"retain","provider":"openai","model":"gpt-5","input":1,"output":1,"cached":0,"thoughts":0,"failed":false}"#
        let r = try JSONDecoder().decode(UsageRecord.self, from: Data(old.utf8))
        XCTAssertEqual(r.startedAt, "")
        XCTAssertTrue(r.isAfter(HSDate.parse("2026-10-19T00:00:00Z")!), "sans horodatage : au jour près")

        var e = LLMRequestEntry(id: "x", status: "success", llmInfo: [:], metadata: [:])
        e.startedAt = "2026-10-19T23:30:00Z"
        let rec = UsageRecord(e, bank: "b")
        XCTAssertEqual(rec.day, "2026-10-19")
        XCTAssertTrue(rec.isAfter(HSDate.parse("2026-10-19T12:00:00Z")!))
        XCTAssertFalse(rec.isAfter(HSDate.parse("2026-10-19T23:45:00Z")!), "« 24 h » compare les horodatages, pas les jours")
        let again = try JSONDecoder().decode(UsageRecord.self, from: JSONEncoder().encode(rec))
        XCTAssertEqual(again, rec)
    }

    func testUsageScreenExplainsDisabledTraces() async {
        let vm = UsageViewModel(
            client: makeClient(MockTransport()), bank: testBank, services: nil,
            features: FeaturesInfo(observations: true, mcp: false, worker: true, bankConfigApi: true, bankLlmHealth: true, fileUploadApi: true, documentExportApi: true, documentImportApi: true, auditLog: true, llmTrace: false, storeDocumentText: true))
        await vm.reload()
        if case .failed(let m) = vm.state { XCTAssertTrue(m.contains(AuditViewModel.llmTraceEnvVar)) } else { XCTFail("explication attendue") }
    }
}

@MainActor
final class ReadClassificationTests: XCTestCase {
    func testWriteMarkersMatchWholeWords() async {
        XCTAssertTrue(ReadLog.isRead("recall"))
        XCTAssertTrue(ReadLog.isRead("get_settings"), "« set » n'est pas un mot de l'action")
        XCTAssertTrue(ReadLog.isRead("list_documents"))
        XCTAssertFalse(ReadLog.isRead("retain"))
        XCTAssertFalse(ReadLog.isRead("set_bank_config"))
        XCTAssertFalse(ReadLog.isRead("consolidation_run"))
        XCTAssertFalse(ReadLog.isRead("documents.delete"))
    }
}

@MainActor
final class MemoryDesignContractTests: XCTestCase {
    /// Toute clé envoyée par l'écran « Structure » doit exister dans le contrat de configuration de banque.
    func testEveryConfigKeyExistsInSpec() async throws {
        let spec = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/openapi.json")
        let doc = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: spec))
        guard case .object(let props)? = doc["components"]?["schemas"]?["BankTemplateConfig"]?["properties"] else {
            return XCTFail("schéma BankTemplateConfig introuvable")
        }
        let keys = try XCTUnwrap(MemoryDesign().values()).keys
        for k in keys { XCTAssertNotNil(props[k], "clé inconnue du contrat : \(k)") }
    }

    func testExistingUppercaseLabelKeysDoNotBlockSaving() async {
        var d = MemoryDesign()
        d.entityLabels = [EntityLabelGroup(key: "Kind", type: "text", tag: true), EntityLabelGroup(key: "fact-type", type: "text", tag: true)]
        XCTAssertTrue(d.problems.isEmpty, d.problems.joined(separator: " | "))
        d.entityLabels.append(EntityLabelGroup(key: "deux mots", type: "text", tag: true))
        XCTAssertEqual(d.problems.count, 1)
    }
}

@MainActor
final class MergeSafetyTests: XCTestCase {
    func banks() -> [BankListItem] {
        try! JSONDecoder().decode(BankListResponse.self, from: Data(Fixture.string("banks").utf8)).banks
    }

    func make(_ t: MockTransport) -> BankManagementViewModel {
        let client = makeClient(t)
        let list = banks()
        let vm = BankManagementViewModel(client: { client }, banks: { list }, refreshBanks: {}, selectBank: { _ in })
        vm.pollInterval = .milliseconds(5)
        return vm
    }

    func prepare(_ t: MockTransport, importResult: String) {
        t.on("POST", "/v1/default/banks/scratch/transfer/export", json: #"{"operation_id":"e1"}"#)
        t.on("GET", "/v1/default/banks/scratch/operations/e1", json: #"{"operation_id":"e1","status":"completed","result_metadata":{"storage_key":"k1"}}"#)
        t.on("GET", "/v1/default/files/download/k1") { _ in .bytes(Data("PK".utf8), contentType: "application/zip") }
        t.on("POST", "\(bankPath)/transfer/import", json: #"{"operation_id":"i1"}"#)
        t.on("GET", "\(bankPath)/operations/i1", json: importResult)
        t.on("DELETE", "/v1/default/banks/scratch", json: #"{"success":true}"#)
    }

    func testSkippedDocumentsKeepTheSource() async throws {
        let t = MockTransport()
        prepare(t, importResult: #"{"operation_id":"i1","status":"completed","result_metadata":{"documents_imported":1,"documents_skipped":2}}"#)
        let vm = make(t)
        vm.requestMerge(source: "scratch", into: testBank, conflict: .skip, after: .deleteSource)
        await vm.confirmation!.perform()
        XCTAssertFalse(t.requests.contains { $0.method == "DELETE" })
        XCTAssertTrue(vm.message?.contains("CONSERVÉE") == true, vm.message ?? "")
    }

    func testAliasFailureAfterDeleteIsReportedTruthfully() async throws {
        let t = MockTransport()
        prepare(t, importResult: #"{"operation_id":"i1","status":"completed","result_metadata":{"documents_imported":2}}"#)
        t.on("POST", "\(bankPath)/aliases", json: #"{"detail":"alias en cours de libération"}"#, status: 409)
        let vm = make(t)
        vm.requestMerge(source: "scratch", into: testBank, conflict: .skip, after: .deleteAndAlias)
        await vm.confirmation!.perform()
        XCTAssertTrue(t.requests.contains { $0.method == "DELETE" })
        XCTAssertTrue(vm.message?.contains("supprimée, mais l'alias") == true, vm.message ?? "")
    }

}

final class DownloadSafetyTests: XCTestCase {
    func testForeignDownloadHostIsRefused() async throws {
        let t = MockTransport()
        t.on("GET", "/v1/default/files/download/ok") { _ in .bytes(Data("PK".utf8), contentType: "application/zip") }
        let client = makeClient(t)
        _ = try await client.downloadFile(url: "http://127.0.0.1:8888/v1/default/files/download/ok")
        do {
            _ = try await client.downloadFile(url: "https://exemple.invalid/archive.zip")
            XCTFail("hôte étranger accepté")
        } catch HindsightError.refused(let m) {
            XCTAssertTrue(m.contains("exemple.invalid"))
        }
    }
}
