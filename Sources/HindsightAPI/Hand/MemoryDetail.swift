import Foundation

/// Lecture tolérante de `GET …/memories/{id}` (le contrat n'en type pas la réponse).
/// Les champs absents restent `nil` ; `raw` conserve la réponse complète pour affichage « JSON brut ».
public struct MemoryDetail: Sendable, Hashable {
    public let raw: JSONValue

    public init(raw: JSONValue) { self.raw = raw }

    private func str(_ keys: String...) -> String? {
        for k in keys { if let v = raw[k]?.stringValue, !v.isEmpty { return v } }
        return nil
    }

    public var id: String? { str("id") }
    public var text: String? { str("text") }
    public var context: String? { str("context") }
    public var factType: String? { str("fact_type", "type") }
    public var documentID: String? { str("document_id") }
    public var chunkID: String? { str("chunk_id") }
    public var mentionedAt: String? { str("mentioned_at", "date") }
    public var occurredStart: String? { str("occurred_start") }
    public var occurredEnd: String? { str("occurred_end") }
    public var state: String? { str("state") }
    /// Où en est la consolidation du fait (serveur 1.1.0 ; absent en 1.0.0).
    public var consolidationState: String? { str("consolidation_state") }
    public var tags: [String] { raw["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [] }
    public var sourceMemoryIDs: [String] { raw["source_memory_ids"]?.arrayValue?.compactMap(\.stringValue) ?? [] }

    /// Entités : liste de chaînes, liste d'objets `{name|canonical_name|text}` ou chaîne séparée par des virgules.
    public var entities: [String] {
        guard let e = raw["entities"] else { return [] }
        if let arr = e.arrayValue {
            return arr.compactMap { item in
                item.stringValue ?? item["name"]?.stringValue ?? item["canonical_name"]?.stringValue
                    ?? item["text"]?.stringValue
            }
        }
        if let s = e.stringValue {
            return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }

    public var attachments: [ChunkAttachment] {
        guard let arr = raw["attachments"]?.arrayValue else { return [] }
        return arr.compactMap { v in
            guard let data = try? JSONEncoder().encode(v) else { return nil }
            return try? JSONDecoder().decode(ChunkAttachment.self, from: data)
        }
    }
}
