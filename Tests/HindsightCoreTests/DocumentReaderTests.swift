import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class DocumentReaderTests: XCTestCase {
    func makeReader(_ t: MockTransport) -> DocumentReaderViewModel {
        let c = makeClient(t)
        return DocumentReaderViewModel(client: c, bank: testBank, documentID: "codex-abc-task-002", attachmentLoader: AttachmentLoader(client: c))
    }

    func testLoadBuildsBlocksWithImagesInPlace() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let r = makeReader(t)
        await r.load()
        XCTAssertNil(r.state.errorMessage)
        XCTAssertNil(r.sourceNote)
        XCTAssertEqual(r.chunks.count, 2)
        XCTAssertEqual(Set(r.attachments.map(\.id)), ["a1b2c3d4", "ffeedd00"])
        let atts = r.blocks.compactMap(\.attachmentRef)
        XCTAssertEqual(atts.map(\.id), ["a1b2c3d4", "ffeedd00", "inconnu99"])
        XCTAssertTrue(atts[0].isImage)
        XCTAssertFalse(atts[1].isImage)  // PDF
        XCTAssertNil(atts[2].attachment)  // jeton inconnu : affiché tel quel
        // L'image apparaît entre les deux étapes.
        let kinds = r.blocks.map { $0.attachmentRef == nil ? "T" : "A" }.joined()
        XCTAssertEqual(kinds, "TATATAT")
    }

    func testFocusChunkHighlightsAndScrollsToItsBlocks() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let r = makeReader(t)
        await r.load(focusChunk: "codex-abc-task-002_1")
        XCTAssertEqual(r.focusedChunkID, "codex-abc-task-002_1")
        // Le chunk 1 commence après l'image : blocs "Étape 2…", image 2, " et ", image 3, ".\nFin."
        XCTAssertFalse(r.focusedBlockIDs.isEmpty)
        let first = try XCTUnwrap(r.scrollTarget)
        XCTAssertEqual(first, r.focusedBlockIDs.min())
        for id in r.focusedBlockIDs {
            let b = r.blocks[id]
            if let txt = b.text { XCTAssertTrue(r.sourceText.contains(txt)) }
        }
        // Le premier chunk (étape 1) n'est pas surligné.
        let step1 = try XCTUnwrap(r.blocks.first)
        XCTAssertFalse(r.focusedBlockIDs.contains(step1.id))
        r.consumeScrollTarget()
        XCTAssertNil(r.scrollTarget)
        r.focus(chunkID: "n'existe-pas")
        XCTAssertTrue(r.focusedBlockIDs.isEmpty)
    }

    func testMissingOriginalTextFallsBackToChunks() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let doc = Fixture.string("document_task").replacingOccurrences(
            of: #""original_text":"#, with: #""ignored":"#)
        // original_text est requis (nullable) : on le met explicitement à null.
        let withNull = doc.replacingOccurrences(of: #""ignored":"#, with: #""original_text":null,"ignored":"#)
        t.on("GET", "\(bankPath)/documents/codex-abc-task-002", json: withNull)
        let r = makeReader(t)
        await r.load(focusChunk: "codex-abc-task-002_1")
        XCTAssertNotNil(r.sourceNote)
        XCTAssertTrue(r.sourceText.contains("Étape 1"))
        XCTAssertTrue(r.sourceText.contains("Étape 2"))
        XCTAssertFalse(r.focusedBlockIDs.isEmpty)
        let focusedText = r.focusedBlockIDs.sorted().compactMap { r.blocks[$0].text }.joined()
        XCTAssertTrue(focusedText.contains("Étape 2"))
        XCTAssertFalse(focusedText.contains("Étape 1"))
    }

    func testFindInDocumentCyclesThroughMatches() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let r = makeReader(t)
        await r.load()
        r.findQuery = "étape"
        XCTAssertEqual(r.matchBlockIDs.count, 2)  // « Étape 1 » et « Étape 2 », insensible à la casse
        XCTAssertEqual(r.currentMatch, 0)
        XCTAssertEqual(r.scrollTarget, r.matchBlockIDs[0])
        r.nextMatch()
        XCTAssertEqual(r.currentMatch, 1)
        r.nextMatch()
        XCTAssertEqual(r.currentMatch, 0)
        r.previousMatch()
        XCTAssertEqual(r.currentMatch, 1)
        r.findQuery = "introuvable"
        XCTAssertTrue(r.matchBlockIDs.isEmpty)
        XCTAssertNil(r.currentMatch)
    }

    func testFactsOfDocumentAndFocusFromFact() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        let r = makeReader(t)
        await r.load()
        await r.loadFacts()
        let facts = try XCTUnwrap(r.facts.value)
        XCTAssertEqual(facts.count, 2)
        XCTAssertEqual(r.factsTotal, 30)
        let req = try XCTUnwrap(t.requests.last { $0.path.hasSuffix("/memories/list") })
        XCTAssertEqual(req.queryValue("document_id"), "codex-abc-task-002")
        r.focus(fact: facts[1])
        XCTAssertEqual(r.focusedChunkID, "codex-abc-task-002_1")
        XCTAssertFalse(r.focusedBlockIDs.isEmpty)
    }

    func testLoadFailureIsReported() async {
        let t = MockTransport()
        t.on("GET", "\(bankPath)/documents/codex-abc-task-002", json: #"{"detail":"Document not found"}"#, status: 404)
        t.on("GET", "\(bankPath)/documents/codex-abc-task-002/chunks", json: Fixture.string("chunks_task"))
        let r = makeReader(t)
        await r.load()
        XCTAssertTrue(r.state.errorMessage?.contains("Document not found") == true)
    }

    func testAttachmentLoaderCachesAndDeduplicates() async throws {
        let t = MockTransport()
        t.delay = .milliseconds(50)
        t.on("GET", "\(bankPath)/attachments/a1b2c3d4") { _ in .bytes(Data(repeating: 7, count: 10), contentType: "image/png") }
        let loader = AttachmentLoader(client: makeClient(t))
        let a = ChunkAttachment(id: "a1b2c3d4", hash: "h", kind: "image", mediaType: "image/png", byteSize: 10, url: "\(bankPath)/attachments/a1b2c3d4")
        async let x = loader.load(a)
        async let y = loader.load(a)
        let (r1, r2) = try await (x, y)
        XCTAssertEqual(r1.data.count, 10)
        XCTAssertEqual(r2.mimeType, "image/png")
        _ = try await loader.load(a)
        XCTAssertEqual(t.requests.count, 1, "trois lectures, une seule requête")
    }

    func testAttachmentLoaderEvictsBeyondLimit() async throws {
        let t = MockTransport()
        t.onFallback { _ in .bytes(Data(repeating: 1, count: 100), contentType: "image/png") }
        let loader = AttachmentLoader(client: makeClient(t), byteLimit: 250)
        for i in 0..<5 {
            let a = ChunkAttachment(id: "i\(i)", hash: "h", kind: "image", mediaType: "image/png", byteSize: 100, url: "/x/\(i)")
            _ = try await loader.load(a)
        }
        let cached = await loader.cachedCount
        XCTAssertEqual(cached, 2)
    }
}

