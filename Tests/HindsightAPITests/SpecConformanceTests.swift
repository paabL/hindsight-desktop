import XCTest
@testable import HindsightAPI
import HindsightTestSupport

/// Vérifie le client contre le contrat `docs/openapi.json` :
///  - chaque méthode du client cible une opération qui existe (méthode + chemin),
///  - n'envoie que des paramètres de requête déclarés et des corps conformes au schéma,
///  - sait décoder une réponse conforme au schéma (complète ET minimale).
final class SpecConformanceTests: XCTestCase {
    static let spec = try! OpenAPISpec.repository()

    typealias Call = @Sendable (HindsightClient) async throws -> Void

    /// operationId -> appel du client. Les paramètres sont arbitraires mais valides.
    static let calls: [String: Call] = {
        let b = "b1"
        var c: [String: Call] = [:]
        c["health_endpoint_health_get"] = { _ = try await $0.health() }
        c["get_version"] = { _ = try await $0.version() }
        c["get_liveness"] = { _ = try await $0.liveness() }
        c["list_banks"] = { _ = try await $0.listBanks(q: "x") }
        c["get_agent_stats"] = { _ = try await $0.bankStats(b, refresh: true) }
        c["get_memories_timeseries"] = { _ = try await $0.memoriesTimeseries(b, period: "30d", timeField: "mentioned_at") }
        c["test_bank_llm"] = { _ = try await $0.llmHealth(b) }
        c["get_bank_config"] = { _ = try await $0.bankConfig(b) }
        c["update_bank_config"] = { _ = try await $0.updateBankConfig(b, updates: ["audit_log_enabled": true]) }
        c["reset_bank_config"] = { _ = try await $0.resetBankConfig(b) }
        c["create_or_update_bank"] = { _ = try await $0.createOrUpdateBank(b, request: CreateBankRequest(name: "n")) }
        c["update_bank"] = { _ = try await $0.updateBank(b, request: CreateBankRequest(name: "n")) }
        c["delete_bank"] = { _ = try await $0.deleteBank(b) }
        c["list_bank_aliases"] = { _ = try await $0.bankAliases(b) }
        c["create_bank_alias"] = { _ = try await $0.createBankAlias(b, alias: "ancien-id", primary: true) }
        c["set_bank_alias_primary"] = { _ = try await $0.setBankAliasPrimary(b, alias: "ancien-id", primary: false) }
        c["delete_bank_alias"] = { _ = try await $0.deleteBankAlias(b, alias: "ancien-id") }
        c["list_tags"] = { _ = try await $0.listTags(b, q: "source:*", source: "memories") }
        c["list_directives"] = { _ = try await $0.listDirectives(b) }
        c["create_directive"] = { _ = try await $0.createDirective(b, CreateDirectiveRequest(name: "n", content: "c")) }
        c["update_directive"] = { _ = try await $0.updateDirective(b, id: "d1", UpdateDirectiveRequest(isActive: false)) }
        c["get_directive"] = { _ = try await $0.directive(b, id: "d1") }
        c["delete_directive"] = { _ = try await $0.deleteDirective(b, id: "d1") }

        c["list_documents"] = {
            _ = try await $0.listDocuments(
                b, q: "codex", tags: TagFilter(tags: ["source:codex"], match: .allStrict),
                window: TimeWindow(field: "created_at", start: Date(timeIntervalSince1970: 1_700_000_000), end: Date()))
        }
        c["get_document"] = { _ = try await $0.document(b, id: "codex-s-task-001") }
        c["get_document_history"] = { _ = try await $0.documentHistory(b, id: "codex-s-task-001") }
        c["list_document_chunks"] = { _ = try await $0.documentChunks(b, id: "d1") }
        c["get_chunk"] = { _ = try await $0.chunk(id: "ck1") }
        c["update_document"] = { _ = try await $0.updateDocumentTags(b, id: "d1", tags: ["a"]) }
        c["reprocess_document"] = { _ = try await $0.reprocessDocument(b, id: "d1") }
        c["delete_document"] = { _ = try await $0.deleteDocument(b, id: "d1") }
        c["get_bank_attachment"] = { _ = try await $0.attachment(b, id: "abc") }

        c["list_memories"] = {
            _ = try await $0.listMemories(
                b,
                MemoryListQuery(
                    type: "world", q: "x", consolidationState: "failed", state: "active", documentID: "d1", entityID: "e1",
                    tags: TagFilter(tags: ["t"], match: .exact),
                    window: TimeWindow(field: "mentioned_at", start: Date(timeIntervalSince1970: 1_700_000_000))))
        }
        c["get_memory"] = { _ = try await $0.memory(b, id: "m1") }
        c["get_observation_history"] = { _ = try await $0.observationHistory(b, id: "m1") }
        c["update_memory"] = { _ = try await $0.updateMemory(b, id: "m1", UpdateMemoryRequest(text: "t")) }
        c["clear_memory_observations"] = { _ = try await $0.clearMemoryObservations(b, id: "m1") }
        c["clear_bank_memories"] = { _ = try await $0.deleteAllMemories(b, type: "observation") }
        c["clear_observations"] = { _ = try await $0.clearObservations(b) }
        c["recall_memories"] = {
            _ = try await $0.recall(
                b,
                RecallRequest(
                    query: "q", types: ["world"], rerank: RerankOptions(prune: false, dedup: true), budget: "mid", maxTokens: 2000, trace: false, tags: ["a"],
                    tagsMatch: "any_strict", tagGroups: [.and([.tags(["a"]), .not(.tags(["b"]))])],
                    temporalWindow: TemporalWindow(start: "2025-01-01T00:00:00Z", end: "2025-02-01T00:00:00Z")))
        }
        c["reflect"] = { _ = try await $0.reflect(b, ReflectRequest(query: "q")) }
        c["retain_memories"] = {
            _ = try await $0.retain(b, RetainRequest(items: [MemoryItem(content: .text("hello"), tags: ["x"])], async: true))
        }
        c["dry_run_extract_memories"] = {
            _ = try await $0.dryRunExtract(b, DryRunExtractRequest(content: .blocks([.text(TextContentBlock(type: "text", text: "x"))]), context: "c"))
        }
        c["get_graph"] = { _ = try await $0.graph(b, type: "world", limit: 200, q: "x", tags: TagFilter(tags: ["t"]), documentID: "d") }
        c["list_entities"] = { _ = try await $0.listEntities(b, tags: TagFilter(tags: ["t"])) }
        c["get_entity"] = { _ = try await $0.entity(b, id: "e1") }
        c["get_entity_graph"] = { _ = try await $0.entityGraph(b, tags: TagFilter(tags: ["t"], match: .all)) }
        c["list_observation_scopes"] = { _ = try await $0.observationScopes(b) }

        c["list_operations"] = { _ = try await $0.listOperations(b, status: "failed", type: "retain", excludeParents: true) }
        c["get_operation_status"] = { _ = try await $0.operation(b, id: "op1") }
        c["retry_operation"] = { _ = try await $0.retryOperation(b, id: "op1") }
        c["cancel_operation"] = { _ = try await $0.cancelOperation(b, id: "op1") }
        c["delete_operation"] = { _ = try await $0.deleteOperation(b, id: "op1") }
        c["trigger_consolidation"] = { _ = try await $0.triggerConsolidation(b) }
        c["recover_consolidation"] = { _ = try await $0.recoverConsolidation(b) }

        c["get_audit_log"] = { _ = try await $0.auditLog(b, id: "log-1") }
        c["list_audit_logs"] = { _ = try await $0.auditLogs(b, action: "recall", transport: "http", start: Date(timeIntervalSince1970: 1_700_000_000)) }
        c["audit_log_stats"] = { _ = try await $0.auditLogStats(b, action: "recall", period: "30d") }
        c["list_llm_requests"] = {
            _ = try await $0.llmRequests(b, status: "error", operation: "retain", scope: "s", provider: "p", traceID: "t", documentID: "d", memoryID: "m", group: true)
        }
        c["llm_request_stats"] = { _ = try await $0.llmRequestStats(b, operation: "retain", period: "1d", callType: "decision", splitBy: "model") }

        c["list_mental_models"] = { _ = try await $0.listMentalModels(b, tags: TagFilter(tags: ["t"])) }
        c["get_mental_model"] = { _ = try await $0.mentalModel(b, id: "mm1") }
        c["create_mental_model"] = { _ = try await $0.createMentalModel(b, CreateMentalModelRequest(name: "n", sourceQuery: "q")) }
        c["update_mental_model"] = { _ = try await $0.updateMentalModel(b, id: "mm1", UpdateMentalModelRequest(name: "n")) }
        c["refresh_mental_model"] = { _ = try await $0.refreshMentalModel(b, id: "mm1") }
        c["delete_mental_model"] = { _ = try await $0.deleteMentalModel(b, id: "mm1") }
        c["get_mental_model_history"] = { _ = try await $0.mentalModelHistory(b, id: "mm1") }
        c["get_knowledge_base_tree"] = { _ = try await $0.knowledgeTree(b) }
        c["get_knowledge_page"] = { _ = try await $0.knowledgePage(b, id: "p1") }
        c["search_knowledge_base"] = { _ = try await $0.searchKnowledgeBase(b, q: "x") }
        c["delete_knowledge_node"] = { _ = try await $0.deleteKnowledgeNode(b, id: "n1") }
        c["update_knowledge_node"] = { _ = try await $0.updateKnowledgeNode(b, id: "n1", UpdateNodeRequest(name: "n")) }

        c["export_bank_transfer"] = { _ = try await $0.exportBank(b, includeHistory: true, documentIDs: ["d1", "d2"]) }
        c["export_documents"] = { _ = try await $0.exportDocuments(b, documentIDs: ["d1"], includeObservations: true) }
        c["clone_bank"] = { _ = try await $0.cloneBank(b, targetBankID: "b2") }
        c["import_bank_transfer"] = { _ = try await $0.importBankArchive(b, archive: Data("PK".utf8), filename: "a.zip", mode: "merge", documentConflict: "replace") }
        c["import_documents"] = { _ = try await $0.importDocumentsArchive(b, archive: Data("PK".utf8), filename: "a.zip", onConflict: "replace") }
        c["export_bank_template"] = { _ = try await $0.exportTemplate(b) }
        c["import_bank_template"] = { _ = try await $0.importTemplate(b, manifest: BankTemplateManifest(version: "1"), dryRun: true) }
        c["download_file"] = { _ = try await $0.downloadFile(key: "k-ey") }
        return c
    }()

