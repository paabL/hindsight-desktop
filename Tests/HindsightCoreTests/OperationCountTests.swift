import Foundation
import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

private func countPage(_ count: Int, status: String, limit: Int = 100, offset: Int = 0) -> MockResponse {
    let rows = (offset..<max(offset, min(offset + limit, count))).map {
        OperationResponse(id: "\(status)-\($0)", taskType: "retain", itemsCount: 1,
                          createdAt: "2026-11-05T12:00:00Z", status: status)
    }
    let page = OperationsListResponse(bankId: testBank, total: count, limit: limit, offset: offset, operations: rows)
    return MockResponse(body: try! JSONEncoder().encode(page))
}

@MainActor
final class OperationCountTests: XCTestCase {
    func testLiveCountsReplaceCachedFailureAfterRetry() async throws {
        let mock = MockTransport(); mock.installStandardRoutes()
        var cached = try JSONDecoder().decode(BankStatsResponse.self, from: Data(Fixture.string("bank_stats").utf8))
        cached.operationsByStatus = ["failed": 1, "pending": 0]
        cached.failedOperations = 1
        mock.on("GET", bankPath + "/stats") { [cached] _ in
            MockResponse(body: try! JSONEncoder().encode(cached))
        }
        mock.on("GET", bankPath + "/operations") { request in
            let status = request.queryValue("status") ?? "all"
            let totals = ["failed": 0, "pending": 1, "processing": 2]
            return countPage(totals[status] ?? 0, status: status,
                             limit: Int(request.queryValue("limit") ?? "100")!)
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed
        await vm.reload()
        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertEqual(vm.operationCounts, ["failed": 0, "pending": 1, "processing": 2])
        XCTAssertFalse(mock.requests.contains { $0.path.hasSuffix("/stats") }, "The cached aggregate is never read")
        let reads = mock.requests.filter { $0.path.hasSuffix("/operations") }
        XCTAssertEqual(reads.count, 3)
        XCTAssertEqual(reads.filter { $0.queryValue("status") == "failed" }.count, 1, "Reuse the displayed filter's total")
        XCTAssertTrue(reads.filter { $0.queryValue("status") != "failed" }.allSatisfy { $0.queryValue("limit") == "1" })
    }

    func testCompleteBankListNeedsNoExtraCounterRequests() async throws {
        let mock = MockTransport(); mock.installStandardRoutes()
        var page = try JSONDecoder().decode(OperationsListResponse.self, from: Data(Fixture.string("operations_list").utf8))
        page.total = page.operations.count
        mock.on("GET", bankPath + "/operations") { [page] _ in
            MockResponse(body: try! JSONEncoder().encode(page))
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        await vm.reload()
        XCTAssertEqual(vm.operationCounts?["pending"], 1)
        XCTAssertEqual(vm.operationCounts?["processing"], 1)
        XCTAssertEqual(vm.operationCounts?["failed"], 3)
        XCTAssertEqual(mock.requests.filter { $0.path.hasSuffix("/operations") }.count, 1)
    }

    func testFilteredPaginationUsesFullTotalAndPreservesGlobalScope() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            let status = request.queryValue("status") ?? "all"
            let totals = ["failed": 245, "pending": 8, "processing": 2]
            return countPage(totals[status] ?? 0, status: status,
                             limit: Int(request.queryValue("limit") ?? "100")!,
                             offset: Int(request.queryValue("offset") ?? "0")!)
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed
        await vm.reload()
        XCTAssertEqual(vm.rows.count, 100)
        XCTAssertEqual(vm.operationCounts, ["failed": 245, "pending": 8, "processing": 2])
        await vm.loadMore()
        XCTAssertEqual(vm.rows.count, 200)
        XCTAssertEqual(vm.operationCounts?["failed"], 245)
        await vm.reload(silently: true)
        XCTAssertEqual(vm.rows.count, 200)
        XCTAssertEqual(vm.operationCounts?["failed"], 245)
        XCTAssertTrue(vm.canLoadMore)
    }

    func testTypeFilterDoesNotNarrowCountersWhichSkipParentBatchesLikeRetry() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            let status = request.queryValue("status") ?? "all"
            let typed = request.queryValue("type") != nil
            // Sans exclusion des lots parents, un échec de plus (le lot) : les compteurs ne doivent pas le voir.
            let parents = request.queryValue("exclude_parents") == "true" ? 0 : 1
            let total = typed ? 2 : (["failed": 9, "pending": 5, "processing": 3][status] ?? 0) + parents
            return countPage(total, status: status, limit: Int(request.queryValue("limit") ?? "100")!)
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed; vm.typeFilter = "retain"
        await vm.reload()
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.operationCounts, ["failed": 9, "pending": 5, "processing": 3])
        // Les deux lectures de l'état de consolidation (type « consolidation ») ne sont pas des compteurs.
        let counters = mock.requests.filter { $0.path.hasSuffix("/operations") && $0.queryValue("limit") == "1" }
        XCTAssertEqual(counters.count, 3)
        XCTAssertTrue(counters.allSatisfy { $0.queryValue("type") == nil && $0.queryValue("exclude_parents") == "true" })
    }

    func testCounterFailureKeepsRowsWithoutPresentingCachedCountsAsLive() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            if request.queryValue("status") == "pending" { return .json("{}", status: 503) }
            return countPage(1, status: request.queryValue("status") ?? "failed")
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed
        await vm.reload()
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertNil(vm.operationCounts, "The UI explicitly falls back to counts among loaded operations")
        XCTAssertNil(vm.state.errorMessage)
    }

    func testRetryWithNoRemainingFailuresRefreshesTheVisibleStateWithoutWriting() async {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            countPage(request.queryValue("status") == "failed" ? 1 : 0,
                      status: request.queryValue("status") ?? "all")
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed
        await vm.reload()
        XCTAssertEqual(vm.rows.count, 1)
        mock.on("GET", bankPath + "/operations") { request in
            countPage(request.queryValue("status") == "pending" ? 1 : 0,
                      status: request.queryValue("status") ?? "all")
        }
        await vm.requestRetryAllFailed()
        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertEqual(vm.operationCounts?["failed"], 0)
        XCTAssertEqual(vm.operationCounts?["pending"], 1)
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(vm.actionMessage, "Aucune opération en échec à relancer.")
        XCTAssertTrue(mock.requests.allSatisfy { $0.method == "GET" })
    }

    func testRefusedRetryRefreshesAnOperationResolvedByAnotherClient() async throws {
        let mock = MockTransport(); mock.installStandardRoutes()
        mock.on("GET", bankPath + "/operations") { request in
            countPage(request.queryValue("status") == "failed" ? 1 : 0,
                      status: request.queryValue("status") ?? "all")
        }
        let vm = OperationsViewModel(client: makeClient(mock), bank: testBank)
        vm.statusFilter = .failed
        await vm.reload()
        let row = try XCTUnwrap(vm.rows.first)
        vm.requestRetry(row)
        mock.on("GET", bankPath + "/operations") { request in
            countPage(0, status: request.queryValue("status") ?? "all")
        }
        mock.on("POST", bankPath + "/operations/\(row.id)/retry",
                json: #"{"detail":"already completed"}"#, status: 409)
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertEqual(vm.operationCounts?["failed"], 0)
        XCTAssertTrue(vm.actionMessage?.contains("already completed") == true)
        XCTAssertEqual(mock.requests.filter { $0.method == "POST" }.count, 1)
    }
}
