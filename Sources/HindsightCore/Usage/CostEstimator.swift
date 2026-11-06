import Foundation
import HindsightAPI
import Observation

/// Consommation observée par opération (retain, consolidation, reflect…), calculée sur les traces LLM
/// récentes : moyenne par appel, et dernier fournisseur/modèle utilisé.
public struct UsageProfile: Sendable, Hashable {
    public struct Operation: Sendable, Hashable {
        public var calls: Int
        public var perCall: TokenCount
        public var provider: String?
        public var model: String?
    }

    public var operations: [String: Operation]

    public init(operations: [String: Operation] = [:]) { self.operations = operations }

    public static func from(_ entries: [LLMRequestEntry]) -> UsageProfile {
        var acc: [String: (n: Int, sum: TokenCount, provider: String?, model: String?, last: String)] = [:]
        for e in entries where e.status.lowercased() == "success" && e.isGenerative {
            // Les appels de vision (scope « vlm ») ont un profil à part : on ne les mélange pas à l'extraction.
            let op = Self.operationKey(e)
            var a = acc[op] ?? (0, TokenCount(), nil, nil, "")
            a.n += 1
            a.sum = a.sum + TokenCount(input: e.inputTokens ?? 0, output: e.outputTokens ?? 0, cached: e.cachedTokens ?? 0, thoughts: e.thoughtsTokens ?? 0)
            let when = e.startedAt ?? ""
            if when >= a.last {
                a.last = when
                a.provider = e.provider
                a.model = e.model
            }
            acc[op] = a
        }
        return UsageProfile(
            operations: acc.mapValues { a in
                Operation(calls: a.n, perCall: a.sum * (1 / Double(max(a.n, 1))), provider: a.provider, model: a.model)
            })
    }

    static func operationKey(_ e: LLMRequestEntry) -> String {
        let op = (e.operation ?? "?").lowercased()
        if (e.scope ?? "").lowercased() == "vlm" { return "vlm" }
        if op.contains("consolid") { return "consolidation" }
        if op.contains("mental") || op.contains("knowledge") { return "mental_model" }
        if op.contains("reflect") { return "reflect" }
        if op.contains("retain") || op.contains("extract") { return "retain" }
        return op
    }
}

/// Ce qu'on veut estimer.
public enum EstimateKind: Sendable, Hashable {
    /// Rétention d'un texte (extraction des faits, puis consolidation automatique si activée).
    case retain(characters: Int, images: Int, consolidation: Bool)
    /// Consolidation de faits en attente.
    case consolidation(facts: Int)
    /// Reflect avec un budget low / mid / high.
    case reflect(budget: String)
    /// Régénération d'une connaissance.
    case mentalModelRefresh

    var title: String {
        switch self {
        case .retain: return "Extraction des faits"
        case .consolidation: return "Consolidation"
        case .reflect: return "Réponses"
        case .mentalModelRefresh: return "Régénération des connaissances"
        }
    }
}

/// Estimation : fourchette de jetons et coût correspondant, avec la base de calcul.
public struct CostEstimate: Sendable, Hashable {
    public struct Part: Sendable, Hashable {
        public var operation: String
        public var tokens: TokenCount
        public var provider: String?
        public var model: String?
        public var billing: Billing
    }

    public var parts: [Part]
    /// Facteurs appliqués pour la fourchette (incertitude du modèle).
    public var low: Double = 0.5
    public var high: Double = 2
    /// « mesuré sur 34 appels récents » ou « valeurs par défaut ».
    public var basis: String

    public var tokens: TokenCount { parts.reduce(TokenCount()) { $0 + $1.tokens } }
    public var dollars: Double? {
        let metered = parts.compactMap { $0.billing.dollars }
        return metered.isEmpty ? nil : metered.reduce(0, +)
    }
    public var subscriptionEquivalent: Double? {
        let eq = parts.compactMap { p -> Double? in
            if case .subscription(_, let e) = p.billing { return e }
            return nil
        }
        return eq.isEmpty ? nil : eq.reduce(0, +)
    }
    public var hasSubscription: Bool {
        parts.contains { if case .subscription = $0.billing { return true } else { return false } }
    }
    public var hasUnknown: Bool { parts.contains { $0.billing == .unknown } }

    /// Résumé d'une ligne, pour les confirmations.
    public var summary: String {
        let t = tokens.total
        guard t > 0 else { return "Aucun appel LLM prévu." }
        var s = "Estimation : ≈ \(Format.tokens(Int(Double(t) * low)))–\(Format.tokens(Int(Double(t) * high))) jetons LLM"
        var costs: [String] = []
        if let d = dollars { costs.append("≈ \(Format.dollars(d * low))–\(Format.dollars(d * high)) facturés") }
        if hasSubscription {
            costs.append("pris sur l'abonnement" + (subscriptionEquivalent.map { " (≈ \(Format.dollars($0)) à l'usage)" } ?? ""))
        }
        if hasUnknown { costs.append("tarif inconnu pour une partie") }
        if !costs.isEmpty { s += ", " + costs.joined(separator: ", ") }
        return s + " — \(basis)."
    }
}

