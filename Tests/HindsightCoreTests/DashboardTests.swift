import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class DashboardTests: XCTestCase {
    func stats(_ patch: (inout BankStatsResponse) -> Void = { _ in }) -> BankStatsResponse {
        var s = try! JSONDecoder().decode(BankStatsResponse.self, from: Data(Fixture.string("bank_stats").utf8))
        patch(&s)
        return s
    }
    func version(audit: Bool = false, observations: Bool = true) -> VersionResponse {
        var v = try! JSONDecoder().decode(VersionResponse.self, from: Data(Fixture.string("version").utf8))
        v.features.auditLog = audit
        v.features.observations = observations
        return v
    }
    let now = HSDate.parse("2026-10-18T12:00:00Z")!

    func ids(_ s: DashboardSnapshot) -> [String] { DashboardInsights.compute(s, now: now).map(\.id) }

    func testRealisticStatsRaiseTheRightAlertsInPriorityOrder() async {
        var snap = DashboardSnapshot(stats: stats(), fetchedAt: now)
        snap.version = version()
        let insights = DashboardInsights.compute(snap, now: now)
        XCTAssertEqual(insights.map(\.id), ["failed-operations", "failed-consolidation", "pending-consolidation", "pending-operations", "audit-disabled"])
        XCTAssertEqual(insights[0].severity, .critical)
        XCTAssertEqual(insights[0].action, .openOperations(status: "failed"))
        XCTAssertEqual(insights[1].action, .recoverConsolidation)
        // Dernière consolidation il y a plus de 24 h => avertissement.
        XCTAssertEqual(insights.first { $0.id == "pending-consolidation" }?.severity, .warning)
        XCTAssertEqual(insights.first { $0.id == "audit-disabled" }?.action, .openAudit)
    }

    func testHealthyBankSaysNothingUrgent() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingConsolidation = 0; s.pendingOperations = 0
        }, fetchedAt: now)
        snap.version = version(audit: true)
        XCTAssertEqual(ids(snap), ["all-good"])
        XCTAssertEqual(DashboardInsights.compute(snap, now: now)[0].severity, .ok)
    }

    func testRecentConsolidationOnlyInforms() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingOperations = 0
            s.lastConsolidatedAt = "2026-10-18T10:00:00Z"
        }, fetchedAt: now)
        snap.version = version(audit: true)
        let i = DashboardInsights.compute(snap, now: now)
        XCTAssertEqual(i.first?.id, "pending-consolidation")
        XCTAssertEqual(i.first?.severity, .info)
    }

    func testRunningConsolidationIsNotOfferedAgain() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingOperations = 0
            s.lastConsolidatedAt = "2026-10-10T10:00:00Z"
        }, fetchedAt: now)
        snap.version = version(audit: true)
        snap.activeConsolidations = 1
        let i = DashboardInsights.compute(snap, now: now).first { $0.id == "pending-consolidation" }
        XCTAssertEqual(i?.actionTitle, "Voir l'avancement", "pas de « Lancer » pendant une consolidation")
        XCTAssertEqual(i?.severity, .info, "en cours : pas d'alerte de retard")
        if case .runConsolidation? = i?.action { XCTFail("ne doit pas proposer de lancer") }
        XCTAssertEqual(DashboardInsights.compute(snap, now: now).first { $0.id == "all-good" }?.detail, "Aucun échec.", "pas « à jour » avec des faits en attente")
    }

    func testObservationsDisabledSuppressesConsolidationAlerts() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingOperations = 0; s.totalObservations = 0
        }, fetchedAt: now)
        snap.version = version(audit: true, observations: false)
        XCTAssertEqual(ids(snap), ["all-good"])
    }

    func testNoObservationsWarning() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingConsolidation = 0; s.pendingOperations = 0
            s.totalObservations = 0
        }, fetchedAt: now)
        snap.version = version(audit: true)
        XCTAssertEqual(ids(snap), ["no-observations"])
    }

    func testLLMHealthFailureIsCritical() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingConsolidation = 0; s.pendingOperations = 0
        }, fetchedAt: now)
        snap.version = version(audit: true)
        snap.llmHealth = BankLlmHealthResponse(bankId: testBank, operations: [
            LlmOperationHealth(operation: "retain", ok: true, status: "connected", latencyMs: 120),
            LlmOperationHealth(operation: "reflect", ok: false, status: "auth_failed"),
        ])
        let i = DashboardInsights.compute(snap, now: now)
        XCTAssertEqual(i.map(\.id), ["llm-health"])
        XCTAssertTrue(i[0].detail.contains("reflect (auth_failed)"))
    }

    func testStaleWritesAndRelativeTime() async {
        var snap = DashboardSnapshot(stats: stats { s in
            s.failedOperations = 0; s.failedConsolidation = 0; s.pendingConsolidation = 0; s.pendingOperations = 0
            s.lastMemoryWriteAt = "2026-10-01T00:00:00Z"
        }, fetchedAt: now)
        snap.version = version(audit: true)
        XCTAssertTrue(ids(snap).contains("stale-writes"))
        XCTAssertEqual(DashboardInsights.relative(now.addingTimeInterval(-30), now: now), "à l'instant")
        XCTAssertEqual(DashboardInsights.relative(now.addingTimeInterval(-600), now: now), "il y a 10 min")
        XCTAssertEqual(DashboardInsights.relative(now.addingTimeInterval(-7200), now: now), "il y a 2 h")
        XCTAssertEqual(DashboardInsights.relative(now.addingTimeInterval(-86400), now: now), "hier")
        XCTAssertEqual(DashboardInsights.relative(now.addingTimeInterval(-86400 * 5), now: now), "il y a 5 jours")
    }

    func testDerivedFigures() async {
        let snap = DashboardSnapshot(stats: stats(), fetchedAt: now)
        XCTAssertEqual(snap.worldFacts, 4100)
        XCTAssertEqual(snap.experienceFacts, 3500)
        XCTAssertEqual(snap.observationFacts, 412)
        XCTAssertEqual(snap.rawFacts, 7600)
        let cov = try! XCTUnwrap(snap.consolidationCoverage)
        XCTAssertEqual(cov, Double(7600 - 257) / 7600, accuracy: 1e-9)
    }

    func testReloadAggregatesAllSources() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        let snap = try XCTUnwrap(vm.snapshot)
        XCTAssertEqual(snap.entityTotal, 3800)
        XCTAssertEqual(snap.timeseries?.buckets?.count, 2)
        XCTAssertEqual(snap.recentDocuments.count, 3)
        XCTAssertEqual(snap.topTags.first?.tag, "source:codex")
        XCTAssertEqual(snap.recentFailures.count, 6)  // la fixture renvoie toute la liste ; le filtrage est côté serveur
        XCTAssertTrue(vm.partialErrors.isEmpty)
        XCTAssertFalse(vm.insights.isEmpty)
        // Requêtes parallèles : échecs récents, puis consolidations en cours et en file (ordre variable).
        let statuses = Set(t.requests.filter { $0.path.hasSuffix("/operations") }.compactMap { $0.queryValue("status") })
        XCTAssertEqual(statuses, ["failed", "processing", "pending"])
    }

    func testSecondarySourceFailureDoesNotBreakDashboard() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "\(bankPath)/stats/memories-timeseries", json: #"{"detail":"trop lent"}"#, status: 504)
        t.on("GET", "\(bankPath)/entities", json: #"{"detail":"x"}"#, status: 500)
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        XCTAssertNotNil(vm.snapshot)
        XCTAssertNil(vm.snapshot?.timeseries)
        XCTAssertNil(vm.snapshot?.entityTotal)
        XCTAssertEqual(vm.partialErrors.count, 2)
    }

    func testStatsFailureIsTheOnlyFatalOne() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "\(bankPath)/stats", json: #"{"detail":"Bank not found"}"#, status: 404)
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        XCTAssertTrue(vm.state.errorMessage?.contains("404") == true)
    }

    func testRefreshStatsFlag() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload(refreshStats: true)
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/stats") }?.queryValue("refresh"), "true")
    }

    func testLLMTestUpdatesInsights() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/health/llm", json: #"{"bank_id":"\#(testBank)","operations":[{"operation":"retain","ok":false,"status":"unreachable"}]}"#)
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        await vm.testLLM()
        XCTAssertTrue(vm.insights.contains { $0.id == "llm-health" })
        // Un rechargement conserve le résultat du test.
        await vm.reload()
        XCTAssertTrue(vm.insights.contains { $0.id == "llm-health" })
    }

    func testDisabledLLMProbeHasItsOwnNoticeAndClearsPreviousHealth() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/health/llm", json: #"{"bank_id":"b","operations":[{"operation":"retain","ok":false,"status":"auth_failed"}]}"#)
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        await vm.testLLM()
        XCTAssertNotNil(vm.snapshot?.llmHealth)
        t.on("POST", "\(bankPath)/health/llm", json: #"{"detail":"Bank LLM health check is disabled. Set HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true to enable."}"#, status: 404)
        await vm.testLLM()
        await vm.testLLM()
        XCTAssertTrue(vm.partialErrors.isEmpty)
        XCTAssertNil(vm.snapshot?.llmHealth)
        XCTAssertFalse(vm.insights.contains { $0.id == "llm-health" })
        XCTAssertTrue(vm.llmTestMessage?.contains("désactivé") == true)
        XCTAssertTrue(vm.llmTestMessage?.contains("relance des opérations reste disponible") == true)
        XCTAssertFalse(vm.isTestingLLM)
    }

    func testOtherLLMProbeErrorsAreNotPresentedAsDisabled() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        t.on("POST", "\(bankPath)/health/llm", json: #"{"detail":"Bank not found"}"#, status: 404)
        await vm.testLLM()
        XCTAssertTrue(vm.llmTestMessage?.contains("Bank not found") == true)
        XCTAssertFalse(vm.llmTestMessage?.contains("désactivé") == true)
        t.on("POST", "\(bankPath)/health/llm", json: #"{"bank_id":"b","operations":[]}"#)
        await vm.testLLM()
        XCTAssertNil(vm.llmTestMessage)
    }

    func testConsultationModeDoesNotCallLLMs() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "/health") { _ in MockResponse(headers: ["X-Hindsight-Mode": "consultation"]) }
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        XCTAssertTrue(vm.snapshot?.consultationOnly == true)
        await vm.testLLM()
        XCTAssertFalse(t.requests.contains { $0.method == "POST" })
        XCTAssertEqual(vm.llmTestRefusal, "Le serveur est en mode consultation : le test des modèles est désactivé.")
        XCTAssertEqual(vm.llmTestMessage, vm.llmTestRefusal, "un test qui ne part pas dit pourquoi")
    }

    func testDisabledProbeIsRefusedBeforeAnyCall() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("GET", "/version", json: Fixture.string("version").replacingOccurrences(of: #""bank_llm_health":true"#, with: #""bank_llm_health":false"#))
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        XCTAssertTrue(vm.llmTestRefusal?.contains("HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true") == true)
        await vm.testLLM()
        XCTAssertFalse(t.requests.contains { $0.method == "POST" })
        XCTAssertEqual(vm.llmTestMessage, vm.llmTestRefusal)
    }

    func testModelTestIsDatedAndAFailedRetestDropsTheOldResult() async {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/health/llm", json: #"{"bank_id":"b","operations":[{"operation":"retain","ok":true,"status":"connected","latency_ms":420},{"operation":"reflect","ok":false,"status":"auth_failed"}]}"#)
        let vm = DashboardViewModel(client: makeClient(t), bank: testBank)
        await vm.reload()
        await vm.testLLM()
        XCTAssertNotNil(vm.llmTestedAt)
        XCTAssertEqual(LLMHealthSummary.sentence(vm.llmHealth!), "Rôle LLM en échec : Réponses (clé refusée).")
        t.on("POST", "\(bankPath)/health/llm", json: #"{"detail":"boom"}"#, status: 500)
        await vm.testLLM()
        XCTAssertNil(vm.llmHealth, "l'ancien résultat ne doit pas passer pour celui du test raté")
        XCTAssertNil(vm.llmTestedAt)
        XCTAssertTrue(vm.llmTestMessage?.hasPrefix("Le test des LLM n'a pas abouti") == true)
    }

    func testModelTestSentencesUseTheModelsPageWords() {
        let ok = BankLlmHealthResponse(bankId: "b", operations: [
            LlmOperationHealth(operation: "retain", ok: true, status: "connected"),
            LlmOperationHealth(operation: "consolidation", ok: true, status: "connected"),
        ])
        XCTAssertEqual(LLMHealthSummary.sentence(ok), "Les 2 rôles LLM testés répondent.")
        let bad = BankLlmHealthResponse(bankId: "b", operations: [
            LlmOperationHealth(operation: "retain", ok: false, status: "unreachable"),
            LlmOperationHealth(operation: "consolidation", ok: false, status: "not_configured"),
        ])
        XCTAssertEqual(
            LLMHealthSummary.sentence(bad),
            "Rôles LLM en échec : Extraction des faits (injoignable), Consolidation (aucun fournisseur configuré).")
        XCTAssertEqual(
            LLMHealthSummary.sentence(BankLlmHealthResponse(bankId: "b", operations: [])),
            "Le serveur n'a renvoyé aucun résultat pour le test des modèles.")
    }
}
