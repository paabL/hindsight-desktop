import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class ConsolidationViewModelTests: XCTestCase {
    func make(_ t: MockTransport) -> ConsolidationViewModel {
        ConsolidationViewModel(client: makeClient(t), bank: testBank)
    }

    func writes(_ t: MockTransport) -> [RecordedRequest] {
        t.requests.filter { $0.method != "GET" }
    }

    nonisolated func iso(_ secondsAgo: TimeInterval) -> String { HSDate.format(Date().addingTimeInterval(-secondsAgo)) }

    nonisolated func operation(_ id: String, status: String, createdAgo: TimeInterval, endedAgo: TimeInterval?, processed: Int?) -> String {
        let progress = processed.map { #","progress":{"stage":"consolidating","at":"\#(iso(endedAgo ?? 0))","processed":\#($0),"total":5000}"# } ?? ""
        let updated = endedAgo.map { #","updated_at":"\#(iso($0))""# } ?? ""
        return #"{"id":"\#(id)","task_type":"consolidation","items_count":0,"created_at":"\#(iso(createdAgo))","status":"\#(status)"\#(updated)\#(progress)}"#
    }

    nonisolated func operations(_ items: [String]) -> String {
        #"{"bank_id":"\#(testBank)","operations":[\#(items.joined(separator: ","))],"total":\#(items.count),"limit":20,"offset":0}"#
    }

    /// Aucune consolidation en cours ni en attente, aucun tour récent.
    func idleConsolidation(_ t: MockTransport) {
        t.on("GET", "\(bankPath)/operations", json: operations([]))
    }

    /// Une consolidation qui tourne depuis 20 minutes après deux tours de 100 faits.
    func runningConsolidation(_ t: MockTransport) {
        t.on("GET", "\(bankPath)/operations") { [self] request in
            switch request.queryValue("status") {
            case "processing":
                return .json(operations([operation("op-run", status: "processing", createdAgo: 1200, endedAgo: 0, processed: 50)]))
            case "completed":
                return .json(operations([
                    operation("op-2", status: "completed", createdAgo: 2400, endedAgo: 1200, processed: 100),
                    operation("op-1", status: "completed", createdAgo: 3000, endedAgo: 2400, processed: 100),
                ]))
            default:
                return .json(operations([]))
            }
        }
    }

    /// `updatedAt` : date fixe, comme sur le serveur tant que l'observation ne change pas.
    nonisolated func item(_ id: String, _ text: String, updatedAt: String, proofs: Int = 1) -> String {
        #"{"id":"\#(id)","text":"\#(text)","context":"","date":"2026-10-30T20:11:54Z","fact_type":"observation","entities":"","proof_count":\#(proofs),"tags":[],"metadata":{},"state":"active","updated_at":"\#(updatedAt)","source_memory_ids":["f-1"]}"#
    }

    /// Deux observations touchées dans la période : `obs-new` créée, `obs-upd` réécrite par un nouveau fait.
    func changes(_ t: MockTransport, created: Int = 12, touched: Int = 30) {
        let newAt = iso(60), updatedAt = iso(120), oldAt = iso(3000)
        t.on("GET", "\(bankPath)/memories/list") { [self] request in
            if request.queryValue("limit") == "1" {
                let total = request.queryValue("time_field") == "created_at" ? created : touched
                return .json(#"{"items":[],"total":\#(total),"limit":1,"offset":0}"#)
            }
            let offset = Int(request.queryValue("offset") ?? "0") ?? 0
            let items = offset == 0
                ? [item("obs-new", "L’essai E210 utilise le cache local.", updatedAt: newAt),
                   item("obs-upd", "Le temps moyen de proto/essai-3/web vaut 2,51 (E212, 21 octobre 2026).", updatedAt: updatedAt, proofs: 3)]
                : [item("obs-old", "Une observation plus ancienne.", updatedAt: oldAt)]
            return .json(#"{"items":[\#(items.joined(separator: ","))],"total":\#(touched),"limit":25,"offset":\#(offset)}"#)
        }
        t.on("GET", "\(bankPath)/memories/obs-new/history", json: "[]")
        t.on("GET", "\(bankPath)/memories/obs-old/history", json: "[]")
        t.on("GET", "\(bankPath)/memories/obs-upd/history", json: """
            [{"previous_text":"Le temps moyen de proto/essai-3/web vaut 2.4261 (E197, 2026-10-21).","previous_tags":[],"changed_at":"\(iso(120))",
              "new_source_memory_ids":["f-9"],
              "source_facts":[{"id":"f-1","text":"Ancien fait.","type":"world","is_new":false},
                              {"id":"f-9","text":"E212 donne un temps moyen de 2,51.","type":"world","context":"campagne","is_new":true}]},
             {"previous_text":"Durée de l’essai 3 inconnue.","previous_tags":[],"changed_at":"\(iso(90_000))","new_source_memory_ids":["f-1"],"source_facts":[]}]
            """)
    }

    // MARK: Chargement

    func testReloadReadsStatusPaceScopesAndChanges() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        runningConsolidation(t)
        changes(t)
        t.on("GET", "\(bankPath)/observations/scopes", json: #"{"scopes":[{"tags":[],"count":412}],"total":1,"limit":6,"offset":0}"#)
        let vm = make(t)
        await vm.reload()
        XCTAssertNotNil(vm.state.value)
        XCTAssertEqual(vm.status?.phase, .running)
        XCTAssertEqual(vm.rawFacts, 7600)
        XCTAssertEqual(vm.consolidatedFacts, 7600 - 250 - 7)
        // 250 faits en 50 minutes de travail : 300 faits par heure, 250 faits en attente → 50 minutes.
        let pace = try XCTUnwrap(vm.pace)
        XCTAssertEqual(pace.factsPerHour, 300, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(pace.remainingSeconds), 3000, accuracy: 40)
        XCTAssertEqual(vm.scopes?.scopes.first?.count, 412)
        XCTAssertEqual(vm.counts, ObservationChangeCounts(created: 12, touched: 30))
        XCTAssertEqual(vm.counts?.updated, 18)
        XCTAssertEqual(vm.changes.map(\.id), ["obs-new", "obs-upd"])
        XCTAssertEqual(vm.changes[0].kind, .created)
        let updated = vm.changes[1]
        XCTAssertEqual(updated.kind, .updated)
        XCTAssertEqual(updated.updates, 1)  // la mise à jour d'hier est hors période
        XCTAssertTrue(updated.textChanged)
        XCTAssertEqual(updated.previousText, "Le temps moyen de proto/essai-3/web vaut 2.4261 (E197, 2026-10-21).")
        XCTAssertEqual(updated.removedValues, ["2.4261", "E197"])  // la date est seulement reformulée
        XCTAssertEqual(updated.newSources.map(\.id), ["f-9"])
        XCTAssertEqual(updated.newSourceCount, 1)
        XCTAssertEqual(updated.proofCount, 3)
        XCTAssertTrue(vm.canLoadMore)
        XCTAssertTrue(vm.partialErrors.isEmpty, "\(vm.partialErrors)")
        // La période est la même pour les totaux et la liste : 24 h jusqu'au chargement.
        let lists = t.requests.filter { $0.path.hasSuffix("/memories/list") }
        XCTAssertEqual(Set(lists.compactMap { $0.queryValue("type") }), ["observation"])
        XCTAssertEqual(Set(lists.compactMap { $0.queryValue("time_field") }), ["created_at", "updated_at"])
        XCTAssertEqual(lists.first { $0.queryValue("limit") == "25" }?.queryValue("time_field"), "updated_at")
    }

    func testHistoryIsReadOncePerVersionOfAnObservation() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        changes(t)
        let vm = make(t)
        await vm.reload()
        let histories = { t.requests.filter { $0.path.hasSuffix("/history") }.count }
        XCTAssertEqual(histories(), 2)
        await vm.reload(silently: true)
        XCTAssertEqual(histories(), 2)  // rien n'a changé : historiques réutilisés
        await vm.setPeriod(.week)  // une autre période relit la liste, pas les historiques inchangés
        XCTAssertEqual(histories(), 2)
        XCTAssertEqual(vm.changes[1].updates, 2)  // sur 7 jours, les deux mises à jour comptent
        XCTAssertEqual(vm.changes[1].previousText, "Durée de l’essai 3 inconnue.")
    }

    func testMoreChangesComeFromTheSameWindow() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        changes(t)
        let vm = make(t)
        await vm.reload()
        await vm.loadMore()
        XCTAssertEqual(vm.changes.map(\.id), ["obs-new", "obs-upd", "obs-old"])
        let pages = t.requests.filter { $0.path.hasSuffix("/memories/list") && $0.queryValue("limit") == "25" }
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[1].queryValue("offset"), "2")
        XCTAssertEqual(pages[1].queryValue("end_date"), pages[0].queryValue("end_date"))
        XCTAssertEqual(pages[1].queryValue("start_date"), pages[0].queryValue("start_date"))
    }

    func testSecondarySourcesFailWithoutHidingTheView() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        t.on("GET", "\(bankPath)/memories/list", json: #"{"detail":"trop lent"}"#, status: 504)
        let vm = make(t)
        await vm.reload()
        XCTAssertNotNil(vm.state.value)
        XCTAssertEqual(vm.status?.phase, .pending)
        XCTAssertNil(vm.scopes)  // 404 : le serveur ne liste pas les portées, sans erreur
        XCTAssertEqual(vm.partialErrors.count, 1)
        XCTAssertTrue(vm.partialErrors[0].hasPrefix("changements : "), vm.partialErrors[0])

        // Une liste des portées en échec, autre qu'un 404, se signale aussi sans masquer la vue.
        t.on("GET", "\(bankPath)/observations/scopes", json: #"{"detail":"boom"}"#, status: 500)
        await vm.reload()
        XCTAssertNotNil(vm.state.value)
        XCTAssertEqual(vm.partialErrors.count, 2)
        XCTAssertTrue(vm.partialErrors.contains { $0.hasPrefix("portées : ") }, "\(vm.partialErrors)")
    }

    func testUnreadableHistoryClaimsNothing() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        changes(t)
        t.on("GET", "\(bankPath)/memories/obs-upd/history", json: #"{"detail":"boom"}"#, status: 500)
        let vm = make(t)
        await vm.reload()
        XCTAssertNil(vm.changes[1].kind)
        XCTAssertTrue(vm.changes[1].removedValues.isEmpty)
    }

    func testSourcesOfAnObservationAreReadFromTheServer() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/memories/obs-new", json: #"{"id":"obs-new","text":"x","source_memories":[{"id":"f-1","text":"E210 utilise le cache local.","type":"world","context":"notes"}]}"#)
        let vm = make(t)
        let sources = try await vm.sources(of: "obs-new")
        XCTAssertEqual(sources.map(\.text), ["E210 utilise le cache local."])
        XCTAssertEqual(sources.first?.context, "notes")
    }

    // MARK: Actions (déplacées de Traitements)

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
        // L'état a été relu après chaque action.
        XCTAssertGreaterThanOrEqual(t.requests.filter { $0.method == "GET" && $0.path.hasSuffix("/stats") }.count, 3)
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

    /// Sans observations, le serveur termine une consolidation sans rien traiter : rien n'est proposé.
    func testDisabledConsolidationIsRefusedWithoutConfirmationOrWrite() async {
        let t = MockTransport()
        t.installStandardRoutes()
        idleConsolidation(t)
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"\#(testBank)","config":{"enable_observations":false,"enable_auto_consolidation":true},"overrides":{"enable_observations":false}}"#)
        let vm = make(t)
        vm.serverObservations = true  // le réglage de la banque l'emporte sur celui du serveur
        await vm.reload()
        XCTAssertEqual(vm.status?.phase, .disabled)
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
        t.installStandardRoutes()
        runningConsolidation(t)
        let vm = make(t)
        await vm.reload()
        XCTAssertEqual(vm.status?.phase, .running)
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
        XCTAssertEqual(upToDate.status?.phase, .upToDate)
        XCTAssertNil(upToDate.pace)
        upToDate.requestConsolidation()
        XCTAssertNil(upToDate.confirmation)
        XCTAssertEqual(upToDate.actionMessage, "Rien à consolider : tous les faits de cette banque sont déjà consolidés.")
        upToDate.requestRecoverConsolidation()
        XCTAssertEqual(upToDate.actionMessage, "Aucun fait en échec de consolidation.")
        XCTAssertTrue(writes(idle).isEmpty)
    }

    func testPausedBankRefusesConsolidation() {
        let vm = make(MockTransport())
        vm.pauseGate = { _ in "Banque en pause." }
        vm.requestConsolidation()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, "Banque en pause.")
    }
}

