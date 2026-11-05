import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

// Passe qualité : régressions des bugs relevés en relecture.

@MainActor
final class ClaudeCodeCommandTests: XCTestCase {
    func testSessionSourceNeedsNoFileRead() async {
        let claude = CodexSessionSummary(file: CodexFile(url: URL(fileURLWithPath: "/Users/x/.claude/projects/p/s.jsonl")))
        XCTAssertEqual(claude.source, .claudeCode)
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
