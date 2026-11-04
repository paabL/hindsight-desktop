import Foundation
import HindsightAPI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Réponse simulée.
public struct MockResponse: Sendable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int = 200, body: Data = Data("{}".utf8), headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public static func json(_ text: String, status: Int = 200) -> MockResponse {
        MockResponse(status: status, body: Data(text.utf8), headers: ["Content-Type": "application/json"])
    }

    public static func json(_ value: JSONValue, status: Int = 200) -> MockResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return MockResponse(status: status, body: data, headers: ["Content-Type": "application/json"])
    }

    public static func bytes(_ data: Data, contentType: String, status: Int = 200) -> MockResponse {
        MockResponse(status: status, body: data, headers: ["Content-Type": contentType])
    }
}

/// Requête enregistrée par le faux serveur.
public struct RecordedRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: [String]]
    public let body: Data?
    public let headers: [String: String]

    public var bodyJSON: JSONValue? {
        body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }
    public func queryValue(_ name: String) -> String? { query[name]?.first }
}

/// Faux serveur HTTP : routes (méthode + chemin) → réponse. Enregistre toutes les requêtes reçues.
/// Chemin : égalité exacte, ou motif avec `*` pour un segment (ex. `/v1/default/banks/*/stats`).
public final class MockTransport: HTTPTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (RecordedRequest) -> MockResponse

    private let lock = NSLock()
    private var routes: [(method: String, pattern: String, handler: Handler)] = []
    private var _requests: [RecordedRequest] = []
    private var fallback: Handler = { _ in MockResponse.json(#"{"detail":"Not Found (mock)"}"#, status: 404) }
    /// Délai artificiel avant chaque réponse (tests d'annulation / de concurrence).
    public var delay: Duration?

    public init() {}

    public var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _requests.removeAll()
    }

    public func on(_ method: String, _ pattern: String, _ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        routes.insert((method.uppercased(), pattern, handler), at: 0)  // la dernière déclaration l'emporte
    }

    public func on(_ method: String, _ pattern: String, json: String, status: Int = 200) {
        on(method, pattern) { _ in .json(json, status: status) }
    }

    public func onFallback(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        fallback = handler
    }

    static func matches(pattern: String, path: String) -> Bool {
        if pattern == path { return true }
        let p = pattern.split(separator: "/", omittingEmptySubsequences: false)
        let s = path.split(separator: "/", omittingEmptySubsequences: false)
        guard p.count == s.count else { return false }
        return zip(p, s).allSatisfy { $0 == "*" || $0 == $1 }
    }

    private func record(_ rec: RecordedRequest, method: String, path: String) -> MockResponse {
        lock.lock()
        _requests.append(rec)
        let handler = routes.first { $0.method == method && Self.matches(pattern: $0.pattern, path: path) }?.handler ?? fallback
        lock.unlock()
        return handler(rec)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HindsightError.invalidResponse
        }
        var query: [String: [String]] = [:]
        for item in comps.queryItems ?? [] { query[item.name, default: []].append(item.value ?? "") }
        let method = (request.httpMethod ?? "GET").uppercased()
        let path = comps.percentEncodedPath.removingPercentEncoding ?? comps.path
        let rec = RecordedRequest(
            method: method, path: path, query: query, body: request.httpBody, headers: request.allHTTPHeaderFields ?? [:])
        if let delay { try await Task.sleep(for: delay) }
        let resp = record(rec, method: method, path: path)
        let http = HTTPURLResponse(url: url, statusCode: resp.status, httpVersion: "HTTP/1.1", headerFields: resp.headers)!
        return (resp.body, http)
    }
}
