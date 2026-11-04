import Foundation
import HindsightAPI

/// Appels qui n'écrivent pas de texte (décision, rerank, embeddings), par genre et par modèle, lus dans les
/// statistiques de traces ventilées par modèle (serveur 1.2.0). Ils restent hors des quotas, plafonds et
/// estimations LLM : les noms publics Hindsight Inference sont valorisés au tarif hébergé de la grille.
public struct ModelServiceUsage: Identifiable, Sendable, Hashable, Codable {
    public var id: String { "\(kind)|\(model)" }
    public var kind: String
    public var model: String
    public var calls: Int
    public var tokens: Int
    /// Équivalent au tarif hébergé Hindsight Inference ; pas une facture : `series` ne donne ni
    /// fournisseur ni URL, et un hs-decide-1-flash local porte aussi ce nom.
    /// `nil` = modèle sans tarif d'inférence reconnu.
    public var dollars: Double?

    public init(kind: String, model: String, calls: Int, tokens: Int, dollars: Double?) {
        self.kind = kind
        self.model = model
        self.calls = calls
        self.tokens = tokens
        self.dollars = dollars
    }

    /// Genres d'appel lus, dans l'ordre d'affichage.
    public static let kinds: [ModelCallKind] = [.decision, .rerank, .embedding]

    /// Nom public d'un modèle Inference (les dépôts locaux ne sont pas valorisés).
    public static func hasInferencePrice(_ model: String) -> Bool {
        PriceBook.inferencePrices.contains { $0.pattern == model.lowercased() }
    }

    /// Somme des tranches d'une ou plusieurs banques ; une réponse sans `series` (serveur 1.1.0) ne compte pas.
    public static func rows(_ stats: [(kind: ModelCallKind, response: LLMRequestStatsResponse)], prices: PriceBook) -> [ModelServiceUsage] {
        var acc: [String: ModelServiceUsage] = [:]
        for (kind, response) in stats {
            for bucket in response.buckets {
                for (model, sums) in bucket.series ?? [:] {
                    let key = "\(kind.rawValue)|\(model)"
                    var row = acc[key] ?? ModelServiceUsage(kind: kind.rawValue, model: model, calls: 0, tokens: 0, dollars: nil)
                    row.calls += sums.calls
                    row.tokens += sums.tokens
                    acc[key] = row
                }
            }
        }
        return acc.values.map { row in
            var r = row
            // Ces modèles ne génèrent rien : tout est facturé comme de l'entrée.
            if hasInferencePrice(r.model) { r.dollars = prices.apiCost(model: r.model, tokens: TokenCount(input: r.tokens)) }
            return r
        }
        .sorted { a, b in
            let ka = kinds.firstIndex { $0.rawValue == a.kind } ?? kinds.count
            let kb = kinds.firstIndex { $0.rawValue == b.kind } ?? kinds.count
            if ka != kb { return ka < kb }
            return a.tokens != b.tokens ? a.tokens > b.tokens : a.model < b.model
        }
    }
}
