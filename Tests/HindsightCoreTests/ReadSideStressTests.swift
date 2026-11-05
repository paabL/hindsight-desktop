import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import HindsightCore

/// Holds chosen reads even after their caller is cancelled. No server or private data is involved.
private actor ReadSideGate: HTTPTransport {
    let mock: MockTransport
    let matches: @Sendable (URLRequest) -> Bool
    private let maxHeld: Int
    private let captureResponse: Bool
    private var held: [CheckedContinuation<Void, Never>] = []
    private var open = false

    init(mock: MockTransport, maxHeld: Int = .max, captureResponse: Bool = false, matches: @escaping @Sendable (URLRequest) -> Bool) {
        self.mock = mock
        self.maxHeld = maxHeld
        self.captureResponse = captureResponse
        self.matches = matches
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if captureResponse {
            let response = try await mock.send(request)
            await hold(request)
            return response
        }
        await hold(request)
        return try await mock.send(request)
    }

    private func hold(_ request: URLRequest) async {
        if !open, held.count < maxHeld, matches(request) {
            await withCheckedContinuation { continuation in
                held.append(continuation)
            }
        }
    }

    func waitForHeld(_ count: Int = 1, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while held.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertGreaterThanOrEqual(held.count, count, "expected synthetic requests were not made", file: file, line: line)
    }

    func release() {
        open = true
        let continuations = held
        held = []
        for continuation in continuations { continuation.resume() }
    }
}

private func readSideClient(_ transport: any HTTPTransport) -> HindsightClient {
    HindsightClient(baseURL: URL(string: "http://127.0.0.1:8888")!, transport: transport)
}

