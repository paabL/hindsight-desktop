import Foundation

/// Corps `multipart/form-data` minimal (un seul fichier).
enum Multipart {
    static func singleFile(field: String, filename: String, mimeType: String, data: Data) -> (boundary: String, body: Data) {
        let boundary = "hindsight-" + UUID().uuidString
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        add("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)--\r\n")
        return (boundary, body)
    }

    /// Corps `multipart/form-data` avec des champs texte puis des fichiers (même nom de champ répété).
    static func form(fields: [(name: String, value: String)], files: [(field: String, file: UploadFile)]) -> (boundary: String, body: Data) {
        let boundary = "hindsight-" + UUID().uuidString
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        for (field, f) in files {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(f.filename)\"\r\n")
            add("Content-Type: \(f.mimeType)\r\n\r\n")
            body.append(f.data)
            add("\r\n")
        }
        add("--\(boundary)--\r\n")
        return (boundary, body)
    }
}

// MARK: - Export / clone / import

extension HindsightClient {
    /// `POST …/transfer/export` — archive ZIP asynchrone ; suivre l'opération puis télécharger `download_url`.
    public func exportBank(
        _ bank: String, includeData: Bool = true, includeBankConfig: Bool = true, includeHistory: Bool = false,
        documentIDs: [String]? = nil
    ) async throws -> BankTransferSubmitResponse {
        try await send(
            APIRequest(
                "POST", Self.bank(bank, "transfer", "export"),
                query: Q.bool("include_data", includeData) +++ Q.bool("include_bank_config", includeBankConfig)
                    +++ Q.bool("include_history", includeHistory) +++ Q.list("document_id", documentIDs)))
    }

    /// `POST …/document-transfer/export` — export des documents (et optionnellement observations / base de connaissance).
    public func exportDocuments(
        _ bank: String, documentIDs: [String]? = nil, includeObservations: Bool = false, includeKnowledgeBase: Bool = false
    ) async throws -> DocumentExportSubmitResponse {
        try await send(
            APIRequest(
                "POST", Self.bank(bank, "document-transfer", "export"),
                query: Q.list("document_id", documentIDs) +++ Q.bool("include_observations", includeObservations)
                    +++ Q.bool("include_knowledge_base", includeKnowledgeBase)))
    }

    /// `POST …/clone` — copie la banque dans une nouvelle (sans LLM). `targetBankID` ne doit pas exister.
    public func cloneBank(
        _ bank: String, targetBankID: String, includeData: Bool = true, includeBankConfig: Bool = true,
        includeHistory: Bool = false
    ) async throws -> BankTransferSubmitResponse {
        try await send(
            APIRequest(
                "POST", Self.bank(bank, "clone"),
                query: Q.str("target_bank_id", targetBankID) +++ Q.bool("include_data", includeData)
                    +++ Q.bool("include_bank_config", includeBankConfig) +++ Q.bool("include_history", includeHistory)))
    }

    /// `POST …/transfer/import` (multipart). `mode` = restore (nouvelle banque) | merge.
    public func importBankArchive(
        _ bank: String, archive: Data, filename: String, mode: String = "restore", targetBankID: String? = nil,
        documentConflict: String = "skip"
    ) async throws -> BankTransferSubmitResponse {
        let mp = Multipart.singleFile(field: "file", filename: filename, mimeType: "application/zip", data: archive)
        return try await send(
            APIRequest(
                "POST", Self.bank(bank, "transfer", "import"),
                query: Q.str("mode", mode) +++ Q.str("target_bank_id", targetBankID)
                    +++ (mode == "merge" ? Q.str("document_conflict", documentConflict) : []),
                body: .multipart(boundary: mp.boundary, data: mp.body), timeout: 600))
    }

    /// `POST …/document-transfer` (multipart) — import d'une archive de documents.
    public func importDocumentsArchive(_ bank: String, archive: Data, filename: String, onConflict: String = "skip")
        async throws -> DocumentImportSubmitResponse
    {
        let mp = Multipart.singleFile(field: "file", filename: filename, mimeType: "application/zip", data: archive)
        return try await send(
            APIRequest(
                "POST", Self.bank(bank, "document-transfer"), query: Q.str("on_conflict", onConflict),
                body: .multipart(boundary: mp.boundary, data: mp.body), timeout: 600))
    }

    /// `GET …/export` — modèle de banque (config + modèles mentaux + directives), rejouable via `importTemplate`.
    public func exportTemplate(_ bank: String) async throws -> BankTemplateManifest {
        try await send(APIRequest("GET", Self.bank(bank, "export")))
    }

    /// `POST …/import` — applique un modèle de banque ; `dryRun` valide sans rien modifier.
    public func importTemplate(_ bank: String, manifest: BankTemplateManifest, dryRun: Bool = false) async throws
        -> BankTemplateImportResponse
    {
        try await send(
            try APIRequest.json("POST", Self.bank(bank, "import"), query: dryRun ? Q.bool("dry_run", true) : [], body: manifest))
    }

    /// `GET /v1/default/files/download/{key}` — télécharge l'archive produite par un export.
    /// Préférer `downloadFile(url:)` avec le `download_url` de `result_metadata` : une clé contenant `/`
    /// n'est pas routable telle quelle.
    public func downloadFile(key: String) async throws -> Data {
        let (data, _) = try await perform(
            APIRequest("GET", ["v1", "default", "files", "download", key], timeout: 3600), accept: "*/*")
        return data
    }

    public func downloadFile(url: String) async throws -> Data {
        guard let resolved = resolve(url) else { throw HindsightError.invalidURL(url) }
        // La requête porte l'en-tête d'autorisation : seul le serveur configuré peut le recevoir.
        guard resolved.scheme == baseURL.scheme, resolved.host == baseURL.host, resolved.port == baseURL.port else {
            throw HindsightError.refused("Le serveur renvoie une adresse de téléchargement hors de \(baseURL.absoluteString) : \(url)")
        }
        var req = APIRequest("GET", [])
        req.absoluteURL = resolved
        req.timeout = 3600
        let (data, _) = try await perform(req, accept: "*/*")
        return data
    }
}
