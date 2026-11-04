import Foundation

/// Erreurs du client Hindsight. Les messages sont destinés à l'affichage direct à l'utilisateur.
public enum HindsightError: Error, Sendable, CustomStringConvertible {
    /// L'URL n'a pas pu être construite (URL de base ou chemin invalide).
    case invalidURL(String)
    /// Le serveur est injoignable (connexion refusée, timeout, hors ligne…).
    case unreachable(String)
    /// Réponse HTTP hors 2xx. `detail` est le champ `detail` FastAPI quand il existe.
    case http(status: Int, detail: String?, path: String)
    /// Le corps reçu ne correspond pas au modèle attendu.
    case decoding(path: String, message: String, snippet: String)
    /// Réponse non HTTP.
    case invalidResponse
    /// Opération refusée localement (garde-fou).
    case refused(String)

    public var description: String {
        switch self {
        case .invalidURL(let s):
            return "URL invalide : \(s)"
        case .unreachable(let s):
            return "Serveur injoignable : \(s)"
        case .http(let status, let detail, let path):
            let d = detail.map { " — \($0)" } ?? ""
            return "HTTP \(status) sur \(path)\(d)"
        case .decoding(let path, let message, _):
            return "Réponse inattendue pour \(path) : \(message)"
        case .invalidResponse:
            return "Réponse non HTTP"
        case .refused(let s):
            return s
        }
    }

    public var httpStatus: Int? {
        if case .http(let s, _, _) = self { return s }
        return nil
    }

    public var isNotFound: Bool { httpStatus == 404 }
}

extension HindsightError: LocalizedError {
    public var errorDescription: String? { description }
}

extension Error {
    /// Message lisible pour l'utilisateur, quel que soit le type d'erreur.
    public var userMessage: String {
        if let e = self as? HindsightError { return e.description }
        if self is CancellationError { return "Annulé" }
        if let e = self as? LocalizedError, let d = e.errorDescription { return d }
        // `self is NSError` est toujours vrai sous macOS (pont automatique) : on teste le type réel.
        if let e = self as? CustomStringConvertible, !(type(of: self) is NSError.Type) { return e.description }
        return (self as NSError).localizedDescription
    }
}
