import Foundation
import HindsightAPI

/// Entité choisie comme filtre.
public struct EntityRef: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Filtres communs à la recherche, à la frise et au graphe : type, tags, tâche, entité, période.
public struct FactFilter: Sendable, Hashable {
    public static let allTypes = ["world", "experience", "observation"]

    /// Types retenus ; vide = tous.
    public var types: Set<String> = []
    public var tags: [String] = []
    public var tagsMatch: TagsMatch = .allStrict
    /// Numéro de tâche (« 012 ») : traduit en tag `task:012`.
    public var task: String?
    public var entity: EntityRef?
    public var start: Date?
    public var end: Date?

    public init() {}

    public var isEmpty: Bool {
        types.isEmpty && tags.isEmpty && task == nil && entity == nil && start == nil && end == nil
    }

    /// Tags effectivement envoyés au serveur (tags choisis + tag de tâche).
    public var effectiveTags: [String] {
        var t = tags
        if let task, !task.isEmpty {
            let tag = task.hasPrefix("task:") ? task : "task:\(task)"
            if !t.contains(tag) { t.append(tag) }
        }
        return t
    }

    /// Un seul type pour `memories/list` (le serveur n'en accepte qu'un) ; `nil` si 0 ou plusieurs.
    var singleType: String? { types.count == 1 ? types.first : nil }

    /// Faut-il filtrer localement par type (plusieurs types choisis, mais pas tous) ?
    var needsLocalTypeFilter: Bool { types.count > 1 && types.count < Self.allTypes.count }

    public func memoryListQuery(q: String? = nil, axis: TimeAxis = .event, limit: Int, offset: Int) -> MemoryListQuery {
        let window = (start != nil || end != nil) ? TimeWindow(field: axis.serverField, start: start, end: end) : TimeWindow()
        return MemoryListQuery(
            type: singleType, q: q?.isEmpty == true ? nil : q, entityID: entity?.id,
            tags: TagFilter(tags: effectiveTags, match: tagsMatch), window: window, limit: limit, offset: offset)
    }

    public func recallRequest(
        query: String, budget: String, maxTokens: Int = 4096, includeChunks: Bool = true, rerank: RerankOptions? = nil
    ) -> RecallRequest {
        let tags = effectiveTags
        var window: TemporalWindow?
        if start != nil || end != nil {
            window = TemporalWindow(
                start: HSDate.format(start ?? Date(timeIntervalSince1970: 0)), end: HSDate.format(end ?? Date()))
        }
        return RecallRequest(
            query: query, types: types.isEmpty ? nil : types.sorted(), rerank: rerank, budget: budget, maxTokens: maxTokens,
            include: includeChunks ? IncludeOptions(chunks: ChunkIncludeOptions(maxTokens: 2000)) : nil,
            tags: tags.isEmpty ? nil : tags, tagsMatch: tags.isEmpty ? "any" : tagsMatch.rawValue, temporalWindow: window)
    }

    public func reflectRequest(query: String, budget: String) -> ReflectRequest {
        let tags = effectiveTags
        return ReflectRequest(
            query: query, budget: budget, include: ReflectIncludeOptions(facts: FactsIncludeOptions()),
            tags: tags.isEmpty ? nil : tags, tagsMatch: tags.isEmpty ? "any" : tagsMatch.rawValue,
            factTypes: types.isEmpty ? nil : types.sorted())
    }

    /// Filtres que le serveur ne sait pas appliquer à recall (entité, période stricte, types multiples en liste).
    public func matchesLocally(_ hit: FactHit, axis: TimeAxis = .event) -> Bool {
        if !types.isEmpty, let t = hit.type, !types.contains(t) { return false }
        if let entity, !hit.entities.contains(where: { $0.caseInsensitiveCompare(entity.name) == .orderedSame }) {
            return false
        }
        if start != nil || end != nil {
            guard let d = hit.date(for: axis) else { return false }
            if let start, d < start { return false }
            if let end, d >= end { return false }
        }
        return true
    }
}
