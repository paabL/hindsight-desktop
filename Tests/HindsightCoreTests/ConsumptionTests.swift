import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

/// Calculs, plafonds, quota Codex, relevés et pause.
@MainActor
final class ConsumptionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func event(
        _ id: String, minutesAgo: Double, bank: String = "a", op: String = "retain", provider: String = "gemini",
        model: String = "gemini-3.8-flash", doc: String = "", input: Int = 1_000_000, output: Int = 0, failed: Bool = false
    ) -> ConsumptionEvent {
        ConsumptionEvent(
            id: id, date: t0.addingTimeInterval(-minutesAgo * 60), bank: bank, operation: op, provider: provider, model: model,
            document: doc, tokens: TokenCount(input: input, output: output), failed: failed)
    }

    func testTotalsSplitBillingAndWindowsUseDates() async {
        let events = [
            event("old", minutesAgo: 600),
            event("api", minutesAgo: 30),
            event("sub", minutesAgo: 20, provider: "openai-codex", model: "gpt-5", input: 1_000),
            event("local", minutesAgo: 10, provider: "ollama", model: "llama", input: 500),
            event("odd", minutesAgo: 2, provider: "acme", model: "mystery", input: 7, failed: true),
        ]
        let all = ConsumptionMath.totals(events, prices: .defaults)
        XCTAssertEqual(all.calls, 5)
        XCTAssertEqual(all.failures, 1)
        XCTAssertEqual(all.dollars, 0.6, accuracy: 1e-9, "deux millions de jetons Gemini Flash à 0,30 $")
        XCTAssertEqual(all.subscriptionTokens, 1_000)
        XCTAssertGreaterThan(all.subscriptionEquivalent, 0)
        XCTAssertEqual(all.localTokens, 500)
        XCTAssertEqual(all.unpricedTokens, 7)

        let hour = ConsumptionMath.since(events, t0.addingTimeInterval(-3_600))
        XCTAssertEqual(hour.map(\.id), ["api", "sub", "local", "odd"])
        let rate = ConsumptionMath.rate(events, now: t0, minutes: 5, prices: .defaults)
        XCTAssertEqual(rate.callsPerMinute, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rate.tokensPerMinute, 1.4, accuracy: 1e-9)

        let buckets = ConsumptionMath.buckets(events, from: t0.addingTimeInterval(-3_600), to: t0, step: 900, prices: .defaults)
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(buckets.map(\.calls), [0, 0, 2, 2])
        XCTAssertEqual(buckets[2].byOperation["retain"], 1_001_000)
        XCTAssertEqual(buckets[3].failures, 1)
    }

    func testBreakdownRanksByCostAndSkipsCallsWithoutDocument() async {
        let events = [
            event("1", minutesAgo: 5, bank: "a", doc: "doc:r:a.md", input: 3_000_000),
            event("2", minutesAgo: 4, bank: "b", doc: "doc:r:b.md", input: 1_000_000),
            event("3", minutesAgo: 3, bank: "b", op: "consolidation", input: 2_000_000),
        ]
        let docs = ConsumptionMath.breakdown(events, by: .document, prices: .defaults)
        XCTAssertEqual(
            docs.map { ConsumptionMath.splitDocumentKey($0.id).document }, ["doc:r:a.md", "doc:r:b.md"],
            "la consolidation n'est attribuée à aucun document")
        XCTAssertEqual(ConsumptionMath.splitDocumentKey(docs[0].id).bank, "a")
        XCTAssertEqual(docs[0].fraction, 0.75, accuracy: 1e-9)
        let banks = ConsumptionMath.breakdown(events, by: .bank, prices: .defaults)
        XCTAssertEqual(banks.map(\.id), ["a", "b"])
        XCTAssertEqual(banks[0].fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ConsumptionMath.breakdown(events, by: .operation, prices: .defaults).first?.id, "retain")
    }

    func testGaugesForDollarsSubscriptionsAndCodexQuota() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let events = [
            event("y", minutesAgo: 60 * 30),  // hier
            event("a", minutesAgo: 30, input: 2_000_000),
            event("s1", minutesAgo: 60 * 4, provider: "openai-codex", model: "gpt-5", input: 70_000),
            event("s2", minutesAgo: 60 * 6, provider: "openai-codex", model: "gpt-5", input: 50_000),
        ].sorted { $0.date < $1.date }
        let budgets = ConsumptionBudgets(
            dailyDollars: 0.5, subscriptions: ["openai-codex": .init(tokens5h: 80_000, tokensWeek: 1_000_000)], codexQuotaPercent: 90)
        let codex = CodexQuota(
            primary: .init(usedPercent: 95, windowMinutes: 300, resetsAt: t0.addingTimeInterval(600)),
            secondary: .init(usedPercent: 50, windowMinutes: 10_080, resetsAt: t0.addingTimeInterval(-60)), observedAt: t0)
        let g = Dictionary(
            uniqueKeysWithValues: ConsumptionMath.gauges(events, budgets: budgets, prices: .defaults, codex: codex, now: t0, calendar: calendar).map {
                ($0.id, $0)
            })
        XCTAssertEqual(g["dollars.day"]?.used ?? 0, 0.6, accuracy: 1e-9, "seul l'appel d'aujourd'hui compte")
        XCTAssertEqual(g["dollars.day"]?.level, .exceeded)
        XCTAssertEqual(g["sub.openai-codex.5h"]?.used, 70_000, "fenêtre glissante de 5 h")
        XCTAssertEqual(g["sub.openai-codex.5h"]?.level, .warning)
        XCTAssertEqual(g["sub.openai-codex.week"]?.used, 120_000)
        XCTAssertEqual(g["sub.openai-codex.week"]?.level, .ok)
        XCTAssertEqual(g["codex.primary"]?.level, .exceeded)
        XCTAssertEqual(g["codex.secondary"]?.used, 0, "fenêtre réinitialisée depuis le relevé")
        XCTAssertEqual(ConsumptionBudgets().effectiveAction, .alert, "sans confirmation, l'app se contente d'alerter")
    }

    func testMenuBarReadingPrefersClaudeFiveHourGauge() {
        func gauge(_ id: String, _ used: Double, _ level: BudgetGauge.Level = .ok) -> BudgetGauge {
            BudgetGauge(id: id, title: id, used: used, limit: 1_000_000, unit: .tokens, level: level, resetsAt: nil, note: nil)
        }
        var busy = ConsumptionMath.Rate()
        busy.callsPerMinute = 2
        let idle = ConsumptionMath.Rate()

        let none = MenuBarReading.make(gauges: [], subscriptionTokens5h: 1_234_567, rate: idle, processing: 0)
        XCTAssertEqual(none.text, "1,2 M", "sans plafond 5 h : les jetons d'abonnement")
        XCTAssertFalse(none.isWorking)

        let both = [gauge("sub.openai-codex.5h", 900_000), gauge("dollars.day", 1), gauge("sub.claude-code.5h", 234_000)]
        let r = MenuBarReading.make(gauges: both, subscriptionTokens5h: 0, rate: busy, processing: 0)
        XCTAssertEqual(r.text, "23 %", "la jauge Claude Code passe devant")
        XCTAssertTrue(r.isWorking)
        XCTAssertTrue(r.spoken.contains("23 %"))

        let over = MenuBarReading.make(
            gauges: [gauge("sub.claude-code.5h", 1_100_000, .exceeded)], subscriptionTokens5h: 0, rate: idle, processing: 3)
        XCTAssertEqual(over.text, "⚠︎ 110 %")
        XCTAssertEqual(over.level, .exceeded)
        XCTAssertTrue(over.isWorking, "des opérations en cours suffisent")
    }

    func testBudgetsSurviveSavingAndOlderSettings() async {
        let store = InMemorySettingsStore()
        var b = ConsumptionBudgets(dailyDollars: 2, action: .freezeQueue, actionConfirmed: true)
        b.subscriptions["claude-code"] = .init(tokens5h: 100)
        b.save(to: store)
        XCTAssertEqual(ConsumptionBudgets.load(from: store), b)
        store.set(#"{"dailyDollars":3}"#, forKey: "consumptionBudgets")
        let old = ConsumptionBudgets.load(from: store)
        XCTAssertEqual(old.dailyDollars, 3)
        XCTAssertEqual(old.warnAt, 0.8)
        ConsumptionBudgets().save(to: store)
        XCTAssertNil(store.string(forKey: "consumptionBudgets"))
    }

    // MARK: Quota Codex

    func testCodexRateLimitFormats() async throws {
        let modern = #"{"timestamp":"2026-10-21T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1792586400},"secondary":{"used_percent":12,"window_minutes":10080,"resets_in_seconds":3600}}}}"#
        let q = try XCTUnwrap(CodexRateLimits.parse(line: modern))
        XCTAssertEqual(q.primary?.usedPercent, 42.5)
        XCTAssertEqual(q.primary?.title, "5 h")
        XCTAssertEqual(q.primary?.resetsAt, Date(timeIntervalSince1970: 1_792_586_400))
        XCTAssertEqual(q.secondary?.title, "semaine")
        XCTAssertEqual(q.secondary?.resetsAt, HSDate.parse("2026-10-21T11:00:00Z"), "délai relatif au relevé")
        XCTAssertEqual(q.observedAt, HSDate.parse("2026-10-21T10:00:00Z"))

        let flat = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary_used_percent":7,"secondary_used_percent":3,"primary_window_minutes":299}}}"#
        let f = try XCTUnwrap(CodexRateLimits.parse(line: flat, fallbackDate: t0))
        XCTAssertEqual(f.primary?.usedPercent, 7)
        XCTAssertEqual(f.observedAt, t0)
        XCTAssertNil(CodexRateLimits.parse(line: #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":null}}"#))
        XCTAssertNil(CodexRateLimits.parse(line: "pas du JSON"))
    }

    func testReadsLatestQuotaFromNewestSessionWithoutWriting() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let old = home.appendingPathComponent("sessions/2026/10/19")
        let new = home.appendingPathComponent("sessions/2026/10/21")
        for d in [old, new] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        func line(_ p: Double) -> String {
            #"{"timestamp":"2026-10-21T09:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(p),"window_minutes":300}}}}"#
        }
        let filler = String(repeating: #"{"type":"response_item","payload":{"text":"x"}}"# + "\n", count: 2_000)
        try (line(10) + "\n").write(to: old.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
        let newest = new.appendingPathComponent("rollout-b.jsonl")
        try (line(55) + "\n" + filler + line(61) + "\n" + filler).write(to: newest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: old.appendingPathComponent("rollout-a.jsonl").path)
        let before = try Data(contentsOf: newest)

        XCTAssertEqual(CodexRateLimits.latestSessionFile(codexHome: home)?.lastPathComponent, "rollout-b.jsonl")
        XCTAssertEqual(CodexRateLimits.latest(codexHome: home)?.primary?.usedPercent, 61, "le relevé le plus récent du fichier")
        XCTAssertEqual(try Data(contentsOf: newest), before)
        XCTAssertEqual(CodexRateLimits.codexHome(environment: ["CODEX_HOME": "/opt/cx"], home: "/h").path, "/opt/cx")
        XCTAssertEqual(CodexRateLimits.codexHome(environment: [:], home: "/h").path, "/h/.codex")
    }

    // MARK: Relevés

    func traces(_ items: [(id: String, doc: String?, start: String)]) -> String {
        let rows = items.map { i in
            let meta = i.doc.map { #"{"document_id":"\#($0)"}"# } ?? "{}"
            return #"{"id":"\#(i.id)","status":"success","operation":"retain","provider":"gemini","model":"gemini-3.8-flash","started_at":"\#(i.start)","input_tokens":1000000,"output_tokens":0,"llm_info":{},"metadata":\#(meta)}"#
        }
        return #"{"bank_id":"b","total":\#(items.count),"limit":200,"offset":0,"items":[\#(rows.joined(separator: ","))]}"#
    }

    func testPollingReadsNewTracesOnceRecordsDocumentsAndAlertsOnCrossing() async throws {
        let t = MockTransport()
        let now = HSDate.parse("2026-10-21T12:00:00Z")!
        let body = Lock(traces([("t1", "doc:r:a.md", "2026-10-21T11:58:00Z")]))
        t.on("GET", "\(bankPath)/llm-requests") { _ in .json(body.value) }
        t.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":3,"limit":1,"offset":0,"operations":[]}"#)
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: ledgerURL) }
        let store = InMemorySettingsStore()
        let monitor = ConsumptionMonitor(
            settings: store, client: { makeClient(t) }, banks: { [testBank] }, ledger: UsageLedger(url: ledgerURL),
            prices: { .defaults }, now: { now }, codex: { nil })
        var alerts: [ConsumptionAlert] = []
        var actions: [ConsumptionBudgets.Action] = []
        monitor.onAlert = { alerts.append($0) }
        monitor.onExceeded = { _, action in actions.append(action) }
        monitor.budgets = ConsumptionBudgets(dailyDollars: 0.35, action: .softPause, actionConfirmed: true)

        await monitor.poll()
        XCTAssertEqual(monitor.events.map(\.id), ["t1"])
        XCTAssertEqual(monitor.events.first?.document, "doc:r:a.md")
        XCTAssertEqual(monitor.summary.today.dollars, 0.3, accuracy: 1e-9)
        XCTAssertEqual(monitor.queues.first?.pending, 3)
        XCTAssertEqual(monitor.gauges.first?.level, .warning)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertNotNil(t.requests.first { $0.path.hasSuffix("/llm-requests") }?.queryValue("start_date"))

        // Même trace relue (recouvrement) et une nouvelle : la première n'est pas comptée deux fois.
        body.value = traces([("t2", nil, "2026-10-21T11:59:00Z"), ("t1", "doc:r:a.md", "2026-10-21T11:58:00Z")])
        await monitor.poll()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(monitor.events.map(\.id), ["t1", "t2"])
        XCTAssertEqual(monitor.gauges.first?.level, .exceeded)
        XCTAssertEqual(alerts.count, 2, "une alerte par seuil franchi")
        XCTAssertEqual(actions, [.softPause])
        await monitor.poll()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(alerts.count, 2, "pas de nouvelle alerte tant que le niveau ne change pas")
        XCTAssertEqual(actions.count, 1, "reprendre à la main n'est pas annulé au relevé suivant")
        let start = try XCTUnwrap(t.requests.last { $0.path.hasSuffix("/llm-requests") }?.queryValue("start_date"))
        XCTAssertEqual(
            HSDate.parse(start), HSDate.parse("2026-10-21T11:55:00Z"),
            "reprise à la dernière trace, moins la durée des appels les plus longs (4 min sans durée connue)")

        // Historique local : un nouveau suivi repart de ce qui a été vu.
        let again = ConsumptionMonitor(
            settings: store, client: { makeClient(t) }, banks: { [] }, ledger: UsageLedger(url: ledgerURL), prices: { .defaults }, now: { now },
            codex: { nil })
        await again.poll()
        XCTAssertEqual(again.events.map(\.id), ["t1", "t2"])
        XCTAssertEqual(again.documentTotals("doc:r:a.md")?.calls, 1)
    }

    func testUsageRecordKeepsDocumentAndReadsOlderLedger() async throws {
        let e = LLMRequestEntry(id: "x", status: "success", startedAt: "2026-10-21T10:00:00Z", llmInfo: [:], metadata: ["document_id": .string("doc:r:a.md")])
        let r = UsageRecord(e, bank: "b")
        XCTAssertEqual(r.documentID, "doc:r:a.md")
        let decoded = try JSONDecoder().decode(UsageRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded.documentID, "doc:r:a.md")
        let older = #"{"id":"y","bank":"b","day":"2026-10-20","operation":"retain","provider":"p","model":"m","input":1,"output":2,"cached":0,"thoughts":0,"failed":false}"#
        let o = try JSONDecoder().decode(UsageRecord.self, from: Data(older.utf8))
        XCTAssertEqual(o.documentID, "")
        XCTAssertNotNil(ConsumptionEvent(o), "sans horodatage, le jour suffit")
    }

    // MARK: Pause

    func pauseFixture(autoConsolidation: Bool = true, explicit: Bool = false) -> (PauseController, MockTransport, InMemorySettingsStore) {
        let t = MockTransport()
        let overrides = explicit ? #"{"enable_auto_consolidation":\#(autoConsolidation)}"# : "{}"
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"b","config":{"enable_auto_consolidation":\#(autoConsolidation)},"overrides":\#(overrides)}"#)
        t.on("PATCH", "\(bankPath)/config", json: #"{"bank_id":"b","config":{},"overrides":{}}"#)
        let store = InMemorySettingsStore()
        let c = PauseController(settings: store, client: { makeClient(t) }, banks: { [testBank] }, service: { nil }, server: { "http://s1" })
        return (c, t, store)
    }

    func testPauseHoldsConsolidationBlocksSendsAndResumeRestoresIt() async throws {
        let (c, t, store) = pauseFixture()
        await c.pause(bank: testBank, reason: nil)
        XCTAssertTrue(c.isPaused(testBank))
        XCTAssertEqual(c.heldBanks, [testBank])
        XCTAssertNotNil(c.blockReason(testBank))
        XCTAssertNil(c.blockReason("autre"))
        let patch = try XCTUnwrap(t.requests.last { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(patch["updates"]?["enable_auto_consolidation"], .bool(false))

        // L'état survit au redémarrage de l'app.
        let reopened = PauseController(settings: store, client: { makeClient(t) }, banks: { [testBank] }, service: { nil })
        XCTAssertTrue(reopened.isPaused(testBank))

        // Une pause globale par-dessus ne mémorise pas une seconde fois l'état d'avant.
        await c.pause(bank: nil, reason: nil)
        XCTAssertEqual(t.requests.filter { $0.method == "PATCH" }.count, 1)
        await c.resume(bank: testBank)
        XCTAssertTrue(c.isPaused(testBank), "toujours concernée par la pause globale")
        XCTAssertEqual(t.requests.filter { $0.method == "PATCH" }.count, 1)
        await c.resume(bank: nil)
        XCTAssertFalse(c.anyPause)
        XCTAssertEqual(
            t.requests.last { $0.method == "PATCH" }?.bodyJSON?["updates"]?["enable_auto_consolidation"], .null,
            "elle suivait la valeur du serveur : la banque y revient, sans réglage propre")
        XCTAssertTrue(c.heldBanks.isEmpty)
    }

    func testExplicitSettingIsRestoredAndOnlyGlobalPauseIsLifted() async throws {
        let (c, t, _) = pauseFixture(explicit: true)
        await c.pause(bank: testBank, reason: nil)
        await c.pause(bank: nil, reason: nil)
        await c.resume(bank: nil)
        XCTAssertTrue(c.isPaused(testBank), "« Reprendre » ne lève que la pause de toutes les banques")
        XCTAssertEqual(t.requests.filter { $0.method == "PATCH" }.count, 1)
        await c.resume(bank: testBank)
        XCTAssertEqual(t.requests.last { $0.method == "PATCH" }?.bodyJSON?["updates"]?["enable_auto_consolidation"], .bool(true))
    }

    func testPauseIsCaughtUpWhenTheServerAnswersAgain() async throws {
        let t = MockTransport()
        let up = Lock(false)
        t.on("GET", "\(bankPath)/config") { _ in
            up.value ? .json(#"{"bank_id":"b","config":{"enable_auto_consolidation":true},"overrides":{}}"#) : .json(#"{"detail":"down"}"#, status: 503)
        }
        t.on("PATCH", "\(bankPath)/config") { _ in
            up.value ? .json(#"{"bank_id":"b","config":{},"overrides":{}}"#) : .json(#"{"detail":"down"}"#, status: 503)
        }
        let banks = Lock<[String]>([])
        let c = PauseController(settings: InMemorySettingsStore(), client: { makeClient(t) }, banks: { banks.value }, service: { nil }, server: { "http://s1" })
        // Lancée serveur injoignable : aucune banque connue.
        await c.pause(bank: nil, reason: nil)
        XCTAssertTrue(c.message?.contains("dès que le serveur répondra") == true)
        XCTAssertTrue(t.requests.isEmpty)
        // Le serveur répond, les banques se chargent : la consolidation est coupée.
        up.value = true
        banks.value = [testBank]
        await c.reconcile()
        XCTAssertEqual(c.heldBanks, [testBank])
        // Reprise pendant une panne : rien n'est perdu, la remise en état attend.
        up.value = false
        await c.resume(bank: nil)
        XCTAssertFalse(c.anyPause)
        XCTAssertTrue(c.message?.contains("À rétablir") == true)
        XCTAssertEqual(c.heldBanks, [testBank])
        up.value = true
        await c.reconcile()
        XCTAssertTrue(c.heldBanks.isEmpty)
        XCTAssertEqual(t.requests.last { $0.method == "PATCH" }?.bodyJSON?["updates"]?["enable_auto_consolidation"], .null)
    }

    func testHeldBanksBelongToTheirServer() async {
        let (c, _, store) = pauseFixture()
        await c.pause(bank: testBank, reason: nil)
        let other = PauseController(settings: store, client: { makeClient(MockTransport()) }, banks: { [testBank] }, service: { nil }, server: { "http://s2" })
        XCTAssertTrue(other.heldBanks.isEmpty, "une banque du même nom sur un autre serveur n'est pas concernée")
        XCTAssertEqual(c.heldBanks, [testBank])
    }

    func testResumeAllLiftsGlobalAndPerBankPauses() async {
        let (c, t, store) = pauseFixture()
        await c.pause(bank: testBank, reason: nil)
        await c.pause(bank: nil, reason: "Plafond atteint")
        XCTAssertEqual(c.autoReason, "Plafond atteint")
        await c.resumeAll()
        XCTAssertFalse(c.anyPause)
        XCTAssertNil(c.autoReason)
        XCTAssertNil(c.since)
        XCTAssertEqual(t.requests.filter { $0.method == "PATCH" }.count, 2, "coupée une fois, rétablie une fois")
        XCTAssertNil(store.string(forKey: "pause.banks"))
        XCTAssertNil(store.string(forKey: "pause.held"))
    }

    func testPauseLeavesDisabledConsolidationAlone() async {
        let (c, t, _) = pauseFixture(autoConsolidation: false, explicit: true)
        await c.pause(bank: testBank, reason: nil)
        await c.resume(bank: testBank)
        XCTAssertFalse(t.requests.contains { $0.method == "PATCH" }, "elle était déjà coupée : rien à rétablir")
    }

    func testDrainCancelsPendingOperationsAfterTypedConfirmation() async throws {
        let (c, t, _) = pauseFixture()
        let ops = (1...12).map { #"{"id":"op\#($0)","task_type":"retain","items_count":1,"status":"pending","created_at":"","updated_at":""}"# }
        t.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":12,"limit":100,"offset":0,"operations":[\#(ops.joined(separator: ","))]}"#)
        t.on("DELETE", "\(bankPath)/operations/*", json: #"{"success":true,"message":"ok","operation_id":"x"}"#)
        await c.requestDrain(bank: nil)
        let confirmation = try XCTUnwrap(c.confirmation)
        XCTAssertEqual(confirmation.requiredText, "vider", "au-delà de dix opérations, il faut retaper")
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/operations") }?.queryValue("status"), "pending")
        XCTAssertFalse(t.requests.contains { $0.method == "DELETE" })
        await confirmation.perform()
        XCTAssertEqual(t.requests.filter { $0.method == "DELETE" }.count, 12)
        XCTAssertEqual(c.message, "12 opérations annulées.")
    }

    /// File de test : rafraîchissements de pages (`mm1` deux fois en attente et une fois en cours, `mm2` une fois)
    /// et une extraction, servis selon le statut demandé.
    func serveRefreshQueue(_ t: MockTransport) {
        func op(_ id: String, _ type: String, _ status: String, _ mm: String?, _ created: String) -> String {
            let model = mm.map { #","mental_model_id":"\#($0)""# } ?? ""
            return #"{"id":"\#(id)","task_type":"\#(type)","items_count":1,"status":"\#(status)","created_at":"\#(created)"\#(model)}"#
        }
        let all = [
            ("r1", "refresh_mental_model", "pending", "mm1", "2026-10-21T10:00:00Z"),
            ("r2", "refresh_mental_model", "pending", "mm1", "2026-10-21T11:00:00Z"),
            ("r3", "refresh_mental_model", "processing", "mm1", "2026-10-21T09:00:00Z"),
            ("r4", "refresh_mental_model", "pending", "mm2", "2026-10-21T10:00:00Z"),
            ("x1", "batch_retain", "pending", nil, "2026-10-21T10:00:00Z"),
        ].map { (status: $0.2, json: op($0.0, $0.1, $0.2, $0.3, $0.4)) }
        t.on("GET", "\(bankPath)/operations") { req in
            let status = req.queryValue("status")
            let ops = all.filter { $0.status == status }.map(\.json)
            return .json(#"{"bank_id":"b","total":\#(ops.count),"limit":100,"offset":0,"operations":[\#(ops.joined(separator: ","))]}"#)
        }
        t.on("DELETE", "\(bankPath)/operations/*", json: #"{"success":true,"message":"ok","operation_id":"x"}"#)
    }

    func testPauseCancelsPageRefreshesButNotTheRestOfTheQueue() async throws {
        let (c, t, _) = pauseFixture()
        serveRefreshQueue(t)
        await c.pause(bank: testBank, reason: nil)
        let cancelled = t.requests.filter { $0.method == "DELETE" }.compactMap { $0.path.split(separator: "/").last.map(String.init) }
        XCTAssertEqual(Set(cancelled), ["r1", "r2", "r3", "r4"], "en cours compris ; l'extraction continue")
        XCTAssertTrue(c.message?.contains("4 rafraîchissements de modèles mentaux annulés") == true, c.message ?? "")

        // Pendant la pause, ce qui arrive est annulé à son tour ; après la reprise, plus rien n'est touché.
        let again = await c.sweepRefreshes()
        XCTAssertEqual(again, 4)
        await c.resume(bank: testBank)
        let before = t.requests.count
        let after = await c.sweepRefreshes()
        XCTAssertEqual(after, 0)
        XCTAssertEqual(t.requests.count, before)
    }

    func testDuplicateRefreshesKeepOnePerPageAfterConfirmation() async throws {
        let (c, t, _) = pauseFixture()
        serveRefreshQueue(t)
        await c.requestCancelDuplicateRefreshes(bank: testBank)
        let confirmation = try XCTUnwrap(c.confirmation)
        XCTAssertTrue(confirmation.message.contains("1 modèle mental est"), confirmation.message)
        XCTAssertFalse(t.requests.contains { $0.method == "DELETE" }, "rien avant la confirmation")
        await confirmation.perform()
        let cancelled = t.requests.filter { $0.method == "DELETE" }.compactMap { $0.path.split(separator: "/").last.map(String.init) }
        XCTAssertEqual(Set(cancelled), ["r1", "r2"], "mm1 garde celui en cours ; mm2 n'a pas de doublon")
        XCTAssertEqual(c.message, "2 opérations annulées.")
    }

    func testDuplicateRefreshesKeepTheNewestPendingWhenNoneRuns() {
        let ops = [("a", "2026-10-21T10:00:00Z"), ("b", "2026-10-21T12:00:00Z"), ("c", "2026-10-21T11:00:00Z")].map {
            OperationResponse(id: $0.0, taskType: "refresh_mental_model", itemsCount: 1, mentalModelId: "mm", createdAt: $0.1, status: "pending")
        }
        let found = PauseController.duplicateRefreshes(ops + [OperationResponse(id: "z", taskType: "refresh_mental_model", itemsCount: 1, createdAt: "", status: "pending")])
        XCTAssertEqual(found.cancel, ["a", "c"])
        XCTAssertEqual(found.pages, 1, "sans page connue, rien n'est compté ni annulé")
    }

    func testAutomaticActionAndFreezeFallback() async {
        let (c, t, _) = pauseFixture()
        await c.apply(.alert, reason: "x")
        XCTAssertFalse(c.anyPause)
        // Sans service géré par l'app, le gel retombe sur la pause.
        XCTAssertFalse(c.canFreeze)
        await c.apply(.freezeQueue, reason: "Plafond atteint")
        XCTAssertTrue(c.globalPause)
        XCTAssertEqual(c.autoReason, "Plafond atteint")
        XCTAssertTrue(t.requests.contains { $0.method == "PATCH" })
        c.requestFreeze()
        XCTAssertNil(c.confirmation)
        XCTAssertTrue(c.message?.contains("HINDSIGHT_API_WORKER_ENABLED=false") == true)
    }

    func testGatedActionsRefuseWhileBankIsPaused() async throws {
        let (c, t, _) = pauseFixture()
        await c.pause(bank: testBank, reason: nil)
        let ops = OperationsViewModel(client: makeClient(t), bank: testBank)
        ops.pauseGate = c.gate
        ops.requestConsolidation()
        XCTAssertNil(ops.confirmation)
        XCTAssertEqual(ops.actionMessage, c.blockReason(testBank))

        let coverage = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(t) }, bank: { testBank })
        coverage.pauseGate = c.gate
        await coverage.requestSend()
        XCTAssertNil(coverage.confirmation)
        XCTAssertNotNil(coverage.actionMessage)
    }
}

extension ConsumptionTests {
    func testBudgetAmountsRejectWhatWouldCrash() async {
        XCTAssertEqual(ConsumptionBudgets.parseAmount("200k"), 200_000)
        XCTAssertEqual(ConsumptionBudgets.parseAmount(" 1,5 "), 1.5)
        XCTAssertEqual(ConsumptionBudgets.parseAmount("1.5M"), 1_500_000)
        for bad in ["", "abc", "-3", "0", "inf", "nan", "1e19", "99999999999999999999"] {
            XCTAssertNil(ConsumptionBudgets.parseAmount(bad), bad)
        }
        XCTAssertEqual(ConsumptionBudgets.amountText(5), "5")
        XCTAssertEqual(ConsumptionBudgets.amountText(1e19), "", "une valeur aberrante déjà enregistrée ne fait pas planter la feuille")
    }

    func testCodexQuotaIsKeptWhenTheNewestSessionHasNoReading() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let day = home.appendingPathComponent("sessions/2026/10/21")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let older = day.appendingPathComponent("rollout-old.jsonl")
        try (#"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":33,"window_minutes":300}}}}"# + "\n").write(to: older, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: older.path)
        try (#"{"type":"session_meta","payload":{"id":"x"}}"# + "\n").write(to: day.appendingPathComponent("rollout-new.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexRateLimits.latest(codexHome: home)?.primary?.usedPercent, 33, "la session qui vient de commencer n'a pas encore de relevé")

        let readings = Lock<[CodexQuota?]>([CodexQuota(primary: .init(usedPercent: 95, windowMinutes: 300), secondary: nil, observedAt: t0), nil])
        let t = MockTransport()
        t.on("GET", "\(bankPath)/llm-requests", json: #"{"bank_id":"b","total":0,"limit":200,"offset":0,"items":[]}"#)
        let monitor = ConsumptionMonitor(
            settings: InMemorySettingsStore(), client: { makeClient(t) }, banks: { [testBank] }, ledger: nil, prices: { .defaults }, now: { [t0] in t0 },
            codex: { readings.value.isEmpty ? nil : readings.value.removeFirst() })
        var alerts = 0
        monitor.onAlert = { _ in alerts += 1 }
        monitor.budgets = ConsumptionBudgets(codexQuotaPercent: 90)
        await monitor.poll()
        XCTAssertEqual(alerts, 1)
        await monitor.poll()
        XCTAssertEqual(monitor.codexQuota?.primary?.usedPercent, 95, "le dernier relevé connu reste affiché")
        await monitor.poll()
        XCTAssertEqual(alerts, 1, "pas de nouvelle alerte faute de relevé")
    }

    func testDayBucketsFollowTheCalendarAcrossDaylightSaving() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        // Mardi 27 octobre 2026, midi à Paris ; l'heure d'hiver est revenue le dimanche 25.
        let now = HSDate.parse("2026-10-27T11:00:00Z")!
        let bounds = ConsumptionMath.dayBoundaries(endingWith: now, days: 7, calendar: calendar)
        XCTAssertEqual(bounds.count, 8)
        let sunday = bounds.firstIndex { calendar.component(.day, from: $0) == 25 }!
        XCTAssertEqual(bounds[sunday + 1].timeIntervalSince(bounds[sunday]), 25 * 3_600, "le dimanche du changement d'heure dure 25 h")
        XCTAssertTrue(bounds.allSatisfy { calendar.component(.hour, from: $0) == 0 }, "chaque tranche commence à minuit")
        let late = ConsumptionEvent(id: "s", date: HSDate.parse("2026-10-25T22:30:00Z")!, bank: "a", operation: "retain", provider: "p", model: "m", tokens: TokenCount(input: 5))
        let buckets = ConsumptionMath.buckets([late], boundaries: bounds, prices: .defaults)
        XCTAssertEqual(buckets[sunday].calls, 1, "23 h 30 le dimanche reste le dimanche")
    }

    func testDocumentCostStaysWithinItsBank() async {
        let monitor = ConsumptionMonitor(
            settings: InMemorySettingsStore(), client: { makeClient(MockTransport()) }, banks: { [] }, ledger: nil, prices: { .defaults },
            now: { [t0] in t0 }, codex: { nil })
        let doc = "doc:r:a.md"
        let items = [event("1", minutesAgo: 3, bank: "a", doc: doc), event("2", minutesAgo: 2, bank: "b", doc: doc), event("3", minutesAgo: 1, bank: "b", doc: doc)]
        monitor.ingestForTesting(items)
        XCTAssertEqual(monitor.documentCost([doc], bank: "a")?.calls, 1)
        XCTAssertEqual(monitor.documentCost([doc], bank: "b")?.calls, 2)
        let rows = monitor.breakdown(.hour, by: .document)
        XCTAssertEqual(rows.count, 2, "même identifiant, deux banques : deux documents")
        XCTAssertEqual(Set(rows.map { ConsumptionMath.splitDocumentKey($0.id).bank }), ["a", "b"])
    }

    func testEmbeddingRerankAndDecisionCallsStayOutOfTheCount() async throws {
        XCTAssertEqual(ModelCallKind(scope: "embedding_query"), .embedding)
        XCTAssertEqual(ModelCallKind(scope: "rerank"), .rerank)
        XCTAssertEqual(ModelCallKind(scope: "decision_recall"), .decision)
        XCTAssertEqual(ModelCallKind(scope: "memory_extraction"), .llm)
        XCTAssertEqual(ModelCallKind(scope: nil), .llm, "serveur 1.0.0 : pas de scope, appel LLM")

        let t = MockTransport()
        let now = HSDate.parse("2026-10-21T12:00:00Z")!
        let row = { (id: String, scope: String) in
            #"{"id":"\#(id)","scope":"\#(scope)","status":"success","operation":"retain","provider":"claude-code","model":"m","started_at":"2026-10-21T11:58:00Z","input_tokens":5000,"output_tokens":100,"llm_info":{},"metadata":{}}"#
        }
        let rows = [row("llm", "memory_extraction"), row("emb", "embedding_document"), row("rr", "rerank"), row("dec", "decision_recall")]
        t.on("GET", "\(bankPath)/llm-requests", json: #"{"bank_id":"b","total":4,"limit":200,"offset":0,"items":[\#(rows.joined(separator: ","))]}"#)
        t.on("GET", "\(bankPath)/operations", json: #"{"bank_id":"b","total":0,"limit":1,"offset":0,"operations":[]}"#)
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: ledgerURL) }
        let ledger = UsageLedger(url: ledgerURL)
        let monitor = ConsumptionMonitor(
            settings: InMemorySettingsStore(), client: { makeClient(t) }, banks: { [testBank] }, ledger: ledger, prices: { .defaults },
            now: { now }, codex: { nil })
        await monitor.poll()
        XCTAssertEqual(monitor.events.map(\.id), ["llm"], "seul l'appel LLM compte")
        XCTAssertEqual(monitor.summary.last5h.subscriptionTokens, 5_100)
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/llm-requests") }?.queryValue("call_type"), "llm")
        await ledger.flushIfDue(now: now.addingTimeInterval(3_600))
        let kept = await ledger.records(bank: nil, since: nil).map(\.id)
        XCTAssertEqual(kept, ["llm"], "le registre local non plus")

        let entries = rows.compactMap { try? JSONDecoder().decode(LLMRequestEntry.self, from: Data($0.utf8)) }
        XCTAssertEqual(UsageProfile.from(entries).operations["retain"]?.calls, 1, "les estimations ne moyennent que les appels LLM")
    }

    func testLedgerWritesAtMostOncePerInterval() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let ledger = UsageLedger(url: url)
        await ledger.setSaveInterval(300)
        let now = HSDate.parse("2026-10-21T12:00:00Z")!
        func entry(_ id: String) -> LLMRequestEntry { LLMRequestEntry(id: id, status: "success", startedAt: "2026-10-21T11:00:00Z", llmInfo: [:], metadata: [:]) }
        await ledger.merge([entry("a")], bank: "b", now: now)
        await ledger.merge([entry("b")], bank: "b", now: now.addingTimeInterval(10))
        let onDisk = try JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: url))
        XCTAssertEqual(onDisk.map(\.id), ["a"], "le second ajout attend la fin de l'intervalle")
        await ledger.flushIfDue(now: now.addingTimeInterval(301))
        XCTAssertEqual(try JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: url)).map(\.id).sorted(), ["a", "b"])
    }
}

/// Valeur partagée entre le test et un faux serveur.
final class Lock<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
