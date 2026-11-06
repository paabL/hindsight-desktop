import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore
@testable import HindsightLayout

@MainActor
final class SearchTests: XCTestCase {
    func routes(_ t: MockTransport) {
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/memories/recall", json: Fixture.string("recall"))
        t.on("POST", "\(bankPath)/reflect", json: Fixture.string("reflect"))
        t.on("GET", "\(bankPath)/memories/obs1", json: Fixture.string("memory_obs1"))
        t.on("GET", "\(bankPath)/memories/m1", json: Fixture.string("memory_m1"))
        t.on("GET", "\(bankPath)/memories/m2", json: Fixture.string("memory_m2"))
        t.on("GET", "\(bankPath)/memories/obs1/history", json: #"[{"change":"created"}]"#)
        t.on("GET", "/v1/default/chunks/codex-abc-task-002_0", json: Fixture.string("chunk_m1"))
    }

    func testFilterTranslatesTaskTypesTagsAndWindow() async {
        var f = FactFilter()
        f.tags = ["source:codex"]
        f.task = "002"
        f.types = ["world"]
        f.entity = EntityRef(id: "e1", name: "Codex")
        f.start = HSDate.parse("2026-10-01T00:00:00Z")
        XCTAssertEqual(f.effectiveTags, ["source:codex", "task:002"])
        let q = f.memoryListQuery(q: "tests", axis: .mentioned, limit: 100, offset: 0)
        XCTAssertEqual(q.type, "world")
        XCTAssertEqual(q.entityID, "e1")
        XCTAssertEqual(q.tags.tags, ["source:codex", "task:002"])
        XCTAssertEqual(q.window.field, "mentioned_at")
        let r = f.recallRequest(query: "x", budget: "high")
        XCTAssertEqual(r.types, ["world"])
        XCTAssertEqual(r.tags, ["source:codex", "task:002"])
        XCTAssertEqual(r.tagsMatch, "all_strict")
        XCTAssertEqual(r.temporalWindow?.start.hasPrefix("2026-10-01"), true)
        XCTAssertNotNil(r.include?.chunks)
        var g = FactFilter()
        g.task = "task:007"
        XCTAssertEqual(g.effectiveTags, ["task:007"])
        XCTAssertEqual(FactFilter().recallRequest(query: "x", budget: "mid").tagsMatch, "any")
    }

    func testRecallSendsFilterAndAppliesEntityLocally() async throws {
        let t = MockTransport()
        routes(t)
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.query = "  tests  "
        vm.filter.entity = EntityRef(id: "e1", name: "codex")
        await vm.run()
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertEqual(vm.hits.map(\.id), ["m1", "obs1"])  // m3 n'a pas l'entité Codex
        XCTAssertEqual(vm.locallyFiltered, 1)
        XCTAssertEqual(vm.total, 2, "le total affiché exclut les résultats écartés localement")
        XCTAssertEqual(vm.hits[0].score, 0.91)
        XCTAssertEqual(vm.chunkText(for: vm.hits[0])?.hasPrefix("Étape 1"), true)
        let body = try XCTUnwrap(t.requests.last { $0.path.hasSuffix("/recall") }?.bodyJSON)
        XCTAssertEqual(body["query"], "tests")
        XCTAssertEqual(body["budget"], "mid")
        XCTAssertNotNil(body["include"]?["chunks"])
    }

    func testTextModePagesAndFiltersSeveralTypesLocally() async {
        let t = MockTransport()
        routes(t)
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.mode = .text
        XCTAssertFalse(vm.canRun)
        vm.filter.types = ["world", "observation"]
        XCTAssertTrue(vm.canRun)  // les filtres seuls suffisent en mode texte
        await vm.run()
        XCTAssertEqual(vm.hits.map(\.id), ["m2"])  // m1 est « experience »
        XCTAssertEqual(vm.total, 30)
        XCTAssertTrue(vm.canLoadMore)
        let r = t.requests.last { $0.path.hasSuffix("/memories/list") }!
        XCTAssertNil(r.queryValue("type"), "plusieurs types : filtrage local")
        await vm.loadMore()
        XCTAssertEqual(t.requests.last { $0.path.hasSuffix("/memories/list") }?.queryValue("offset"), "2")
    }

    func testReflectShowsAnswerAndBasedOnFacts() async {
        let t = MockTransport()
        routes(t)
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.mode = .reflect
        vm.query = "Pourquoi les tests échouaient ?"
        vm.filter.task = "002"
        await vm.run()
        XCTAssertTrue(vm.answer?.text.hasPrefix("Les échecs") == true)
        XCTAssertEqual(vm.hits.map(\.id), ["m1"])
        XCTAssertEqual(vm.answer?.usage?.totalTokens, 1280)
        let body = t.requests.last { $0.path.hasSuffix("/reflect") }!.bodyJSON!
        XCTAssertEqual(body["tags"], ["task:002"])
        XCTAssertNotNil(body["include"]?["facts"])
    }

    func testRecallErrorIsReported() async {
        let t = MockTransport()
        t.on("POST", "\(bankPath)/memories/recall", json: #"{"detail":"embedding provider down"}"#, status: 503)
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.query = "x"
        await vm.run()
        XCTAssertTrue(vm.state.errorMessage?.contains("embedding provider down") == true)
    }

    func testFactDetailLoadsChunkAndDocumentTarget() async throws {
        let t = MockTransport()
        routes(t)
        let vm = SearchViewModel(client: makeClient(t), bank: testBank)
        vm.query = "tests"
        await vm.run()
        let d = FactDetailViewModel(client: makeClient(t), bank: testBank, hit: vm.hits[0])
        await d.load()
        XCTAssertEqual(d.chunk.value?.chunkText.hasPrefix("Étape 1"), true)
        XCTAssertEqual(d.documentTarget?.documentID, "codex-abc-task-002")
        XCTAssertEqual(d.documentTarget?.chunkID, "codex-abc-task-002_0")
        XCTAssertEqual(d.hit.score, 0.91, "le score de recall est conservé")
    }

    func testObservationDetailResolvesSourceFacts() async throws {
        let t = MockTransport()
        routes(t)
        let hit = FactHit(id: "obs1", text: "Codex corrige…", type: "observation", sourceFactIDs: ["m1", "m2"])
        let d = FactDetailViewModel(client: makeClient(t), bank: testBank, hit: hit)
        await d.load()
        XCTAssertEqual(d.hit.entities, ["Codex"])  // entités sous forme d'objets {name}
        let sources = try XCTUnwrap(d.sources.value)
        XCTAssertEqual(sources.map(\.id), ["m1", "m2"])
        XCTAssertEqual(sources[1].entities, ["Codex"])  // entités sous forme de chaîne
        XCTAssertEqual(sources[0].documentID, "codex-abc-task-002")
        XCTAssertNotNil(d.history)
        XCTAssertNil(d.documentTarget, "une observation n'a pas de document propre")
    }

    func testCatalogTasksAndEntitySearch() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/tags", json: #"{"items":[{"tag":"task:010","count":3},{"tag":"source:codex","count":9},{"tag":"task:002","count":5},{"tag":"task:1","count":1}],"total":4,"limit":500,"offset":0}"#)
        t.on("GET", "\(bankPath)/entities", json: #"{"items":[{"id":"e1","canonical_name":"Codex","mention_count":9},{"id":"e2","canonical_name":"Élise","mention_count":2}],"total":2,"limit":500,"offset":0}"#)
        let c = BankCatalog(client: makeClient(t), bank: testBank)
        await c.loadIfNeeded()
        XCTAssertEqual(c.tasks, ["1", "002", "010"])
        XCTAssertEqual(c.plainTags.map(\.tag), ["source:codex"])
        XCTAssertEqual(c.entities(matching: "elise").map(\.id), ["e2"])
        XCTAssertEqual(c.entities(matching: "").count, 2)
    }
}

@MainActor
final class TimelineTests: XCTestCase {
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testLoadsAllPagesAndGroupsByDay() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/memories/list") { r in
            .json(Fixture.string(r.queryValue("offset") == "3" ? "timeline_p2" : "timeline_p1"))
        }
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        vm.axis = .mentioned
        await vm.reload()
        XCTAssertEqual(vm.facts.count, 6)
        XCTAssertEqual(t.requests.map { $0.queryValue("offset") }, ["0", "3"])
        XCTAssertEqual(t.requests[0].queryValue("limit"), "3")
        XCTAssertEqual(vm.undated.map(\.id), ["t5"])
        // mentioned_at : 01/10 (t0,t1), 02/10 (t2,t3), 03/10 (t4)
        XCTAssertEqual(vm.periods.map(\.count), [2, 2, 1])
        XCTAssertEqual(vm.bars.reduce(0) { $0 + $1.count }, 5)
        vm.granularity = .month
        XCTAssertEqual(vm.periods.map(\.count), [5])
        vm.axis = .occurred
        // occurred_start n'existe que pour t0..t2 (septembre)
        XCTAssertEqual(vm.periods.map(\.count), [3])
        XCTAssertEqual(vm.undated.count, 3)
        vm.axis = .event  // occurred_start, sinon mentioned_at
        vm.granularity = .day
        XCTAssertEqual(vm.periods.reduce(0) { $0 + $1.count }, 5)
    }

