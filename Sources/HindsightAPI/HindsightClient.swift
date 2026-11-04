import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Une requête HTTP décrite de façon déclarative (chemin, requête, corps).
public struct APIRequest: Sendable {
    public enum Body: Sendable {
        case none
        case json(Data)
        case multipart(boundary: String, data: Data)
    }

    public var method: String
    /// Segments de chemin non encodés ; l'encodage est fait à la construction de l'URL.
    public var segments: [String]
    public var query: [(name: String, value: String)]
    public var body: Body
    public var timeout: TimeInterval?
    /// URL déjà complète (ex. `attachments[].url` résolue) ; remplace `segments`/`query`.
    public var absoluteURL: URL?

    public init(
        _ method: String, _ segments: [String], query: [(String, String?)] = [], body: Body = .none,
        timeout: TimeInterval? = nil
    ) {
        self.method = method
        self.segments = segments
        self.query = query.compactMap { n, v in v.map { (n, $0) } }
        self.body = body
        self.timeout = timeout
    }
}

/// Client HTTP pur de l'API Hindsight. Aucune logique d'interface ici.
public struct HindsightClient: Sendable {
    public let baseURL: URL
    public let transport: any HTTPTransport
    /// En-tête `Authorization` complet (ex. « Bearer … »), si le serveur en exige un. Jamais écrit sur disque ici.
    public let authorization: String?

    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8888")!

    public init(
        baseURL: URL = HindsightClient.defaultBaseURL, transport: any HTTPTransport = URLSessionTransport(),
        authorization: String? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.authorization = authorization
    }

    /// Valide et normalise une URL saisie par l'utilisateur (schéma http/https + hôte obligatoires).
    public static func normalizedBaseURL(from text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "http://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    // MARK: Construction des URL

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    public func url(for req: APIRequest) throws -> URL {
        if let u = req.absoluteURL { return u }
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        for seg in req.segments { s += "/" + Self.encode(seg) }
        if !req.query.isEmpty {
            s += "?" + req.query.map { "\(Self.encode($0.name))=\(Self.encode($0.value))" }.joined(separator: "&")
        }
        guard let url = URL(string: s) else { throw HindsightError.invalidURL(s) }
        return url
    }

    /// Résout une URL de pièce jointe renvoyée par l'API (chemin absolu `/v1/...` ou URL complète).
    public func resolve(_ pathOrURL: String) -> URL? {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") { return URL(string: pathOrURL) }
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + (pathOrURL.hasPrefix("/") ? "" : "/") + pathOrURL)
    }

    func urlRequest(_ req: APIRequest, accept: String = "application/json") throws -> URLRequest {
        let target = try url(for: req)
        guard let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme),
              target.host != nil, target.user == nil, target.password == nil,
              scheme == "https" || Self.sameOrigin(target, baseURL) else {
            throw HindsightError.refused("Adresse de pièce jointe refusée : utilisez HTTPS sans identifiants, ou le serveur configuré.")
        }
        var r = URLRequest(url: target)
        r.httpMethod = req.method
        r.setValue(accept, forHTTPHeaderField: "Accept")
        // Une pièce jointe peut être hébergée ailleurs : la clé du serveur ne doit jamais la suivre.
        if let authorization, Self.sameOrigin(target, baseURL) {
            r.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        if let t = req.timeout { r.timeoutInterval = t }
        switch req.body {
        case .none: break
        case .json(let d):
            r.httpBody = d
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .multipart(let boundary, let d):
            r.httpBody = d
            r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }

    // MARK: Exécution

    /// Exécute la requête et renvoie le corps brut (2xx uniquement).
    public func perform(_ req: APIRequest, accept: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let urlReq = try urlRequest(req, accept: accept)
        let (data, http) = try await transport.send(urlReq)
        try Task.checkCancellation()
        guard (200..<300).contains(http.statusCode) else {
            throw HindsightError.http(
                status: http.statusCode, detail: Self.errorDetail(from: data), path: "/" + req.segments.joined(separator: "/"))
        }
        return (data, http)
    }

    public func send<T: Decodable & Sendable>(_ req: APIRequest, as: T.Type = T.self) async throws -> T {
        let (data, _) = try await perform(req)
        return try Self.decode(T.self, from: data, path: "/" + req.segments.joined(separator: "/"))
    }

    /// Variante qui ignore le corps (utile quand seule la réussite compte).
    public func sendIgnoringBody(_ req: APIRequest) async throws {
        _ = try await perform(req)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as DecodingError {
            throw HindsightError.decoding(path: path, message: describe(e), snippet: snippet(data))
        } catch {
            throw HindsightError.decoding(path: path, message: error.localizedDescription, snippet: snippet(data))
        }
    }

    static func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(400), as: UTF8.self)
    }

    public static func describe(_ e: DecodingError) -> String {
        func p(_ c: [CodingKey]) -> String {
            c.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch e {
        case .keyNotFound(let k, let ctx): return "champ manquant « \(k.stringValue) » à \(p(ctx.codingPath))"
        case .typeMismatch(let t, let ctx): return "type inattendu (\(t)) à \(p(ctx.codingPath)) : \(ctx.debugDescription)"
        case .valueNotFound(let t, let ctx): return "valeur nulle (\(t)) à \(p(ctx.codingPath))"
        case .dataCorrupted(let ctx): return "JSON invalide à \(p(ctx.codingPath)) : \(ctx.debugDescription)"
        @unknown default: return "\(e)"
        }
    }

    /// Extrait un message lisible du corps d'erreur FastAPI (`{"detail": "…"}` ou liste de validations).
    static func errorDetail(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let v = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if let detail = v["detail"] {
                if let s = detail.stringValue { return s }
                if let arr = detail.arrayValue {
                    let msgs = arr.compactMap { item -> String? in
                        guard let msg = item["msg"]?.stringValue else { return nil }
                        let loc = (item["loc"]?.arrayValue ?? []).compactMap { $0.stringValue }.joined(separator: ".")
                        return loc.isEmpty ? msg : "\(loc) : \(msg)"
                    }
                    if !msgs.isEmpty { return msgs.joined(separator: " ; ") }
                }
                return detail.prettyString()
            }
            if let m = v["message"]?.stringValue ?? v["error"]?.stringValue { return m }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Une page HTML (ex. le Control Plane sur le mauvais port) n'est pas un message lisible.
        if text.isEmpty || text.hasPrefix("<") { return nil }
        return text
    }
}

// MARK: - Corps JSON

extension APIRequest {
    /// Construit une requête avec corps JSON encodé (les `nil` sont omis, conformément au contrat).
    public static func json<B: Encodable>(
        _ method: String, _ segments: [String], query: [(String, String?)] = [], body: B,
        timeout: TimeInterval? = nil
    ) throws -> APIRequest {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return APIRequest(method, segments, query: query, body: .json(try enc.encode(body)), timeout: timeout)
    }
}

// MARK: - Raccourcis de chemin

extension HindsightClient {
    static func bank(_ id: String, _ rest: String...) -> [String] {
        ["v1", "default", "banks", id] + rest
    }
}
