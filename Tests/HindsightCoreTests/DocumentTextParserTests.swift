import XCTest
import HindsightAPI
@testable import HindsightCore

final class DocumentTextParserTests: XCTestCase {
    func att(_ id: String, kind: String = "image", mime: String = "image/png") -> ChunkAttachment {
        ChunkAttachment(id: id, hash: id + "0000", kind: kind, mediaType: mime, byteSize: 1, url: "/a/\(id)")
    }

    func testSplitsTextAndAttachmentsInOrder() {
        let text = "avant ⟦hs-att:aaaa1111⟧ milieu ⟦hs-att:bbbb2222⟧ après"
        let blocks = DocumentTextParser.parse(text: text, attachments: [att("aaaa1111"), att("bbbb2222", kind: "file", mime: "application/pdf")])
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0].text, "avant ")
        XCTAssertEqual(blocks[1].attachmentRef?.attachment?.id, "aaaa1111")
        XCTAssertTrue(blocks[1].attachmentRef!.isImage)
        XCTAssertEqual(blocks[2].text, " milieu ")
        XCTAssertFalse(blocks[3].attachmentRef!.isImage)
        XCTAssertEqual(blocks[4].text, " après")
        XCTAssertEqual(blocks.map(\.id), [0, 1, 2, 3, 4])
        // Les intervalles couvrent le texte sans trou ni chevauchement.
        var cursor = 0
        for b in blocks {
            XCTAssertEqual(b.range.lowerBound, cursor)
            cursor = b.range.upperBound
        }
        XCTAssertEqual(cursor, text.utf16.count)
    }

    func testUnknownAttachmentKeepsTokenButNoMetadata() {
        let blocks = DocumentTextParser.parse(text: "⟦hs-att:zzzz9999⟧", attachments: [att("aaaa1111")])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].attachmentRef?.id, "zzzz9999")
        XCTAssertNil(blocks[0].attachmentRef?.attachment)
        XCTAssertFalse(blocks[0].attachmentRef!.isImage)
    }

    func testTokenWithExtraPartsStillResolves() {
        let ref = DocumentTextParser.resolve(token: "aaaa1111:image/png:capture.png", attachments: [att("aaaa1111")])
        XCTAssertEqual(ref.id, "aaaa1111")
        XCTAssertNotNil(ref.attachment)
        // Résolution par préfixe de hash lorsque l'id exact diffère.
        let long = ChunkAttachment(id: "x", hash: "deadbeefcafe1234", kind: "image", mediaType: "image/png", byteSize: 1, url: "/u")
        XCTAssertNotNil(DocumentTextParser.resolve(token: "deadbeef", attachments: [long]).attachment)
    }

    func testLongTextIsSplitAtNewlinesWithoutLoss() {
        let line = String(repeating: "x", count: 99) + "\n"
        let text = String(repeating: line, count: 200)  // 20 000 caractères
        let blocks = DocumentTextParser.parse(text: text, attachments: [], maxTextBlock: 1000)
        XCTAssertGreaterThan(blocks.count, 15)
        XCTAssertEqual(blocks.compactMap(\.text).joined(), text)
        XCTAssertTrue(blocks.dropLast().allSatisfy { $0.text!.hasSuffix("\n") })
        XCTAssertTrue(blocks.allSatisfy { ($0.text?.utf16.count ?? 0) <= 1000 })
    }

    func testSurrogatePairsAreNotSplit() {
        let text = String(repeating: "😀", count: 50)  // pas de retour à la ligne
        let blocks = DocumentTextParser.parse(text: text, attachments: [], maxTextBlock: 7)
        XCTAssertEqual(blocks.compactMap(\.text).joined(), text)
        for b in blocks { XCTAssertNotNil(b.text?.unicodeScalars.first) }
    }

    func testEmptyAndPlain() {
        XCTAssertTrue(DocumentTextParser.parse(text: "", attachments: []).isEmpty)
        XCTAssertEqual(DocumentTextParser.plain("a ⟦hs-att:1234⟧ b"), "a [pièce jointe] b")
    }

    func testMergeDeduplicates() {
        let merged = DocumentTextParser.merge([[att("a"), att("b")], nil, [att("b"), att("c")]])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }
}

final class UnreferencedAttachmentTests: XCTestCase {
    func testAttachmentsWithoutTokenAreAppendedAtTheEnd() {
        let a = ChunkAttachment(id: "aaaa1111", hash: "h", kind: "image", mediaType: "image/png", byteSize: 1, url: "/a")
        let b = ChunkAttachment(id: "bbbb2222", hash: "h2", kind: "image", mediaType: "image/png", byteSize: 1, url: "/b")
        let text = "texte ⟦hs-att:aaaa1111⟧ fin"
        let blocks = DocumentTextParser.parse(text: text, attachments: [a, b])
        let extra = DocumentTextParser.unreferencedBlocks(attachments: [a, b], after: blocks, textLength: text.utf16.count)
        XCTAssertEqual(extra.map { $0.attachmentRef?.attachment?.id }, ["bbbb2222"])
        XCTAssertEqual(extra[0].id, blocks.count)
    }
}