    func testJumpSelectsNearestPeriodAndFactDetail() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/memories/list") { r in
            .json(Fixture.string(r.queryValue("offset") == "3" ? "timeline_p2" : "timeline_p1"))
        }
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        vm.axis = .mentioned
        await vm.reload()
        vm.jump(to: HSDate.parse("2026-10-02T23:00:00Z")!)
        XCTAssertEqual(vm.selectedPeriod, HSDate.parse("2026-10-02T00:00:00Z"))
        XCTAssertEqual(vm.factsOfSelectedPeriod.map(\.id), ["t2", "t3"])
        vm.jump(to: HSDate.parse("2030-01-01T00:00:00Z")!)
        XCTAssertEqual(vm.selectedPeriod, HSDate.parse("2026-10-03T00:00:00Z"))
    }

    func testMaxFactsTruncates() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/memories/list") { r in
            .json(Fixture.string(r.queryValue("offset") == "3" ? "timeline_p2" : "timeline_p1"))
        }
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        vm.maxFacts = 3
        await vm.reload()
        XCTAssertEqual(vm.facts.count, 3)
        XCTAssertTrue(vm.isTruncated)
        XCTAssertEqual(t.requests.count, 1)
    }

    func testFiltersAreSentWithTimeField() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/memories/list", json: Fixture.string("timeline_p2"))
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, calendar: utc)
        vm.filter.task = "003"
        vm.filter.start = HSDate.parse("2026-10-01T00:00:00Z")
        vm.text = "build"
        await vm.reload()
        let r = t.requests[0]
        XCTAssertEqual(r.query["tags"], ["task:003"])
        XCTAssertEqual(r.queryValue("time_field"), "occurred_start")
        XCTAssertEqual(r.queryValue("q"), "build")
        XCTAssertEqual(r.queryValue("limit"), "1000")
    }

    /// `count` faits (10 par défaut) servis par pages de 3 ; la page `failing` répond par une erreur serveur.
    /// Avec `reversed`, les pages lointaines répondent les premières, comme un serveur sous charge.
    func serveTenFacts(_ t: MockTransport, count: Int = 10, failing: String? = nil, reversed: Bool = false) {
        t.on("GET", "\(bankPath)/memories/list") { r in
            if let failing, r.queryValue("offset") == failing { return .json(#"{"detail":"panne"}"#, status: 500) }
            let offset = Int(r.queryValue("offset") ?? "") ?? 0
            if reversed, offset > 0 { Thread.sleep(forTimeInterval: Double(count + 2 - offset) * 0.003) }
            let items = (offset..<min(offset + 3, count)).map {
                #"{"id":"f\#($0)","text":"fait \#($0)","fact_type":"world","mentioned_at":"2026-10-0\#(1 + $0 % 3)T10:00:00Z","tags":[],"entities":"","metadata":{},"source_memory_ids":[]}"#
            }
            return .json(#"{"items":[\#(items.joined(separator: ","))],"total":\#(count),"limit":3,"offset":\#(offset)}"#)
        }
    }

    func testRemainingPagesLoadTogetherInServerOrder() async {
        let t = MockTransport()
        serveTenFacts(t)
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        await vm.reload()
        XCTAssertEqual(vm.facts.map(\.id), (0..<10).map { "f\($0)" })
        XCTAssertEqual(t.requests.first?.queryValue("offset"), "0")
        XCTAssertEqual(t.requests.compactMap { $0.queryValue("offset") }.sorted(), ["0", "3", "6", "9"])
        XCTAssertFalse(vm.isTruncated)
    }

    /// Plus de pages que de requêtes simultanées, terminées en ordre inverse : l'ordre du serveur demeure.
    func testPagesFinishingOutOfOrderKeepServerOrder() async {
        let t = MockTransport()
        serveTenFacts(t, count: 30, reversed: true)
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        await vm.reload()
        XCTAssertEqual(vm.facts.map(\.id), (0..<30).map { "f\($0)" })
        XCTAssertEqual(t.requests.count, 10)
    }

    func testFailedPageKeepsEarlierPagesAsSequentialLoadingDid() async {
        let t = MockTransport()
        serveTenFacts(t, failing: "6")
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        await vm.reload()
        XCTAssertEqual(vm.facts.map(\.id), (0..<6).map { "f\($0)" })
        XCTAssertNotNil(vm.state.errorMessage)
    }

    func testPrefetchStopsAtMaxFacts() async {
        let t = MockTransport()
        serveTenFacts(t)
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        vm.maxFacts = 5
        await vm.reload()
        XCTAssertEqual(t.requests.map { $0.queryValue("offset") }, ["0", "3"])
        XCTAssertEqual(vm.facts.count, 5)
        XCTAssertTrue(vm.isTruncated)
    }

    func testLocalTypeFilterStillLoadsPageByPage() async {
        let t = MockTransport()
        serveTenFacts(t)
        let vm = TimelineViewModel(client: makeClient(t), bank: testBank, pageSize: 3, calendar: utc)
        vm.filter.types = ["world", "experience"]
        await vm.reload()
        XCTAssertEqual(t.requests.map { $0.queryValue("offset") }, ["0", "3", "6", "9"])
        XCTAssertEqual(vm.facts.count, 10)
    }
}

@MainActor
final class GraphTests: XCTestCase {
    func testSimulationIsDeterministicSettlesAndSpreadsNodes() async {
        let links = (1..<200).map { ForceSimulation.Link($0 / 4, $0) }  // arbre
        var a = ForceSimulation(nodeCount: 200, links: links)
        var b = ForceSimulation(nodeCount: 200, links: links)
        a.tick(400)
        b.tick(400)
        XCTAssertEqual(a.positions, b.positions, "déterministe")
        XCTAssertTrue(a.isSettled)
        XCTAssertTrue(a.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        // Pas de nœuds superposés, centrés autour de l'origine.
        var minD = Double.infinity
        for i in 0..<200 { for j in (i + 1)..<200 { minD = min(minD, hypot(a.x[i] - a.x[j], a.y[i] - a.y[j])) } }
        XCTAssertGreaterThan(minD, 0.5)
        let cx = a.x.reduce(0, +) / 200, cy = a.y.reduce(0, +) / 200
        XCTAssertLessThan(hypot(cx, cy), 30)
        // Les nœuds liés sont plus proches que des voisins d'indice quelconques.
        func dist(_ i: Int, _ j: Int) -> Double { hypot(a.x[i] - a.x[j], a.y[i] - a.y[j]) }
        var linked = 0.0
        for l in links { linked += dist(l.a, l.b) }
        linked /= Double(links.count)
        var other = 0.0
        for i in 0..<100 { other += dist(i, 199 - i) }
        other /= 100
        XCTAssertLessThan(linked, other)
    }

    func testQuadTreeConservesMassIncludingCoincidentPoints() async {
        var t = QuadTree()
        t.build(x: [0, 0, 0, 10, -5, 3], y: [0, 0, 0, 10, 7, -2])
        XCTAssertEqual(t.totalMass, 6)
        t.build(x: [1, 2], y: [1, 2])  // réutilisation des tampons
        XCTAssertEqual(t.totalMass, 2)
        var many = ForceSimulation(nodeCount: 50, links: [])
        many.tick(50)
        XCTAssertTrue(many.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testSimulationHandlesDegenerateInput() async {
        var s = ForceSimulation(nodeCount: 3, links: [ForceSimulation.Link(0, 0), ForceSimulation.Link(0, 9)])
        s.tick(10)
        XCTAssertTrue(s.positions.allSatisfy { $0.x.isFinite })
        var empty = ForceSimulation(nodeCount: 0, links: [])
        empty.tick(5)
        XCTAssertTrue(empty.positions.isEmpty)
        s.alpha = 0
        XCTAssertTrue(s.isSettled)
        s.reheat()
        XCTAssertFalse(s.isSettled)
    }

    func testLargeGraphStepIsFast() async {
        let n = 2000
        let links = (1..<n).map { ForceSimulation.Link(($0 * 7919) % $0, $0) }
        var s = ForceSimulation(nodeCount: n, links: links)
        let start = Date()
        s.tick(10)
        // Moteur compilé en -O : 10 pas sur 2 000 nœuds doivent tenir largement sous la seconde.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testFactGraphKeepsTheSharedEntityExplainingARelationship() async throws {
        let t = MockTransport()
        var response = try JSONDecoder().decode(GraphDataResponse.self, from: Data(Fixture.string("graph").utf8))
        response.edges[0].data.linkType = "entity"
        response.edges[0].data.entityName = "NOMAD"
        let json = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        t.on("GET", "\(bankPath)/graph", json: json)
        let vm = GraphViewModel(client: makeClient(t), bank: testBank)
        await vm.reload(layout: false)
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertEqual(vm.edges.first?.label, "NOMAD")
        XCTAssertEqual(vm.edges.first?.kind, "entity")
    }

    func testDesktopGraphLoadsDataWithoutStartingAnUnusedNativeLayout() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/entities/graph", json: Fixture.string("entity_graph"))
        let vm = GraphViewModel(client: makeClient(t), bank: testBank)
        vm.mode = .entities
        await vm.reload(layout: false)
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertEqual(vm.nodes.count, 6)
        XCTAssertTrue(vm.positions.isEmpty)
        XCTAssertFalse(vm.isAnimating)
        XCTAssertEqual(vm.serverNodeTotal, 3800)
    }

    func testEntityGraphKeepsTopNodesAndSelectionLoadsDetail() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/entities/graph", json: Fixture.string("entity_graph"))
        t.on("GET", "\(bankPath)/entities/e0", json: Fixture.string("entity_e0"))
        t.on("GET", "\(bankPath)/memories/list", json: Fixture.string("memories_doc"))
        let vm = GraphViewModel(client: makeClient(t), bank: testBank, animated: false)
        vm.mode = .entities
        XCTAssertEqual(vm.colorMode, .importance)
        vm.maxNodes = 4
        vm.minCount = 3
        await vm.reload()
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertEqual(vm.nodes.map(\.id), ["e0", "e1", "e2", "e3"])
        XCTAssertEqual(vm.edges.count, 3, "liens vers e4/e5 écartés")
        XCTAssertEqual(vm.links.count, 3)
        XCTAssertEqual(vm.positions.count, 4)
        XCTAssertEqual(vm.fitGeneration, 1)
        XCTAssertEqual(vm.serverNodeTotal, 3800)
        let req = t.requests[0]
        XCTAssertEqual(req.queryValue("min_count"), "3")
        XCTAssertEqual(req.queryValue("limit"), "32")
        XCTAssertEqual(vm.colorValues.first ?? nil, 1.0, "le plus mentionné est au maximum")
        vm.highlight = "entité 2"
        XCTAssertEqual(vm.highlightedIDs, ["e2"])
        XCTAssertEqual(Set(vm.neighbors(of: 0)), [1, 2, 3])
        await vm.select("e0")
        XCTAssertEqual(vm.neighborIDs, ["e1", "e2", "e3"])
        XCTAssertEqual(vm.entityDetail.value?.observations.count, 1)
        XCTAssertEqual(vm.nodeFacts.value?.count, 2)
        XCTAssertEqual(t.requests.last { $0.path.hasSuffix("/memories/list") }?.queryValue("entity_id"), "e0")
        vm.hover(2)
        XCTAssertEqual(vm.hoveredNode?.id, "e2")
    }

    func testFactGraphColorsByRecencyAndUsesTableRows() async throws {
        let t = MockTransport()
        // Dates de mention : f0 la plus ancienne, f2 la plus récente, f3 sans date.
        let t0 = try JSONDecoder().decode(GraphDataResponse.self, from: Data(Fixture.string("graph").utf8))
        var rows = t0.tableRows
        rows[0].mentionedAt = "2026-10-15T00:00:00Z"
        rows[1].mentionedAt = "2026-10-16T12:00:00Z"
        rows[2].mentionedAt = "2026-10-18T00:00:00Z"
        rows[2].occurredStart = "2026-01-01T00:00:00Z"
        var patched = t0
        patched.tableRows = rows
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(patched))
        t.on("GET", "\(bankPath)/graph") { _ in .json(body) }
        t.on("GET", "\(bankPath)/memories/f0", json: #"{"id":"f0","text":"Fait numéro 0"}"#)
        t.on("GET", "/v1/default/chunks/codex-abc-task-002_0", json: Fixture.string("chunk_m1"))
        let vm = GraphViewModel(client: makeClient(t), bank: testBank, animated: false)
        XCTAssertEqual(vm.mode, .facts)
        XCTAssertEqual(vm.maxNodes, 1000)
        await vm.reload()
        XCTAssertEqual(t.requests[0].queryValue("limit"), "1000")
        XCTAssertEqual(vm.nodes.first?.id, "f0", "le nœud le plus connecté d'abord")
        XCTAssertEqual(vm.nodes.first { $0.id == "f3" }?.kind, "observation")
        XCTAssertLessThanOrEqual(vm.nodes.first { $0.id == "f1" }!.label.count, 60)
        XCTAssertEqual(vm.dateRange?.lowerBound, HSDate.parse("2026-10-15T00:00:00Z"))
        let values = Dictionary(uniqueKeysWithValues: zip(vm.nodes.map(\.id), vm.colorValues))
        XCTAssertEqual(values["f0"] ?? nil, 0)
        XCTAssertEqual(values["f2"] ?? nil, 1)
        XCTAssertEqual(try XCTUnwrap(values["f1"] ?? nil), 0.5, accuracy: 0.001)
        XCTAssertNil(values["f3"] ?? nil, "sans date : couleur neutre")
        vm.colorMode = .recencyOccurred
        XCTAssertEqual(vm.dateRange?.lowerBound, HSDate.parse("2026-01-01T00:00:00Z"), "occurred_start prioritaire")
        vm.colorMode = .type
        XCTAssertTrue(vm.colorValues.allSatisfy { $0 == nil })
        await vm.select("f0")
        XCTAssertEqual(vm.selectedFact?.documentTarget?.documentID, "codex-abc-task-002")
    }

    func testAnimationRunsPausesAndResumes() async throws {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/entities/graph", json: Fixture.string("entity_graph"))
        let vm = GraphViewModel(client: makeClient(t), bank: testBank)
        vm.mode = .entities
        await vm.reload()
        XCTAssertTrue(vm.isAnimating)
        let before = vm.positions
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotEqual(vm.positions, before, "les positions évoluent")
        vm.pause()
        XCTAssertTrue(vm.isPaused)
        XCTAssertFalse(vm.isAnimating)
        let frozen = vm.positions
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.positions, frozen)
        vm.resume()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(vm.isPaused)
        vm.stopAnimation()
    }
}

@MainActor
final class AuditTests: XCTestCase {
    func features(audit: Bool, trace: Bool = true, configAPI: Bool = true) -> FeaturesInfo {
        var f = try! JSONDecoder().decode(VersionResponse.self, from: Data(Fixture.string("version").utf8)).features
        f.auditLog = audit
        f.llmTrace = trace
        f.bankConfigApi = configAPI
        return f
    }

    func routes(_ t: MockTransport, config: String = Fixture.string("bank_config")) {
        t.on("GET", "\(bankPath)/config", json: config)
        t.on("GET", "\(bankPath)/audit-logs", json: Fixture.string("audit_logs"))
        t.on("GET", "\(bankPath)/audit-logs/stats", json: Fixture.string("audit_stats"))
        t.on("GET", "\(bankPath)/llm-requests", json: Fixture.string("llm_requests"))
        t.on("GET", "\(bankPath)/llm-requests/stats", json: Fixture.string("llm_stats"))
    }

    func testWhoAccessedAndHowManyTimes() async throws {
        let t = MockTransport()
        routes(t)
        let vm = AuditViewModel(client: makeClient(t), bank: testBank, features: features(audit: true))
        await vm.reload()
        let rows = vm.accessRows
        XCTAssertEqual(rows.first?.actor, "mcp · codex-cli")
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(rows.first?.actions["recall"], 2)
        XCTAssertEqual(rows.first?.lastSeen, HSDate.parse("2026-10-17T11:00:00Z"))
        XCTAssertTrue(rows.contains { $0.actor == "http · python-httpx/0.27" }, "identité lue dans request")
        XCTAssertTrue(rows.contains { $0.actor == "http · appelant non identifié" })
        XCTAssertEqual(rows.reduce(0) { $0 + $1.count }, 5)
        XCTAssertEqual(vm.actionCounts.first?.action, "recall")
        XCTAssertEqual(vm.groupingKeys, ["client_name", "user_agent"])
        vm.groupBy = "user_agent"
        XCTAssertEqual(vm.accessRows.first { $0.actor.contains("codex/1.0") }?.count, 1)
        XCTAssertEqual(vm.auditStats?.buckets.first?.total, 3)
    }

    func testLLMUsageByOperationProviderModel() async throws {
        let t = MockTransport()
        routes(t)
        let vm = AuditViewModel(client: makeClient(t), bank: testBank, features: features(audit: true))
        await vm.reload()
        let usage = vm.llmUsage
        XCTAssertEqual(usage.count, 2)
        let claude = try XCTUnwrap(usage.first { $0.provider == "claude-code" })
        XCTAssertEqual(claude.calls, 2)
        XCTAssertEqual(claude.errors, 1)
        XCTAssertEqual(claude.inputTokens, 1000)
        XCTAssertEqual(claude.averageDurationMs, 2000)
        XCTAssertEqual(vm.llmStats?.buckets.first?.tokens.total, 4250)
    }

    func testDisabledAuditStateAndEnableFlowRequiresConfirmation() async throws {
        let t = MockTransport()
        routes(t)
        t.on("PATCH", "\(bankPath)/config") { _ in
            .json(#"{"bank_id":"b","config":{"audit_log_enabled":true},"overrides":{"audit_log_enabled":true}}"#)
        }
        let vm = AuditViewModel(client: makeClient(t), bank: testBank, features: features(audit: false))
        await vm.reload()
        XCTAssertEqual(vm.auditStatus, .disabled(canEnableViaAPI: true))
        vm.requestEnableAudit()
        XCTAssertTrue(t.requests.filter { $0.method == "PATCH" }.isEmpty)
        // Après l'écriture, le serveur renvoie l'override : on recharge l'état.
        routes(t, config: #"{"bank_id":"b","config":{"audit_log_enabled":true},"overrides":{"audit_log_enabled":true}}"#)
        await vm.confirmation!.perform()
        let patch = try XCTUnwrap(t.requests.first { $0.method == "PATCH" })
        XCTAssertEqual(patch.bodyJSON?["updates"]?["audit_log_enabled"], true)
        XCTAssertEqual(vm.auditStatus, .enabled(viaBankOverride: true))
        XCTAssertEqual(vm.actionMessage, "Journal d'audit activé pour cette banque.")
    }

    func testRefusedEnableExplainsEnvironmentVariable() async {
        let t = MockTransport()
        routes(t)
        t.on("PATCH", "\(bankPath)/config", json: #"{"detail":"Bank config API is disabled"}"#, status: 403)
        let vm = AuditViewModel(client: makeClient(t), bank: testBank, features: features(audit: false, configAPI: false))
        await vm.reload()
        XCTAssertEqual(vm.auditStatus, .disabled(canEnableViaAPI: false))
        vm.requestEnableAudit()
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage!.contains("HINDSIGHT_API_AUDIT_LOG_ENABLED=true"), vm.actionMessage!)
    }

    func testLLMTraceDisabledSkipsRequests() async {
        let t = MockTransport()
        routes(t)
        let vm = AuditViewModel(client: makeClient(t), bank: testBank, features: features(audit: true, trace: false))
        await vm.reload()
        XCTAssertFalse(vm.llmTraceEnabled)
        XCTAssertTrue(t.requests.allSatisfy { !$0.path.contains("llm-requests") })
    }

    func testStatusFromFeaturesWhenConfigUnavailable() async {
        XCTAssertEqual(AuditViewModel.status(config: nil, features: features(audit: true)), .enabled(viaBankOverride: false))
        XCTAssertEqual(AuditViewModel.status(config: nil, features: nil), .unknown)
    }
}
