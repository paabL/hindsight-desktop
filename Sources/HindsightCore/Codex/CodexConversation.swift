import Foundation
import HindsightAPI

/// En-tête d'une session (Codex `session_meta`, ou équivalent pour Claude Code).
public struct CodexSessionMeta: Sendable, Hashable, Codable {
    public var id: String
    /// Session racine (différente de `id` pour un sous-agent ou une revue).
    public var rootID: String?
    public var timestamp: Date?
    public var cwd: String?
    public var originator: String?
    public var cliVersion: String?
    /// `user`, `subagent`, `guardian_review`, `chatgpt_handoff`… ; absent sur les versions anciennes.
    public var threadSource: String?
    public var modelProvider: String?
    public var parentThreadID: String?
    public var forkedFromID: String?
    /// Outil d'origine (`nil` = Codex, pour les caches écrits avant l'ajout des autres sources).
    public var sourceKind: ConversationSource?
    /// Titre de la session quand l'outil en donne un.
    public var title: String?

    public var source: ConversationSource { sourceKind ?? .codex }

    /// Session vraisemblablement tapée par l'utilisateur (filtre par défaut du catalogue).
    public var isUserConversation: Bool {
        guard let t = threadSource else { return true }
        return ["user", "chatgpt_handoff", "voice_chat", "realtime_voice"].contains(t)
    }

    public var projectName: String? { cwd.map { ($0 as NSString).lastPathComponent } }
}

/// Bloc d'un message : texte ou image (base64, jamais de chemin local).
public enum CodexBlock: Sendable, Hashable {
    case text(String)
    case image(mediaType: String, base64: String, name: String?)
}

/// Élément de conversation retenu pour l'import (les doublons `item_completed`, le contenu chiffré et
/// les instructions injectées par Codex sont écartés à la lecture).
public enum CodexEvent: Sendable, Hashable {
    case user(ordinal: Int, date: Date?, blocks: [CodexBlock])
    case assistant(ordinal: Int, date: Date?, text: String, phase: String?)
    case toolCall(ordinal: Int, date: Date?, name: String, input: String, callID: String?)
    case toolOutput(ordinal: Int, date: Date?, callID: String?, output: String)
    case reasoning(ordinal: Int, date: Date?, summary: String)
    case webSearch(ordinal: Int, date: Date?, query: String)
    case turnStarted(ordinal: Int, date: Date?, turnID: String?, trigger: String?)
    case turnEnded(ordinal: Int, date: Date?, turnID: String?, aborted: Bool)

    public var date: Date? {
        switch self {
        case .user(_, let d, _), .assistant(_, let d, _, _), .toolCall(_, let d, _, _, _), .toolOutput(_, let d, _, _),
            .reasoning(_, let d, _), .webSearch(_, let d, _), .turnStarted(_, let d, _, _), .turnEnded(_, let d, _, _):
            return d
        }
    }

    public var ordinal: Int {
        switch self {
        case .user(let o, _, _), .assistant(let o, _, _, _), .toolCall(let o, _, _, _, _), .toolOutput(let o, _, _, _),
            .reasoning(let o, _, _), .webSearch(let o, _, _), .turnStarted(let o, _, _, _), .turnEnded(let o, _, _, _):
            return o
        }
    }
}

/// Conversation lue depuis un fichier, avec ce qui a été écarté (pour l'afficher honnêtement).
public struct CodexConversation: Sendable {
    public var meta: CodexSessionMeta
    public var events: [CodexEvent] = []
    /// Lignes ignorées par type (`event_msg/token_count`, `world_state`…).
    public var skipped: [String: Int] = [:]
    /// Messages ou blocs écartés car injectés par Codex (instructions, contexte d'environnement).
    public var injectedBlocks = 0
    /// Lignes illisibles (JSON invalide, ligne partielle d'une session en cours d'écriture).
    public var invalidLines = 0
    public var warnings: [String] = []

    public var userMessageCount: Int { events.filter { if case .user = $0 { return true } else { return false } }.count }
    public var imageCount: Int {
        events.reduce(0) { n, e in
            guard case .user(_, _, let blocks) = e else { return n }
            return n + blocks.filter { if case .image = $0 { return true } else { return false } }.count
        }
    }
}

/// Résumé d'une session pour la liste (lu sur les premières lignes seulement).
public struct CodexSessionSummary: Identifiable, Sendable, Hashable, Codable {
    public var id: String { file.key }
    public let file: CodexFile
    public var meta: CodexSessionMeta?
    /// Premier message réellement tapé (tronqué).
    public var firstUserText: String?
    public var isLegacyFlat = false
    public var error: String?

    public var sortDate: Date { meta?.timestamp ?? file.modified }

    /// Outil d'origine, sans relire le fichier : les métadonnées, sinon l'emplacement.
    public var source: ConversationSource {
        if let s = meta?.sourceKind { return s }
        return file.path.contains("/.claude/") ? .claudeCode : .codex
    }
}
