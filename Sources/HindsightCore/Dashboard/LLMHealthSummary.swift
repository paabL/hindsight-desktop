import Foundation
import HindsightAPI

/// Résultat du test des modèles dit avec les mots de la page Modèles (« Extraction des faits », « Réponses »),
/// jamais avec les identifiants du serveur (`retain`, `auth_failed`).
public enum LLMHealthSummary {
    /// Titre du rôle tel que la page Modèles l'affiche.
    public static func roleTitle(_ operation: String) -> String {
        ServerSettingsCatalog.roles.first { $0.id == operation }?.title ?? operation
    }

    /// État d'un rôle en quelques mots.
    public static func statusLabel(_ status: String) -> String {
        switch status {
        case "connected": return "répond"
        case "not_configured": return "aucun fournisseur configuré"
        case "auth_failed": return "clé refusée"
        case "unreachable": return "injoignable"
        default: return status
        }
    }

    /// « Extraction des faits (injoignable), Réponses (clé refusée) » ; nil quand tous les rôles répondent.
    public static func failures(_ health: BankLlmHealthResponse) -> String? {
        let bad = health.operations.filter { !$0.ok }
        guard !bad.isEmpty else { return nil }
        return bad.map { "\(roleTitle($0.operation)) (\(statusLabel($0.status)))" }.joined(separator: ", ")
    }

    /// Bilan en une phrase, affiché après le test.
    public static func sentence(_ health: BankLlmHealthResponse) -> String {
        guard !health.operations.isEmpty else { return "Le serveur n'a renvoyé aucun résultat pour le test des modèles." }
        if let failures = failures(health) {
            let count = health.operations.filter { !$0.ok }.count
            return "\(count == 1 ? "Rôle LLM en échec" : "Rôles LLM en échec") : \(failures)."
        }
        return health.operations.count == 1 ? "Le rôle LLM testé répond." : "Les \(health.operations.count) rôles LLM testés répondent."
    }
}
