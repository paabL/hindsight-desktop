import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class AppModelTests: XCTestCase {
    func makeApp(_ t: MockTransport, settings: [String: String] = [:]) -> (AppModel, InMemorySettingsStore) {
        let store = InMemorySettingsStore(settings)
        return (AppModel(settings: store, transport: t), store)
    }

    func testManualHostConnectDoesNotReconcileOrReadProfiles() async {
        let transport = MockTransport()
        transport.installStandardRoutes()
        let app = AppModel(settings: InMemorySettingsStore(["pause.global": "1"]), transport: transport, ledger: nil, automaticActions: false)
        app.pause.refreshSweepInterval = .milliseconds(1)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(transport.requests.isEmpty)
        await app.connect()
        app.selectBank("scratch")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(transport.requests.map(\.path), ["/version", "/v1/default/banks"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.method == "GET" })
        XCTAssertEqual(app.selectedBankID, "scratch")
    }

    func testCancelledConnectCannotSelectABankAfterAnUncancellableResponse() async {
        for path in ["/version", "/v1/default/banks"] {
            let mock = MockTransport()
            mock.installStandardRoutes()
            let transport = HeldReadTransport(mock: mock, path: path)
            let app = AppModel(settings: InMemorySettingsStore(), transport: transport, ledger: nil, automaticActions: false)
            let request = Task { await app.connect() }
            await transport.waitForHold()
            request.cancel()
            await transport.release()
            await request.value
            XCTAssertNil(app.session)
            XCTAssertEqual(mock.requests.map(\.path), path == "/version" ? ["/version"] : ["/version", "/v1/default/banks"])
        }
    }

    func testClosingReaderCancelsItsFollowupFactsRead() async {
        let mock = MockTransport()
        mock.installStandardRoutes()
        let path = bankPath + "/documents/codex-abc-task-002"
        let transport = HeldReadTransport(mock: mock, path: path)
        let app = AppModel(settings: InMemorySettingsStore(), transport: transport, ledger: nil, automaticActions: false)
        await app.connect()
        let documents = app.session!.documents
        documents.open(documentID: "codex-abc-task-002")
        await transport.waitForHold()
        documents.closeReader()
        await transport.release()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertNil(documents.reader)
        XCTAssertFalse(mock.requests.contains { $0.path == bankPath + "/memories/list" })
    }

    func testDefaultServerURL() async {
        let (app, _) = makeApp(MockTransport())
        XCTAssertEqual(app.serverURL.absoluteString, "http://127.0.0.1:8888")
    }

    func testRestoredServerAddressStillPassesSecurityPolicy() {
        for address in ["http://public.example.com", "http://127.example.com", "https://user:private@example.com"] {
            let transport = MockTransport()
            let app = AppModel(settings: InMemorySettingsStore([SettingsKey.serverURL: address]), transport: transport, ledger: nil, automaticActions: false)
            XCTAssertEqual(app.serverURL.absoluteString, AppModel.defaultServerURL)
            XCTAssertTrue(app.serverURLNotice?.contains("refusée") == true)
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testConnectLoadsVersionBanksAndSelectsFirstBank() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, store) = makeApp(t)
        await app.connect()
        XCTAssertEqual(app.connection.version?.apiVersion, "1.0.0")
        XCTAssertEqual(app.banks.map(\.bankId), [testBank, "scratch"])
        XCTAssertEqual(app.selectedBankID, testBank)
        XCTAssertEqual(store.string(forKey: SettingsKey.lastBank), testBank)
    }

    func testLastBankIsRestored() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, _) = makeApp(t, settings: [SettingsKey.lastBank: "scratch"])
        await app.connect()
        XCTAssertEqual(app.selectedBankID, "scratch")
    }

    func testConnectionFailureIsReported() async {
        let t = MockTransport()
        t.on("GET", "/version", json: #"{"detail":"boom"}"#, status: 500)
        let (app, _) = makeApp(t)
        await app.connect()
        guard case .failed(let msg) = app.connection else { return XCTFail("\(app.connection)") }
        XCTAssertTrue(msg.contains("HTTP 500"))
        XCTAssertNil(app.session)
    }

    func testApplyServerURLValidatesPersistsAndReconnects() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, store) = makeApp(t)
        let bad = await app.applyServerURL("   ")
        XCTAssertFalse(bad)
        XCTAssertEqual(app.serverURL.absoluteString, "http://127.0.0.1:8888")
        let ok = await app.applyServerURL("localhost:9000/")
        XCTAssertTrue(ok)
        XCTAssertEqual(app.serverURL.absoluteString, "http://localhost:9000")
        XCTAssertEqual(store.string(forKey: SettingsKey.serverURL), "http://localhost:9000")
        XCTAssertTrue(app.connection.isConnected)
        XCTAssertTrue(t.requests.contains { $0.path == "/version" })
        // Un nouvel AppModel relit l'URL enregistrée.
        let (again, _) = makeApp(t, settings: [SettingsKey.serverURL: "http://localhost:9000"])
        XCTAssertEqual(again.serverURL.absoluteString, "http://localhost:9000")
    }

    func testOpenDocumentSwitchesSectionAndFocusesChunk() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, _) = makeApp(t)
        await app.connect()
        app.openDocument(id: "codex-abc-task-002", chunkID: "codex-abc-task-002_1")
        XCTAssertEqual(app.selectedSection, .documents)
        let reader = try! XCTUnwrap(app.session?.documents.reader)
        for _ in 0..<100 where reader.state.value == nil { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(reader.focusedChunkID, "codex-abc-task-002_1")
        XCTAssertFalse(reader.focusedBlockIDs.isEmpty)
    }

    func testInsightActionsNavigateAndNeverWriteWithoutConfirmation() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, _) = makeApp(t)
        await app.connect()
        // La consolidation se lance et se reprend depuis sa vue (Mémoire › Consolidation), toujours après confirmation.
        app.handle(.runConsolidation)
        XCTAssertEqual(app.selectedSection, .operations)
        XCTAssertNotNil(app.session?.consolidation.confirmation)
        app.handle(.recoverConsolidation)
        XCTAssertNotNil(app.session?.consolidation.confirmation)
        XCTAssertTrue(t.requests.filter { $0.method != "GET" }.isEmpty)
        app.handle(.openOperations(status: "failed"))
        XCTAssertEqual(app.session?.operations.statusFilter, .failed)
    }

    func testSwitchingBankCreatesFreshSession() async {
        let t = MockTransport()
        t.installStandardRoutes()
        let (app, _) = makeApp(t)
        await app.connect()
        let first = app.session
        app.selectBank("scratch")
        XCTAssertEqual(app.selectedBankID, "scratch")
        XCTAssertFalse(first === app.session)
        app.selectBank("scratch")  // idempotent
        XCTAssertEqual(app.selectedBankID, "scratch")
    }
}

/// A response which deliberately ignores cancellation, to exercise the caller's boundary checks.
private actor HeldReadTransport: HTTPTransport {
    let mock: MockTransport
    let path: String
    private var held: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(mock: MockTransport, path: String) { self.mock = mock; self.path = path }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == path {
            await withCheckedContinuation { held = $0; observer?.resume(); observer = nil }
        }
        return try await mock.send(request)
    }
    func waitForHold() async {
        if held != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { held?.resume(); held = nil }
}