/// Rythme, changements et valeurs : calculs purs.
final class ConsolidationAnalysisTests: XCTestCase {
    let now = HSDate.parse("2026-11-08T23:00:00Z")!

    func op(_ id: String, created: String, ended: String?, processed: Int?, status: String = "completed") -> OperationResponse {
        OperationResponse(
            id: id, taskType: "consolidation", itemsCount: 0, createdAt: created, updatedAt: ended, status: status,
            progress: processed.map { OperationProgress(stage: "consolidating", at: ended ?? created, processed: $0, total: 30_000) })
    }

    func testPaceFollowsChainedRoundsAndIgnoresQueueWaits() throws {
        // Créé à 12 h mais lancé seulement à la fin du tour précédent (21 h 50) : seule l'heure de travail compte.
        let rounds = [
            op("a", created: "2026-11-08T12:00:00Z", ended: "2026-11-08T22:20:00Z", processed: 100),
            op("b", created: "2026-11-08T22:20:00Z", ended: "2026-11-08T22:40:00Z", processed: 100),
        ]
        let running = op("c", created: "2026-11-08T22:40:00Z", ended: nil, processed: 100, status: "processing")
        let pace = try XCTUnwrap(ConsolidationPace.measure(completed: rounds, running: running, pendingFacts: 600, now: now))
        // Fenêtre 22 h – 23 h : 20 min du tour a (sur ses 10 h 20, soit ~3 faits), puis b et c entiers.
        XCTAssertEqual(pace.measuredSeconds, 3600, accuracy: 1)
        XCTAssertEqual(pace.factsPerHour, 203.2, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(pace.remainingSeconds) / 3600, 600 / 203.2, accuracy: 0.01)
    }

