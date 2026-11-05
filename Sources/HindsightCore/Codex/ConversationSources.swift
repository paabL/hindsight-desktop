import Foundation

/// Outil dont proviennent les conversations collectées dans le dossier commun.
public enum ConversationSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex
    case claudeCode = "claude-code"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    /// Rôle de l'assistant dans le texte de conversation.
    public var assistantName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude"
        }
    }

    /// Préfixe des identifiants de documents (`codex-<session>-task-NNN`, `claude-code-…`).
    public var documentPrefix: String { rawValue }
    /// Valeur du tag `source:` et de la métadonnée `source`.
    public var tagValue: String { rawValue }
}
