import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class OperationsViewModelTests: XCTestCase {
    func make(_ t: MockTransport) -> OperationsViewModel {
        OperationsViewModel(client: makeClient(t), bank: testBank)
    }

    func writes(_ t: MockTransport) -> [RecordedRequest] {
        t.requests.filter { $0.method != "GET" }
    }

    /// Aucune consolidation en file ni en cours : les lectures `type=consolidation` renvoient une liste vide.
    func idleConsolidation(_ t: MockTransport) {
        let list = Fixture.string("operations_list")
        t.on("GET", "\(bankPath)/operations") { request in
            request.queryValue("type") == "consolidation"
                ? .json(#"{"bank_id":"\#(testBank)","operations":[],"total":0,"limit":1,"offset":0}"#) : .json(list)
        }
    }

    func testReloadBuildsRowsAndStats() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        XCTAssertEqual(vm.rows.count, 6)
        XCTAssertEqual(vm.stats?.pendingConsolidation, 250)
        XCTAssertEqual(vm.activeCount, 2)
        let proc = vm.rows[0]
        XCTAssertEqual(proc.status, .processing)
        XCTAssertEqual(proc.title, "Consolidation")
        XCTAssertEqual(try XCTUnwrap(proc.progressFraction), 0.25, accuracy: 0.0001)
        XCTAssertEqual(proc.progressLabel, "llm_batches — 30/120")
        XCTAssertEqual(vm.rows[1].target, "codex-abc-task-011")
        XCTAssertEqual(vm.rows[1].title, "Extraction des faits")
    }

    func testStatusFilterIsSentToServer() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        vm.statusFilter = .failed
        vm.typeFilter = "retain"
        vm.excludeParents = true
        await vm.reload()
        // La page affichée (100 lignes), pas les compteurs lus à une ligne.
        let list = { t.requests.first { $0.path.hasSuffix("/operations") && $0.queryValue("limit") == "100" }! }
        let r = list()
        XCTAssertEqual(r.queryValue("status"), "failed")
        XCTAssertEqual(r.queryValue("type"), "retain")
        XCTAssertEqual(r.queryValue("exclude_parents"), "true")
        vm.statusFilter = .all
        t.reset()
        await vm.reload()
        XCTAssertNil(list().queryValue("status"))
    }

    func testFailureGroupingMergesSameCauseIgnoringNumbers() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        XCTAssertEqual(vm.failedRows.count, 3)
        let groups = vm.failureGroups
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].signature, "Gemini VLM error 429 quota exceeded for request N")
        XCTAssertEqual(Set(groups[0].operationIDs), ["op-f1", "op-f2"])
        XCTAssertEqual(groups[1].signature, "(aucun message d'erreur)")
    }

    func testSelectingAnOperationLoadsItsDetail() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        await vm.reload()
        await vm.select("op-f1")
        let d = try XCTUnwrap(vm.selectedDetail.value)
        XCTAssertEqual(d.status, "failed")
        XCTAssertEqual(d.childOperations?.count, 1)
        XCTAssertEqual(d.retryCount, 3)
        await vm.select(nil)
        XCTAssertNil(vm.selectedDetail.value)
    }

    func testRetryRequiresConfirmationBeforeAnyWrite() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/operations/op-f1/retry", json: #"{"success":true,"message":"Opération relancée","operation_id":"op-f1"}"#)
        let vm = make(t)
        await vm.reload()
        vm.requestRetry(vm.rows.first { $0.id == "op-f1" }!)
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertEqual(c.severity, .normal)
        XCTAssertTrue(writes(t).isEmpty, "rien n'est envoyé avant confirmation")
        await c.perform()
        XCTAssertEqual(writes(t).map(\.path), ["\(bankPath)/operations/op-f1/retry"])
        XCTAssertEqual(vm.actionMessage, "Opération relancée.", "le message du serveur (anglais, avec l'identifiant) n'est jamais repris")
    }

    func testDeleteAndCancelAreDestructiveConfirmations() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("DELETE", "\(bankPath)/operations/op-ok/delete", json: #"{"success":true,"message":"supprimée","operation_id":"op-ok"}"#)
        t.on("DELETE", "\(bankPath)/operations/op-pend", json: #"{"success":true,"message":"annulée","operation_id":"op-pend"}"#)
        let vm = make(t)
        await vm.reload()
        vm.requestDelete(vm.rows.first { $0.id == "op-ok" }!)
        XCTAssertEqual(vm.confirmation?.severity, .destructive)
        XCTAssertTrue(writes(t).isEmpty)
        await vm.confirmation!.perform()
        XCTAssertEqual(writes(t).last?.method, "DELETE")
        XCTAssertEqual(writes(t).last?.path, "\(bankPath)/operations/op-ok/delete")
        vm.requestCancel(vm.rows.first { $0.id == "op-pend" }!)
        await vm.confirmation!.perform()
        XCTAssertEqual(writes(t).last?.path, "\(bankPath)/operations/op-pend")
    }

    func testDecliningConfirmationSendsNothing() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        let vm = make(t)
        await vm.reload()
        vm.requestConsolidation()
        XCTAssertNotNil(vm.confirmation)
        vm.confirmation = nil  // l'utilisateur annule
        XCTAssertTrue(writes(t).isEmpty)
    }

    func testConsolidationAndRecoverMessages() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        t.on("POST", "\(bankPath)/consolidate", json: #"{"operation_id":"op-new","deduplicated":false}"#)
        t.on("POST", "\(bankPath)/consolidation/recover", json: #"{"retried_count":7}"#)
        let vm = make(t)
        await vm.reload()
        vm.requestConsolidation()
        XCTAssertEqual(vm.confirmation?.title, "Consolider les faits ?")
        XCTAssertEqual(vm.confirmation?.confirmTitle, "Consolider")
        XCTAssertTrue(vm.confirmation!.message.hasPrefix(
            "Le serveur va créer ou mettre à jour les observations à partir des \(Format.number(250)) faits pas encore consolidés."))
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "Consolidation mise en file.")
        vm.requestRecoverConsolidation()
        XCTAssertEqual(vm.confirmation?.confirmTitle, "Reconsolider")
        XCTAssertTrue(vm.confirmation!.message.contains("faits en échec de consolidation seront remis dans la file"))
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "7 faits remis en file.")
        // La liste a été rechargée après chaque action.
        XCTAssertGreaterThanOrEqual(t.requests.filter { $0.method == "GET" && $0.path.hasSuffix("/operations") }.count, 3)
    }

    func testRetryAllFailedReportsPartialRefusals() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/operations/op-f1/retry", json: #"{"success":true,"message":"ok","operation_id":"op-f1"}"#)
        t.on("POST", "\(bankPath)/operations/op-f2/retry", json: #"{"success":false,"message":"non relançable","operation_id":"op-f2"}"#)
        t.on("POST", "\(bankPath)/operations/op-f3/retry", json: #"{"detail":"introuvable"}"#, status: 404)
        let vm = make(t)
        await vm.reload()
        await vm.requestRetryAllFailed()
        XCTAssertTrue(vm.confirmation!.title.contains("3"))
        await vm.confirmation!.perform()
        XCTAssertEqual(writes(t).count, 3)
        XCTAssertTrue(vm.actionMessage!.hasPrefix("1 opération relancée, 2 refusées"), vm.actionMessage ?? "")
    }

    func testActionFailureIsSurfaced() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        t.on("POST", "\(bankPath)/consolidate", json: #"{"detail":"worker indisponible"}"#, status: 503)
        let vm = make(t)
        await vm.reload()
        vm.requestConsolidation()
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage!.contains("worker indisponible"), vm.actionMessage ?? "")
    }

    func testBulkRetryLoadsEveryPageBeforeWritingAndIgnoresDisplayFilters() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "\(bankPath)/operations") { request in
            let offset = Int(request.queryValue("offset") ?? "0")!
            let operations = (offset..<min(offset + 100, 205)).map {
                OperationResponse(id: "failed-\($0)", taskType: "retain", itemsCount: 1,
                                  createdAt: "2026-10-20T10:00:00Z", status: "failed")
            }
            let page = OperationsListResponse(bankId: testBank, total: 205, limit: 100, offset: offset, operations: operations)
            return MockResponse(body: try! JSONEncoder().encode(page))
        }
        t.on("POST", "\(bankPath)/operations/*/retry", json: #"{"success":true,"message":"ok","operation_id":"queued"}"#)
        let vm = make(t)
        vm.statusFilter = .processing
        vm.typeFilter = "consolidation"
        await vm.requestRetryAllFailed()
        let pages = t.requests
        XCTAssertEqual(pages.map { $0.queryValue("offset") }, ["0", "100", "200"])
        XCTAssertTrue(pages.allSatisfy { $0.queryValue("status") == "failed" && $0.queryValue("type") == nil && $0.queryValue("exclude_parents") == "true" })
        XCTAssertTrue(writes(t).isEmpty)
        XCTAssertTrue(vm.confirmation?.title.contains("205") == true)
        await vm.confirmation!.perform()
        XCTAssertEqual(writes(t).count, 205)
        XCTAssertEqual(Set(writes(t).map(\.path)).count, 205)
        XCTAssertEqual(vm.actionMessage, "205 opérations relancées.")
        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.activityMessage)
    }

    func testBulkRetryPageFailureDoesNotOfferAPartialRetryOrWriteAnything() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/operations") { request in
            if request.queryValue("offset") == "0" {
                return .json(#"{"bank_id":"b","total":2,"limit":100,"offset":0,"operations":[{"id":"first","task_type":"retain","items_count":1,"created_at":"2026-10-20T10:00:00Z","status":"failed"}]}"#)
            }
            return .json(#"{"detail":"indisponible"}"#, status: 503)
        }
        let vm = make(t)
        await vm.requestRetryAllFailed()
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(writes(t).isEmpty)
        XCTAssertTrue(vm.actionMessage?.contains("Impossible de préparer") == true)
        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.activityMessage)
    }

    func testIndividualRetryRefusalIsReportedAsFailure() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/operations/op-f1/retry", json: #"{"success":false,"message":"non relançable","operation_id":"op-f1"}"#)
        let vm = make(t)
        await vm.reload()
        vm.requestRetry(try XCTUnwrap(vm.failedRows.first { $0.id == "op-f1" }))
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "Échec : non relançable")
    }

    func testConsultationModeKeepsReadsAvailableAndDoesNotPrepareRetries() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "/health") { _ in MockResponse(headers: ["X-Hindsight-Mode": "consultation"]) }
        let vm = make(t)
        await vm.reload()
        XCTAssertTrue(vm.consultationOnly)
        XCTAssertFalse(vm.rows.isEmpty)
        vm.requestRetry(vm.failedRows[0])
        await vm.requestRetryAllFailed()
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(writes(t).isEmpty)
    }

    func testAutoRefreshPollsAndStops() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = make(t)
        vm.startAutoRefresh(every: 0.05, idleFactor: 1)
        try await Task.sleep(for: .milliseconds(300))
        vm.stopAutoRefresh()
        let n = t.requests.filter { $0.path.hasSuffix("/operations") }.count
        XCTAssertGreaterThanOrEqual(n, 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(t.requests.filter { $0.path.hasSuffix("/operations") }.count, n, "plus de requêtes après l'arrêt")
    }

    func testAutoRefreshSlowsDownWhenNothingIsActive() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":0,"limit":100,"offset":0,"operations":[]}"#)
        let vm = make(t)
        await vm.reload()
        t.reset()
        vm.startAutoRefresh(every: 0.05, idleFactor: 10)  // 0,5 s au repos
        try await Task.sleep(for: .milliseconds(300))
        vm.stopAutoRefresh()
        XCTAssertEqual(t.requests.filter { $0.path.hasSuffix("/operations") }.count, 0)
    }
    /// Sans observations, le serveur termine une consolidation sans rien traiter : rien n'est proposé.
    func testDisabledConsolidationIsRefusedWithoutConfirmationOrWrite() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"\#(testBank)","config":{"enable_observations":false,"enable_auto_consolidation":true},"overrides":{"enable_observations":false}}"#)
        let vm = make(t)
        vm.serverObservations = true  // le réglage de la banque l'emporte sur celui du serveur
        await vm.reload()
        XCTAssertEqual(vm.consolidation?.phase, .disabled)
        XCTAssertEqual(vm.consolidation?.automatic, false)  // sans observations, rien d'automatique non plus
        vm.requestConsolidation()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, ConsolidationStatus.disabledMessage)
        vm.actionMessage = nil
        vm.requestRecoverConsolidation()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, ConsolidationStatus.disabledMessage)
        XCTAssertTrue(writes(t).isEmpty)
    }

    func testRunningOrFinishedConsolidationIsNotOfferedAgain() async {
        let t = MockTransport()
        t.installStandardRoutes()  // la file contient une consolidation en cours
        let vm = make(t)
        await vm.reload()
        XCTAssertEqual(vm.consolidation?.phase, .running)
        vm.requestConsolidation()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, "Une consolidation est déjà en cours pour cette banque.")

        let idle = MockTransport()
        idle.installStandardRoutes()
        idleConsolidation(idle)
        idle.on("GET", "\(bankPath)/stats") { _ in
            .json(#"{"bank_id":"\#(testBank)","total_nodes":10,"total_links":0,"total_documents":1,"nodes_by_fact_type":{},"links_by_link_type":{},"links_by_fact_type":{},"links_breakdown":{},"pending_operations":0,"failed_operations":0,"pending_consolidation":0,"failed_consolidation":0}"#)
        }
        let upToDate = make(idle)
        await upToDate.reload()
        XCTAssertEqual(upToDate.consolidation?.phase, .upToDate)
        upToDate.requestConsolidation()
        XCTAssertNil(upToDate.confirmation)
        XCTAssertEqual(upToDate.actionMessage, "Rien à consolider : tous les faits de cette banque sont déjà consolidés.")
        upToDate.requestRecoverConsolidation()
        XCTAssertEqual(upToDate.actionMessage, "Aucun fait en échec de consolidation.")
        XCTAssertTrue(writes(idle).isEmpty)
    }

    func testConsolidationStatusUsesTheBankSettingThenTheServerFlag() throws {
        let stats = BankStatsResponse(
            bankId: testBank, totalNodes: 5, totalLinks: 0, totalDocuments: 1, nodesByFactType: [:], linksByLinkType: [:],
            linksByFactType: [:], linksBreakdown: [:], pendingOperations: 0, failedOperations: 0,
            lastConsolidatedAt: "2026-10-23T11:29:00Z", pendingConsolidation: 4)
        let off = BankConfigResponse(bankId: testBank, config: ["enable_observations": .bool(false)], overrides: [:])
        XCTAssertEqual(ConsolidationStatus(stats: stats, config: off, serverObservations: true, operations: ActiveConsolidations()).phase, .disabled)
        XCTAssertEqual(ConsolidationStatus(stats: stats, config: nil, serverObservations: false, operations: ActiveConsolidations()).phase, .disabled)
        let fallback = ConsolidationStatus(stats: stats, config: nil, serverObservations: nil, operations: ActiveConsolidations())
        XCTAssertEqual(fallback.phase, .pending)
        XCTAssertEqual(fallback.pendingFacts, 4)
        XCTAssertEqual(fallback.lastConsolidatedAt, "2026-10-23T11:29:00Z")
        XCTAssertEqual(ConsolidationStatus(stats: stats, config: nil, serverObservations: nil, operations: ActiveConsolidations(running: 1, queued: 1)).phase, .running)
        // Une consolidation qui attend son tour est « en attente », comme sa ligne dans Traitements.
        XCTAssertEqual(ConsolidationStatus(stats: stats, config: nil, serverObservations: nil, operations: ActiveConsolidations(queued: 1)).phase, .queued)
        // Réglages inconnus : la consolidation automatique est supposée active (estimation prudente).
        XCTAssertTrue(fallback.automatic)
        let manual = BankConfigResponse(bankId: testBank, config: ["enable_auto_consolidation": .bool(false)], overrides: [:])
        XCTAssertFalse(ConsolidationStatus.consolidatesAfterExtraction(manual, serverObservations: true))
        XCTAssertFalse(ConsolidationStatus.consolidatesAfterExtraction(off, serverObservations: true))
        XCTAssertNil(fallback.refusal)
        XCTAssertEqual(OperationsViewModel.consolidationMessage(pending: 1).contains("du seul fait pas encore consolidé"), true)
    }

}


