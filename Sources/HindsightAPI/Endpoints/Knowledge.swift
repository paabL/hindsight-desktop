import Foundation

// MARK: - Modèles mentaux & pages de connaissance

extension HindsightClient {
    public func listMentalModels(_ bank: String, tags: TagFilter = TagFilter(), limit: Int = 100, offset: Int = 0) async throws
        -> MentalModelListResponse
    {
        var query = Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { query += Q.str("tags_match", tags.match.rawValue) }
        query += Q.int("limit", limit) +++ Q.int("offset", offset)
        return try await send(APIRequest("GET", Self.bank(bank, "mental-models"), query: query))
    }

    public func mentalModel(_ bank: String, id: String) async throws -> MentalModelResponse {
        try await send(APIRequest("GET", Self.bank(bank, "mental-models", id)))
    }

    public func createMentalModel(_ bank: String, _ request: CreateMentalModelRequest) async throws -> CreateMentalModelResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "mental-models"), body: request))
    }

    public func updateMentalModel(_ bank: String, id: String, _ request: UpdateMentalModelRequest) async throws
        -> MentalModelResponse
    {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "mental-models", id), body: request))
    }

    /// `POST …/mental-models/{id}/refresh` — appelle le LLM ; opération asynchrone.
    public func refreshMentalModel(_ bank: String, id: String) async throws -> AsyncOperationSubmitResponse {
        try await send(APIRequest("POST", Self.bank(bank, "mental-models", id, "refresh")))
    }

    /// `DELETE …/mental-models/{id}` — destructif.
    public func deleteMentalModel(_ bank: String, id: String) async throws -> JSONValue {
        try await send(APIRequest("DELETE", Self.bank(bank, "mental-models", id)))
    }

    public func mentalModelHistory(_ bank: String, id: String) async throws -> JSONValue {
        try await send(APIRequest("GET", Self.bank(bank, "mental-models", id, "history")))
    }

    // MARK: Base de connaissance

    public func knowledgeTree(_ bank: String) async throws -> KnowledgeTreeResponse {
        try await send(APIRequest("GET", Self.bank(bank, "knowledge-base", "tree")))
    }

    public func knowledgePage(_ bank: String, id: String) async throws -> KnowledgePageResponse {
        try await send(APIRequest("GET", Self.bank(bank, "knowledge-base", "pages", id)))
    }

    public func searchKnowledgeBase(_ bank: String, q: String, limit: Int = 20) async throws -> KnowledgePageSearchResponse {
        try await send(
            APIRequest("GET", Self.bank(bank, "knowledge-base", "search"), query: Q.str("q", q) +++ Q.int("limit", limit)))
    }

    public func deleteKnowledgeNode(_ bank: String, id: String) async throws -> JSONValue {
        try await send(APIRequest("DELETE", Self.bank(bank, "knowledge-base", "nodes", id)))
    }
}