/// Banque qui ne crée pas d'observations : le lecteur ne promet aucune reconsolidation et refuse la portée.
@MainActor
final class ReaderWithoutObservationsTests: XCTestCase {
    func testTagsAndScopeFollowTheBankSetting() async throws {
        let t = MockTransport()
        let doc = "\(bankPath)/documents/d1"
        t.on("GET", doc, json: #"{"id":"d1","bank_id":"b","original_text":"x","created_at":"","updated_at":"","memory_unit_count":1,"tags":["a"],"observation_scopes":"shared"}"#)
        t.on("GET", "\(doc)/chunks", json: #"{"items":[],"total":0,"limit":1000,"offset":0}"#)
        t.on("GET", "\(doc)/history", json: #"{"document_id":"d1","items":[],"total":0,"limit":50,"offset":0}"#)
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"b","config":{"enable_observations":false},"overrides":{"enable_observations":false}}"#)
        let client = makeClient(t)
        let r = DocumentReaderViewModel(client: client, bank: testBank, documentID: "d1", attachmentLoader: AttachmentLoader(client: client))
        r.serverIs110 = true
        await r.load()
        XCTAssertEqual(r.createsObservations, false)

        r.requestUpdateTags(["a", "b"])
        let c = try XCTUnwrap(r.confirmation)
        XCTAssertEqual(c.title, "Enregistrer les étiquettes du document ?")
        XCTAssertTrue(c.message.hasSuffix("Cette banque ne crée pas d'observations : rien n'est reconsolidé."), c.message)
        XCTAssertFalse(c.message.contains("appel LLM"))
        r.confirmation = nil

        r.requestUpdateScope("per_tag")
        XCTAssertNil(r.confirmation)
        XCTAssertEqual(r.actionMessage, "Cette banque ne crée pas d'observations : changer la portée n'aurait aucun effet.")
        XCTAssertFalse(t.requests.contains { $0.method == "PATCH" })
    }
}

/// Portée d'observation d'un document (`observation_scopes`, ou à défaut `retain_params`).
final class ObservationScopeTests: XCTestCase {
    func testLabelsScopeFromDocumentOrRetainParams() {
        XCTAssertEqual(ObservationScope.label(.string("shared")), "partagée")
        XCTAssertEqual(ObservationScope.label(nil, retainParams: ["observation_scopes": .string("per_tag")]), "par étiquette")
        XCTAssertEqual(
            ObservationScope.label(.array([.array([.string("repo:a"), .string("kind:b")]), .array([.string("c")])])), "étiquettes : repo:a + kind:b, c")
        XCTAssertNil(ObservationScope.label(nil, retainParams: nil), "rien à dire si le serveur ne l'a pas gardée")
        XCTAssertNil(ObservationScope.label(.null))
    }
}

/// Serveur 1.1.0 : version, historique et portée d'un document, relance d'une opération différée.
@MainActor
final class Server110FeaturesTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(ServerCapabilities.is110("1.1.0"))
        XCTAssertTrue(ServerCapabilities.is110("1.2.0-dev"))
        XCTAssertFalse(ServerCapabilities.is110("1.0.0"))
        XCTAssertFalse(ServerCapabilities.is110(nil))
        XCTAssertEqual(ObservationScope.consolidationTitle("pending"), "en attente")
    }

