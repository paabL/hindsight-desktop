import Foundation
import HindsightAPI

/// Tarif d'un modèle, en dollars US par million de jetons.
public struct ModelPrice: Codable, Sendable, Hashable, Identifiable {
    public var id: String { pattern }
    /// Sous-chaîne recherchée dans le nom du modèle (minuscules) ; le motif le plus long l'emporte.
    public var pattern: String
    public var input: Double
    public var output: Double
    /// Lecture depuis le cache de prompt (souvent 10 à 25 % du prix d'entrée) ; `nil` = prix d'entrée.
    public var cachedInput: Double?

    public init(_ pattern: String, input: Double, output: Double, cachedInput: Double? = nil) {
        self.pattern = pattern
        self.input = input
        self.output = output
        self.cachedInput = cachedInput
    }
}

/// Coût estimé d'une consommation de jetons.
public enum Billing: Sendable, Hashable {
    /// Facturé à l'usage par le fournisseur (USD).
    case metered(Double)
    /// Inclus dans un abonnement (Claude Code, ChatGPT/Codex) : consomme le quota, pas d'argent en plus.
    /// `apiEquivalent` : ce que coûteraient les mêmes jetons à l'usage, pour juger la part du quota.
    case subscription(provider: String, apiEquivalent: Double?)
    /// Modèle local (Ollama, LM Studio, vLLM…) : pas de coût par jeton.
    case local
    /// Modèle absent de la grille tarifaire.
    case unknown

    public var dollars: Double? {
        if case .metered(let d) = self { return d }
        return nil
    }
}

/// Jetons consommés (entrée, sortie, lus depuis le cache, réflexion).
public struct TokenCount: Sendable, Hashable {
    public var input = 0
    public var output = 0
    public var cached = 0
    public var thoughts = 0

    public init(input: Int = 0, output: Int = 0, cached: Int = 0, thoughts: Int = 0) {
        self.input = input
        self.output = output
        self.cached = cached
        self.thoughts = thoughts
    }

    public var total: Int { input + output + thoughts }

    public static func + (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(input: a.input + b.input, output: a.output + b.output, cached: a.cached + b.cached, thoughts: a.thoughts + b.thoughts)
    }

    public static func * (a: TokenCount, k: Double) -> TokenCount {
        TokenCount(input: Int(Double(a.input) * k), output: Int(Double(a.output) * k), cached: Int(Double(a.cached) * k), thoughts: Int(Double(a.thoughts) * k))
    }
}

/// Grille tarifaire modifiable (Réglages › Tarifs). Les valeurs par défaut sont des prix publics
/// indicatifs : ils changent, et l'app ne les met pas à jour seule.
public struct PriceBook: Codable, Sendable, Hashable {
    public var prices: [ModelPrice]
    /// Fournisseurs facturés par abonnement (identifiants `HINDSIGHT_API_*_PROVIDER`).
    public var subscriptionProviders: [String]
    /// Fournisseurs locaux (aucun coût par jeton).
    public var localProviders: [String]
    /// Date de relevé des prix par défaut, affichée avec les estimations.
    public var asOf: String

    public init(prices: [ModelPrice], subscriptionProviders: [String], localProviders: [String], asOf: String) {
        self.prices = prices
        self.subscriptionProviders = subscriptionProviders
        self.localProviders = localProviders
        self.asOf = asOf
    }

    public static let defaults = PriceBook(
        prices: [
            // Anthropic (cache : 10 % du prix d'entrée)
            ModelPrice("claude-opus-4-1", input: 15, output: 75, cachedInput: 1.5),
            ModelPrice("claude-opus-4-2025", input: 15, output: 75, cachedInput: 1.5),  // claude-opus-4-20250514
            ModelPrice("claude-opus", input: 5, output: 25, cachedInput: 0.5),
            ModelPrice("claude-sonnet", input: 3, output: 15, cachedInput: 0.3),
            ModelPrice("claude-haiku", input: 1, output: 5, cachedInput: 0.1),
            ModelPrice("claude-3-5-haiku", input: 0.8, output: 4, cachedInput: 0.08),
            // Alias courts (fournisseur claude-code : « sonnet », « opus »…)
            ModelPrice("opus", input: 5, output: 25, cachedInput: 0.5),
            ModelPrice("sonnet", input: 3, output: 15, cachedInput: 0.3),
            ModelPrice("haiku", input: 1, output: 5, cachedInput: 0.1),
            // OpenAI
            ModelPrice("gpt-5", input: 1.25, output: 10, cachedInput: 0.125),
            ModelPrice("gpt-5-mini", input: 0.25, output: 2, cachedInput: 0.025),
            ModelPrice("gpt-5-nano", input: 0.05, output: 0.4, cachedInput: 0.005),
            ModelPrice("gpt-4.1", input: 2, output: 8, cachedInput: 0.5),
            ModelPrice("gpt-4.1-mini", input: 0.4, output: 1.6, cachedInput: 0.1),
            ModelPrice("gpt-4o", input: 2.5, output: 10, cachedInput: 1.25),
            ModelPrice("gpt-4o-mini", input: 0.15, output: 0.6, cachedInput: 0.075),
            // Google (cache : 25 %)
            ModelPrice("gemini-2.5-pro", input: 1.25, output: 10, cachedInput: 0.31),
            ModelPrice("gemini", input: 0.3, output: 2.5, cachedInput: 0.075),
            ModelPrice("flash-lite", input: 0.1, output: 0.4, cachedInput: 0.025),
            // Groq, Mistral…
            ModelPrice("llama", input: 0.6, output: 0.8),
            ModelPrice("mistral", input: 0.4, output: 2),
        ] + inferencePrices,
        subscriptionProviders: ["claude-code", "openai-codex", "codex", "chatgpt"],
        localProviders: ["ollama", "lmstudio", "vllm", "local", "llamacpp", "none"],
        asOf: "2026-06")