/// Une opération « terminée » sans rien traiter n'est pas affichée comme une réussite.
final class OperationEndedWithoutWorkTests: XCTestCase {
    func testOnlyZeroProcessedCompletedRunsAreFlagged() {
        XCTAssertTrue(OperationRow.endedWithoutWork(status: "completed", processed: 0, total: 5463))
        XCTAssertFalse(OperationRow.endedWithoutWork(status: "completed", processed: 100, total: 5648), "un tour partiel est normal")
        XCTAssertFalse(OperationRow.endedWithoutWork(status: "processing", processed: 0, total: 5463))
        XCTAssertFalse(OperationRow.endedWithoutWork(status: "completed", processed: nil, total: nil))
    }

    /// Le serveur garde l'erreur d'une tentative ratée sur l'opération qui a repris : ce n'est pas un échec actuel.
    func testErrorOfAnActiveOperationIsFromAPreviousAttempt() {
        func row(_ status: String, _ error: String?) -> OperationRow {
            OperationRow(OperationResponse(id: "op", taskType: "consolidation", itemsCount: 0, createdAt: "2026-10-23T19:01:08Z",
                                           status: status, errorMessage: error))
        }
        let quota = "Exception: Failed to generate batch embeddings: 429 RESOURCE_EXHAUSTED."
        XCTAssertTrue(row("processing", quota).errorIsFromPreviousAttempt)
        XCTAssertTrue(row("pending", quota).errorIsFromPreviousAttempt, "en attente de sa prochaine tentative")
        XCTAssertFalse(row("failed", quota).errorIsFromPreviousAttempt, "échec réel : reste en rouge")
        XCTAssertFalse(row("processing", nil).errorIsFromPreviousAttempt)
        XCTAssertFalse(row("processing", "  ").errorIsFromPreviousAttempt)
    }
}
