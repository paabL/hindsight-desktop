import Foundation
import HindsightAPI

/// Un appel LLM réduit à ses compteurs (aucun contenu : ni prompt, ni réponse).
public struct UsageRecord: Codable, Sendable, Hashable {
    public var id: String
    public var bank: String
    /// Jour (AAAA-MM-JJ, UTC).
    public var day: String
    public var operation: String
    public var provider: String
    public var model: String
    public var input: Int
    public var output: Int
    public var cached: Int
    public var thoughts: Int
    public var failed: Bool

    /// Horodatage complet (ISO 8601) ; vide pour les enregistrements d'un historique plus ancien.
    public var startedAt: String = ""
    /// Document traité par l'appel (extraction d'un retain, métadonnée `document_id` de la trace) ; vide sinon.
    public var documentID: String = ""

    public init(_ e: LLMRequestEntry, bank: String) {
        id = e.id
        self.bank = e.bankId ?? bank
        startedAt = e.startedAt ?? ""
        if case .string(let d)? = e.metadata["document_id"] { documentID = d }
        day = String(startedAt.prefix(10))
        operation = UsageProfile.operationKey(e)
        provider = e.provider ?? "?"
        model = e.model ?? "?"
        input = e.inputTokens ?? 0
        output = e.outputTokens ?? 0
        cached = e.cachedTokens ?? 0
        thoughts = e.thoughtsTokens ?? 0
        failed = e.status.lowercased() != "success"
    }

    public var tokens: TokenCount { TokenCount(input: input, output: output, cached: cached, thoughts: thoughts) }

    /// Postérieur à `since` : à l'horodatage près quand il est connu, sinon au jour (UTC) près.
    public func isAfter(_ since: Date) -> Bool {
        if let d = HSDate.parse(startedAt) { return d >= since }
        return day >= UsageLedger.dayString(since)
    }

    enum CodingKeys: String, CodingKey {
        case id, bank, day, operation, provider, model, input, output, cached, thoughts, failed, startedAt
        case documentID = "document"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        bank = try c.decode(String.self, forKey: .bank)
        day = try c.decode(String.self, forKey: .day)
        operation = try c.decode(String.self, forKey: .operation)
        provider = try c.decode(String.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        input = try c.decode(Int.self, forKey: .input)
        output = try c.decode(Int.self, forKey: .output)
        cached = try c.decode(Int.self, forKey: .cached)
        thoughts = try c.decode(Int.self, forKey: .thoughts)
        failed = try c.decode(Bool.self, forKey: .failed)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt) ?? ""
        documentID = try c.decodeIfPresent(String.self, forKey: .documentID) ?? ""
    }
}

public struct DailyUsage: Identifiable, Sendable, Hashable {
    public var id: String { day }
    public let day: String
    public let tokens: Int
}

/// Ligne de synthèse : une opération sur un modèle.
public struct UsageRow: Identifiable, Sendable, Hashable {
    public var id: String { "\(operation)|\(provider)|\(model)" }
    public let operation: String
    public let provider: String
    public let model: String
    public let calls: Int
    public let failures: Int
    public let tokens: TokenCount
    public let billing: Billing
}

public struct UsageTotals: Sendable, Hashable {
    public var tokens = TokenCount()
    public var metered: Double = 0
    public var subscriptionTokens = 0
    public var subscriptionEquivalent: Double = 0
    public var localTokens = 0
    public var unknownTokens = 0
}

public enum UsageSummary {
    public static func rows(_ records: [UsageRecord], prices: PriceBook) -> [UsageRow] {
        var acc: [String: (op: String, p: String, m: String, n: Int, f: Int, t: TokenCount)] = [:]
        for r in records {
            let k = "\(r.operation)|\(r.provider)|\(r.model)"
            var a = acc[k] ?? (r.operation, r.provider, r.model, 0, 0, TokenCount())
            a.n += 1
            if r.failed { a.f += 1 }
            a.t = a.t + r.tokens
            acc[k] = a
        }
        return acc.values.map { a in
            UsageRow(operation: a.op, provider: a.p, model: a.m, calls: a.n, failures: a.f, tokens: a.t, billing: prices.billing(provider: a.p, model: a.m, tokens: a.t))
        }.sorted { ($1.tokens.total, $0.id) < ($0.tokens.total, $1.id) }
    }