    func testDefaultScopeIsSentOnlyWhenChangedAndRunNowNeeds110() throws {
        let before = MemoryDesign()
        var after = before
        XCTAssertNil(after.updates(from: before)?["default_observation_scopes"], "inchangée : jamais envoyée (serveur 1.0.0)")
        after.defaultObservationScopes = "shared"
        XCTAssertEqual(after.updates(from: before)?["default_observation_scopes"], .string("shared"))

        let raw = try JSONDecoder().decode(
            OperationResponse.self,
            from: Data(#"{"id":"o1","task_type":"retain","items_count":0,"document_id":null,"created_at":"","status":"pending","error_message":null,"next_retry_at":"2099-01-01T00:00:00Z"}"#.utf8))
        let row = OperationRow(raw)
        let vm = OperationsViewModel(client: makeClient(MockTransport()), bank: testBank)
        XCTAssertFalse(vm.canRunNow(row), "serveur 1.0.0")
        vm.serverIs110 = true
        XCTAssertTrue(vm.canRunNow(row))
    }

    func testReaderLoadsHistoryOnlyOn110AndPatchesScope() async throws {
        let t = MockTransport()
        let doc = "\(bankPath)/documents/d1"
        t.on("GET", doc, json: #"{"id":"d1","bank_id":"b","original_text":"x","created_at":"","updated_at":"","memory_unit_count":1,"tags":[],"observation_scopes":"shared"}"#)
        t.on("GET", "\(doc)/chunks", json: #"{"items":[],"total":0,"limit":1000,"offset":0}"#)
        t.on("GET", "\(doc)/history", json: #"{"document_id":"d1","items":[{"document_id":"d1","kind":"retain","facts_added":3,"facts_removed":0}],"total":1,"limit":50,"offset":0}"#)
        t.on("PATCH", doc, json: #"{"success":true}"#)
        let client = makeClient(t)
        let old = DocumentReaderViewModel(client: client, bank: testBank, documentID: "d1", attachmentLoader: AttachmentLoader(client: client))
        await old.load()
        XCTAssertNil(old.history, "serveur 1.0.0 : pas d'historique demandé")
        XCTAssertFalse(t.requests.contains { $0.path.hasSuffix("/history") })
        old.requestUpdateScope("per_tag")
        XCTAssertNil(old.confirmation, "serveur 1.0.0 : la portée ne change pas")
        XCTAssertEqual(old.actionMessage, "Changer la portée d'un document demande un serveur Hindsight 1.1.0 ou plus récent.")

        let r = DocumentReaderViewModel(client: client, bank: testBank, documentID: "d1", attachmentLoader: AttachmentLoader(client: client))
        r.serverIs110 = true
        await r.load()
        XCTAssertEqual(r.history?.first?.factsAdded, 3)
        XCTAssertEqual(r.currentScopeMode, "shared")
        r.requestUpdateScope("shared")
        XCTAssertNil(r.confirmation, "même portée : rien à confirmer")
        XCTAssertEqual(r.actionMessage, "Ce document a déjà cette portée.")
        r.requestUpdateScope("per_tag")
        await r.confirmation?.perform()
        let patch = try XCTUnwrap(t.requests.last { $0.method == "PATCH" })
        XCTAssertEqual(try JSONDecoder().decode([String: JSONValue].self, from: patch.body ?? Data()), ["observation_scopes": .string("per_tag")])
    }
}
