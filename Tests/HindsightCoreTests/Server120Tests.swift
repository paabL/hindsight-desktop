import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

/// Serveur 1.2.0 : modèles Hindsight (décision, rerank, embeddings) et options prune/dedup de recall.
@MainActor
final class Server120Tests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(ServerCapabilities.is120("1.2.0"))
        XCTAssertTrue(ServerCapabilities.is120("1.3.0-dev"))
        XCTAssertFalse(ServerCapabilities.is120("1.1.0"))
        XCTAssertFalse(ServerCapabilities.is120(nil))
    }

    func testCatalogKnowsHindsightInference() {
        let names = ServerSettingsCatalog.knownNames
        for n in [
            "HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER", "HINDSIGHT_API_RECALL_DECISION_MODEL_PRUNE",
            "HINDSIGHT_API_RECALL_DECISION_MODEL_DEDUP", "HINDSIGHT_API_EMBEDDINGS_HINDSIGHT_API_KEY",
            "HINDSIGHT_API_RERANKER_HINDSIGHT_API_KEY",
        ] { XCTAssertTrue(names.contains(n), n) }
        let decision = ServerSettingsCatalog.roles.first { $0.id == "decision" }
        XCTAssertTrue(decision?.fields.first?.help.contains("hindsight") == true)
        XCTAssertTrue(LaunchScript.isSecret("HINDSIGHT_API_RERANKER_HINDSIGHT_API_KEY"), "clé masquée")
    }

    func testDecisionModelBankOptionsAreReadAndSentOnlyWhenChanged() throws {
        let before = MemoryDesign(config: ["reflect_use_decision_model": false])
        XCTAssertFalse(before.recallDecisionModelPrune, "défaut du serveur")
        var after = before
        XCTAssertNil(after.updates(from: before)?["recall_decision_model_prune"], "inchangée : jamais envoyée (serveur 1.1.0)")
        after.recallDecisionModelPrune = true
        let updates = try XCTUnwrap(after.updates(from: before))
        XCTAssertEqual(updates, ["recall_decision_model_prune": true])
        // Le modèle de décision par fonction se règle dans Modèles, pour tout le serveur : la banque
        // n'envoie jamais d'exception, même si une ancienne valeur figure dans sa configuration.
        XCTAssertNil(MemoryDesign.labels["reflect_use_decision_model"])
        XCTAssertFalse(try XCTUnwrap(after.values()).keys.contains { $0.hasSuffix("_use_decision_model") })
    }

    func testPreferObservationsIsReadAndSentOnlyWhenChanged() throws {
        let before = MemoryDesign(config: [:])
        XCTAssertFalse(before.recallPreferObservations, "défaut du serveur")
        XCTAssertTrue(MemoryDesign(config: ["recall_prefer_observations": true]).recallPreferObservations)
        var after = before
        XCTAssertNil(after.updates(from: before)?["recall_prefer_observations"], "inchangée : jamais envoyée")
        after.recallPreferObservations = true
        XCTAssertEqual(try XCTUnwrap(after.updates(from: before)), ["recall_prefer_observations": true])
        XCTAssertEqual(MemoryDesign.labels["recall_prefer_observations"], "Préférer les observations")
    }

    func testSearchPoolCountsWhatSearchDrawsFromWithAndWithoutPreference() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"\#(testBank)","config":{"recall_prefer_observations":false},"overrides":{}}"#)
        t.on("GET", "\(bankPath)/memories/list") { request in
            let total: Int
            switch (request.queryValue("type"), request.queryValue("consolidation_state")) {
            case ("world"?, nil): total = 2500
            case ("experience"?, nil): total = 31
            case ("observation"?, nil): total = 3709
            case (nil, "pending"?): total = 250
            case (nil, "failed"?): total = 8
            default: total = -1
            }
            return .json(#"{"items":[],"total":\#(total),"limit":1,"offset":0}"#)
        }
        let vm = MemoryDesignViewModel(client: makeClient(t), bank: testBank, estimator: nil)
        await vm.reload()
        let pool = try XCTUnwrap(vm.searchPool)
        XCTAssertEqual(pool, SearchPool(facts: 2531, observations: 3709, notYetConsolidated: 258))
        XCTAssertEqual(pool.withoutPreference, 6240)
        XCTAssertEqual(pool.withPreference, 3967)

        // Les comptes sont un repère : sans eux, la page des réglages s'affiche quand même.
        t.on("GET", "\(bankPath)/memories/list", json: #"{"detail":"trop lent"}"#, status: 504)
        await vm.reload()
        XCTAssertNil(vm.searchPool)
        XCTAssertNil(vm.state.errorMessage)
    }

    func testRecallSendsRerankOnlyOn120WhenAsked() async throws {
        let t = MockTransport()
        t.on("POST", "\(bankPath)/memories/recall", json: Fixture.string("recall"))
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.query = "q"
        vm.prune = true
        await vm.run()
        XCTAssertNil(t.requests.last?.bodyJSON?["rerank"], "serveur 1.1.0 : rien")

        vm.serverIs120 = true
        vm.prune = nil
        await vm.run()
        XCTAssertNil(t.requests.last?.bodyJSON?["rerank"], "rien de coché : défaut de la banque")

        vm.dedup = true
        await vm.run()
        XCTAssertEqual(t.requests.last?.bodyJSON?["rerank"], ["dedup": true])

        vm.prune = false
        vm.dedup = false
        await vm.run()
        XCTAssertEqual(t.requests.last?.bodyJSON?["rerank"], ["prune": false, "dedup": false], "désactivation explicite des défauts de la banque")

        vm.serverIs120 = false
        await vm.run()
        XCTAssertNil(t.requests.last?.bodyJSON?["rerank"], "même un choix explicite reste omis sur un ancien serveur")
    }

    func testServiceUsageValuesPublicInferenceNamesAtHostedRates() throws {
        let stats = try JSONDecoder().decode(
            LLMRequestStatsResponse.self,
            from: Data(
                #"""
                {"bank_id":"b","period":"7d","trunc":"day","start":"2026-10-27T00:00:00Z","buckets":[
                 {"time":"2026-11-01T00:00:00Z","statuses":{"success":3},"total":3,"tokens":{"input":0,"output":0,"cached":0,"total":0},
                  "series":{"hs-decide-1-flash":{"calls":2,"tokens":1000000},"hindsight-ai/hs-rerank-1":{"calls":1,"tokens":500}}},
                 {"time":"2026-11-02T00:00:00Z","statuses":{"success":1},"total":1,"tokens":{"input":0,"output":0,"cached":0,"total":0},
                  "series":{"hs-decide-1-flash":{"calls":1,"tokens":500000}}}]}
                """#.utf8))
        let old = try JSONDecoder().decode(
            LLMRequestStatsResponse.self,
            from: Data(#"{"bank_id":"b","period":"7d","trunc":"day","start":"","buckets":[{"time":"","statuses":{},"total":4,"tokens":{"input":1,"output":0,"cached":0,"total":1}}]}"#.utf8))
        let rows = ModelServiceUsage.rows([(.decision, stats), (.rerank, old)], prices: .defaults)
        XCTAssertEqual(rows.count, 2, "sans series (1.1.0), rien à ventiler")
        let decide = try XCTUnwrap(rows.first { $0.model == "hs-decide-1-flash" })
        XCTAssertEqual(decide.calls, 3)
        XCTAssertEqual(decide.tokens, 1_500_000)
        XCTAssertEqual(try XCTUnwrap(decide.dollars), 0.03, accuracy: 1e-9)
        XCTAssertNil(rows.first { $0.model == "hindsight-ai/hs-rerank-1" }?.dollars, "modèle local : non chiffré")
    }

    func testSavedPriceBookGainsInferencePrices() {
        let store = InMemorySettingsStore()
        var old = PriceBook.defaults
        old.prices.removeAll { $0.pattern.hasPrefix("hs-") }
        old.prices.append(ModelPrice("hs-embed-1", input: 0.01, output: 0))
        old.save(to: store)
        let book = PriceBook.load(from: store)
        XCTAssertEqual(book.price(for: "hs-decide-1-flash")?.input, 0.02)
        XCTAssertEqual(book.price(for: "hs-embed-1")?.input, 0.01, "tarif modifié conservé")
    }

    func testServiceStatsCacheResetsWithServerAndRevaluesPrices() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/llm-requests/stats") { request in
            XCTAssertEqual(request.queryValue("split_by"), "model")
            XCTAssertEqual(request.queryValue("period"), "7d")
            let series = request.queryValue("call_type") == "decision"
                ? #"{"hs-decide-1-flash":{"calls":2,"tokens":1000000}}"# : "{}"
            return .json("""
                {"bank_id":"b","period":"7d","trunc":"day","start":"","buckets":[
                {"time":"","statuses":{},"total":2,"tokens":{"input":1000000,"output":0,"cached":0,"total":1000000},"series":\(series)}]}
                """)
        }
        var book = PriceBook.defaults
        let monitor = ConsumptionMonitor(settings: InMemorySettingsStore(), client: { makeClient(t) },
            banks: { [testBank] }, ledger: nil, prices: { book })
        await monitor.loadServices(serverIs120: false)
        XCTAssertTrue(t.requests.isEmpty, "pas de split_by sur un serveur 1.1")
        await monitor.loadServices(serverIs120: true)
        XCTAssertEqual(t.requests.count, 3)
        XCTAssertEqual(try XCTUnwrap(monitor.services.first?.dollars), 0.02, accuracy: 1e-9)
        book.prices.removeAll { $0.pattern == "hs-decide-1-flash" }
        book.prices.append(ModelPrice("hs-decide-1-flash", input: 0.04, output: 0))
        await monitor.loadServices(serverIs120: true)
        XCTAssertEqual(t.requests.count, 3, "le cache économise les requêtes, pas le recalcul du tarif")
        XCTAssertEqual(try XCTUnwrap(monitor.services.first?.dollars), 0.04, accuracy: 1e-9)
        monitor.reset()
        XCTAssertTrue(monitor.services.isEmpty, "autre serveur : aucun chiffre de l'ancien")
        await monitor.loadServices(serverIs120: true)
        XCTAssertEqual(t.requests.count, 6, "le nouveau serveur est relu sans attendre 5 min")
    }

    func testServiceStatsFailuresAreVisibleAndRetryable() async {
        let t = MockTransport()
        let monitor = ConsumptionMonitor(settings: InMemorySettingsStore(), client: { makeClient(t) },
            banks: { [testBank] }, ledger: nil, prices: { .defaults })
        await monitor.loadServices(serverIs120: true)
        XCTAssertNotNil(monitor.servicesError, "une erreur n'est pas une consommation nulle")
        await monitor.loadServices(serverIs120: true)
        XCTAssertEqual(t.requests.count, 6, "les échecs ne bloquent pas une nouvelle tentative")
        await monitor.loadServices(serverIs120: false)
        XCTAssertNil(monitor.servicesError)
        XCTAssertTrue(monitor.services.isEmpty)
    }

    func testResetDiscardsServiceStatsAlreadyInFlight() async {
        let t = MockTransport()
        t.delay = .milliseconds(30)
        let monitor = ConsumptionMonitor(settings: InMemorySettingsStore(), client: { makeClient(t) },
            banks: { [testBank] }, ledger: nil, prices: { .defaults })
        let load = Task { await monitor.loadServices(serverIs120: true) }
        await Task.yield()
        monitor.reset()
        await load.value
        XCTAssertNil(monitor.servicesError, "l'ancien serveur ne peut publier son erreur après reset")
        XCTAssertTrue(monitor.services.isEmpty)
    }
}
