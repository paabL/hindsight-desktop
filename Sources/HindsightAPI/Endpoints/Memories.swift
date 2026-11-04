import Foundation

/// Paramètres de `GET …/memories/list`.
public struct MemoryListQuery: Sendable, Hashable {
    public var type: String?
    public var q: String?
    public var consolidationState: String?
    public var state: String?
    public var documentID: String?
    public var entityID: String?
    public var tags: TagFilter
    public var window: TimeWindow
    public var limit: Int
    public var offset: Int

    public init(
        type: String? = nil, q: String? = nil, consolidationState: String? = nil, state: String? = nil,
        documentID: String? = nil, entityID: String? = nil, tags: TagFilter = TagFilter(),
        window: TimeWindow = TimeWindow(), limit: Int = 100, offset: Int = 0
    ) {
        self.type = type
        self.q = q
        self.consolidationState = consolidationState
        self.state = state
        self.documentID = documentID
        self.entityID = entityID
        self.tags = tags
        self.window = window
        self.limit = limit
        self.offset = offset
    }

    var queryItems: [(String, String?)] {
        var items = Q.str("type", type) +++ Q.str("q", q) +++ Q.str("consolidation_state", consolidationState)
            +++ Q.str("state", state) +++ Q.str("document_id", documentID) +++ Q.str("entity_id", entityID)
        items += Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { items += Q.str("tags_match", tags.match.rawValue) }
        items += window.queryItems +++ Q.int("limit", limit) +++ Q.int("offset", offset)
        return items
    }
}

// MARK: - Faits, recall, reflect, graphes

extension HindsightClient {
    /// `GET …/memories/list`
    public func listMemories(_ bank: String, _ query: MemoryListQuery = MemoryListQuery()) async throws
        -> ListMemoryUnitsResponse
    {
        try await send(APIRequest("GET", Self.bank(bank, "memories", "list"), query: query.queryItems, timeout: 120))
    }

    /// `GET …/memories/{id}` — la réponse n'est pas typée par le contrat : lecture tolérante.
    public func memory(_ bank: String, id: String) async throws -> MemoryDetail {
        let raw: JSONValue = try await send(APIRequest("GET", Self.bank(bank, "memories", id)))
        return MemoryDetail(raw: raw)
    }

    /// `GET …/memories/{id}/history` — historique d'une observation (faits sources résolus).
    public func observationHistory(_ bank: String, id: String) async throws -> JSONValue {
        try await send(APIRequest("GET", Self.bank(bank, "memories", id, "history")))
    }

    /// `PATCH …/memories/{id}` — corrige le texte et/ou invalide/rétablit un fait (world/experience seulement).
    public func updateMemory(_ bank: String, id: String, _ request: UpdateMemoryRequest) async throws -> JSONValue {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "memories", id), body: request))
    }

    /// `DELETE …/memories/{id}/observations` — efface les observations dérivées d'un fait.
    public func clearMemoryObservations(_ bank: String, id: String) async throws -> ClearMemoryObservationsResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "memories", id, "observations")))
    }

    /// `DELETE …/memories` — DESTRUCTIF et irréversible. `type` restreint à world/experience/observation.
    public func deleteAllMemories(_ bank: String, type: String? = nil) async throws -> DeleteResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "memories"), query: Q.str("type", type)))
    }

    /// `DELETE …/observations` — DESTRUCTIF : efface toutes les observations (réinitialise la consolidation).
    public func clearObservations(_ bank: String) async throws -> DeleteResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "observations")))
    }

    /// `POST …/memories/recall`
    public func recall(_ bank: String, _ request: RecallRequest) async throws -> RecallResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "memories", "recall"), body: request, timeout: 300))
    }

    /// `POST …/reflect` — appelle le LLM de la banque ; peut être long.
    public func reflect(_ bank: String, _ request: ReflectRequest) async throws -> ReflectResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "reflect"), body: request, timeout: 600))
    }

    /// `POST …/memories` — retient du contenu (extraction LLM). `async=true` pour ne pas bloquer.
    public func retain(_ bank: String, _ request: RetainRequest) async throws -> RetainResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "memories"), body: request, timeout: 600))
    }

    /// `POST …/memories/dry-run-extract` — aperçu des faits extraits, sans rien enregistrer (appelle le LLM).
    public func dryRunExtract(_ bank: String, _ request: DryRunExtractRequest) async throws -> DryRunExtractionResult {
        try await send(try APIRequest.json("POST", Self.bank(bank, "memories", "dry-run-extract"), body: request, timeout: 600))
    }

    /// `GET …/graph` — graphe des faits (limité par `limit`).
    public func graph(
        _ bank: String, type: String? = nil, limit: Int = 1000, q: String? = nil, tags: TagFilter = TagFilter(),
        documentID: String? = nil, chunkID: String? = nil
    ) async throws -> GraphDataResponse {
        var query = Q.str("type", type) +++ Q.int("limit", limit) +++ Q.str("q", q) +++ Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { query += Q.str("tags_match", tags.match.rawValue) }
        query += Q.str("document_id", documentID) +++ Q.str("chunk_id", chunkID)
        return try await send(APIRequest("GET", Self.bank(bank, "graph"), query: query, timeout: 120))
    }

    /// `GET …/entities`
    public func listEntities(_ bank: String, limit: Int = 100, offset: Int = 0, tags: TagFilter = TagFilter()) async throws
        -> EntityListResponse
    {
        var query = Q.int("limit", limit) +++ Q.int("offset", offset) +++ Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { query += Q.str("tags_match", tags.match.rawValue) }
        return try await send(APIRequest("GET", Self.bank(bank, "entities"), query: query))
    }

    public func entity(_ bank: String, id: String) async throws -> EntityDetailResponse {
        try await send(APIRequest("GET", Self.bank(bank, "entities", id)))
    }

    /// `GET …/entities/graph`
    public func entityGraph(_ bank: String, limit: Int = 500, minCount: Int = 1, tags: TagFilter = TagFilter()) async throws
        -> EntityGraphResponse
    {
        var query = Q.int("limit", limit) +++ Q.int("min_count", minCount) +++ Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { query += Q.str("tags_match", tags.match.rawValue) }
        return try await send(APIRequest("GET", Self.bank(bank, "entities", "graph"), query: query, timeout: 120))
    }

    /// `GET …/observations/scopes`
    public func observationScopes(_ bank: String, limit: Int = 100, offset: Int = 0) async throws
        -> ObservationScopesResponse
    {
        try await send(
            APIRequest("GET", Self.bank(bank, "observations", "scopes"), query: Q.int("limit", limit) +++ Q.int("offset", offset)))
    }
}
