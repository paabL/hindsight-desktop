import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Octets d'une pièce jointe (image, PDF…) avec son type MIME déclaré par le serveur.
public struct AttachmentData: Sendable {
    public let data: Data
    public let mimeType: String?
}

// MARK: - Documents, chunks, pièces jointes

extension HindsightClient {
    /// `GET …/documents`
    public func listDocuments(
        _ bank: String, q: String? = nil, tags: TagFilter = TagFilter(), window: TimeWindow = TimeWindow(),
        limit: Int = 100, offset: Int = 0
    ) async throws -> ListDocumentsResponse {
        var query = Q.str("q", q) +++ Q.list("tags", tags.isEmpty ? nil : tags.tags)
        if !tags.isEmpty { query += Q.str("tags_match", tags.match.rawValue) }
        // Pour les documents, seuls created_at / updated_at sont acceptés.
        query += window.queryItems +++ Q.int("limit", limit) +++ Q.int("offset", offset)
        return try await send(APIRequest("GET", Self.bank(bank, "documents"), query: query))
    }

    /// `GET …/documents/{id}` — inclut `original_text` et les pièces jointes.
    public func document(_ bank: String, id: String) async throws -> DocumentResponse {
        try await send(APIRequest("GET", Self.bank(bank, "documents", id), timeout: 120))
    }

    /// `GET …/documents/{id}/history` : ce qui a changé le document et ses faits (serveur 1.1.0).
    public func documentHistory(_ bank: String, id: String, limit: Int = 100, offset: Int = 0) async throws -> DocumentHistoryResponse {
        try await send(APIRequest("GET", Self.bank(bank, "documents", id, "history"), query: Q.int("limit", limit) +++ Q.int("offset", offset)))
    }

    /// `GET …/documents/{id}/chunks`
    public func documentChunks(_ bank: String, id: String, limit: Int = 1000, offset: Int = 0) async throws
        -> ListChunksResponse
    {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "documents", id, "chunks"), query: Q.int("limit", limit) +++ Q.int("offset", offset),
                timeout: 120))
    }

    /// `GET /v1/default/chunks/{chunk_id}`
    public func chunk(id: String) async throws -> ChunkResponse {
        try await send(APIRequest("GET", ["v1", "default", "chunks", id]))
    }

    /// `PATCH …/documents/{id}` — REMPLACE l'ensemble des tags (ce n'est pas une fusion).
    public func updateDocumentTags(_ bank: String, id: String, tags: [String]) async throws -> UpdateDocumentResponse {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "documents", id), body: UpdateDocumentRequest(tags: tags)))
    }

    /// `PATCH …/documents/{id}` avec `observation_scopes` (serveur 1.1.0) : change la portée sans réextraire.
    public func updateDocumentScopes(_ bank: String, id: String, scopes: JSONValue) async throws -> UpdateDocumentResponse {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "documents", id), body: UpdateDocumentRequest(observationScopes: scopes)))
    }

    /// `POST …/documents/{id}/reprocess` — supprime les faits du document puis les réextrait (consomme du LLM).
    public func reprocessDocument(_ bank: String, id: String) async throws -> ReprocessDocumentResponse {
        try await send(APIRequest("POST", Self.bank(bank, "documents", id, "reprocess")))
    }

    /// `DELETE …/documents/{id}` — destructif (supprime aussi les faits du document).
    public func deleteDocument(_ bank: String, id: String) async throws -> DeleteDocumentResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "documents", id)))
    }

    /// Télécharge une pièce jointe à partir de `ChunkAttachment.url` (chemin d'API relatif ou URL complète).
    public func attachment(url: String) async throws -> AttachmentData {
        guard let resolved = resolve(url) else { throw HindsightError.invalidURL(url) }
        var req = APIRequest("GET", [])
        req.absoluteURL = resolved
        req.timeout = 120
        let (data, http) = try await perform(req, accept: "*/*")
        return AttachmentData(data: data, mimeType: http.value(forHTTPHeaderField: "Content-Type"))
    }

    /// `GET …/attachments/{id}` à partir d'un identifiant seul.
    public func attachment(_ bank: String, id: String) async throws -> AttachmentData {
        let (data, http) = try await perform(
            APIRequest("GET", Self.bank(bank, "attachments", id), timeout: 120), accept: "*/*")
        return AttachmentData(data: data, mimeType: http.value(forHTTPHeaderField: "Content-Type"))
    }
}
