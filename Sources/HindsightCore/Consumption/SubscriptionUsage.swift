import Foundation
#if canImport(Security)
import Security
#endif

/// Quotas d'abonnement relevés en direct, auprès des endpoints d'usage que les CLI interrogent eux-mêmes :
/// Claude (`/usage` de Claude Code) et ChatGPT (`/status` de Codex). Aucun appel au LLM, aucun quota consommé.
///
/// Lecture seule : le jeton Claude vient du Trousseau (élément « Claude Code-credentials »), celui de Codex de
/// `~/.codex/auth.json`. Ils ne sont jamais actualisés, écrits ni journalisés, et ne quittent ce Mac que vers
/// leur propre service. Un jeton expiré n'est pas utilisé : on se rabat sur les relevés locaux (cache de
/// `~/.claude.json`, sessions Codex).
public enum SubscriptionUsage {
    public static let claudeURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let codexURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let keychainService = "Claude Code-credentials"

    /// Résultat d'un relevé : un quota par service, ou la raison de son absence.
    public struct Reading: Sendable, Hashable {
        public var claude: CodexQuota?
        public var codex: CodexQuota?
        public var claudeProblem: String?
        public var codexProblem: String?
        /// L'accès au Trousseau a été refusé : ne plus le demander pendant cette session.
        public var keychainDenied = false

        public init(claude: CodexQuota? = nil, codex: CodexQuota? = nil, claudeProblem: String? = nil, codexProblem: String? = nil) {
            self.claude = claude
            self.codex = codex
            self.claudeProblem = claudeProblem
            self.codexProblem = codexProblem
        }
    }

    public static func fetch(askKeychain: Bool = true, now: Date = Date(), codexHome: URL = CodexRateLimits.codexHome()) async -> Reading {
        var r = Reading()
        switch askKeychain ? claudeToken(now: now) : .failure(Unavailable(message: "Claude : accès au Trousseau refusé")) {
        case .success(let token):
            do { r.claude = try await get(claudeURL, ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20"], parse: parseClaude) }
            catch { r.claudeProblem = "Claude : \(error.localizedDescription)" }
        case .failure(let e):
            r.claudeProblem = e.message
            r.keychainDenied = !askKeychain || e.denied
        }
        switch codexToken(codexHome: codexHome, now: now) {
        case .success(let (token, account)):
            var headers = ["Authorization": "Bearer \(token)"]
            if let account { headers["ChatGPT-Account-Id"] = account }
            do { r.codex = try await get(codexURL, headers, parse: parseCodex) }
            catch { r.codexProblem = "Codex : \(error.localizedDescription)" }
        case .failure(let e): r.codexProblem = e.message
        }
        return r
    }

    // MARK: Jetons (lecture seule)

    public struct Unavailable: Error, Sendable, Hashable {
        public let message: String
        public var denied = false
    }

    static func claudeToken(now: Date) -> Result<String, Unavailable> {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            return .failure(Unavailable(message: "Claude : accès au Trousseau refusé", denied: true))
        }
        guard status == errSecSuccess, let data = item as? Data else {
            return .failure(Unavailable(message: "Claude : aucun jeton de Claude Code dans le Trousseau"))
        }
        return claudeToken(credentials: data, now: now)
        #else
        return .failure(Unavailable(message: "Claude : Trousseau indisponible"))
        #endif
    }

    /// `{"claudeAiOauth": {"accessToken": …, "expiresAt": <ms>}}`, tel que Claude Code l'enregistre.
    static func claudeToken(credentials: Data, now: Date) -> Result<String, Unavailable> {
        guard let root = try? JSONSerialization.jsonObject(with: credentials) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return .failure(Unavailable(message: "Claude : jeton illisible")) }
        if let ms = number(oauth["expiresAt"]), Date(timeIntervalSince1970: ms / 1000) <= now {
            return .failure(Unavailable(message: "Claude : jeton expiré (une session `claude` dans un terminal le renouvelle)"))
        }
        return .success(token)
    }