/// Estimations de consommation avant une action. Calibrées sur les traces LLM récentes de la banque
/// quand il y en a (moyenne par appel), sinon sur des valeurs par défaut tirées des réglages du serveur
/// (taille des morceaux 3 000 caractères, lots de consolidation de 8 faits…).
@MainActor
@Observable
public final class CostEstimator {
    /// Valeurs par appel quand aucune trace n'est disponible (ordres de grandeur).
    public struct Defaults: Sendable, Hashable {
        public var chunkCharacters = 3000
        public var retainPerChunk = TokenCount(input: 3500, output: 900)
        public var factsPerChunk = 12
        public var factsPerConsolidationCall = 8
        public var consolidationPerCall = TokenCount(input: 3000, output: 600)
        public var tokensPerImage = 1500
        public var reflect: [String: TokenCount] = [
            "low": TokenCount(input: 8000, output: 800), "mid": TokenCount(input: 20000, output: 1500),
            "high": TokenCount(input: 50000, output: 2500),
        ]
        public var mentalModel = TokenCount(input: 25000, output: 2500)
        public init() {}
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    /// Fournisseur/modèle d'un rôle selon le script de lancement (repli quand aucune trace n'existe).
    @ObservationIgnored public var roleModel: (@MainActor (String) -> (provider: String?, model: String?))?
    public var priceBook: PriceBook {
        didSet { priceBook.save(to: settings) }
    }
    public var defaults = Defaults()
    public private(set) var profiles: [String: UsageProfile] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]

    public init(settings: SettingsStore, client: @escaping @MainActor () -> HindsightClient) {
        self.settings = settings
        self.clientProvider = client
        self.priceBook = PriceBook.load(from: settings)
    }

    /// Met à jour le profil de la banque depuis ses traces LLM (au plus toutes les 10 minutes).
    public func refreshProfile(bank: String, force: Bool = false) async {
        if !force, let t = fetchedAt[bank], Date().timeIntervalSince(t) < 600 { return }
        // Horodaté après succès : un échec (traces désactivées, serveur absent) sera retenté au prochain appel.
        if let list = try? await clientProvider().llmRequests(bank, callType: ModelCallKind.generativeFilter, limit: 500) {
            profiles[bank] = UsageProfile.from(list.items)
            fetchedAt[bank] = Date()
        }
    }

    public func setProfile(_ p: UsageProfile, bank: String) {
        profiles[bank] = p
        fetchedAt[bank] = Date()
    }

    func part(_ op: String, calls: Double, fallback: TokenCount, bank: String?, role: String) -> (CostEstimate.Part, observed: Int) {
        let observed = bank.flatMap { profiles[$0]?.operations[op] }
        let perCall = (observed?.calls ?? 0) >= 3 ? observed!.perCall : fallback
        let fallbackModel = roleModel?(role)
        let provider = observed?.provider ?? fallbackModel?.provider
        let model = observed?.model ?? fallbackModel?.model
        let tokens = perCall * calls
        return (
            CostEstimate.Part(
                operation: op, tokens: tokens, provider: provider, model: model,
                billing: priceBook.billing(provider: provider, model: model, tokens: tokens)),
            (observed?.calls ?? 0) >= 3 ? observed!.calls : 0
        )
    }

    public func estimate(_ kind: EstimateKind, bank: String?) -> CostEstimate {
        let d = defaults
        var parts: [(CostEstimate.Part, Int)] = []
        switch kind {
        case .retain(let chars, let images, let consolidation):
            let chunks = max(1, Int((Double(chars) / Double(d.chunkCharacters)).rounded(.up)))
            parts.append(part("retain", calls: Double(chunks), fallback: d.retainPerChunk, bank: bank, role: "retain"))
            if images > 0 {
                parts.append(part("vlm", calls: Double(images), fallback: TokenCount(input: d.tokensPerImage, output: 150), bank: bank, role: "vlm"))
            }
            if consolidation {
                let calls = Double(chunks * d.factsPerChunk) / Double(d.factsPerConsolidationCall)
                parts.append(part("consolidation", calls: calls.rounded(.up), fallback: d.consolidationPerCall, bank: bank, role: "consolidation"))
            }
        case .consolidation(let facts):
            let calls = (Double(max(facts, 0)) / Double(d.factsPerConsolidationCall)).rounded(.up)
            parts.append(part("consolidation", calls: calls, fallback: d.consolidationPerCall, bank: bank, role: "consolidation"))
        case .reflect(let budget):
            parts.append(part("reflect", calls: 1, fallback: d.reflect[budget] ?? d.reflect["mid"] ?? TokenCount(input: 20_000, output: 1_500), bank: bank, role: "reflect"))
        case .mentalModelRefresh:
            parts.append(part("mental_model", calls: 1, fallback: d.mentalModel, bank: bank, role: "mental_model"))
        }
        let observed = parts.map(\.1).reduce(0, +)
        let basis = observed > 0 ? "calibrée sur \(observed) appels LLM récents de cette banque" : "valeurs par défaut (aucune trace récente)"
        var e = CostEstimate(parts: parts.map(\.0), basis: basis)
        if observed > 0 {
            e.low = 0.7
            e.high = 1.5
        }
        return e
    }

    /// Estimation calée sur une mesure réelle (essai à blanc d'extraction) : jetons mesurés pour
    /// `sampleCharacters`, extrapolés à `totalCharacters`.
    public func extrapolate(measured: TokenCount, sampleCharacters: Int, totalCharacters: Int, bank: String?) -> CostEstimate {
        let k = Double(totalCharacters) / Double(max(sampleCharacters, 1))
        let fb = roleModel?("retain")
        let observed = bank.flatMap { profiles[$0]?.operations["retain"] }
        let provider = observed?.provider ?? fb?.provider
        let model = observed?.model ?? fb?.model
        let tokens = measured * k
        var e = CostEstimate(
            parts: [CostEstimate.Part(operation: "retain", tokens: tokens, provider: provider, model: model, billing: priceBook.billing(provider: provider, model: model, tokens: tokens))],
            basis: "mesurée sur l'essai à blanc")
        e.low = 0.8
        e.high = 1.3
        return e
    }
}
