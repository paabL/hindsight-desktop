import Foundation
import HindsightAPI

/// Un appel LLM prêt pour les calculs : date analysée une fois, compteurs seulement (aucun contenu).
public struct ConsumptionEvent: Sendable, Hashable, Identifiable {
    public let id: String
    public let date: Date
    public let bank: String
    public let operation: String
    public let provider: String
    public let model: String
    /// Document traité (extraction d'un retain) ; vide pour la consolidation, reflect…
    public let document: String
    public let tokens: TokenCount
    public let failed: Bool

    public init(
        id: String, date: Date, bank: String, operation: String, provider: String, model: String, document: String = "",
        tokens: TokenCount, failed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.bank = bank
        self.operation = operation
        self.provider = provider
        self.model = model
        self.document = document
        self.tokens = tokens
        self.failed = failed
    }

    /// Enregistrement de l'historique local ; sans horodatage complet (historique ancien), midi UTC du jour.
    public init?(_ r: UsageRecord) {
        guard let date = HSDate.parse(r.startedAt) ?? HSDate.parse(r.day.isEmpty ? nil : r.day + "T12:00:00Z") else { return nil }
        self.init(
            id: r.id, date: date, bank: r.bank, operation: r.operation, provider: r.provider.lowercased(), model: r.model,
            document: r.documentID, tokens: r.tokens, failed: r.failed)
    }
}

/// Sommes d'une période, réparties selon la facturation.
public struct ConsumptionTotals: Sendable, Hashable {
    public var calls = 0
    public var failures = 0
    public var tokens = TokenCount()
    /// Facturé à l'usage (USD, grille de Tarifs).
    public var dollars = 0.0
    /// Jetons pris sur un abonnement (Claude Code, Codex) : ils consomment le quota, pas d'argent.
    public var subscriptionTokens = 0
    /// Ce que coûteraient ces jetons d'abonnement à l'usage.
    public var subscriptionEquivalent = 0.0
    public var localTokens = 0
    /// Modèles absents de la grille : ni dollars ni quota connus.
    public var unpricedTokens = 0

    public init() {}

    /// Poids pour classer : dollars facturés et valeur des jetons d'abonnement.
    public var weight: Double { dollars + subscriptionEquivalent }

    mutating func add(_ e: ConsumptionEvent, _ billing: Billing) {
        calls += 1
        if e.failed { failures += 1 }
        tokens = tokens + e.tokens
        switch billing {
        case .metered(let d): dollars += d
        case .subscription(_, let eq):
            subscriptionTokens += e.tokens.total
            subscriptionEquivalent += eq ?? 0
        case .local: localTokens += e.tokens.total
        case .unknown: unpricedTokens += e.tokens.total
        }
    }
}

/// Facturation par fournisseur/modèle, mémorisée le temps d'un calcul (la grille est parcourue par motif).
struct BillingCache {
    let prices: PriceBook
    private var kinds: [String: Kind] = [:]

    private enum Kind {
        case subscription(String, ModelPrice?)
        case local
        case metered(ModelPrice)
        case unknown
    }

    init(_ prices: PriceBook) { self.prices = prices }

    mutating func billing(_ e: ConsumptionEvent) -> Billing {
        let key = e.provider + "|" + e.model
        let kind: Kind
        if let k = kinds[key] {
            kind = k
        } else {
            if prices.subscriptionProviders.contains(e.provider) {
                kind = .subscription(e.provider, prices.price(for: e.model))
            } else if prices.localProviders.contains(e.provider) {
                kind = .local
            } else if let p = prices.price(for: e.model) {
                kind = .metered(p)
            } else {
                kind = .unknown
            }
            kinds[key] = kind
        }
        switch kind {
        case .subscription(let provider, let price): return .subscription(provider: provider, apiEquivalent: price.map { Self.cost($0, e.tokens) })
        case .local: return .local
        case .metered(let p): return .metered(Self.cost(p, e.tokens))
        case .unknown: return .unknown
        }
    }

    /// Même règle que `PriceBook.apiCost` : cache au tarif réduit, réflexion au prix de la sortie.
    static func cost(_ p: ModelPrice, _ t: TokenCount) -> Double {
        let cached = min(t.cached, t.input)
        let dollars = Double(t.input - cached) * p.input + Double(cached) * (p.cachedInput ?? p.input) + Double(t.output + t.thoughts) * p.output
        return dollars / 1_000_000
    }
}

/// Calculs de consommation sur des appels triés par date croissante.
public enum ConsumptionMath {
    /// Rythme récent (moyenne sur une courte fenêtre glissante).
    public struct Rate: Sendable, Hashable {
        public var tokensPerMinute: Double = 0
        public var callsPerMinute: Double = 0
        public var dollarsPerHour: Double = 0
        public var subscriptionTokensPerHour: Double = 0
        public init() {}
        public var isIdle: Bool { callsPerMinute == 0 }
    }

    /// Une tranche d'histogramme.
    public struct Bucket: Sendable, Hashable, Identifiable {
        public var id: Date { start }
        public let start: Date
        public var tokens: Int
        public var calls: Int
        public var failures: Int
        public var dollars: Double
        /// Jetons par opération (pour colorer les barres).
        public var byOperation: [String: Int]
    }

    /// Une ligne de répartition (banque, opération, modèle ou document).
    public struct Share: Sendable, Hashable, Identifiable {
        public let id: String
        public var totals: ConsumptionTotals
        /// Part du total de la période (poids en dollars, sinon en jetons).
        public var fraction: Double
    }

