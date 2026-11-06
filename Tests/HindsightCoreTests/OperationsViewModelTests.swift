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
        let r = t.requests.first { $0.path.hasSuffix("/operations") }!
        XCTAssertEqual(r.queryValue("status"), "failed")
        XCTAssertEqual(r.queryValue("type"), "retain")
        XCTAssertEqual(r.queryValue("exclude_parents"), "true")
        vm.statusFilter = .all
        t.reset()
        await vm.reload()
        XCTAssertNil(t.requests.first { $0.path.hasSuffix("/operations") }!.queryValue("status"))
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
        XCTAssertEqual(vm.actionMessage, "Opération relancée")
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
        t.on("POST", "\(bankPath)/consolidate", json: #"{"operation_id":"op-new","deduplicated":false}"#)
        t.on("POST", "\(bankPath)/consolidation/recover", json: #"{"retried_count":7}"#)
        let vm = make(t)
        await vm.reload()
        vm.requestConsolidation()
        XCTAssertTrue(vm.confirmation!.message.contains("250"))
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "Opération op-new créée.")
        vm.requestRecoverConsolidation()
        XCTAssertTrue(vm.confirmation!.message.contains("7"))
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "7 fait(s) remis en file.")
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
        XCTAssertTrue(vm.actionMessage!.hasPrefix("1 relancée(s), 2 refusée(s)"), vm.actionMessage ?? "")
    }

    func testActionFailureIsSurfaced() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
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
        XCTAssertEqual(vm.actionMessage, "205 relancée(s)")
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