    /// Opérations du contrat volontairement non exposées par le client (hors périmètre ou retirées du serveur).
    static let unsupported: [String: String] = [
        "metrics_endpoint_metrics_get": "Prometheus, hors périmètre",
        "get_readiness": "sonde de readiness, hors périmètre",
        "get_bank_profile": "retiré du serveur (utiliser GET …/config)",
        "update_bank_disposition": "retiré du serveur (utiliser PATCH …/config)",
        "add_bank_background": "retiré du serveur (utiliser PATCH …/config)",
        "export_documents_sync_removed": "retiré du serveur",
        "get_bank_template_schema": "schéma JSON de modèle, hors périmètre",
        "file_retain": "upload multipart de fichiers à retenir, hors périmètre",
        "preview_prompt": "prévisualisation de prompts, hors périmètre",
        "regenerate_entity_observations": "obsolète côté serveur",
        "dry_run_refresh_mental_model": "hors périmètre",
        "clear_mental_model": "hors périmètre",
        "create_knowledge_folder": "hors périmètre (lecture seule de la base de connaissance)",
        "create_knowledge_page": "hors périmètre (lecture seule de la base de connaissance)",
        "export_knowledge_base": "hors périmètre",
        "preview_consolidation_strategies": "hors périmètre",
        "create_webhook": "webhooks hors périmètre",
        "list_webhooks": "webhooks hors périmètre",
        "delete_webhook": "webhooks hors périmètre",
        "update_webhook": "webhooks hors périmètre",
        "list_webhook_deliveries": "webhooks hors périmètre",
    ]