private func readSidePage(offset: Int, count: Int, total: Int, prefix: String = "f") -> String {
    let items = (offset..<(offset + count)).map { i in
        #"{"id":"\#(prefix)\#(i)","text":"Synthetic fact \#(i)","fact_type":"\#(["world", "experience", "observation"][i % 3])","mentioned_at":"2026-10-\#(String(format: "%02d", 1 + i % 28))T10:00:00Z","tags":[],"entities":"","metadata":{},"source_memory_ids":[]}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))],"total":\#(total),"limit":\#(count),"offset":\#(offset)}"#
}

/// Real asynchronous delays let later pages finish first without blocking an executor thread.
private actor ReadSidePagingTransport: HTTPTransport {
    let total: Int
    private(set) var offsets: [Int] = []
    private(set) var completed: [Int] = []
    private(set) var peak = 0
    private var active = 0

    init(total: Int) { self.total = total }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let offset = Int(query.first { $0.name == "offset" }!.value!)!
        let limit = Int(query.first { $0.name == "limit" }!.value!)!
        offsets.append(offset)
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        if offset > 0 {
            let index = offset / limit
            try await Task.sleep(for: .milliseconds((4 - index % 4) * 4))
        }
        completed.append(offset)
        let json = readSidePage(offset: offset, count: max(0, min(limit, total - offset)), total: total)
        return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class TimelineReadStressTests: XCTestCase {
    func testSupersededSuccessAndFailureCannotReplaceNewTimeline() async {
        for status in [200, 500] {
            let mock = MockTransport()
            mock.on("GET", "\(bankPath)/memories/list") { request in
                if request.queryValue("q") == "old" {
                    return .json(status == 200 ? readSidePage(offset: 0, count: 1, total: 1, prefix: "old") : #"{"detail":"old failure"}"#, status: status)
                }
                return .json(readSidePage(offset: 0, count: 2, total: 2, prefix: "new"))
            }
            let gate = ReadSideGate(mock: mock) { $0.url?.query?.contains("q=old") == true }
            let vm = TimelineViewModel(client: readSideClient(gate), bank: testBank)
            vm.text = "old"
            let old = Task { await vm.reload() }
            await gate.waitForHeld()
            vm.text = "new"
            await vm.reload()
            await gate.release()
            await old.value
            XCTAssertEqual(vm.facts.map(\.id), ["new0", "new1"])
            XCTAssertEqual(vm.totalAvailable, 2)
            XCTAssertNotNil(vm.state.value)
            XCTAssertEqual(vm.periods.reduce(0) { $0 + $1.count } + vm.undated.count, 2)
        }
    }

    func testCancellingCallerCancelsOwnedLoadAndRejectsLateResponse() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/list", json: readSidePage(offset: 0, count: 3, total: 3))
        let gate = ReadSideGate(mock: mock) { _ in true }
        let vm = TimelineViewModel(client: readSideClient(gate), bank: testBank)
        let task = Task { await vm.reload() }
        await gate.waitForHeld()
        task.cancel()
        await gate.release()
        await task.value
        XCTAssertTrue(vm.facts.isEmpty)
        XCTAssertTrue(vm.periods.isEmpty)
        XCTAssertFalse(vm.state.isLoading)
        XCTAssertNil(vm.state.errorMessage)
    }

    func testQueryIsFrozenAndServerEntityMatchIsNotDiscardedByLocalTypeFilter() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/list") { request in
            let offset = Int(request.queryValue("offset")!)!
            return .json(readSidePage(offset: offset, count: min(2, 6 - offset), total: 6))
        }
        let gate = ReadSideGate(mock: mock) { $0.url?.query?.contains("offset=0") == true }
        let vm = TimelineViewModel(client: readSideClient(gate), bank: testBank, pageSize: 2)
        vm.text = "frozen"
        vm.filter.types = ["world", "experience"]
        vm.filter.entity = EntityRef(id: "entity-1", name: "Name absent from list rows")
        vm.filter.tags = ["frozen-tag"]
        let task = Task { await vm.reload() }
        await gate.waitForHeld()
        vm.text = "edited"
        vm.filter = FactFilter()
        vm.axis = .mentioned
        vm.maxFacts = 1
        await gate.release()
        await task.value
        XCTAssertEqual(vm.facts.map(\.id), ["f0", "f1", "f3", "f4"])
        XCTAssertFalse(vm.isTruncated, "editing the next load's limit must not relabel this complete filtered result")
        XCTAssertEqual(mock.requests.count, 3)
        for request in mock.requests {
            XCTAssertEqual(request.queryValue("q"), "frozen")
            XCTAssertEqual(request.queryValue("entity_id"), "entity-1")
            XCTAssertEqual(request.query["tags"], ["frozen-tag"])
        }
    }

    func testTwentyThousandFactsRemainOrderedBoundedAndAccountedFor() async {
        let transport = ReadSidePagingTransport(total: 25_317)
        let vm = TimelineViewModel(client: readSideClient(transport), bank: testBank, pageSize: 137)
        let start = ContinuousClock.now
        await vm.reload()
        let elapsed = start.duration(to: .now)
        let peak = await transport.peak
        let offsets = await transport.offsets
        let completed = await transport.completed
        XCTAssertEqual(vm.facts.map(\.id), (0..<20_000).map { "f\($0)" })
        XCTAssertEqual(Set(vm.facts.map(\.id)).count, 20_000)
        XCTAssertEqual(vm.periods.reduce(0) { $0 + $1.count } + vm.undated.count, 20_000)
        XCTAssertEqual(vm.bars.reduce(0) { $0 + $1.count }, 20_000)
        XCTAssertEqual(offsets.sorted(), Array(stride(from: 0, to: 20_000, by: 137)))
        XCTAssertNotEqual(completed, completed.sorted(), "the transport must actually complete out of order")
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertTrue(vm.isTruncated)
        XCTAssertNotNil(vm.state.value)
        print("READ-SIDE DIAGNOSTIC (synthetic, not a benchmark): 20000 facts, \(offsets.count) pages, peak=\(peak), elapsed=\(elapsed)")
    }

    func testLocalTypeFilteringScansBeyondTwentyThousandRawRowsToKeepTwentyThousandMatches() async {
        let transport = ReadSidePagingTransport(total: 45_000)
        let vm = TimelineViewModel(client: readSideClient(transport), bank: testBank)
        vm.filter.types = ["world", "experience"]
        await vm.reload()
        let expected = (0..<30_000).filter { $0 % 3 != 2 }.map { "f\($0)" }
        XCTAssertEqual(vm.facts.map(\.id), expected)
        XCTAssertEqual(vm.facts.count, 20_000)
        let offsets = await transport.offsets
        let peak = await transport.peak
        XCTAssertEqual(offsets, Array(stride(from: 0, to: 30_000, by: 1000)))
        XCTAssertEqual(peak, 1, "local filtering preserves sequential scanning until enough matching facts are collected")
        XCTAssertTrue(vm.isTruncated)
        XCTAssertNotNil(vm.state.value)
    }

    func testPartialFailureRebuildsHistogramFromCurrentPartialFacts() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/list", json: readSidePage(offset: 0, count: 6, total: 6))
        let vm = TimelineViewModel(client: makeClient(mock), bank: testBank, pageSize: 2)
        await vm.reload()
        mock.on("GET", "\(bankPath)/memories/list") { request in
            if request.queryValue("offset") != "0" { return .json(#"{"detail":"failure"}"#, status: 500) }
            return .json(readSidePage(offset: 0, count: 2, total: 6, prefix: "partial"))
        }
        await vm.reload()
        XCTAssertEqual(vm.facts.map(\.id), ["partial0", "partial1"])
        XCTAssertEqual(vm.periods.flatMap(\.facts).map(\.id).sorted(), ["partial0", "partial1"])
        XCTAssertEqual(vm.bars.reduce(0) { $0 + $1.count }, 2)
        XCTAssertNotNil(vm.state.errorMessage)
    }

    func testShortPrefetchedPageResumesAtActualOffsetWithoutMissingOrDuplicatingFacts() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/list") { request in
            let offset = Int(request.queryValue("offset")!)!
            let count = offset == 3 ? 1 : min(3, 12 - offset)
            return .json(readSidePage(offset: offset, count: count, total: 12))
        }
        let vm = TimelineViewModel(client: makeClient(mock), bank: testBank, pageSize: 3)
        await vm.reload()
        XCTAssertEqual(vm.facts.map(\.id), (0..<12).map { "f\($0)" })
        XCTAssertTrue(mock.requests.contains { $0.queryValue("offset") == "4" })
        XCTAssertNil(vm.state.errorMessage)
    }

    func testZeroCapDoesNotFetchAndNonpositivePageSizeCannotCreateZeroStride() async {
        let mock = MockTransport()
        let vm = TimelineViewModel(client: makeClient(mock), bank: testBank, pageSize: 0)
        vm.maxFacts = 0
        await vm.reload()
        XCTAssertEqual(vm.pageSize, 1)
        XCTAssertTrue(mock.requests.isEmpty)
        XCTAssertTrue(vm.facts.isEmpty)
        XCTAssertNotNil(vm.state.value)
        XCTAssertNil(vm.progress)
    }
}