    func testPaceNeedsEnoughWorkInTheWindow() {
        let short = [op("a", created: "2026-11-08T22:57:00Z", ended: "2026-11-08T22:59:00Z", processed: 10)]
        XCTAssertNil(ConsolidationPace.measure(completed: short, running: nil, pendingFacts: 5, now: now))
        let old = [op("a", created: "2026-11-08T10:00:00Z", ended: "2026-11-08T11:00:00Z", processed: 100)]
        XCTAssertNil(ConsolidationPace.measure(completed: old, running: nil, pendingFacts: 5, now: now))
        let pace = ConsolidationPace.measure(
            completed: [op("a", created: "2026-11-08T22:00:00Z", ended: "2026-11-08T22:30:00Z", processed: 50)],
            running: nil, pendingFacts: 0, now: now)
        XCTAssertNil(pace?.remainingSeconds)  // rien en attente : pas de fin à annoncer
    }

    func testRemovedValuesToleratesRewordingButKeepsLosses() {
        XCTAssertEqual(ObservationValues.removed(
            from: "Le score vaut 0,0059 pour jeu_essai_4/serie_8 (n=1, lot 51200417).",
            to: "Le score vaut 0.0059 pour jeu_essai_4/serie_8 (n=1, lot 51200417)."), [])
        XCTAssertEqual(ObservationValues.removed(
            from: "Écart −14,5604 % mesuré le 2026-10-21.", to: "Écart de -14.5604 % mesuré le 21 octobre 2026."), [])
        XCTAssertEqual(ObservationValues.removed(
            from: "Les essais E078 à E083 ont 307 étapes ; source_horloge vaut interface_native.",
            to: "Les essais ont des étapes."), ["E078", "E083", "307", "source_horloge", "interface_native"])
        XCTAssertEqual(ObservationValues.removed(from: "Il y a 3 essais.", to: "Il y a trois essais."), [])  // un chiffre seul ne compte pas
        XCTAssertEqual(ObservationValues.removed(from: "E078–E083 terminés.", to: "E078 et E083 terminés."), [])
    }

