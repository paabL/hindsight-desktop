import Foundation

/// Un fichier à envoyer tel quel au serveur.
public struct UploadFile: Sendable, Hashable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// Réglages d'un fichier de `POST …/files/retain` (une entrée par fichier, dans le même ordre).
/// Le serveur n'accepte pas `observation_scopes` ici, contrairement à `retain`.
public struct FileRetainMetadata: Codable, Sendable, Hashable {
    public var documentId: String?
    public var context: String?
    public var metadata: [String: String]?
    public var tags: [String]?
    public var timestamp: String?
    public var strategy: String?

    public init(
        documentId: String? = nil, context: String? = nil, metadata: [String: String]? = nil, tags: [String]? = nil,
        timestamp: String? = nil, strategy: String? = nil
    ) {
        self.documentId = documentId
        self.context = context
        self.metadata = metadata
        self.tags = tags
        self.timestamp = timestamp
        self.strategy = strategy
    }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case context, metadata, tags, timestamp, strategy
    }
}

// MARK: - Fichiers

extension HindsightClient {
    /// `POST …/files/retain` (multipart, toujours asynchrone) : chaque fichier est converti en texte côté
    /// serveur, puis devient un document. 10 fichiers et 100 Mo au plus par requête (réglages serveur par défaut).
    public func retainFiles(_ bank: String, files: [UploadFile], metadata: [FileRetainMetadata]) async throws -> FileRetainResponse {
        struct Request: Encodable {
            let filesMetadata: [FileRetainMetadata]
            enum CodingKeys: String, CodingKey { case filesMetadata = "files_metadata" }
        }
        let request = String(decoding: try JSONEncoder().encode(Request(filesMetadata: metadata)), as: UTF8.self)
        let mp = Multipart.form(fields: [("request", request)], files: files.map { ("files", $0) })
        return try await send(
            APIRequest("POST", Self.bank(bank, "files", "retain"), body: .multipart(boundary: mp.boundary, data: mp.body), timeout: 600))
    }
}
