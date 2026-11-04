import Foundation
import HindsightAPI

/// Découpage d'une conversation en documents à retenir.
public enum CodexSplitMode: String, CaseIterable, Sendable, Identifiable {
    /// Une tâche = un message tapé par l'utilisateur et tout ce qui suit jusqu'au suivant
    /// (convention de la banque existante : `codex-<session>-task-NNN`).
    case perUserMessage
    /// Un seul document par conversation (`codex-<session>`).
    case perConversation

    public var id: String { rawValue }
    public var title: String { self == .perUserMessage ? "Un document par tâche" : "Un document par conversation" }
}

public struct CodexImportOptions: Sendable, Hashable {
    public var mode: CodexSplitMode = .perUserMessage
    public var includeToolCalls = true
    /// Longueur maximale conservée d'une entrée ou sortie d'outil (au-delà : tronquée, avec mention).
    public var toolTextLimit = 2000
    /// Résumés de raisonnement (rarement présents, le raisonnement complet est chiffré).
    public var includeReasoning = false
    public var includeImages = true
    /// Le répertoire de travail apparaît dans le texte et les métadonnées (chemin personnel).
    public var includeWorkingDirectory = true

    public init() {}
}

/// Un document prêt à retenir.
public struct CodexTask: Identifiable, Sendable, Hashable {
    public var id: String { documentID }
    public let number: Int
    public let documentID: String
    public let date: Date?
    public let title: String
    public let content: HSContent
    public let textLength: Int
    public let imageCount: Int
    public let imageBytes: Int
    public let userMessages: Int

    /// Jetons approximatifs envoyés au LLM d'extraction (≈ 4 caractères par jeton, hors images).
    public var approxTokens: Int { textLength / 4 }
}

public enum CodexTranscript {
    public static func taskNumber(_ n: Int) -> String { String(format: "%03d", n) }

    public static func documentID(sessionID: String, task: Int?, source: ConversationSource = .codex) -> String {
        let p = source.documentPrefix
        return task.map { "\(p)-\(sessionID)-task-\(taskNumber($0))" } ?? "\(p)-\(sessionID)"
    }

    /// Regroupe les évènements en tâches selon le mode, puis rend chaque tâche en contenu multimodal.
    public static func tasks(_ conv: CodexConversation, options: CodexImportOptions = CodexImportOptions()) -> [CodexTask] {
        let groups: [[CodexEvent]]
        switch options.mode {
        case .perConversation:
            groups = conv.events.isEmpty ? [] : [conv.events]
        case .perUserMessage:
            var g: [[CodexEvent]] = []
            var current: [CodexEvent] = []
            var sawUser = false
            for e in conv.events {
                if case .user = e {
                    if sawUser {
                        g.append(current)
                        current = []
                    }
                    sawUser = true
                }
                current.append(e)
            }
            if !current.isEmpty { g.append(current) }
            groups = g
        }
        return groups.enumerated().compactMap { i, events in
            render(events, meta: conv.meta, number: options.mode == .perUserMessage ? i + 1 : nil, options: options)
        }
    }

    static func stamp(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return " · " + f.string(from: d)
    }

    static func clip(_ s: String, _ limit: Int) -> String {
        guard s.count > limit else { return s }
        return String(s.prefix(limit)) + "\n… [\(s.count - limit) caractères tronqués]"
    }