    func testWordDiffRebuildsBothTexts() {
        let old = "Le temps moyen vaut 2.43 pour l’essai 3."
        let new = "Le temps total moyen vaut 2.51 pour l’essai 3."
        let diff = TextDiff.words(old, new)
        XCTAssertEqual(diff.filter { $0.kind != .added }.map(\.text).joined(), old)
        XCTAssertEqual(diff.filter { $0.kind != .removed }.map(\.text).joined(), new)
        XCTAssertEqual(diff.filter { $0.kind == .removed }.map { $0.text.trimmingCharacters(in: .whitespaces) }, ["2.43"])
        XCTAssertEqual(diff.filter { $0.kind == .added }.map { $0.text.trimmingCharacters(in: .whitespaces) }, ["total", "2.51"])
        XCTAssertEqual(TextDiff.words("", ""), [])
    }

    func testConfirmationKeepsTheTextAndNamesTheNewSource() throws {
        let item = MemoryUnitListItem(
            id: "o", text: "Même texte.", context: "", date: "2026-11-01T00:00:00Z", entities: "", proofCount: 2, tags: ["t"],
            metadata: [:], state: "active", updatedAt: "2026-11-08T22:59:00Z", sourceMemoryIds: ["f-1", "f-2"])
        let history = try JSONDecoder().decode(JSONValue.self, from: Data("""
            [{"previous_text":"Même  texte.","changed_at":"2026-11-08T22:59:00Z","new_source_memory_ids":["f-2"],
              "source_facts":[{"id":"f-2","text":"Le même fait, redit.","type":"experience","is_new":true}]}]
            """.utf8))
        let change = ObservationChange(item: item, history: history, since: now.addingTimeInterval(-3600))
        XCTAssertEqual(change.kind, .updated)
        XCTAssertFalse(change.textChanged)  // seuls les espaces diffèrent
        XCTAssertNil(change.diff)
        XCTAssertEqual(change.newSources.map(\.text), ["Le même fait, redit."])
        XCTAssertEqual(change.newSourceCount, 1)
        XCTAssertTrue(change.removedValues.isEmpty)
    }
}
