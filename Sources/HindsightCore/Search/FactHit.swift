import Foundation
import HindsightAPI

/// Un fait, quelle que soit sa provenance (recall, liste, reflect, détail) — forme unique pour l'affichage.
public struct FactHit: Identifiable, Sendable, Hashable {
    public let id: String
    public let text: String
    public let type: String?
    public let context: String?
    public let mentionedAt: String?
    public let occurredStart: String?
    public let occurredEnd: String?
    public let documentID: String?
    public let chunkID: String?
    public let tags: [String]
    public let entities: [String]
    public let score: Double?
    public let sourceFactIDs: [String]
    public let attachments: [ChunkAttachment]
    public let state: String?

    public init(
        id: String, text: String, type: String? = nil, context: String? = nil, mentionedAt: String? = nil,
        occurredStart: String? = nil, occurredEnd: String? = nil, documentID: String? = nil, chunkID: String? = nil,
        tags: [String] = [], entities: [String] = [], score: Double? = nil, sourceFactIDs: [String] = [],
        attachments: [ChunkAttachment] = [], state: String? = nil
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.context = context.flatMap { $0.isEmpty ? nil : $0 }
        self.mentionedAt = mentionedAt.flatMap { $0.isEmpty ? nil : $0 }
        self.occurredStart = occurredStart.flatMap { $0.isEmpty ? nil : $0 }
        self.occurredEnd = occurredEnd.flatMap { $0.isEmpty ? nil : $0 }
        self.documentID = documentID
        self.chunkID = chunkID
        self.tags = tags
        self.entities = entities
        self.score = score
        self.sourceFactIDs = sourceFactIDs
        self.attachments = attachments
        self.state = state
    }

    public init(_ r: RecallResult) {
        self.init(
            id: r.id, text: r.text, type: r.type, context: r.context, mentionedAt: r.mentionedAt,
            occurredStart: r.occurredStart, occurredEnd: r.occurredEnd, documentID: r.documentId, chunkID: r.chunkId,
            tags: r.tags ?? [], entities: r.entities ?? [], score: r.scores?.final, sourceFactIDs: r.sourceFactIds ?? [],
            attachments: r.attachments ?? [])
    }

    public init(_ u: MemoryUnitListItem) {
        self.init(
            id: u.id, text: u.text, type: u.factType, context: u.context, mentionedAt: u.mentionedAt ?? (u.date.isEmpty ? nil : u.date),
            occurredStart: u.occurredStart, occurredEnd: u.occurredEnd, documentID: u.documentId, chunkID: u.chunkId,
            tags: u.tags, entities: Self.splitEntities(u.entities), sourceFactIDs: u.sourceMemoryIds, state: u.state)
    }

    public init(_ f: ReflectFact) {
        self.init(
            id: f.id ?? UUID().uuidString, text: f.text, type: f.type, context: f.context, mentionedAt: f.mentionedAt,
            occurredStart: f.occurredStart, occurredEnd: f.occurredEnd, documentID: f.documentId, chunkID: f.chunkId,
            tags: f.tags ?? [], attachments: f.attachments ?? [])
    }

    public init(_ d: MemoryDetail, fallbackID: String) {
        self.init(
            id: d.id ?? fallbackID, text: d.text ?? "", type: d.factType, context: d.context, mentionedAt: d.mentionedAt,
            occurredStart: d.occurredStart, occurredEnd: d.occurredEnd, documentID: d.documentID, chunkID: d.chunkID,
            tags: d.tags, entities: d.entities, sourceFactIDs: d.sourceMemoryIDs, attachments: d.attachments, state: d.state)
    }

    /// `entities` des listes est une chaîne (« A, B, C »).
    static func splitEntities(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Date de l'événement : début d'occurrence si connu, sinon date de mention.
    public var eventDate: Date? { HSDate.parse(occurredStart) ?? HSDate.parse(mentionedAt) }

    public func date(for field: TimeAxis) -> Date? {
        switch field {
        case .event: return eventDate
        case .mentioned: return HSDate.parse(mentionedAt)
        case .occurred: return HSDate.parse(occurredStart)
        }
    }

    /// Numéro de tâche tiré du tag `task:NNN` ou de l'identifiant de document `…-task-NNN`.
    public var taskTag: String? { tags.first { $0.hasPrefix("task:") } }

    public var isObservation: Bool { type == "observation" }
}

/// Axe temporel d'un fait.
public enum TimeAxis: String, CaseIterable, Sendable, Identifiable {
    /// `occurred_start`, sinon `mentioned_at`.
    case event
    case mentioned
    case occurred

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .event: return "Date de l'événement"
        case .mentioned: return "Date de mention"
        case .occurred: return "Début d'occurrence"
        }
    }

    /// Champ serveur utilisé pour filtrer/ordonner (`time_field`).
    public var serverField: String {
        switch self {
        case .event, .occurred: return "occurred_start"
        case .mentioned: return "mentioned_at"
        }
    }
}