    static func codexToken(codexHome: URL, now: Date) -> Result<(String, String?), Unavailable> {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("auth.json")) else {
            return .failure(Unavailable(message: "Codex : pas de connexion ChatGPT (auth.json absent)"))
        }
        return codexToken(auth: data, now: now)
    }

    /// `{"tokens": {"access_token": <JWT>, "account_id": …}}` ; l'expiration est lue dans le JWT.
    static func codexToken(auth: Data, now: Date) -> Result<(String, String?), Unavailable> {
        guard let root = try? JSONSerialization.jsonObject(with: auth) as? [String: Any], let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String, !token.isEmpty
        else { return .failure(Unavailable(message: "Codex : pas de connexion ChatGPT dans auth.json")) }
        if let exp = jwtExpiry(token), exp <= now {
            return .failure(Unavailable(message: "Codex : jeton expiré (Codex le renouvellera)"))
        }
        return .success((token, tokens["account_id"] as? String))
    }

    static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = number(payload["exp"])
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: Réponses

    struct HTTPFailure: LocalizedError {
        let status: Int
        var errorDescription: String? { status == 401 || status == 403 ? "jeton refusé (\(status))" : "réponse \(status)" }
    }

    static func get(_ url: URL, _ headers: [String: String], parse: (Data, Date) -> CodexQuota?) async throws -> CodexQuota? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HindsightMac", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw HTTPFailure(status: http.statusCode) }
        return parse(data, Date())
    }

    /// `{"five_hour": {"utilization": 18, "resets_at": "…"}, "seven_day": {…}}` (aussi le format du cache de
    /// `~/.claude.json`).
    public static func parseClaude(_ data: Data, now: Date) -> CodexQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claudeQuota(root, observedAt: now)
    }

    static func claudeQuota(_ root: [String: Any], observedAt: Date) -> CodexQuota? {
        func window(_ key: String, _ minutes: Int) -> CodexQuota.Window? {
            guard let w = root[key] as? [String: Any], let used = number(w["utilization"]) else { return nil }
            return .init(usedPercent: used, windowMinutes: minutes, resetsAt: (w["resets_at"] as? String).flatMap(isoDate))
        }
        let q = CodexQuota(primary: window("five_hour", 300), secondary: window("seven_day", 10_080), observedAt: observedAt)
        return q.primary == nil && q.secondary == nil ? nil : q
    }

    /// `{"rate_limit": {"primary_window": {"used_percent", "limit_window_seconds", "reset_at"}, "secondary_window": …}}`
    public static func parseCodex(_ data: Data, now: Date) -> CodexQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let limits = root["rate_limit"] as? [String: Any]
        else { return nil }
        func window(_ key: String) -> CodexQuota.Window? {
            guard let w = limits[key] as? [String: Any], let used = number(w["used_percent"]) else { return nil }
            let reset = number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                ?? number(w["reset_after_seconds"]).map { now.addingTimeInterval($0) }
            return .init(usedPercent: used, windowMinutes: number(w["limit_window_seconds"]).map { Int($0 / 60) }, resetsAt: reset)
        }
        let q = CodexQuota(primary: window("primary_window"), secondary: window("secondary_window"), observedAt: now)
        return q.primary == nil && q.secondary == nil ? nil : q
    }

    // MARK: Repli local

    /// Dernier relevé que Claude Code a mis en cache dans `~/.claude.json` (à chaque `/usage`) : peut dater.
    public static func claudeCache(home: String = NSHomeDirectory()) -> CodexQuota? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: home).appendingPathComponent(".claude.json")) else { return nil }
        return claudeCache(data)
    }

    static func claudeCache(_ data: Data) -> CodexQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cache = root["cachedUsageUtilization"] as? [String: Any], let usage = cache["utilization"] as? [String: Any],
            let ms = number(cache["fetchedAtMs"])
        else { return nil }
        return claudeQuota(usage, observedAt: Date(timeIntervalSince1970: ms / 1000))
    }

    // MARK: Outils

    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    /// ISO 8601 avec ou sans fraction de seconde (Anthropic en donne six chiffres).
    static func isoDate(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
