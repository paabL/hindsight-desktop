import Foundation
import HindsightAPI

/// « Qui a accédé à la banque, et combien de fois » à partir des entrées d'audit.
public struct AccessRow: Identifiable, Sendable, Hashable {
    public var id: String { actor }
    public let actor: String
    public let transport: String
    public let count: Int
    public let actions: [String: Int]
    public let lastSeen: Date?
    /// Signature d'un client HTTP non identifié (pour le nommer), et ses réglages distinctifs.
    public var signature: String? = nil
    public var signatureDescription: String? = nil
}

public enum AccessSummary {
    /// Clés, par ordre de préférence, qui identifient l'appelant dans `metadata` puis `request`.
    public static let actorKeys = [
        "client_name", "client", "client_id", "mcp_client", "agent_name", "agent", "user", "user_id", "tenant",
        "tenant_id", "api_key_name", "api_key_id", "key_id", "user_agent", "remote_addr", "client_ip", "ip",
    ]

    /// Clés présentes dans les entrées (pour choisir manuellement le regroupement).
    public static func availableKeys(_ entries: [AuditLogEntry]) -> [String] {
        var keys = Set<String>()
        for e in entries {
            for (k, v) in e.metadata where v.stringValue != nil { keys.insert(k) }
        }
        return keys.sorted()
    }

    /// Champs de requête qui changent à chaque appel (exclus de la signature d'un client).
    static let volatileKeys: Set<String> = [
        "query", "q", "text", "question", "content", "items", "query_timestamp", "document_id", "memory_id", "entity_id",
        "mental_model_id", "source_query", "context", "timestamp", "name",
    ]

    /// Signature d'un appelant HTTP non identifié : le serveur ne journalise ni client ni user-agent pour
    /// HTTP, mais chaque intégration envoie ses propres réglages (budget, max_tokens, types, options…).
    /// Même signature = vraisemblablement le même client. `nil` si l'entrée identifie déjà son appelant.
    public static func signature(of e: AuditLogEntry) -> String? {
        guard identity(of: e) == nil, let req = e.request, !req.isEmpty else { return nil }
        let stable = req.filter { !volatileKeys.contains($0.key) }.mapValues { v -> JSONValue in
            // Les tags varient d'un appel à l'autre ; seul compte le fait d'en utiliser.
            if case .array(let a) = v { return a.isEmpty ? .array([]) : .string("[…]") }
            return v
        }
        let canonical = JSONValue.object(stable).prettyString()
        return String(SHA256.hex(Data((e.transport + "|" + canonical).utf8)).prefix(6))
    }

    /// Réglages qui distinguent un client (pour aider à le reconnaître avant de le nommer).
    public static func signatureDescription(of e: AuditLogEntry) -> String {
        let req = e.request ?? [:]
        var parts: [String] = []
        for k in ["budget", "max_tokens", "types", "tags_match", "prefer_observations", "trace", "response_schema"] {
            guard let v = req[k], v != .null else { continue }
            let s = v.prettyString().replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
            parts.append("\(k) \(s.count > 30 ? String(s.prefix(30)) + "…" : s)")
        }
        return parts.joined(separator: " · ")
    }

    static func identity(of e: AuditLogEntry) -> String? {
        let sources: [[String: JSONValue]] = [e.metadata, e.request ?? [:]]
        for key in actorKeys {
            for s in sources { if let v = s[key]?.stringValue, !v.isEmpty { return v } }
        }
        return nil
    }

    /// Identité de l'appelant : valeur de `groupBy` si fournie, sinon première clé connue trouvée, sinon
    /// nom donné à sa signature (`names`), sinon « profil » de la signature.
    public static func actor(of e: AuditLogEntry, groupBy: String? = nil, names: [String: String] = [:]) -> String {
        let sources: [[String: JSONValue]] = [e.metadata, e.request ?? [:]]
        if let key = groupBy {
            for s in sources { if let v = s[key]?.stringValue, !v.isEmpty { return "\(e.transport) · \(v)" } }
            return "\(e.transport) · (sans \(key))"
        }
        if let id = identity(of: e) { return "\(e.transport) · \(id)" }
        if let sig = signature(of: e) {
            if let name = names[sig], !name.isEmpty { return "\(e.transport) · \(name)" }
            return "\(e.transport) · client non identifié (profil \(sig))"
        }
        return "\(e.transport) · appelant non identifié"
    }

    public static func compute(_ entries: [AuditLogEntry], groupBy: String? = nil, names: [String: String] = [:]) -> [AccessRow] {
        var acc: [String: (transport: String, count: Int, actions: [String: Int], last: Date?)] = [:]
        var sigs: [String: (String, String)] = [:]
        for e in entries {
            let a = actor(of: e, groupBy: groupBy, names: names)
            if groupBy == nil, sigs[a] == nil, let s = signature(of: e) { sigs[a] = (s, signatureDescription(of: e)) }
            var row = acc[a] ?? (e.transport, 0, [:], nil)
            row.count += 1
            row.actions[e.action, default: 0] += 1
            if let d = HSDate.parse(e.startedAt), row.last.map({ d > $0 }) ?? true { row.last = d }
            acc[a] = row
        }
        return acc.map {
            AccessRow(
                actor: $0.key, transport: $0.value.transport, count: $0.value.count, actions: $0.value.actions, lastSeen: $0.value.last,
                signature: sigs[$0.key]?.0, signatureDescription: sigs[$0.key]?.1)
        }
            .sorted { ($1.count, $0.actor) < ($0.count, $1.actor) }
    }

    /// Nombre d'appels par action, du plus fréquent au plus rare.
    public static func actionCounts(_ entries: [AuditLogEntry]) -> [(action: String, count: Int)] {
        var c: [String: Int] = [:]
        for e in entries { c[e.action, default: 0] += 1 }
        return c.map { ($0.key, $0.value) }.sorted { ($1.count, $0.action) < ($0.count, $1.action) }
    }
}

/// Consommation LLM regroupée par opération / fournisseur / modèle.
public struct LLMUsageRow: Identifiable, Sendable, Hashable {
    public var id: String { "\(operation)|\(provider)|\(model)" }
    public let operation: String
    public let provider: String
    public let model: String
    public let calls: Int
    public let errors: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int
    public let averageDurationMs: Int?
}

public enum LLMUsageSummary {
    public static func compute(_ entries: [LLMRequestEntry]) -> [LLMUsageRow] {
        struct Acc { var calls = 0, errors = 0, input = 0, output = 0, cached = 0, durSum = 0, durN = 0 }
        var acc: [String: (String, String, String, Acc)] = [:]
        for e in entries {
            let op = e.operation ?? "?", p = e.provider ?? "?", m = e.model ?? "?"
            let key = "\(op)|\(p)|\(m)"
            var a = acc[key]?.3 ?? Acc()
            a.calls += 1
            if e.status.lowercased() != "success" { a.errors += 1 }
            a.input += e.inputTokens ?? 0
            a.output += e.outputTokens ?? 0
            a.cached += e.cachedTokens ?? 0
            if let d = e.durationMs {
                a.durSum += d
                a.durN += 1
            }
            acc[key] = (op, p, m, a)
        }
        return acc.values.map { op, p, m, a in
            LLMUsageRow(
                operation: op, provider: p, model: m, calls: a.calls, errors: a.errors, inputTokens: a.input,
                outputTokens: a.output, cachedTokens: a.cached, averageDurationMs: a.durN > 0 ? a.durSum / a.durN : nil)
        }.sorted { ($1.calls, $0.id) < ($0.calls, $1.id) }
    }
}