    /// Hindsight Inference (novembre 2026) : facturé à l'entrée seulement, ces modèles n'écrivent rien.
    public static let inferencePrices: [ModelPrice] = [
        ModelPrice("hs-decide-1-flash", input: 0.02, output: 0),
        ModelPrice("hs-rerank-1", input: 0.015, output: 0),
        ModelPrice("hs-embed-1", input: 0.005, output: 0),
    ]

    /// Motif le plus long contenu dans le nom du modèle.
    public func price(for model: String?) -> ModelPrice? {
        guard let m = model?.lowercased(), !m.isEmpty else { return nil }
        return prices.filter { !$0.pattern.isEmpty && m.contains($0.pattern.lowercased()) }.max { $0.pattern.count < $1.pattern.count }
    }

    /// Prix à l'usage, en dollars, de `tokens` sur `model` (jetons de réflexion facturés comme la sortie).
    public func apiCost(model: String?, tokens: TokenCount) -> Double? {
        guard let p = price(for: model) else { return nil }
        let cached = min(tokens.cached, tokens.input)
        let uncached = tokens.input - cached
        let dollars =
            Double(uncached) * p.input + Double(cached) * (p.cachedInput ?? p.input) + Double(tokens.output + tokens.thoughts) * p.output
        return dollars / 1_000_000
    }

    public func billing(provider: String?, model: String?, tokens: TokenCount) -> Billing {
        let prov = provider?.lowercased() ?? ""
        if subscriptionProviders.contains(prov) { return .subscription(provider: prov, apiEquivalent: apiCost(model: model, tokens: tokens)) }
        if localProviders.contains(prov) { return .local }
        if let d = apiCost(model: model, tokens: tokens) { return .metered(d) }
        return .unknown
    }

    // MARK: Persistance (réglages de l'app, JSON)

    @MainActor
    public static func load(from settings: SettingsStore) -> PriceBook {
        guard let raw = settings.string(forKey: SettingsKey.priceBook),
            var book = try? JSONDecoder().decode(PriceBook.self, from: Data(raw.utf8))
        else { return .defaults }
        // Fournisseur d'abonnement apparu après l'enregistrement de la grille (serveur 1.1.0).
        if !book.subscriptionProviders.contains("chatgpt"), !book.localProviders.contains("chatgpt") { book.subscriptionProviders.append("chatgpt") }
        // Modèles Hindsight Inference apparus après l'enregistrement de la grille (serveur 1.2.0).
        for p in inferencePrices where !book.prices.contains(where: { $0.pattern == p.pattern }) { book.prices.append(p) }
        return book
    }

    @MainActor
    public func save(to settings: SettingsStore) {
        if self == .defaults {
            settings.set(nil, forKey: SettingsKey.priceBook)
        } else if let data = try? JSONEncoder().encode(self) {
            settings.set(String(decoding: data, as: UTF8.self), forKey: SettingsKey.priceBook)
        }
    }
}

extension Billing {
    /// « 0,42 $ », « abonnement (≈ 0,42 $ à l'usage) », « local », « tarif inconnu ».
    public var label: String {
        switch self {
        case .metered(let d): return Format.dollars(d)
        case .subscription(let p, let eq):
            return "inclus dans l'abonnement \(p)" + (eq.map { " (≈ \(Format.dollars($0)) à l'usage)" } ?? "")
        case .local: return "local (gratuit)"
        case .unknown: return "tarif inconnu"
        }
    }
}

extension Format {
    /// Montant en dollars avec une précision adaptée aux petites sommes.
    public static func dollars(_ d: Double) -> String {
        if d == 0 { return "0 $" }
        if d < 0.01 { return "< 0,01 $" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = d < 10 ? 2 : 0
        return (f.string(from: NSNumber(value: d)) ?? String(format: "%.2f", d)) + " $"
    }

    /// « 12,3 k » / « 1,2 M » jetons.
    public static func tokens(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        if n >= 1_000_000 { return (f.string(from: NSNumber(value: Double(n) / 1_000_000)) ?? "") + " M" }
        if n >= 1_000 { return (f.string(from: NSNumber(value: Double(n) / 1_000)) ?? "") + " k" }
        return "\(n)"
    }
}
