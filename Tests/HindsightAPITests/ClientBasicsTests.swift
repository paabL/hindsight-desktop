import XCTest
@testable import HindsightAPI
import HindsightTestSupport

final class ClientBasicsTests: XCTestCase {
    func client(_ t: MockTransport, auth: String? = nil) -> HindsightClient {
        HindsightClient(baseURL: URL(string: "http://127.0.0.1:8888")!, transport: t, authorization: auth)
    }

    func testNormalizedBaseURL() {
        XCTAssertEqual(HindsightClient.normalizedBaseURL(from: "127.0.0.1:8888")?.absoluteString, "http://127.0.0.1:8888")
        XCTAssertEqual(HindsightClient.normalizedBaseURL(from: " http://localhost:8888/ ")?.absoluteString, "http://localhost:8888")
        XCTAssertEqual(HindsightClient.normalizedBaseURL(from: "https://mac.local/hs/")?.absoluteString, "https://mac.local/hs")
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: ""))
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: "ftp://x"))
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: "http://"))
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: "https://user:secret@example.com"))
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: "https://example.com?token=secret"))
        XCTAssertNil(HindsightClient.normalizedBaseURL(from: "https://example.com#fragment"))
    }

    func testPathSegmentsAreEncodedAndQueryArraysRepeat() async throws {
        let t = MockTransport()
        t.on("GET", "/v1/default/banks/*/documents/*", json: "{}")
        t.onFallback { _ in .json("{}", status: 200) }
        let c = client(t)
        let req = APIRequest(
            "GET", ["v1", "default", "banks", "my bank/é", "documents", "codex-1/task 001"],
            query: [("tags", "source:codex"), ("tags", "a&b"), ("q", "x y+z")])
        let url = try c.url(for: req)
        XCTAssertEqual(
            url.absoluteString,
            "http://127.0.0.1:8888/v1/default/banks/my%20bank%2F%C3%A9/documents/codex-1%2Ftask%20001?tags=source%3Acodex&tags=a%26b&q=x%20y%2Bz")
        _ = try await c.perform(req)
        let r = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(r.query["tags"], ["source:codex", "a&b"])
        XCTAssertEqual(r.queryValue("q"), "x y+z")
    }

    func testAuthorizationHeaderOnlyWhenConfigured() async throws {
        let t = MockTransport()
        t.onFallback { _ in .json(#"{"status":"healthy"}"#) }
        _ = try await client(t).health()
        XCTAssertNil(t.requests[0].headers["Authorization"])
        _ = try await client(t, auth: "Bearer abc").health()
        XCTAssertEqual(t.requests[1].headers["Authorization"], "Bearer abc")
    }

    func testCancelledRequestNeverReachesTheTransport() async throws {
        let transport = MockTransport()
        transport.onFallback { _ in .json(#"{"status":"healthy"}"#) }
        let c = client(transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await c.health()
        }
        do {
            _ = try await task.value
            XCTFail("Une requête annulée ne doit pas partir.")
        } catch is CancellationError {
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testExternalAttachmentsNeverReceiveServerAuthorization() throws {
        let c = HindsightClient(baseURL: URL(string: "https://memory.example.com")!, authorization: "Bearer private")
        var req = APIRequest("GET", [])
        for address in ["https://cdn.example.com/image.png", "https://memory.example.com:444/image.png"] {
            req.absoluteURL = URL(string: address)
            XCTAssertNil(try c.urlRequest(req).value(forHTTPHeaderField: "Authorization"))
        }
        req.absoluteURL = URL(string: "https://MEMORY.example.com:443/image.png")
        XCTAssertEqual(try c.urlRequest(req).value(forHTTPHeaderField: "Authorization"), "Bearer private")
        for address in ["http://cdn.example.com/image.png", "https://user:secret@cdn.example.com/image.png", "file:///etc/passwd"] {
            req.absoluteURL = URL(string: address)
            XCTAssertThrowsError(try c.urlRequest(req))
        }
    }

    func testRedirectsCannotCrossOriginOrDowngradeEncryption() {
        let source = URL(string: "https://memory.example.com/v1/upload")!
        XCTAssertTrue(SameOriginRedirects.allowed(from: source, to: URL(string: "https://MEMORY.example.com:443/v1/upload/")!))
        for address in ["https://other.example.com/upload", "http://memory.example.com/upload", "https://memory.example.com:444/upload", "https://user:secret@memory.example.com/upload"] {
            XCTAssertFalse(SameOriginRedirects.allowed(from: source, to: URL(string: address)!))
        }
    }

    func testHTTPErrorsCarryDetail() async throws {
        let t = MockTransport()
        t.on("GET", "/v1/default/banks/x/stats", json: #"{"detail":"Bank 'x' not found"}"#, status: 404)
        t.on(
            "PATCH", "/v1/default/banks/x/config",
            json: #"{"detail":[{"loc":["body","updates"],"msg":"Field required","type":"missing"}]}"#, status: 422)
        let c = client(t)
        do {
            _ = try await c.bankStats("x")
            XCTFail("attendu : erreur")
        } catch let e as HindsightError {
            XCTAssertTrue(e.isNotFound)
            XCTAssertTrue(e.description.contains("Bank 'x' not found"), e.description)
        }
        do {
            _ = try await c.updateBankConfig("x", updates: [:])
            XCTFail("attendu : erreur")
        } catch let e as HindsightError {
            XCTAssertEqual(e.httpStatus, 422)
            XCTAssertTrue(e.description.contains("body.updates : Field required"), e.description)
        }
    }

    func testHTMLErrorBodyIsNotShownAsDetail() {
        XCTAssertNil(HindsightClient.errorDetail(from: Data("<!DOCTYPE html><html><body>Not Found</body></html>".utf8)))
        XCTAssertEqual(HindsightClient.errorDetail(from: Data("Bad gateway".utf8)), "Bad gateway")
    }

    func testDecodingErrorNamesTheField() async throws {
        let t = MockTransport()
        // total_nodes absent => erreur de décodage lisible
        t.on("GET", "/v1/default/banks/x/stats", json: #"{"bank_id":"x"}"#)
        do {
            _ = try await client(t).bankStats("x")
            XCTFail("attendu : erreur")
        } catch let e as HindsightError {
            guard case .decoding(let path, let message, let snippet) = e else { return XCTFail("\(e)") }
            XCTAssertEqual(path, "/v1/default/banks/x/stats")
            XCTAssertTrue(message.contains("total_nodes"), message)
            XCTAssertTrue(snippet.contains("bank_id"))
        }
    }

    func testTransportFailureBecomesUnreachable() async throws {
        struct Boom: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                throw HindsightError.unreachable("connexion refusée")
            }
        }
        let c = HindsightClient(transport: Boom())
        do {
            _ = try await c.version()
            XCTFail("attendu : erreur")
        } catch let e as HindsightError {
            XCTAssertEqual(e.description, "Serveur injoignable : connexion refusée")
        }
    }

    func testAttachmentURLResolutionAndFetch() async throws {
        let t = MockTransport()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        t.on("GET", "/v1/default/banks/b1/attachments/abc123") { _ in .bytes(png, contentType: "image/png") }
        let c = client(t)
        XCTAssertEqual(c.resolve("/v1/default/banks/b1/attachments/abc123")?.absoluteString,
                       "http://127.0.0.1:8888/v1/default/banks/b1/attachments/abc123")
        XCTAssertEqual(c.resolve("https://other/x")?.absoluteString, "https://other/x")
        let a = try await c.attachment(url: "/v1/default/banks/b1/attachments/abc123")
        XCTAssertEqual(a.data, png)
        XCTAssertEqual(a.mimeType, "image/png")
        let b = try await c.attachment("b1", id: "abc123")
        XCTAssertEqual(b.data, png)
    }

    func testBodiesOmitNilFields() throws {
        let req = try APIRequest.json("POST", ["x"], body: RecallRequest(query: "q"))
        guard case .json(let data) = req.body else { return XCTFail() }
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(v["query"], "q")
        XCTAssertNil(v["tags"])
        XCTAssertNil(v["tag_groups"])
    }

    func testTagGroupCodableRoundTrip() throws {
        let json = #"[{"tags":["a"],"match":"all"},{"and":[{"tags":["b"]},{"not":{"tags":["c"],"resolve":"fuzzy"}}]},{"or":[{"tags":["d"]}]}]"#
        let groups = try JSONDecoder().decode([TagGroup].self, from: Data(json.utf8))
        XCTAssertEqual(groups.count, 3)
        guard case .and(let inner) = groups[1], case .not(.leaf(let leaf)) = inner[1] else { return XCTFail("\(groups)") }
        XCTAssertEqual(leaf.resolve, "fuzzy")
        let again = try JSONDecoder().decode([TagGroup].self, from: try JSONEncoder().encode(groups))
        XCTAssertEqual(groups, again)
    }

    func testHSDateParsing() {
        XCTAssertNotNil(HSDate.parse("2025-03-01T10:20:30.123456Z"))
        XCTAssertNotNil(HSDate.parse("2025-03-01T10:20:30+02:00"))
        XCTAssertNotNil(HSDate.parse("2025-03-01T10:20:30"))
        XCTAssertNotNil(HSDate.parse("2025-03-01"))
        XCTAssertNotNil(HSDate.parse("2025-03-01 10:20:30.5"))
        XCTAssertNil(HSDate.parse("pas une date"))
        XCTAssertNil(HSDate.parse(nil))
        let a = HSDate.parse("2025-03-01T10:20:30Z")!
        let b = HSDate.parse("2025-03-01T12:20:30+02:00")!
        XCTAssertEqual(a, b)
    }

    /// La lecture directe des dates canoniques doit donner exactement l'instant du formateur ISO 8601,
    /// et laisser au formateur toute date qu'elle ne sait pas lire (jour impossible, seconde 60…).
    func testCanonicalDatesMatchTheFormatterExactly() {
        let fractional = ISO8601DateFormatter(), plain = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plain.formatOptions = [.withInternetDateTime]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        var samples = [
            "2024-02-29T23:59:59.999Z", "2000-02-29T00:00:00Z", "1900-01-01T00:00:00Z", "2999-12-31T23:59:59.999+14:00",
            "1970-01-01T00:00:00.000Z", "2026-11-03T12:00:00-09:30", "2026-03-29T02:30:00+01:00",
        ]
        let unreadable = [
            "2025-02-29T00:00:00Z", "2100-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-01-01T24:00:00Z",
            "2026-01-01T00:60:00Z", "2026-12-31T23:59:60Z", "1899-12-31T23:59:59Z", "3000-01-01T00:00:00Z",
            "2026-01-01T00:00:00+24:00", "2026-01-01T00:00:00", "2026-01-01T00:00:00.12Z", "2026-01-01T00:00:00+0100",
        ]
        for _ in 0..<5_000 {
            let fraction = next(2) == 0 ? "" : "." + String(1_000 + next(1_000)).dropFirst()
            let zone = next(3) == 0 ? "Z" : (next(2) == 0 ? "+" : "-") + two(next(15)) + ":" + two([0, 15, 30, 45][next(4)])
            samples.append("\(1900 + next(1_100))-\(two(1 + next(12)))-\(two(1 + next(31)))T\(two(next(24))):\(two(next(60))):\(two(next(60)))\(fraction)\(zone)")
        }
        var read = 0
        for s in samples {
            // Déjà sous forme canonique : `parse` n'y retouche rien et doit répondre comme le formateur seul.
            let formatter = fractional.date(from: s) ?? plain.date(from: s)
            XCTAssertEqual(HSDate.parse(s), formatter, s)
            if let date = HSDate.canonicalDate(s) {
                read += 1
                XCTAssertEqual(date.timeIntervalSinceReferenceDate, formatter?.timeIntervalSinceReferenceDate, s)
            }
        }
        XCTAssertGreaterThan(read, 4_500)
        for s in unreadable { XCTAssertNil(HSDate.canonicalDate(s), s) }
    }

    func testMultipartFraming() {
        let mp = Multipart.singleFile(field: "file", filename: "a.zip", mimeType: "application/zip", data: Data("PK".utf8))
        let s = String(decoding: mp.body, as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("--\(mp.boundary)\r\n"))
        XCTAssertTrue(s.contains("name=\"file\"; filename=\"a.zip\""))
        XCTAssertTrue(s.hasSuffix("--\(mp.boundary)--\r\n"))
    }
}
