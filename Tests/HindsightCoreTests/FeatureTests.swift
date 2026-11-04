import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

// MARK: - Structure de la mémoire

@MainActor
final class MemoryDesignTests: XCTestCase {
    static let config = #"""
        {"bank_id":"b","config":{
          "retain_mission":"Retenir les décisions","retain_extraction_mode":"concise","retain_chunk_size":3000,
          "entity_labels":[{"key":"kind","description":"Nature","type":"value","optional":true,"tag":true,
             "values":[{"value":"decision","description":"Choix"},{"value":"bug","description":""}],"fields":{}}],
          "entities_allow_free_form":true,"enable_observations":true,"observations_mission":null,
          "disposition_skepticism":4,"disposition_literalism":3,"disposition_empathy":3,
          "consolidation_strategies":null,"audit_log_enabled":false},
         "overrides":{"retain_mission":"Retenir les décisions","disposition_skepticism":4}}
        """#

    func make(_ t: MockTransport) -> MemoryDesignViewModel {
        t.on("GET", "\(bankPath)/config", json: Self.config)
        t.on("PATCH", "\(bankPath)/config", json: Self.config)
        return MemoryDesignViewModel(client: makeClient(t), bank: testBank, estimator: nil)
    }

    func testLoadsResolvedConfigAndOverrides() async {
        let vm = make(MockTransport())
        await vm.reload()
        XCTAssertEqual(vm.draft.retainMission, "Retenir les décisions")
        XCTAssertEqual(vm.draft.skepticism, 4)
        XCTAssertEqual(vm.draft.entityLabels.first?.key, "kind")
        XCTAssertEqual(vm.draft.entityLabels.first?.valuesText, "decision — Choix\nbug")
        XCTAssertTrue(vm.isOverridden("retain_mission"))
        XCTAssertFalse(vm.isOverridden("retain_extraction_mode"))
        XCTAssertFalse(vm.hasChanges, "relire la configuration ne crée aucun changement")
    }

    func testSavesOnlyChangesAfterConfirmation() async throws {
        let t = MockTransport()
        let vm = make(t)
        await vm.reload()
        vm.draft.extractionMode = "custom"
        vm.draft.customInstructions = "Extraire seulement les décisions."
        vm.draft.observationsMission = "Une synthèse par projet."
        vm.draft.entityLabels[0].valuesText = "decision — Choix\nbug — Problème\npreference"
        XCTAssertEqual(Set(vm.changes.keys), ["retain_extraction_mode", "retain_custom_instructions", "observations_mission", "entity_labels"])
        vm.requestSave()
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(c.message.contains("PROCHAINES"))
        XCTAssertFalse(t.requests.contains { $0.method == "PATCH" })
        await c.perform()
        let body = try XCTUnwrap(t.requests.first { $0.method == "PATCH" }?.bodyJSON?["updates"])
        XCTAssertEqual(body["retain_extraction_mode"], "custom")
        XCTAssertNil(body["retain_mission"], "champ inchangé non envoyé")
        guard case .array(let groups)? = body["entity_labels"], case .array(let values)? = groups.first?["values"] else {
            return XCTFail("entity_labels attendu")
        }
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(groups.first?["fields"], .object([:]), "les champs non édités sont conservés")
    }

    func testProblemsBlockSave() async {
        let vm = make(MockTransport())
        await vm.reload()
        vm.draft.extractionMode = "custom"
        vm.draft.consolidationStrategies = "{pas du json"
        vm.draft.entityLabels.append(EntityLabelGroup(key: "Kind!", type: "value"))
        XCTAssertTrue(vm.problems.contains { $0.contains("custom") })
        XCTAssertTrue(vm.problems.contains { $0.contains("JSON") })
        XCTAssertTrue(vm.problems.contains { $0.contains("Kind!") })
        vm.requestSave()
        XCTAssertNil(vm.confirmation)
        XCTAssertNotNil(vm.actionMessage)
    }

    func testEmptyingAMissionResetsItToServerValue() async throws {
        let vm = make(MockTransport())
        await vm.reload()
        vm.draft.retainMission = "   "
        XCTAssertEqual(vm.changes["retain_mission"], .null)
    }

    func testTrialUsesUnsavedDraft() async throws {
        let t = MockTransport()
        let vm = make(t)
        t.on("POST", "\(bankPath)/memories/dry-run-extract", json: #"{"facts":[{"text":"On garde SQLite.","fact_type":"world"}],"usage":{"input_tokens":2000,"output_tokens":300,"total_tokens":2300,"cached_tokens":0,"thoughts_tokens":0}}"#)
        await vm.reload()
        vm.apply(MemoryDesignPreset.all[0])
        vm.sampleText = "Nous avons décidé de garder SQLite."
        vm.requestTrial()
        await vm.confirmation!.perform()
        let body = try XCTUnwrap(t.requests.first { $0.path.hasSuffix("dry-run-extract") }?.bodyJSON)
        XCTAssertTrue(body["retain_mission"]?.stringValue?.contains("prochaines sessions") == true)
        XCTAssertEqual(body["content"], "Nous avons décidé de garder SQLite.")
        XCTAssertEqual(vm.trial.value?.facts?.count, 1)
        XCTAssertFalse(t.requests.contains { $0.method == "PATCH" }, "l'essai n'enregistre rien")
    }
}

// MARK: - Lectures et appelants

@MainActor
final class ReadsTests: XCTestCase {
    static let log = #"""
        {"bank_id":"b","total":4,"limit":500,"offset":0,"items":[
         {"id":"a1","action":"recall","transport":"http","bank_id":"b","started_at":"2026-10-19T15:35:00Z","ended_at":"2026-10-19T15:35:01Z","duration_ms":800,
          "request":{"query":"base de données","budget":"mid","max_tokens":4096,"types":null,"tags":[],"trace":false},
          "response":{"results":[{"id":"m1","text":"On garde SQLite.","type":"world"},{"id":"m2","text":"Postgres en prod.","type":"world"}]},"metadata":{}},
         {"id":"a2","action":"recall","transport":"http","bank_id":"b","started_at":"2026-10-19T15:36:00Z","ended_at":null,
          "request":{"query":"autre question","budget":"mid","max_tokens":4096,"types":null,"tags":[],"trace":false},
          "response":{"results":[{"id":"m1","text":"On garde SQLite.","type":"world"}]},"metadata":{}},
         {"id":"a3","action":"reflect","transport":"mcp","bank_id":"b","started_at":"2026-10-19T15:40:00Z","ended_at":null,
          "request":{"query":"Résume"},"response":null,"metadata":{"client_name":"codex-cli"}},
         {"id":"a4","action":"retain","transport":"http","bank_id":"b","started_at":"2026-10-19T15:41:00Z","ended_at":null,"request":null,"response":null,"metadata":{}}
        ]}
        """#

    func entries() -> [AuditLogEntry] {
        try! JSONDecoder().decode(AuditLogPage.self, from: Data(Self.log.utf8)).items
    }

    func testClassifiesReadsAndExtractsReturnedFacts() async {
        XCTAssertTrue(ReadLog.isRead("recall"))
        XCTAssertTrue(ReadLog.isRead("list_memories"))
        XCTAssertFalse(ReadLog.isRead("retain"))
        XCTAssertFalse(ReadLog.isRead("delete_document"))
        let e = ReadLog.event(entries()[0])
        XCTAssertEqual(e.query, "base de données")
        XCTAssertEqual(e.items.map(\.id), ["m1", "m2"])
        XCTAssertTrue(e.parameters.contains("budget mid"))
        XCTAssertNotNil(e.replayableRecall)
        let reads = entries().filter { ReadLog.isRead($0.action) }.map { ReadLog.event($0) }
        XCTAssertEqual(ReadLog.mostRead(reads).first?.item.id, "m1")
        XCTAssertEqual(ReadLog.mostRead(reads).first?.count, 2)
    }

    func testUnidentifiedHTTPClientsAreGroupedBySignatureAndCanBeNamed() async {
        let es = entries()
        let s1 = AccessSummary.signature(of: es[0]), s2 = AccessSummary.signature(of: es[1])
        XCTAssertNotNil(s1)
        XCTAssertEqual(s1, s2, "même client, autre question : même signature")
        XCTAssertNil(AccessSummary.signature(of: es[2]), "client MCP identifié")
        XCTAssertEqual(AccessSummary.actor(of: es[2]), "mcp · codex-cli")
        XCTAssertTrue(AccessSummary.actor(of: es[0]).contains("profil \(s1!)"))
        XCTAssertEqual(AccessSummary.actor(of: es[0], names: [s1!: "Plugin Codex"]), "http · Plugin Codex")
        var other = es[0]
        other.request?["budget"] = "high"
        XCTAssertNotEqual(AccessSummary.signature(of: other), s1, "autres réglages : autre client")
        let rows = AccessSummary.compute(es)
        XCTAssertEqual(rows.first { $0.signature == s1 }?.count, 2)
        XCTAssertTrue(rows.first { $0.signature == s1 }?.signatureDescription?.contains("budget") == true)
    }

    func testReadsViewModelReplaysRecallAndNamesCaller() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/audit-logs", json: Self.log)
        t.on("POST", "\(bankPath)/memories/recall", json: Fixture.string("recall"))
        let vm = ReadsViewModel(client: makeClient(t), bank: testBank)
        let store = InMemorySettingsStore()
        vm.callers = CallerDirectory(settings: store)
        await vm.reload()
        XCTAssertEqual(vm.events.count, 3, "l'écriture retain est exclue")
        XCTAssertTrue(vm.responsesAreLogged)
        let first = try XCTUnwrap(vm.events.first { $0.id == "a1" })
        vm.select(first)
        await vm.replaySelected()
        let body = try XCTUnwrap(t.requests.first { $0.path.hasSuffix("/recall") }?.bodyJSON)
        XCTAssertEqual(body["query"], "base de données")
        XCTAssertEqual(body["budget"], "mid")
        XCTAssertNotNil(vm.replay.value)

        vm.nameCaller(try XCTUnwrap(first.signature), "Plugin Codex")
        XCTAssertEqual(vm.events.first { $0.id == "a1" }?.who, "http · Plugin Codex")
        XCTAssertEqual(vm.readers.sorted(), ["http · Plugin Codex", "mcp · codex-cli"])
        XCTAssertEqual(CallerDirectory(settings: store).names[first.signature!], "Plugin Codex", "nom conservé")
        vm.whoFilter = "mcp · codex-cli"
        XCTAssertEqual(vm.events.map(\.id), ["a3"])
    }
}

// MARK: - Renommer et fusionner

@MainActor
final class BankManagementTests: XCTestCase {
    func banks() -> [BankListItem] {
        try! JSONDecoder().decode(BankListResponse.self, from: Data(Fixture.string("banks").utf8)).banks
    }

    func make(_ t: MockTransport, selected: Box<String?> = Box(nil)) -> BankManagementViewModel {
        let client = makeClient(t)
        let list = banks()
        let vm = BankManagementViewModel(client: { client }, banks: { list }, refreshBanks: {}, selectBank: { selected.value = $0 })
        vm.pollInterval = .milliseconds(5)
        return vm
    }

    func testRenameAndAlias() async throws {
        let t = MockTransport()
        t.on("PATCH", bankPath, json: #"{"bank_id":"b","name":"Mémoire Codex","disposition":{"skepticism":3,"literalism":3,"empathy":3},"mission":"","background":""}"#)
        t.on("GET", "\(bankPath)/aliases", json: #"{"bank_id":"b","aliases":[]}"#)
        t.on("POST", "\(bankPath)/aliases", json: #"{"bank_id":"b","aliases":[{"alias":"codex","primary":true}]}"#)
        let vm = make(t)
        vm.requestRename(testBank, name: "Mémoire Codex")
        await vm.confirmation!.perform()
        XCTAssertEqual(t.requests.first { $0.method == "PATCH" }?.bodyJSON?["name"], "Mémoire Codex")

        vm.confirmation = nil  // l'interface la referme après usage
        vm.requestShowAlias(testBank, alias: "scratch")
        XCTAssertNil(vm.confirmation, "nom déjà pris par une banque")
        vm.requestShowAlias(testBank, alias: "codex")
        await vm.confirmation!.perform()
        let post = try XCTUnwrap(t.requests.first { $0.method == "POST" && $0.path.hasSuffix("/aliases") }?.bodyJSON)
        XCTAssertEqual(post["alias"], "codex")
        XCTAssertEqual(post["primary"], true)
    }

    func testChangeIDClonesDeletesAndAliases() async throws {
        let t = MockTransport()
        t.on("POST", "\(bankPath)/clone", json: #"{"operation_id":"c1"}"#)
        t.on("GET", "\(bankPath)/operations/c1", json: #"{"operation_id":"c1","status":"completed"}"#)
        t.on("DELETE", bankPath, json: #"{"success":true}"#)
        t.on("POST", "/v1/default/banks/codex-memoire/aliases", json: #"{"bank_id":"codex-memoire","aliases":[]}"#)
        let selected = Box<String?>(nil)
        let vm = make(t, selected: selected)
        vm.requestChangeID(testBank, to: "codex-memoire")
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertEqual(c.requiredText, testBank)
        await c.perform()
        let order = t.requests.map { "\($0.method) \($0.path)" }
        let clone = order.firstIndex { $0.hasSuffix("/clone") }!, del = order.firstIndex { $0 == "DELETE \(bankPath)" }!
        let alias = order.firstIndex { $0.hasSuffix("codex-memoire/aliases") }!
        XCTAssertTrue(clone < del && del < alias, "clone, puis suppression, puis alias")
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/clone") }?.queryValue("include_history"), "true")
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("codex-memoire/aliases") }?.bodyJSON?["alias"]?.stringValue, testBank)
        XCTAssertEqual(selected.value, "codex-memoire")
    }

    func testMergeExportsImportsThenOptionallyDeletesSource() async throws {
        let t = MockTransport()
        t.on("POST", "/v1/default/banks/scratch/transfer/export", json: #"{"operation_id":"e1"}"#)
        t.on("GET", "/v1/default/banks/scratch/operations/e1", json: #"{"operation_id":"e1","status":"completed","result_metadata":{"download_url":"/v1/default/files/download/x.zip","filename":"scratch.zip"}}"#)
        t.on("GET", "/v1/default/files/download/x.zip") { _ in .bytes(Data("PK".utf8), contentType: "application/zip") }
        t.on("POST", "\(bankPath)/transfer/import", json: #"{"operation_id":"i1"}"#)
        t.on("GET", "\(bankPath)/operations/i1", json: #"{"operation_id":"i1","status":"completed","result_metadata":{"documents_imported":3,"documents_skipped":1}}"#)
        t.on("DELETE", "/v1/default/banks/scratch", json: #"{"success":true}"#)
        t.on("POST", "\(bankPath)/aliases", json: #"{"bank_id":"b","aliases":[]}"#)
        let vm = make(t)
        vm.requestMerge(source: testBank, into: testBank)
        XCTAssertNil(vm.confirmation)
        vm.requestMerge(source: "scratch", into: testBank, conflict: .newID, after: .deleteAndAlias)
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertEqual(c.requiredText, "scratch", "suppression de la source : saisie exigée")
        XCTAssertTrue(c.message.contains("Sans appel LLM"))
        await c.perform()
        let export = try XCTUnwrap(t.requests.first { $0.path.hasSuffix("scratch/transfer/export") })
        XCTAssertEqual(export.queryValue("include_bank_config"), "false")
        let imp = try XCTUnwrap(t.requests.first { $0.path.hasSuffix("/transfer/import") })
        XCTAssertEqual(imp.queryValue("mode"), "merge")
        XCTAssertEqual(imp.queryValue("document_conflict"), "new-id")
        XCTAssertTrue(t.requests.contains { $0.method == "DELETE" && $0.path == "/v1/default/banks/scratch" })
        XCTAssertEqual(t.requests.first { $0.method == "POST" && $0.path.hasSuffix("\(testBank)/aliases") }?.bodyJSON?["alias"], "scratch")
        XCTAssertTrue(vm.message?.contains("documents_imported 3") == true)
    }

    func testFailedImportNeverDeletesSource() async throws {
        let t = MockTransport()
        t.on("POST", "/v1/default/banks/scratch/transfer/export", json: #"{"operation_id":"e1"}"#)
        t.on("GET", "/v1/default/banks/scratch/operations/e1", json: #"{"operation_id":"e1","status":"completed","result_metadata":{"storage_key":"k1"}}"#)
        t.on("GET", "/v1/default/files/download/k1") { _ in .bytes(Data("PK".utf8), contentType: "application/zip") }
        t.on("POST", "\(bankPath)/transfer/import", json: #"{"operation_id":"i1"}"#)
        t.on("GET", "\(bankPath)/operations/i1", json: #"{"operation_id":"i1","status":"failed","error_message":"archive invalide"}"#)
        let vm = make(t)
        vm.requestMerge(source: "scratch", into: testBank, after: .deleteSource)
        await vm.confirmation!.perform()
        XCTAssertFalse(t.requests.contains { $0.method == "DELETE" })
        XCTAssertTrue(vm.message?.contains("archive invalide") == true)
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

// MARK: - Coûts

@MainActor
final class UsageTests: XCTestCase {
    func testPriceBookMatchingAndBilling() async {
        let b = PriceBook.defaults
        XCTAssertEqual(b.price(for: "gemini-2.5-flash-lite")?.pattern, "flash-lite")
        XCTAssertEqual(b.price(for: "gpt-5-mini-2025")?.pattern, "gpt-5-mini")
        XCTAssertEqual(b.price(for: "sonnet")?.pattern, "sonnet")
        XCTAssertNil(b.price(for: "modele-inconnu"))
        // 1 M jetons d'entrée dont 0,5 M en cache + 0,1 M de sortie sur Sonnet : 0,5×3 + 0,5×0,3 + 0,1×15 = 3,15 $
        let cost = b.apiCost(model: "claude-sonnet-4-5", tokens: TokenCount(input: 1_000_000, output: 100_000, cached: 500_000))
        XCTAssertEqual(cost ?? 0, 3.15, accuracy: 0.0001)
        if case .subscription(let p, let eq) = b.billing(provider: "claude-code", model: "sonnet", tokens: TokenCount(input: 1_000_000)) {
            XCTAssertEqual(p, "claude-code")
            XCTAssertEqual(eq ?? 0, 3, accuracy: 0.001)
        } else {
            XCTFail("abonnement attendu")
        }
        XCTAssertEqual(b.billing(provider: "ollama", model: "llama3", tokens: TokenCount(input: 10)), .local)
        XCTAssertEqual(b.billing(provider: "openai", model: "inconnu", tokens: TokenCount(input: 10)), .unknown)
    }

    func testPriceBookPersistsOnlyWhenModified() async {
        let s = InMemorySettingsStore()
        var b = PriceBook.load(from: s)
        XCTAssertEqual(b, .defaults)
        b.prices.append(ModelPrice("mon-modele", input: 1, output: 2))
        b.save(to: s)
        XCTAssertNotNil(s.string(forKey: SettingsKey.priceBook))
        XCTAssertEqual(PriceBook.load(from: s).price(for: "mon-modele-v2")?.output, 2)
        PriceBook.defaults.save(to: s)
        XCTAssertNil(s.string(forKey: SettingsKey.priceBook))
    }

    func traces() -> [LLMRequestEntry] {
        try! JSONDecoder().decode(LLMRequestListResponse.self, from: Data(Fixture.string("llm_requests").utf8)).items
    }

    func testSummaryAndLedgerDeduplicate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = UsageLedger(url: url)
        let now = HSDate.parse("2026-10-18T00:00:00Z")!
        let added = await ledger.merge(traces(), bank: "b", now: now)
        XCTAssertEqual(added, 3)
        let again = await ledger.merge(traces(), bank: "b", now: now)
        XCTAssertEqual(again, 0, "dédoublonné par identifiant")
        let reread = await UsageLedger(url: url).records(bank: "b", since: nil)
        XCTAssertEqual(reread.count, 3, "historique relu depuis le disque")
        let rows = UsageSummary.rows(reread, prices: .defaults)
        let extract = try XCTUnwrap(rows.first { $0.operation == "retain" && $0.provider == "claude-code" })
        XCTAssertEqual(extract.calls, 2)
        XCTAssertEqual(extract.failures, 1)
        XCTAssertEqual(rows.first { $0.operation == "vlm" }?.model, "gemini-2.5-flash", "la vision a sa propre ligne")
        let totals = UsageSummary.totals(rows)
        XCTAssertEqual(totals.subscriptionTokens, 1200)
        XCTAssertGreaterThan(totals.metered, 0)
        // Purge au-delà de 400 jours
        _ = await ledger.merge([], bank: "b", now: now.addingTimeInterval(500 * 86_400))
        let purged = await ledger.records(bank: nil, since: nil)
        XCTAssertTrue(purged.isEmpty)
    }

    func testEstimatorUsesObservedProfileOrDefaults() async {
        let est = CostEstimator(settings: InMemorySettingsStore(), client: { makeClient(MockTransport()) })
        let fresh = est.estimate(.retain(characters: 30_000, images: 0, consolidation: true), bank: "b")
        XCTAssertTrue(fresh.basis.contains("défaut"))
        XCTAssertEqual(fresh.parts.first { $0.operation == "retain" }?.tokens.input, 35_000, "10 morceaux × 3 500 jetons")
        XCTAssertTrue(fresh.summary.contains("jetons"))

        var many = traces().filter { $0.status == "success" && $0.scope != "vlm" }
        many += many + many  // ≥ 3 appels observés
        est.setProfile(UsageProfile.from(many), bank: "b")
        let calibrated = est.estimate(.retain(characters: 3000, images: 0, consolidation: false), bank: "b")
        XCTAssertTrue(calibrated.basis.contains("calibrée"))
        XCTAssertEqual(calibrated.parts.first?.tokens.input, 1000)
        XCTAssertTrue(calibrated.hasSubscription, "claude-code : abonnement")

        let reflect = est.estimate(.reflect(budget: "high"), bank: nil)
        XCTAssertEqual(reflect.tokens.input, 50_000)
    }
}

// MARK: - Claude Code et Hermes

final class ConversationSourcesTests: XCTestCase {
    func testHermesRowsBecomeConversation() async {
        let session: [String: JSONValue] = ["id": "20261001_abc", "source": "cli", "model": "anthropic/claude-sonnet-4.6", "title": "Refonte", "started_at": 1_790_000_000.5]
        let image = "\u{0}json:" + #"[{"type":"text","text":"Regarde ça"},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgo="}}]"#
        let rows: [[String: JSONValue]] = [
            ["id": 1, "role": "system", "content": "Tu es Hermes.", "timestamp": 1_790_000_000.6],
            ["id": 2, "role": "user", "content": .string(image), "timestamp": 1_790_000_001, "active": 0, "compacted": 1],
            ["id": 3, "role": "assistant", "content": "Je lance la recherche.", "timestamp": 1_790_000_002,
             "tool_calls": #"[{"id":"c1","type":"function","function":{"name":"web_search","arguments":"{\"q\":\"x\"}"}}]"#],
            ["id": 4, "role": "tool", "content": "3 résultats", "tool_call_id": "c1", "timestamp": 1_790_000_003],
            ["id": 5, "role": "user", "content": "Résumé de la conversation…", "timestamp": 1_790_000_004, "_compressed_summary": 1],
            ["id": 6, "role": "user", "content": .string(image), "timestamp": 1_790_000_001, "active": 1, "compacted": 0],
            ["id": 7, "role": "user", "content": "message de groupe", "timestamp": 1_790_000_005, "observed": 1],
        ]
        let conv = HermesReader.conversation(session: session, messages: rows)
        XCTAssertEqual(conv.meta.source, .hermes)
        XCTAssertEqual(conv.meta.title, "Refonte")
        XCTAssertTrue(conv.meta.isUserConversation)
        let users = conv.events.compactMap { e -> [CodexBlock]? in if case .user(_, _, let b) = e { return b } else { return nil } }
        XCTAssertEqual(users.count, 1, "doublon de compaction, résumé et message observé écartés")
        XCTAssertEqual(users[0].count, 2)
        XCTAssertTrue(conv.events.contains { if case .toolCall(_, _, "web_search", _, "c1") = $0 { return true } else { return false } })
        XCTAssertTrue(conv.events.contains { if case .toolOutput(_, _, "c1", "3 résultats") = $0 { return true } else { return false } })
        XCTAssertEqual(conv.skipped["system"], 1)
        XCTAssertEqual(CodexTranscript.tasks(conv).first?.documentID, "hermes-20261001_abc-task-001")

        let sub = HermesReader.meta(["id": "s2", "source": "subagent"])
        XCTAssertFalse(sub.isUserConversation)
        XCTAssertEqual(HermesReader.quoted("abc_1"), "'abc_1'")
        XCTAssertNil(HermesReader.quoted("x'; DROP TABLE messages; --"), "identifiant refusé dans une requête")
    }
}

// MARK: - Tableau de bord

final class DashboardAuditOverrideTests: XCTestCase {
    func testBankOverrideOfAuditSilencesInsight() async throws {
        let stats = try JSONDecoder().decode(BankStatsResponse.self, from: Data(Fixture.string("bank_stats").utf8))
        var snap = DashboardSnapshot(stats: stats)
        snap.version = try JSONDecoder().decode(VersionResponse.self, from: Data(Fixture.string("version").utf8))
        snap.version?.features.auditLog = false
        XCTAssertTrue(DashboardInsights.compute(snap).contains { $0.id == "audit-disabled" })
        snap.config = BankConfigResponse(bankId: "b", config: ["audit_log_enabled": .bool(true)], overrides: ["audit_log_enabled": .bool(true)])
        XCTAssertFalse(DashboardInsights.compute(snap).contains { $0.id == "audit-disabled" }, "activé pour la banque")
    }
}

/// Serveur 1.1.0 : la liste du journal n'a plus les corps ; l'écran Lectures lit le détail des lectures.
@MainActor
final class AuditBodiesTests: XCTestCase {
    func testReadsWithoutBodiesAreCompletedFromTheDetail() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/audit-logs/a1", json: #"{"id":"a1","action":"recall","transport":"http","metadata":{},"request":{"query":"q"},"response":{"results":[]}}"#)
        let summary = AuditLogEntry(id: "a1", action: "recall", transport: "http", metadata: [:])
        let full = AuditLogEntry(id: "a0", action: "recall", transport: "http", metadata: [:], request: ["query": .string("déjà là")])
        let out = await ReadsViewModel.withBodies([summary, full], bank: testBank, client: makeClient(t))
        XCTAssertEqual(out[0].request?["query"], .string("q"))
        XCTAssertEqual(out[1].request?["query"], .string("déjà là"))
        XCTAssertEqual(t.requests.filter { $0.path.contains("/audit-logs/") }.count, 1, "une entrée complète n'est pas relue")
    }
}