    public enum Dimension: String, CaseIterable, Identifiable, Sendable {
        case bank, operation, model, document
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .bank: return "Banque"
            case .operation: return "Opération"
            case .model: return "Modèle"
            case .document: return "Document"
            }
        }

        func key(_ e: ConsumptionEvent) -> String {
            switch self {
            case .bank: return e.bank
            case .operation: return e.operation
            case .model: return e.provider + " · " + e.model
            // Un même identifiant (doc:dépôt:chemin) peut exister dans deux banques : ce sont deux documents.
            case .document: return e.document.isEmpty ? "" : ConsumptionMath.documentKey(bank: e.bank, document: e.document)
            }
        }
    }

    /// Clé d'un document dans une banque (répartition par document).
    public static func documentKey(bank: String, document: String) -> String { bank + "\u{1F}" + document }

    public static func splitDocumentKey(_ key: String) -> (bank: String, document: String) {
        guard let sep = key.firstIndex(of: "\u{1F}") else { return ("", key) }
        return (String(key[..<sep]), String(key[key.index(after: sep)...]))
    }

    /// Premier indice dont la date est ≥ `start` (recherche dichotomique).
    public static func firstIndex(_ events: [ConsumptionEvent], from start: Date) -> Int {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].date < start { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public static func since(_ events: [ConsumptionEvent], _ start: Date) -> ArraySlice<ConsumptionEvent> {
        events[firstIndex(events, from: start)...]
    }

    public static func totals<S: Sequence>(_ events: S, prices: PriceBook) -> ConsumptionTotals where S.Element == ConsumptionEvent {
        var cache = BillingCache(prices)
        var t = ConsumptionTotals()
        for e in events { t.add(e, cache.billing(e)) }
        return t
    }

    /// Rythme sur les `minutes` dernières minutes.
    public static func rate(_ events: [ConsumptionEvent], now: Date, minutes: Double = 5, prices: PriceBook) -> Rate {
        let t = totals(since(events, now.addingTimeInterval(-minutes * 60)), prices: prices)
        var r = Rate()
        r.tokensPerMinute = Double(t.tokens.total) / minutes
        r.callsPerMinute = Double(t.calls) / minutes
        r.dollarsPerHour = t.dollars * 60 / minutes
        r.subscriptionTokensPerHour = Double(t.subscriptionTokens) * 60 / minutes
        return r
    }

    /// Histogramme de `from` à `to` par pas de `step` secondes (tranches vides comprises).
    public static func buckets(_ events: [ConsumptionEvent], from: Date, to: Date, step: TimeInterval, prices: PriceBook) -> [Bucket] {
        guard step > 0, to > from else { return [] }
        let count = Int(((to.timeIntervalSince(from)) / step).rounded(.up))
        return buckets(events, boundaries: (0...count).map { from.addingTimeInterval(Double($0) * step) }, prices: prices)
    }

    /// Histogramme sur des bornes données (croissantes) : `boundaries.count - 1` tranches.
    public static func buckets(_ events: [ConsumptionEvent], boundaries: [Date], prices: PriceBook) -> [Bucket] {
        guard boundaries.count >= 2 else { return [] }
        var out = boundaries.dropLast().map { Bucket(start: $0, tokens: 0, calls: 0, failures: 0, dollars: 0, byOperation: [:]) }
        var cache = BillingCache(prices)
        let end = boundaries[boundaries.count - 1]
        var i = 0
        for e in since(events, boundaries[0]) where e.date < end {
            while i + 1 < boundaries.count - 1, e.date >= boundaries[i + 1] { i += 1 }
            out[i].tokens += e.tokens.total
            out[i].calls += 1
            if e.failed { out[i].failures += 1 }
            out[i].dollars += cache.billing(e).dollars ?? 0
            out[i].byOperation[e.operation, default: 0] += e.tokens.total
        }
        return out
    }

    /// Bornes des `days` derniers jours civils, aujourd'hui compris (un jour de changement d'heure dure 23 ou 25 h).
    public static func dayBoundaries(endingWith now: Date, days: Int, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0...days).compactMap { calendar.date(byAdding: .day, value: $0 - days + 1, to: today) }
    }

    /// Répartition triée du plus coûteux au moins coûteux ; les appels sans clé (document vide) sont écartés.
    public static func breakdown<S: Sequence>(_ events: S, by dimension: Dimension, prices: PriceBook, limit: Int? = nil) -> [Share]
    where S.Element == ConsumptionEvent {
        var cache = BillingCache(prices)
        var acc: [String: ConsumptionTotals] = [:]
        for e in events {
            let k = dimension.key(e)
            guard !k.isEmpty else { continue }
            acc[k, default: ConsumptionTotals()].add(e, cache.billing(e))
        }
        let byWeight = acc.values.contains { $0.weight > 0 }
        let total = acc.values.reduce(0.0) { $0 + (byWeight ? $1.weight : Double($1.tokens.total)) }
        var rows = acc.map { k, t in
            Share(id: k, totals: t, fraction: total > 0 ? (byWeight ? t.weight : Double(t.tokens.total)) / total : 0)
        }
        rows.sort { ($0.fraction, $0.totals.tokens.total, $1.id) > ($1.fraction, $1.totals.tokens.total, $0.id) }
        if let limit { rows = Array(rows.prefix(limit)) }
        return rows
    }

    public static func startOfDay(_ now: Date, calendar: Calendar = .current) -> Date { calendar.startOfDay(for: now) }

    /// Nom court d'une opération de trace (`UsageProfile.operationKey`).
    public static func operationTitle(_ key: String) -> String {
        switch key {
        case "retain": return "Extraction"
        case "consolidation": return "Consolidation"
        case "reflect": return "Reflect"
        case "mental_model": return "Modèles mentaux"
        case "vlm": return "Images"
        default: return key.replacingOccurrences(of: "_", with: " ")
        }
    }
}
