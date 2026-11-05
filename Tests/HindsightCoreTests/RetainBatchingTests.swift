import HindsightAPI
import XCTest

@testable import HindsightCore

final class RetainBatchingTests: XCTestCase {
    private func items(_ sizes: [Int]) -> [(item: MemoryItem, bytes: Int)] {
        sizes.enumerated().map { index, bytes in
            (MemoryItem(content: .text("Document \(index)"), metadata: ["source": "catalog"], documentId: "doc-\(index)", tags: ["source:catalog"]), bytes)
        }
    }

    private func ids(_ batches: [[MemoryItem]]) -> [[String]] {
        batches.map { $0.compactMap(\.documentId) }
    }

    func testEmptyInputProducesNoRequests() {
        XCTAssertTrue(RetainBatching.batches([], byteLimit: 100, itemLimit: 2).isEmpty)
    }

    func testItemLimitPreservesOrderAndContents() {
        let input = items([1, 1, 1, 1, 1])
        let batches = RetainBatching.batches(input, byteLimit: 100, itemLimit: 2)
        XCTAssertEqual(ids(batches), [["doc-0", "doc-1"], ["doc-2", "doc-3"], ["doc-4"]])
        XCTAssertEqual(batches.flatMap { $0 }, input.map(\.item))
    }

    func testExactByteLimitFitsButNextItemStartsAnotherRequest() {
        let batches = RetainBatching.batches(items([40, 60, 1]), byteLimit: 100, itemLimit: 10)
        XCTAssertEqual(ids(batches), [["doc-0", "doc-1"], ["doc-2"]])
    }

    func testOversizedItemIsSentAloneWithoutLosingItsNeighbours() {
        let input = items([30, 200, 30, 30])
        let batches = RetainBatching.batches(input, byteLimit: 100, itemLimit: 10)
        XCTAssertEqual(ids(batches), [["doc-0"], ["doc-1"], ["doc-2", "doc-3"]])
        XCTAssertEqual(batches.flatMap { $0 }, input.map(\.item))
    }
}