    static func render(_ events: [CodexEvent], meta: CodexSessionMeta, number: Int?, options: CodexImportOptions) -> CodexTask? {
        guard events.contains(where: {
            switch $0 {
            case .user, .assistant: return true
            default: return false
            }
        }) else { return nil }
        var blocks: [ContentBlock] = []
        var text = ""
        var textLength = 0
        var images = 0
        var imageBytes = 0
        var users = 0
        var title: String?
        var date: Date?

        func flush() {
            guard !text.isEmpty else { return }
            blocks.append(.text(TextContentBlock(type: "text", text: text)))
            textLength += text.count
            text = ""
        }

        let label = number.map { "tâche \(taskNumber($0))" } ?? "conversation"
        text += "# Session \(meta.source.title) \(meta.id) — \(label)\n"
        if let t = meta.title { text += "Titre : \(t)\n" }
        if options.includeWorkingDirectory, let cwd = meta.cwd { text += "Répertoire : \(cwd)\n" }
        if let o = meta.originator { text += "Application : \(o)\(meta.cliVersion.map { " \($0)" } ?? "")\n" }

        for e in events {
            switch e {
            case .user(_, let d, let bs):
                users += 1
                if date == nil { date = d }
                text += "\n## Utilisateur\(stamp(d))\n"
                for b in bs {
                    switch b {
                    case .text(let t):
                        if title == nil { title = String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)) }
                        text += t + "\n"
                    case .image(let mime, let data, let name):
                        if options.includeImages {
                            text += "[Image\(name.map { " \($0)" } ?? "")]\n"
                            flush()
                            blocks.append(.image(ImageContentBlock(type: "image", source: Base64AttachmentSource(mediaType: mime, data: data))))
                            images += 1
                            imageBytes += data.count * 3 / 4
                        } else {
                            text += "[Image\(name.map { " \($0)" } ?? "") non importée]\n"
                        }
                    }
                }
            case .assistant(_, let d, let t, let phase):
                if date == nil { date = d }
                text += "\n## \(meta.source.assistantName)\(phase == "commentary" ? " (en cours)" : "")\(stamp(d))\n\(t)\n"
            case .toolCall(_, _, let name, let input, _):
                guard options.includeToolCalls else { continue }
                text += "\n### Outil « \(name) »\n```\n\(clip(input, options.toolTextLimit))\n```\n"
            case .toolOutput(_, _, _, let output):
                guard options.includeToolCalls, !output.isEmpty else { continue }
                text += "Résultat :\n```\n\(clip(output, options.toolTextLimit))\n```\n"
            case .reasoning(_, _, let s):
                guard options.includeReasoning else { continue }
                text += "\n_Raisonnement (résumé)_ : \(s)\n"
            case .webSearch(_, _, let q):
                guard options.includeToolCalls else { continue }
                text += "\n### Recherche web : \(q)\n"
            case .turnStarted(_, let d, _, _):
                if date == nil { date = d }
            case .turnEnded(_, _, _, let aborted):
                if aborted { text += "\n_(tour interrompu)_\n" }
            }
        }
        flush()
        let content: HSContent
        if blocks.count == 1, case .text(let only) = blocks[0] { content = .text(only.text) } else { content = .blocks(blocks) }
        return CodexTask(
            number: number ?? 1, documentID: documentID(sessionID: meta.id, task: number, source: meta.source), date: date ?? meta.timestamp,
            title: title ?? "(sans message utilisateur)", content: content, textLength: textLength, imageCount: images,
            imageBytes: imageBytes, userMessages: users)
    }

    /// Item de rétention pour une tâche.
    public static func memoryItem(_ task: CodexTask, meta: CodexSessionMeta, options: CodexImportOptions, updateMode: String = "replace")
        -> MemoryItem
    {
        var metadata = ["source": meta.source.tagValue, "session_id": meta.id]
        if options.mode == .perUserMessage { metadata["task"] = taskNumber(task.number) }
        if let o = meta.originator { metadata["originator"] = o }
        if let v = meta.cliVersion { metadata["cli_version"] = v }
        if options.includeWorkingDirectory, let c = meta.cwd { metadata["cwd"] = c }
        var tags = ["source:\(meta.source.tagValue)", "session:\(meta.id)"]
        if options.mode == .perUserMessage { tags.append("task:\(taskNumber(task.number))") }
        if let p = meta.projectName { tags.append("repo:\(p)") }
        let context =
            "Conversation \(meta.source.title)\(meta.projectName.map { " (projet \($0))" } ?? "")"
            + (options.mode == .perUserMessage ? ", tâche \(taskNumber(task.number))" : "")
        // Périmètre "shared" : les tags filtrent les recherches sans découper les observations. Par défaut,
        // le serveur ferait un périmètre par jeu de tags, donc un silo par tâche.
        return MemoryItem(
            content: task.content, timestamp: task.date.map { .string(HSDate.format($0)) }, context: context, metadata: metadata,
            documentId: task.documentID, tags: tags, observationScopes: .string("shared"), updateMode: updateMode)
    }
}