    public static func totals(_ rows: [UsageRow]) -> UsageTotals {
        var t = UsageTotals()
        for r in rows {
            t.tokens = t.tokens + r.tokens
            switch r.billing {
            case .metered(let d): t.metered += d
            case .subscription(_, let eq):
                t.subscriptionTokens += r.tokens.total
                t.subscriptionEquivalent += eq ?? 0
            case .local: t.localTokens += r.tokens.total
            case .unknown: t.unknownTokens += r.tokens.total
            }
        }
        return t
    }

    /// Jetons par jour (pour un histogramme).
    public static func daily(_ records: [UsageRecord]) -> [DailyUsage] {
        var d: [String: Int] = [:]
        for r in records where !r.day.isEmpty { d[r.day, default: 0] += r.tokens.total }
        return d.sorted { $0.key < $1.key }.map { DailyUsage(day: $0.key, tokens: $0.value) }
    }
}

/// Historique local de consommation : le serveur ne garde ses traces LLM qu'un jour par défaut
/// (`HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS`). À chaque consultation, l'app y verse les compteurs des
/// traces lues (dédoublonnées par identifiant) pour garder un historique sur 400 jours.
public actor UsageLedger {
    private let url: URL
    private var records: [String: UsageRecord]?
    public static let keepDays = 400
    /// Écriture différée : au plus une fois par intervalle (0 : à chaque ajout). Le suivi de consommation relève
    /// souvent ; un ajout non écrit sera relu sur le serveur, qui garde ses traces au moins un jour.
    private var saveInterval: TimeInterval = 0
    private var lastSave = Date.distantPast
    private var dirty = false

    public func setSaveInterval(_ seconds: TimeInterval) { saveInterval = seconds }

    public init(url: URL = UsageLedger.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HindsightMac/usage-ledger.json")
    }

    private func load() -> [String: UsageRecord] {
        if let records { return records }
        let list = (try? JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: url))) ?? []
        let r = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        records = r
        return r
    }

    /// Ajoute les traces (déjà connues : ignorées) et retourne le nombre de nouvelles.
    @discardableResult
    public func merge(_ entries: [LLMRequestEntry], bank: String, now: Date = Date()) -> Int {
        var r = load()
        var added = 0
        // Embeddings, rerank et décision (serveur 1.1.0) ne consomment ni quota ni plafond : pas dans le registre.
        for e in entries where r[e.id] == nil && e.isGenerative {
            r[e.id] = UsageRecord(e, bank: bank)
            added += 1
        }
        let cutoff = Self.dayString(now.addingTimeInterval(-Double(Self.keepDays) * 86_400))
        r = r.filter { $0.value.day.isEmpty || $0.value.day >= cutoff }
        records = r
        if added > 0 {
            dirty = true
            flushIfDue(now: now)
        }
        return added
    }

    /// Écrit les ajouts en attente si l'intervalle est écoulé.
    public func flushIfDue(now: Date = Date()) {
        guard dirty, now.timeIntervalSince(lastSave) >= saveInterval else { return }
        flush(now: now)
    }

    /// Écrit les ajouts en attente tout de suite.
    public func flush(now: Date = Date()) {
        guard dirty, let records else { return }
        save(records)
        lastSave = now
        dirty = false
    }

    /// Date de la trace la plus récente d'une banque (reprise du suivi au lancement).
    public func latestStart(bank: String) -> String? {
        load().values.filter { $0.bank == bank }.map(\.startedAt).max()
    }

    public func records(bank: String?, since: Date?) -> [UsageRecord] {
        load().values.filter { (bank == nil || $0.bank == bank) && (since == nil || $0.isAfter(since!)) }
    }

    private func save(_ r: [String: UsageRecord]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(r.values).sorted { $0.id < $1.id })
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