@MainActor
final class GraphReadStressTests: XCTestCase {
    func testOldModeResponseCannotReplaceNewGraphOrTotals() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/entities/graph", json: Fixture.string("entity_graph"))
        mock.on("GET", "\(bankPath)/graph", json: Fixture.string("graph"))
        let gate = ReadSideGate(mock: mock) { $0.url?.path.hasSuffix("/entities/graph") == true }
        let vm = GraphViewModel(client: readSideClient(gate), bank: testBank)
        vm.mode = .entities
        let old = Task { await vm.reload(layout: false) }
        await gate.waitForHeld()
        vm.mode = .facts
        await vm.reload(layout: false)
        let nodes = vm.nodes, edges = vm.edges, total = vm.serverNodeTotal
        await gate.release()
        await old.value
        XCTAssertEqual(vm.nodes, nodes)
        XCTAssertEqual(vm.edges, edges)
        XCTAssertEqual(vm.serverNodeTotal, total)
        XCTAssertTrue(vm.nodes.allSatisfy { $0.kind != "entity" })
        XCTAssertTrue(vm.positions.isEmpty)
        XCTAssertFalse(vm.isAnimating)
    }

    func testOldEntitySuccessAndFailureCannotReplaceNewSelection() async {
        for status in [200, 500] {
            let mock = MockTransport()
            mock.on("GET", "\(bankPath)/entities/e0", json: status == 200 ? Fixture.string("entity_e0") : #"{"detail":"old failure"}"#, status: status)
            mock.on("GET", "\(bankPath)/entities/e1", json: #"{"id":"e1","canonical_name":"New entity","mention_count":1,"observations":[]}"#)
            mock.on("GET", "\(bankPath)/memories/list") { request in
                if request.queryValue("entity_id") == "e0" {
                    return .json(status == 200 ? readSidePage(offset: 0, count: 1, total: 1, prefix: "old") : #"{"detail":"old failure"}"#, status: status)
                }
                return .json(readSidePage(offset: 0, count: 1, total: 1, prefix: "new"))
            }
            let gate = ReadSideGate(mock: mock) { $0.url?.path.hasSuffix("/entities/e0") == true || $0.url?.query?.contains("entity_id=e0") == true }
            let vm = GraphViewModel(client: readSideClient(gate), bank: testBank)
            vm.mode = .entities
            let old = Task { await vm.select("e0") }
            await gate.waitForHeld(2)
            await vm.select("e1")
            await gate.release()
            await old.value
            XCTAssertEqual(vm.selectedNodeID, "e1")
            XCTAssertEqual(vm.entityDetail.value?.id, "e1")
            XCTAssertEqual(vm.nodeFacts.value?.map(\.id), ["new0"])
            XCTAssertNil(vm.entityDetail.errorMessage)
            XCTAssertNil(vm.nodeFacts.errorMessage)
        }
    }

    func testDeselectionAndReloadInvalidatePendingEntityRead() async {
        for reload in [false, true] {
            let mock = MockTransport()
            mock.on("GET", "\(bankPath)/entities/e0", json: Fixture.string("entity_e0"))
            mock.on("GET", "\(bankPath)/memories/list", json: readSidePage(offset: 0, count: 1, total: 1))
            mock.on("GET", "\(bankPath)/entities/graph", json: Fixture.string("entity_graph"))
            let gate = ReadSideGate(mock: mock) { $0.url?.path.hasSuffix("/entities/e0") == true || $0.url?.path.hasSuffix("/memories/list") == true }
            let vm = GraphViewModel(client: readSideClient(gate), bank: testBank)
            vm.mode = .entities
            let old = Task { await vm.select("e0") }
            await gate.waitForHeld(2)
            if reload { await vm.reload(layout: false) } else { await vm.select(nil) }
            await gate.release()
            await old.value
            XCTAssertNil(vm.selectedNodeID)
            XCTAssertNil(vm.entityDetail.value)
            XCTAssertNil(vm.nodeFacts.value)
            XCTAssertFalse(vm.entityDetail.isLoading)
            XCTAssertFalse(vm.nodeFacts.isLoading)
        }
    }

    func testCancelledGraphReadDoesNotPublishLateSuccess() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/graph", json: Fixture.string("graph"))
        let gate = ReadSideGate(mock: mock) { _ in true }
        let vm = GraphViewModel(client: readSideClient(gate), bank: testBank)
        let task = Task { await vm.reload(layout: false) }
        await gate.waitForHeld()
        task.cancel()
        await gate.release()
        await task.value
        XCTAssertTrue(vm.nodes.isEmpty)
        XCTAssertFalse(vm.state.isLoading)
        XCTAssertNil(vm.state.errorMessage)
    }

    func testNegativeAndStaleInteractionIndicesAreSafe() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/graph", json: Fixture.string("graph"))
        let vm = GraphViewModel(client: makeClient(mock), bank: testBank)
        await vm.reload(layout: false)
        XCTAssertEqual(vm.neighbors(of: -1), [])
        XCTAssertEqual(vm.neighbors(of: vm.nodes.count), [])
        vm.hover(-1)
        XCTAssertNil(vm.hoveredNode)
        vm.hover(vm.nodes.count)
        XCTAssertNil(vm.hoveredNode)
    }
}

