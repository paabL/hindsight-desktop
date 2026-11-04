import Foundation
import HindsightAPI
import Observation

/// Un élément de mémoire renvoyé par une lecture (quand le journal l'a conservé).
public struct ReadItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let text: String?
    public let type: String?
}

/// Une lecture de la banque : qui, quand, quelle question, et ce qui a été renvoyé si le serveur l'a journalisé.
public struct ReadEvent: Identifiable, Sendable, Hashable {
    public let id: String
    public let action: String
    public let transport: String
    public let who: String
    /// Signature du client HTTP non identifié (pour le nommer).
    public let signature: String?
    public let date: Date?
    public let durationMs: Int?
    /// Question ou filtre de la lecture.
    public let query: String?
    /// Paramètres notables (budget, types, tags…).
    public let parameters: [String]
    public let items: [ReadItem]
    /// Nombre d'éléments renvoyés, s'il est connu (même quand leur contenu n'est pas journalisé).
    public let returnedCount: Int?
    public let entry: AuditLogEntry

    /// Lecture qui fait appel à un LLM génératif (reflect, modèle mental…) : ce qui a été « lu » est dans ses traces.
    public var usesLLM: Bool { action.lowercased().contains("reflect") }
    /// Le recall peut être rejoué tel quel (requête complète journalisée).
    public var replayableRecall: RecallRequest? {
        guard action.lowercased().contains("recall"), let r = entry.request else { return nil }
        guard let data = try? JSONEncoder().encode(JSONValue.object(r)) else { return nil }
        return try? JSONDecoder().decode(RecallRequest.self, from: data)
    }
}

public enum ReadLog {
    /// Une action d'écriture contient l'un de ces mots (entiers) ; tout le reste est une lecture.
    static let writeMarkers: Set<String> = [
        "retain", "delete", "update", "create", "clear", "import", "consolidate", "consolidation", "refresh", "invalidate",
        "revalidate", "set", "patch", "reprocess", "cancel", "retry", "recover", "add", "remove", "upsert", "write",
    ]

    public static func isRead(_ action: String) -> Bool {
        // Comparaison par mot entier : « get_settings » n'est pas une écriture.
        let words = action.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !words.contains { writeMarkers.contains($0) }
    }

    public static func event(_ e: AuditLogEntry, names: [String: String] = [:]) -> ReadEvent {
        let req = e.request ?? [:]
        let query = ["query", "q", "search", "question", "text"].lazy.compactMap { req[$0]?.stringValue }.first { !$0.isEmpty }
        var params: [String] = []
        if let b = req["budget"]?.stringValue { params.append("budget \(b)") }
        if case .array(let types)? = req["types"] { params.append("types " + types.compactMap(\.stringValue).joined(separator: ",")) }
        if case .array(let tags)? = req["tags"], !tags.isEmpty {
            params.append("tags " + tags.compactMap(\.stringValue).joined(separator: ","))
        }
        if let m = req["max_tokens"]?.intValue { params.append("max \(m) jetons") }
        for k in ["document_id", "memory_id", "entity_id", "mental_model_id"] {
            if let v = req[k]?.stringValue { params.append("\(k.replacingOccurrences(of: "_id", with: "")) \(v)") }
        }
        let items = e.response.map { collectItems(.object($0)) } ?? []
        var count: Int? = items.isEmpty ? nil : items.count
        if count == nil, let r = e.response {
            count = ["result_count", "results_count", "count", "total", "n_results"].lazy.compactMap { r[$0]?.intValue }.first
        }
        return ReadEvent(
            id: e.id, action: e.action, transport: e.transport, who: AccessSummary.actor(of: e, names: names), signature: AccessSummary.signature(of: e),
            date: e.startedAt.flatMap(HSDate.parse), durationMs: e.durationMs, query: query, parameters: params,
            items: items, returnedCount: count, entry: e)
    }

    /// Cherche, à faible profondeur, des tableaux d'objets portant un `id` et un texte ou un type
    /// (`results`, `memories`, `based_on.memories`…).
    static func collectItems(_ v: JSONValue, depth: Int = 0) -> [ReadItem] {
        guard depth <= 3 else { return [] }
        switch v {
        case .array(let a):
            let objects = a.compactMap { x -> [String: JSONValue]? in if case .object(let o) = x { return o } else { return nil } }
            let items = objects.compactMap { o -> ReadItem? in
                guard let id = o["id"]?.stringValue, o["text"] != nil || o["type"] != nil || o["fact_type"] != nil else { return nil }
                return ReadItem(id: id, text: o["text"]?.stringValue, type: (o["type"] ?? o["fact_type"])?.stringValue)
            }
            if !items.isEmpty { return items }
            return a.flatMap { collectItems($0, depth: depth + 1) }
        case .object(let o):
            var seen = Set<String>()
            return o.keys.sorted().flatMap { collectItems(o[$0]!, depth: depth + 1) }.filter { seen.insert($0.id).inserted }
        default:
            return []
        }
    }

    /// Éléments les plus souvent renvoyés sur un ensemble de lectures.
    public static func mostRead(_ events: [ReadEvent], limit: Int = 20) -> [(item: ReadItem, count: Int)] {
        var count: [String: Int] = [:]
        var first: [String: ReadItem] = [:]
        for e in events {
            for i in Set(e.items.map(\.id)) { count[i, default: 0] += 1 }
            for i in e.items where first[i.id] == nil || first[i.id]?.text == nil { first[i.id] = i }
        }
        return count.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(limit).map { (first[$0.key]!, $0.value) }
    }
}

