import Foundation

/// Demande de confirmation explicite avant une écriture.
///
/// Règle de l'app : aucune écriture destructive ou coûteuse (suppression, relance LLM, remise à zéro…) n'est
/// exécutée directement par un ViewModel. Il publie une `ConfirmationRequest` ; l'interface l'affiche et
/// n'appelle `perform()` qu'après validation par l'utilisateur. Si `requiredText` est défini (opérations
/// irréversibles à grande échelle), l'utilisateur doit le retaper à l'identique.
@MainActor
public struct ConfirmationRequest: Identifiable {
    public enum Severity: Sendable { case normal, destructive }

    public let id = UUID()
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let severity: Severity
    /// Texte à retaper pour activer le bouton de confirmation (ex. l'identifiant de la banque).
    public let requiredText: String?
    private let action: @MainActor () async -> Void

    public init(
        title: String, message: String, confirmTitle: String, severity: Severity = .destructive,
        requiredText: String? = nil, action: @escaping @MainActor () async -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.severity = severity
        self.requiredText = requiredText
        self.action = action
    }

    /// Vrai si `typed` satisfait l'exigence de saisie (toujours vrai sans `requiredText`).
    public func isSatisfied(by typed: String) -> Bool {
        guard let requiredText else { return true }
        return typed == requiredText
    }

    /// À n'appeler qu'après confirmation de l'utilisateur.
    public func perform() async {
        await action()
    }
}