    func testEveryOperationIsEitherImplementedOrExplicitlyUnsupported() {
        let ids = Set(Self.spec.operations.map(\.operationID))
        for id in Self.calls.keys { XCTAssertTrue(ids.contains(id), "le client cible une opération inconnue : \(id)") }
        for id in Self.unsupported.keys {
            XCTAssertTrue(ids.contains(id), "« unsupported » mentionne une opération inconnue : \(id)")
        }
        let missing = ids.subtracting(Self.calls.keys).subtracting(Self.unsupported.keys).sorted()
        XCTAssertTrue(missing.isEmpty, "Opérations du contrat ni implémentées ni listées comme non supportées : \(missing)")
    }

    func testSynthesizedSamplesAreValidAgainstTheirSchemas() {
        for op in Self.spec.operations {
            guard let schema = op.responseSchema else { continue }
            for mode in [OpenAPISpec.SampleMode.full, .minimal] {
                let sample = Self.spec.sample(schema, mode: mode)
                let errs = Self.spec.validate(sample, against: schema)
                XCTAssertTrue(errs.isEmpty, "\(op.operationID) (\(mode)) : \(errs.prefix(3))")
            }
        }
    }

    /// Cœur du test : pour chaque appel du client, le faux serveur renvoie un échantillon complet puis minimal.
    func testClientCallsMatchContractAndDecodeSamples() async throws {
        for mode in [OpenAPISpec.SampleMode.full, .minimal] {
            for (opID, call) in Self.calls.sorted(by: { $0.key < $1.key }) {
                let t = MockTransport()
                let spec = Self.spec
                t.onFallback { req in
                    guard let op = spec.operation(method: req.method, path: req.path) else {
                        return .json(#"{"detail":"chemin hors contrat"}"#, status: 599)
                    }
                    guard let schema = op.responseSchema else { return .json("{}", status: op.successStatus ?? 200) }
                    if schema["type"]?.stringValue == "string" { return .bytes(Data([1, 2, 3]), contentType: "application/octet-stream") }
                    return .json(spec.sample(schema, mode: mode), status: op.successStatus ?? 200)
                }
                let client = HindsightClient(baseURL: URL(string: "http://127.0.0.1:8888")!, transport: t)
                do {
                    try await call(client)
                } catch {
                    XCTFail("\(opID) [\(mode)] : \(error.userMessage)")
                    continue
                }
                guard let rec = t.requests.last else { XCTFail("\(opID) : aucune requête"); continue }
                guard let op = Self.spec.operation(method: rec.method, path: rec.path) else {
                    XCTFail("\(opID) : \(rec.method) \(rec.path) n'existe pas dans le contrat"); continue
                }
                XCTAssertEqual(op.operationID, opID, "\(opID) a appelé \(op.operationID)")
                // Paramètres de requête déclarés ?
                let declared = Set(op.parameters.filter { $0.location == "query" }.map(\.name))
                for name in rec.query.keys { XCTAssertTrue(declared.contains(name), "\(opID) : paramètre de requête non déclaré « \(name) »") }
                // Paramètres requis fournis ?
                for p in op.parameters where p.location == "query" && p.required {
                    XCTAssertNotNil(rec.query[p.name], "\(opID) : paramètre requis manquant « \(p.name) »")
                }
                // Corps JSON conforme au schéma de requête.
                if op.requestContentType == "application/json", let schema = op.requestSchema {
                    if let body = rec.bodyJSON {
                        let errs = Self.spec.validate(body, against: schema)
                        XCTAssertTrue(errs.isEmpty, "\(opID) : corps non conforme : \(errs.prefix(3))")
                    }
                }
                if op.requestContentType == "multipart/form-data" {
                    XCTAssertTrue(rec.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true, opID)
                }
            }
        }
    }
}
