import Foundation
import HindsightAPI

/// Ce que permet la version de l'API du serveur (`/version`). Les écrans masquent ce qu'un serveur plus ancien
/// n'accepterait pas, au lieu d'échouer à l'usage.
public enum ServerCapabilities {
    /// Le serveur accepte-t-il les réglages par banque (`PATCH`/`DELETE …/config`) ? Vrai par défaut et quand
    /// l'information manque : seul `bank_config_api: false` les refuse.
    public static func bankConfigWritable(_ features: FeaturesInfo?) -> Bool { features?.bankConfigApi != false }

    public static let bankConfigDisabledMessage =
        "Ce serveur n'accepte pas les réglages par banque. Pour les activer, ajoutez HINDSIGHT_API_ENABLE_BANK_CONFIG_API=true au script de lancement, puis redémarrez le serveur."

    /// `api_version` au moins égale à `minimum` (« 1.1.0 ») ; faux si inconnue.
    public static func atLeast(_ version: String?, _ minimum: String) -> Bool {
        guard let version else { return false }
        func parts(_ s: String) -> [Int] {
            s.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(version), b = parts(minimum)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }

    /// Serveur 1.1.0 : historique des documents, portée modifiable, relance immédiate d'une opération différée.
    public static func is110(_ version: String?) -> Bool { atLeast(version, "1.1.0") }

    /// Serveur 1.2.0 : options prune/dedup de recall, fournisseur `hindsight` (Hindsight Inference).
    public static func is120(_ version: String?) -> Bool { atLeast(version, "1.2.0") }
}
