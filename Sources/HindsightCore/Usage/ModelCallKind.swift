import Foundation
import HindsightAPI

/// Genre d'un appel tracé par `/llm-requests`, déduit de son `scope` comme le fait le serveur 1.1.0 :
/// `embedding_*`, `rerank`, `decision_*` ; tout le reste est un appel LLM génératif. Seuls ces derniers
/// comptent dans les quotas, les plafonds, la pause automatique et les estimations de coût. Le serveur 1.0.0
/// ne trace que des appels LLM.
public enum ModelCallKind: String, Sendable, Hashable, CaseIterable {
    case llm, embedding, rerank, decision

    /// Valeur du filtre `call_type` des traces (ignoré par un serveur 1.0.0).
    public static let generativeFilter = ModelCallKind.llm.rawValue

    public init(scope: String?) {
        let s = scope ?? ""
        if s.hasPrefix("embedding_") { self = .embedding }
        else if s == "rerank" { self = .rerank }
        else if s.hasPrefix("decision_") { self = .decision }
        else { self = .llm }
    }
}

extension LLMRequestEntry {
    public var callKind: ModelCallKind { ModelCallKind(scope: scope) }
    /// Appel LLM qui écrit du texte (et consomme du quota ou des dollars).
    public var isGenerative: Bool { callKind == .llm }
}