/// « Qui a lu quoi, et quand » : lectures de la banque d'après le journal d'audit.
///
/// Limite du serveur : le journal garde la requête et, selon la version, tout ou partie de la réponse.
/// Quand les éléments renvoyés n'y sont pas, l'app propose de rejouer un recall (état ACTUEL de la
/// mémoire, sans LLM génératif) et, pour un reflect, d'ouvrir les traces LLM de ce moment-là (le prompt
/// contient les faits réellement fournis au modèle).
@MainActor
@Observable
public final class ReadsViewModel {
    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public var period = "7d"
    public var whoFilter: String?
    public var search = ""
    public private(set) var state: LoadState<[ReadEvent]> = .idle
    /// Entrées du journal lues (lectures et écritures confondues) : 0 avec un journal désactivé.
    public private(set) var scannedEntries = 0
    public private(set) var selected: ReadEvent?
    public private(set) var replay: LoadState<[FactHit]> = .idle
    public private(set) var traces: LoadState<[LLMRequestEntry]> = .idle
    /// Noms donnés aux clients non identifiés (partagés entre banques).
    @ObservationIgnored public var callers: CallerDirectory?
    @ObservationIgnored private var raw: [AuditLogEntry] = []

    /// Recalcule les lecteurs (après avoir nommé un client).
    public func rebuild() {
        let names = callers?.names ?? [:]
        state = .loaded(raw.map { ReadLog.event($0, names: names) })
        if let id = selected?.id { selected = state.value?.first { $0.id == id } }
    }

    public func nameCaller(_ signature: String, _ name: String) {
        callers?.setName(name, for: signature)
        rebuild()
    }

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    static func start(of period: String, now: Date = Date()) -> Date? {
        guard let n = Double(period.dropLast()), period.hasSuffix("d") else { return nil }
        return now.addingTimeInterval(-n * 86_400)
    }

    /// Numéro du dernier chargement : un résultat dépassé (période changée entre-temps) est ignoré.
    @ObservationIgnored private var loadID = 0

    public func reload() async {
        loadID += 1
        let mine = loadID
        state = .loading
        do {
            var all: [AuditLogEntry] = []
            var offset = 0
            let since = Self.start(of: period)
            while offset < 2000 {
                let page = try await client.auditLogs(bank, start: since, limit: 500, offset: offset)
                all += page.items
                offset += page.items.count
                if page.items.count < 500 || offset >= page.total { break }
            }
            guard mine == loadID else { return }
            scannedEntries = all.count
            let reads = await Self.withBodies(all.filter { ReadLog.isRead($0.action) }, bank: bank, client: client)
            guard mine == loadID else { return }
            raw = reads
            rebuild()
        } catch is CancellationError {
        } catch {
            if mine == loadID { state = .failed(error.userMessage) }
        }
    }

    /// Serveur 1.1.0 : la liste du journal n'a plus les corps (requête, éléments renvoyés). On lit le détail des
    /// lectures qui en manquent, 300 au plus, huit à la fois ; un serveur 1.0.0 les donne déjà, rien n'est lu.
    static func withBodies(_ entries: [AuditLogEntry], bank: String, client: HindsightClient) async -> [AuditLogEntry] {
        let missing = entries.indices.filter { entries[$0].request == nil && entries[$0].response == nil }.prefix(300)
        guard !missing.isEmpty else { return entries }
        var out = entries
        await withTaskGroup(of: (Int, AuditLogEntry?).self) { group in
            var next = missing.makeIterator()
            func add() {
                guard let i = next.next() else { return }
                let id = entries[i].id
                group.addTask { (i, try? await client.auditLog(bank, id: id)) }
            }
            for _ in 0..<8 { add() }
            for await (i, full) in group {
                if let full { out[i] = full }
                add()
            }
        }
        return out
    }

    public var readers: [String] { Array(Set((state.value ?? []).map(\.who))).sorted() }

    public var events: [ReadEvent] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (state.value ?? []).filter { e in
            (whoFilter == nil || e.who == whoFilter)
                && (q.isEmpty || (e.query ?? "").lowercased().contains(q) || e.action.lowercased().contains(q)
                    || e.items.contains { ($0.text ?? "").lowercased().contains(q) })
        }
    }

    /// Le journal contient-il le contenu renvoyé ? (au moins une lecture avec des éléments)
    public var responsesAreLogged: Bool { (state.value ?? []).contains { !$0.items.isEmpty } }
    public var mostRead: [(item: ReadItem, count: Int)] { ReadLog.mostRead(events) }

    public func select(_ e: ReadEvent?) {
        selected = e
        replay = .idle
        traces = .idle
    }

    /// Rejoue le recall journalisé : lecture seule, sur l'état actuel de la mémoire.
    public func replaySelected() async {
        guard let req = selected?.replayableRecall else { return }
        replay = .loading
        do {
            replay = .loaded(try await client.recall(bank, req).results.map(FactHit.init))
        } catch {
            replay = .failed(error.userMessage)
        }
    }

    /// Traces LLM émises pendant la lecture (± 5 s) : pour un reflect, ce que le modèle a lu.
    public func loadTracesForSelected() async {
        guard let e = selected, let start = e.date else { return }
        let end = start.addingTimeInterval(Double(e.durationMs ?? 60_000) / 1000 + 5)
        traces = .loading
        do {
            let r = try await client.llmRequests(bank, start: start.addingTimeInterval(-5), end: end, limit: 100)
            traces = .loaded(r.items)
        } catch {
            traces = .failed(error.userMessage)
        }
    }
}
