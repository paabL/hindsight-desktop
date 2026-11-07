import Foundation
import HindsightAPI

/// Portée d'observation d'un document, choisie à l'envoi (`observation_scopes` du retain) et modifiable ensuite par
/// `PATCH` avec un serveur 1.1.0 : elle décide dans quel
/// compartiment d'observations ses faits peuvent se fondre. Le serveur consolide les lots d'un même compartiment
/// l'un après l'autre ; le parallélisme de la consolidation n'agit qu'entre compartiments différents.
public enum ObservationScope {
    public static let help =
        "Portée des observations : elle décide avec quelles observations les faits du document peuvent se fondre. Choisie à l'envoi ; modifiable ensuite avec un serveur 1.1.0. Une même portée est consolidée lot après lot."

    /// `consolidation_state` d'un fait (serveur 1.1.0), en clair.
    public static func consolidationTitle(_ state: String) -> String {
        switch state {
        case "pending": return "en attente"
        case "consolidated", "done": return "consolidé"
        case "failed": return "en échec"
        case "skipped": return "ignoré"
        default: return state
        }
    }

    /// Libellé court (« partagée », « par étiquette », « étiquettes : a + b ») ; nil si le serveur n'en dit rien.
    public static func label(_ scopes: JSONValue?, retainParams: [String: JSONValue]? = nil) -> String? {
        switch scopes ?? retainParams?["observation_scopes"] {
        case .string(let s)?:
            switch s {
            case "combined": return "combinée"
            case "shared": return "partagée"
            case "per_tag": return "par étiquette"
            case "all_combinations": return "toutes les combinaisons"
            default: return s
            }
        case .array(let sets)?:
            let names = sets.compactMap { set -> String? in
                guard case .array(let tags) = set else { return nil }
                let t = tags.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                return t.isEmpty ? nil : t.joined(separator: " + ")
            }
            return names.isEmpty ? nil : "étiquettes : " + names.joined(separator: ", ")
        default:
            return nil
        }
    }
}