@MainActor
final class BankCatalogReadStressTests: XCTestCase {
    func testTagCapIsExactEvenIfServerReturnsAnOversizedLastPage() async throws {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/tags") { request in
            let offset = Int(request.queryValue("offset")!)!
            let items = (offset..<(offset + 500)).map { #"{"tag":"tag:\#($0)","count":1}"# }
            return .json(#"{"items":[\#(items.joined(separator: ","))],"total":2000,"limit":500,"offset":\#(offset)}"#)
        }
        let tags = try await BankCatalog.allTags(client: makeClient(mock), bank: testBank, cap: 501)
        XCTAssertEqual(tags.count, 501)
        XCTAssertEqual(tags.last?.tag, "tag:500")
        XCTAssertEqual(mock.requests.map { $0.queryValue("limit") }, ["500", "1"])
        XCTAssertEqual(mock.requests.map { $0.queryValue("offset") }, ["0", "500"])
    }

    func testCancelledCatalogDoesNotPublishPartialResults() async {
        let mock = MockTransport()
        mock.installStandardRoutes()
        let gate = ReadSideGate(mock: mock) { $0.url?.path.hasSuffix("/tags") == true }
        let catalog = BankCatalog(client: readSideClient(gate), bank: testBank)
        let task = Task { await catalog.loadIfNeeded() }
        await gate.waitForHeld()
        task.cancel()
        await gate.release()
        await task.value
        XCTAssertTrue(catalog.tags.isEmpty)
        XCTAssertTrue(catalog.entities.isEmpty)
        XCTAssertFalse(catalog.state.isLoading)
        XCTAssertNil(catalog.state.errorMessage)
        XCTAssertTrue(catalog.entities(matching: "", limit: -1).isEmpty)
    }
}

@MainActor
final class DocumentWriteRefreshTests: XCTestCase {
    private let documentID = "codex-abc-task-002"

