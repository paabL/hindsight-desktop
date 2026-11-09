import Foundation
import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

private actor OperationReadGate: HTTPTransport {
    let mock: MockTransport
    let matches: @Sendable (URLRequest) -> Bool
    let override: MockResponse?
    private var armed = true
    private var held: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(mock: MockTransport, override: MockResponse? = nil, matches: @escaping @Sendable (URLRequest) -> Bool) {
        self.mock = mock; self.matches = matches; self.override = override
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if armed, matches(request) {
            armed = false
            await withCheckedContinuation { held = $0; observer?.resume(); observer = nil }
            if let override {
                return (override.body, HTTPURLResponse(url: request.url!, statusCode: override.status, httpVersion: nil, headerFields: override.headers)!)
            }
        }
        return try await mock.send(request)
    }
    func wait() async { if held == nil { await withCheckedContinuation { observer = $0 } } }
    func release() { held?.resume(); held = nil }
}

private func operationPage(_ ids: [String], status: String = "completed", total: Int? = nil, offset: Int = 0) -> MockResponse {
    let rows = ids.map { OperationResponse(id: $0, taskType: "retain", itemsCount: 1, createdAt: "2026-11-04T12:00:00Z", status: status) }
    return MockResponse(body: try! JSONEncoder().encode(OperationsListResponse(bankId: testBank, total: total ?? ids.count, limit: 100, offset: offset, operations: rows)))
}

