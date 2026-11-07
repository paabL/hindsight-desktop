import XCTest
@testable import HindsightCore

final class BridgeLinesTests: XCTestCase {
    private func lines(_ text: String, limit: Int = 16_000_000) -> [BridgeLineReader.Line] {
        var reader = BridgeLineReader(limit: limit)
        return Array(text.utf8).compactMap { reader.consume($0) }
    }

    func testOnlyNewlineEndsARequest() throws {
        // Séparateurs de ligne et de paragraphe Unicode et NEL restent dans la requête (permis tels quels en JSON).
        let text = "{\"query\":\"a\u{2028}b\u{2029}c\u{0085}d\"}"
        let result = lines(text + "\n{\"id\":2}\n")
        XCTAssertEqual(result.count, 2)
        guard case .request(let first) = result[0] else { return XCTFail("first line missing") }
        XCTAssertEqual(String(decoding: first, as: UTF8.self), text)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(object["query"] as? String, "a\u{2028}b\u{2029}c\u{0085}d")
        // Un retour chariot seul ne termine pas non plus la ligne.
        XCTAssertEqual(lines("a\rb\n"), [.request(Data("a\rb".utf8))])
    }

    func testOversizedLineIsSkippedAndTheNextOneIsRead() {
        let result = lines("0123456789\nabc\n", limit: 5)
        XCTAssertEqual(result, [.oversized, .request(Data("abc".utf8))])
        XCTAssertEqual(lines("12345\n", limit: 5), [.request(Data("12345".utf8))])
    }

    func testRepliesEscapeLineSeparatorsWithoutChangingTheirValue() throws {
        let value = "« x »\u{2028}é\u{2029}\u{0085}fin"
        let data = try JSONSerialization.data(withJSONObject: ["text": value])
        let safe = BridgeLineReader.lineSafe(data)
        let raw = String(decoding: safe, as: UTF8.self)
        XCTAssertFalse(raw.contains("\u{2028}") || raw.contains("\u{2029}") || raw.contains("\u{0085}"))
        XCTAssertTrue(raw.contains("\\u2028") && raw.contains("\\u2029") && raw.contains("\\u0085"))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: safe) as? [String: String])
        XCTAssertEqual(decoded["text"], value)
        // Sans séparateur, la réponse est rendue telle quelle.
        let plain = try JSONSerialization.data(withJSONObject: ["text": "« é » ordinaire"])
        XCTAssertEqual(BridgeLineReader.lineSafe(plain), plain)
    }
}