    private func make(_ transport: any HTTPTransport) -> DocumentsViewModel {
        let client = readSideClient(transport)
        return DocumentsViewModel(client: client, bank: testBank, attachmentLoader: AttachmentLoader(client: client))
    }

    private func waitForFacts(_ reader: DocumentReaderViewModel, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while reader.facts.value == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(reader.facts.value, file: file, line: line)
    }

    func testTagScopeAndReprocessWritesRefreshReaderAndAwaitListWithoutTrackingCallback() async throws {
        for action in ["tags", "scope", "reprocess"] {
            let mock = MockTransport()
            mock.installStandardRoutes()
            let gate = ReadSideGate(mock: mock) { $0.url?.path == "\(bankPath)/documents" }
            let vm = make(gate)
            vm.serverIs110 = action == "scope"
            XCTAssertNil(vm.onDocumentChanged)
            let reader = vm.open(documentID: documentID)
            await waitForFacts(reader)
            await reader.loadFacts(limit: 37)

            mock.on("GET", "\(bankPath)/documents/\(documentID)", json: Fixture.string("document_task").replacingOccurrences(of: "source:codex", with: "after-write"))
            mock.on("GET", "\(bankPath)/documents", json: Fixture.string("documents_page1").replacingOccurrences(of: "source:codex", with: "after-write"))
            mock.on("GET", "\(bankPath)/memories/list", json: readSidePage(offset: 0, count: 2, total: 2, prefix: "current"))
            mock.on("PATCH", "\(bankPath)/documents/\(documentID)", json: #"{"success":true}"#)
            mock.on("POST", "\(bankPath)/documents/\(documentID)/reprocess", json: #"{"success":true,"operation_id":"synthetic-op","items_count":1}"#)
            switch action {
            case "tags": reader.requestUpdateTags(["after-write"])
            case "scope": reader.requestUpdateScope("per_tag")
            default: reader.requestReprocess()
            }
            let confirmation = try XCTUnwrap(reader.confirmation)
            var finished = false
            let write = Task { await confirmation.perform(); finished = true }
            await gate.waitForHeld()
            XCTAssertFalse(finished, "the write reply must wait for its own list refresh")
            XCTAssertTrue(reader.document?.tags.contains("after-write") == true)
            XCTAssertEqual(reader.facts.value?.map(\.id), ["current0", "current1"])
            XCTAssertEqual(mock.requests.last { $0.path.hasSuffix("/memories/list") }?.queryValue("limit"), "37")
            await gate.release()
            await write.value
            XCTAssertTrue(finished)
            XCTAssertTrue(vm.reader === reader)
            XCTAssertTrue(vm.items.first { $0.id == documentID }?.tags.contains("after-write") == true)
            if action == "reprocess" { XCTAssertTrue(reader.actionMessage?.contains("synthetic-op") == true) }
        }
    }

    func testDeleteRefreshesListAndCannotCloseAnotherReaderOpenedDuringTheWrite() async throws {
        for openAnother in [false, true] {
            let mock = MockTransport()
            mock.installStandardRoutes()
            mock.on("DELETE", "\(bankPath)/documents/\(documentID)", json: #"{"success":true,"message":"ok","document_id":"codex-abc-task-002","memory_units_deleted":30}"#)
            let gate = ReadSideGate(mock: mock) { $0.httpMethod == "DELETE" }
            let vm = make(gate)
            await vm.reload()
            let original = vm.open(documentID: documentID)
            await waitForFacts(original)
            original.requestDelete()
            let confirmation = try XCTUnwrap(original.confirmation)
            XCTAssertFalse(confirmation.isSatisfied(by: "wrong document"))
            XCTAssertTrue(confirmation.isSatisfied(by: documentID))
            let deletion = Task { await confirmation.perform() }
            await gate.waitForHeld()
            let next = openAnother ? vm.open(documentID: "notes-misc") : nil
            mock.on("GET", "\(bankPath)/documents", json: #"{"items":[],"total":0,"limit":100,"offset":0}"#)
            await gate.release()
            await deletion.value
            if let next { XCTAssertTrue(vm.reader === next) } else { XCTAssertNil(vm.reader) }
            XCTAssertTrue(vm.items.isEmpty, "list refresh is complete when deletion returns")
            XCTAssertEqual(vm.total, 0)
            XCTAssertTrue(vm.deletedIDs.contains(documentID))
            XCTAssertTrue(vm.actionMessage?.contains("Supprimé") == true)
            vm.closeReader()
        }
    }

    func testPendingOldDocumentPageCannotAppendAfterAWriteRefresh() async {
        let mock = MockTransport()
        mock.installStandardRoutes()
        let gate = ReadSideGate(mock: mock) { $0.url?.query?.contains("offset=3") == true }
        let vm = make(gate)
        await vm.reload()
        let oldPage = Task { await vm.loadMore() }
        await gate.waitForHeld()
        mock.on("GET", "\(bankPath)/documents") { request in
            if request.queryValue("offset") == "3" { return .json(Fixture.string("documents_page2")) }
            return .json(#"{"items":[],"total":0,"limit":100,"offset":0}"#)
        }
        await vm.reload()
        await gate.release()
        await oldPage.value
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.total, 0)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNotNil(vm.state.value)
    }
}

private actor SourceFactDelayTransport: HTTPTransport {
    let mock: MockTransport
    private(set) var completed: [Int] = []

    init(mock: MockTransport) { self.mock = mock }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let name = request.url?.lastPathComponent ?? ""
        if name.hasPrefix("source-"), let index = Int(name.dropFirst(7)) {
            try await Task.sleep(for: .milliseconds((20 - index) * 4))
            let response = try await mock.send(request)
            completed.append(index)
            return response
        }
        return try await mock.send(request)
    }
}

@MainActor
final class FactDetailReadStressTests: XCTestCase {
    func testTwentySourcesKeepTheirOrderAndLimitDespiteReversedRepliesAndOneFailure() async throws {
        let mock = MockTransport()
        let ids = (0..<25).map { "source-\($0)" }
        let raw: JSONValue = .object([
            "id": .string("obs"), "text": .string("Synthetic observation"), "type": .string("observation"),
            "source_memory_ids": .array(ids.map(JSONValue.string))
        ])
        mock.on("GET", "\(bankPath)/memories/obs") { _ in .json(raw) }
        mock.on("GET", "\(bankPath)/memories/obs/history", json: #"[{"change":"current"}]"#)
        for index in 0..<25 {
            mock.on("GET", "\(bankPath)/memories/source-\(index)", json: index == 7
                ? #"{"detail":"one unavailable source"}"#
                : #"{"id":"source-\#(index)","text":"Source \#(index)","type":"world","document_id":"synthetic-document-\#(index)"}"#,
                status: index == 7 ? 500 : 200)
        }
        let transport = SourceFactDelayTransport(mock: mock)
        let vm = FactDetailViewModel(client: readSideClient(transport), bank: testBank,
                                     hit: FactHit(id: "obs", text: "Summary", type: "observation", documentID: "recall-document", tags: ["from-list"], score: 0.91))
        await vm.load()
        let sources = try XCTUnwrap(vm.sources.value)
        XCTAssertEqual(sources.map(\.id), (0..<20).filter { $0 != 7 }.map { "source-\($0)" })
        XCTAssertEqual(sources.first?.documentID, "synthetic-document-0")
        XCTAssertEqual(vm.hit.sourceFactIDs, ids, "the fetch cap must not truncate the fact's source metadata")
        XCTAssertEqual(vm.hit.score, 0.91)
        XCTAssertEqual(vm.hit.tags, ["from-list"])
        XCTAssertEqual(vm.documentTarget?.documentID, "recall-document")
        let completed = await transport.completed
        XCTAssertEqual(completed.count, 20)
        XCTAssertNotEqual(completed, completed.sorted())
        XCTAssertFalse(mock.requests.contains { $0.path.hasSuffix("source-20") })
        XCTAssertEqual(vm.history, .array([.object(["change": .string("current")])]))
    }

    func testOlderDetailSuccessAndFailureCannotOverwriteReloadedFact() async {
        for status in [200, 500] {
            let mock = MockTransport()
            mock.on("GET", "\(bankPath)/memories/fact", json: status == 200
                ? #"{"id":"fact","text":"Old detail","type":"world"}"#
                : #"{"detail":"old failure"}"#, status: status)
            let gate = ReadSideGate(mock: mock, maxHeld: 1, captureResponse: true) { _ in true }
            let vm = FactDetailViewModel(client: readSideClient(gate), bank: testBank, hit: FactHit(id: "fact", text: "Summary", type: "world", score: 0.8))
            let old = Task { await vm.load() }
            await gate.waitForHeld()
            mock.on("GET", "\(bankPath)/memories/fact", json: #"{"id":"fact","text":"Current detail","type":"world"}"#)
            await vm.load()
            await gate.release()
            await old.value
            XCTAssertEqual(vm.hit.text, "Current detail")
            XCTAssertEqual(vm.detail.value?.text, "Current detail")
            XCTAssertEqual(vm.hit.score, 0.8)
            XCTAssertNil(vm.detail.errorMessage)
        }
    }

    func testOlderChunkSourcesAndHistoryCannotOverwriteReloadedProvenance() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/obs", json: #"{"id":"obs","text":"Old detail","type":"observation","chunk_id":"old-chunk","source_memory_ids":["old-source"]}"#)
        mock.on("GET", "\(bankPath)/memories/old-source", json: #"{"id":"old-source","text":"Old source","type":"world"}"#)
        mock.on("GET", "\(bankPath)/memories/obs/history", json: #"[{"change":"old"}]"#)
        mock.on("GET", "/v1/default/chunks/old-chunk", json: Fixture.string("chunk_m1").replacingOccurrences(of: "codex-abc-task-002_0", with: "old-chunk"))
        let gate = ReadSideGate(mock: mock, maxHeld: 3, captureResponse: true) {
            let path = $0.url?.path ?? ""
            return path.hasSuffix("/old-chunk") || path.hasSuffix("/old-source") || path.hasSuffix("/history")
        }
        let vm = FactDetailViewModel(client: readSideClient(gate), bank: testBank, hit: FactHit(id: "obs", text: "Summary", type: "observation"))
        let old = Task { await vm.load() }
        await gate.waitForHeld(3)
        mock.on("GET", "\(bankPath)/memories/obs", json: #"{"id":"obs","text":"Current detail","type":"observation","chunk_id":"new-chunk","source_memory_ids":["new-source"]}"#)
        mock.on("GET", "\(bankPath)/memories/new-source", json: #"{"id":"new-source","text":"Current source","type":"world"}"#)
        mock.on("GET", "\(bankPath)/memories/obs/history", json: #"[{"change":"current"}]"#)
        mock.on("GET", "/v1/default/chunks/new-chunk", json: Fixture.string("chunk_m1").replacingOccurrences(of: "codex-abc-task-002_0", with: "new-chunk"))
        await vm.load()
        await gate.release()
        await old.value
        XCTAssertEqual(vm.hit.text, "Current detail")
        XCTAssertEqual(vm.chunk.value?.chunkId, "new-chunk")
        XCTAssertEqual(vm.sources.value?.map(\.id), ["new-source"])
        XCTAssertEqual(vm.history, .array([.object(["change": .string("current")])]))
    }

    func testSwitchingTimelineSelectionRejectsCancelledLateDetailAndFollowupReads() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/old", json: #"{"id":"old","text":"Late detail","type":"observation","chunk_id":"obsolete-chunk","source_memory_ids":["obsolete-source"]}"#)
        mock.on("GET", "\(bankPath)/memories/current", json: #"{"id":"current","text":"Current detail","type":"world"}"#)
        let gate = ReadSideGate(mock: mock, captureResponse: true) { $0.url?.path.hasSuffix("/memories/old") == true }
        let timeline = TimelineViewModel(client: readSideClient(gate), bank: testBank)
        timeline.selectFact(FactHit(id: "old", text: "Old summary", type: "world"))
        let old = timeline.selectedFact!
        await gate.waitForHeld()
        timeline.selectFact(FactHit(id: "current", text: "Current summary", type: "world"))
        let current = timeline.selectedFact!
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while current.detail.value == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        await gate.release()
        while old.detail.isLoading, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(timeline.selectedFact === current)
        XCTAssertEqual(current.hit.text, "Current detail")
        XCTAssertEqual(old.hit.text, "Old summary")
        XCTAssertNil(old.detail.value)
        XCTAssertFalse(old.detail.isLoading)
        XCTAssertFalse(mock.requests.contains { $0.path.hasSuffix("/obsolete-chunk") || $0.path.hasSuffix("/obsolete-source") || $0.path.hasSuffix("/old/history") })
    }

    func testObservationWithoutSourcesStillLoadsHistoryAndLaterWorldReloadClearsIt() async {
        let mock = MockTransport()
        mock.on("GET", "\(bankPath)/memories/fact", json: #"{"id":"fact","text":"Observation","type":"observation"}"#)
        mock.on("GET", "\(bankPath)/memories/fact/history", json: #"[{"change":"created"}]"#)
        let vm = FactDetailViewModel(client: makeClient(mock), bank: testBank, hit: FactHit(id: "fact", text: "Summary"))
        await vm.load()
        XCTAssertEqual(vm.history, .array([.object(["change": .string("created")])]))
        XCTAssertNil(vm.sources.value)
        mock.reset()
        mock.on("GET", "\(bankPath)/memories/fact", json: #"{"id":"fact","text":"Current fact","type":"world"}"#)
        await vm.load()
        XCTAssertNil(vm.history)
        XCTAssertFalse(mock.requests.contains { $0.path.hasSuffix("/history") })
    }
}