@MainActor
final class OperationStateStressTests: XCTestCase {
    func testLateCounterCannotOverwriteTheCurrentFiltersCounts() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            let status = request.queryValue("status") ?? "completed"
            let total = ["pending": 7, "processing": 2, "failed": 1, "completed": 1][status] ?? 0
            return operationPage([status], status: status, total: total)
        }
        let gate = OperationReadGate(mock: mock, override: operationPage(["old"], status: "pending", total: 99)) {
            let query = URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return query.contains(URLQueryItem(name: "status", value: "pending"))
                && query.contains(URLQueryItem(name: "limit", value: "1"))
        }
        let vm = OperationsViewModel(client: HindsightClient(transport: gate), bank: testBank)
        vm.statusFilter = .failed
        let old = Task { await vm.reload() }
        await gate.wait()
        vm.statusFilter = .completed
        await vm.reload()
        await gate.release(); await old.value
        XCTAssertEqual(vm.rows.map(\.id), ["completed"])
        XCTAssertEqual(vm.operationCounts?["pending"], 7)
        XCTAssertEqual(vm.operationCounts?["failed"], 1)
        XCTAssertFalse(vm.isRefreshing)
    }

    func testOldFilterResponseCannotReplaceTheNewFilter() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            let status = request.queryValue("status") ?? "completed"
            return operationPage([status], status: status)
        }
        let gate = OperationReadGate(mock: mock) { request in
            request.url?.path.hasSuffix("/operations") == true && request.url?.query?.contains("status=failed") == true
        }
        let vm = OperationsViewModel(client: HindsightClient(transport: gate), bank: testBank)
        vm.statusFilter = .failed
        let old = Task { await vm.reload() }
        await gate.wait()
        vm.statusFilter = .completed
        await vm.reload()
        await gate.release(); await old.value
        XCTAssertEqual(vm.rows.map(\.id), ["completed"])
        XCTAssertEqual(vm.rows.first?.status, .completed)
        XCTAssertFalse(vm.isRefreshing)
    }

    func testStaleNextPageCannotAppendToAnotherFilter() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            if request.queryValue("status") == "failed" { return operationPage(["failure"], status: "failed") }
            let offset = Int(request.queryValue("offset") ?? "0") ?? 0
            return operationPage((offset..<min(offset + 100, 200)).map { "row-\($0)" }, total: 200, offset: offset)
        }
        let gate = OperationReadGate(mock: mock) { $0.url?.query?.contains("offset=100") == true }
        let vm = OperationsViewModel(client: HindsightClient(transport: gate), bank: testBank)
        await vm.reload()
        let more = Task { await vm.loadMore() }
        await gate.wait()
        vm.statusFilter = .failed
        await vm.reload()
        await gate.release(); await more.value
        XCTAssertEqual(vm.rows.map(\.id), ["failure"])
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testQuietRefreshPreservesOpenedPagesAndDeduplicatesRows() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            let offset = Int(request.queryValue("offset") ?? "0") ?? 0
            return operationPage((offset..<min(offset + 100, 225)).map { "row-\($0)" }, total: 225, offset: offset)
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        await vm.reload(); await vm.loadMore()
        XCTAssertEqual(vm.rows.count, 200)
        await vm.reload(silently: true)
        XCTAssertEqual(vm.rows.count, 200)
        XCTAssertEqual(Set(vm.rows.map(\.id)).count, 200)
        await vm.loadMore()
        XCTAssertEqual(vm.rows.count, 225)
        XCTAssertFalse(vm.canLoadMore)
    }

    func testOperationsListNeverWaitsOnBankStatistics() async {
        // `/stats` relit toute la banque : Traitements, qui sonde, ne lit que les listes d'opérations. La
        // consolidation (statistiques, réglages, consolidations actives) se lit dans sa vue.
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/stats", json: "{}", status: 503)
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        await vm.reload()
        await vm.reload(silently: true)
        XCTAssertFalse(vm.rows.isEmpty)
        XCTAssertNil(vm.state.errorMessage)
        XCTAssertFalse(mock.requests.contains { $0.path.hasSuffix("/stats") || $0.path.hasSuffix("/config") })
        XCTAssertFalse(mock.requests.contains { $0.queryValue("type") == "consolidation" })
    }

    func testCancelAndDeleteRefusalsAreNotReportedAsSuccess() async throws {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("DELETE", bankPath + "/operations/op-pend", json: #"{"success":false,"message":"still running","operation_id":"op-pend"}"#)
        mock.on("DELETE", bankPath + "/operations/op-ok/delete", json: #"{"success":false,"message":"not deleted","operation_id":"op-ok"}"#)
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        await vm.reload()
        vm.requestCancel(try XCTUnwrap(vm.rows.first { $0.id == "op-pend" }))
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage?.contains("Échec") == true)
        vm.requestDelete(try XCTUnwrap(vm.rows.first { $0.id == "op-ok" }))
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage?.contains("not deleted") == true)
        XCTAssertTrue(vm.actionMessage?.contains("Échec") == true)
    }

    func testLateConnectionFailureFromAnotherServerCannotDisconnectCurrentServer() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        let gate = OperationReadGate(mock: mock, override: .json(#"{"detail":"old failure"}"#, status: 503)) {
            $0.url?.host == "old.example.test" && $0.url?.path == "/version"
        }
        let app = AppModel(settings: InMemorySettingsStore([SettingsKey.serverURL:"https://old.example.test"]), transport: gate, ledger: nil, automaticActions: false)
        let old = Task { await app.connect() }
        await gate.wait()
        let accepted = await app.applyServerURL("https://new.example.test")
        XCTAssertTrue(accepted)
        await gate.release(); await old.value
        XCTAssertTrue(app.connection.isConnected)
        XCTAssertEqual(app.session?.client.baseURL.host, "new.example.test")
    }

    func testLateBankListCannotClearBanksOfTheCurrentServer() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        let gate = OperationReadGate(mock: mock, override: .json(#"{"banks":[],"total":0,"limit":200,"offset":0}"#)) {
            $0.url?.host == "old.example.test" && $0.url?.path == "/v1/default/banks"
        }
        let app = AppModel(settings: InMemorySettingsStore([SettingsKey.serverURL:"https://old.example.test"]), transport: gate, ledger: nil, automaticActions: false)
        let old = Task { await app.connect() }
        await gate.wait()
        let accepted = await app.applyServerURL("https://new.example.test")
        XCTAssertTrue(accepted)
        await gate.release(); await old.value
        XCTAssertFalse(app.banks.isEmpty)
        XCTAssertEqual(app.session?.client.baseURL.host, "new.example.test")
    }
}
