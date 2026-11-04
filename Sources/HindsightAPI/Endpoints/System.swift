import Foundation

// MARK: - Serveur, banques, configuration

extension HindsightClient {
    /// `GET /health` — le corps n'est pas typé par le contrat ; seule la réussite compte.
    public func health() async throws -> JSONValue {
        try await send(APIRequest("GET", ["health"]))
    }

    /// Mode de secours local : le serveur annonce que seules les lectures sont disponibles.
    public func isConsultationOnly() async throws -> Bool {
        let (_, response) = try await perform(APIRequest("GET", ["health"]))
        return response.value(forHTTPHeaderField: "X-Hindsight-Mode") == "consultation"
    }

    /// `GET /version` — version de l'API et drapeaux de fonctionnalités.
    public func version() async throws -> VersionResponse {
        try await send(APIRequest("GET", ["version"]))
    }

    public func liveness() async throws -> LivenessResponse {
        try await send(APIRequest("GET", ["health", "live"]))
    }

    /// `GET /v1/default/banks`
    public func listBanks(q: String? = nil, limit: Int = 100, offset: Int = 0) async throws -> BankListResponse {
        try await send(
            APIRequest("GET", ["v1", "default", "banks"], query: Q.str("q", q) +++ Q.int("limit", limit) +++ Q.int("offset", offset)))
    }

    /// `GET …/stats`
    public func bankStats(_ bank: String, refresh: Bool = false) async throws -> BankStatsResponse {
        try await send(APIRequest("GET", Self.bank(bank, "stats"), query: refresh ? Q.bool("refresh", true) : []))
    }

    /// `GET …/stats/memories-timeseries` (`period` : 1d, 7d, 30d… ; `timeField` : created_at, mentioned_at, occurred_start)
    public func memoriesTimeseries(_ bank: String, period: String = "7d", timeField: String? = nil) async throws
        -> MemoriesTimeseriesResponse
    {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "stats", "memories-timeseries"),
                query: Q.str("period", period) +++ Q.str("time_field", timeField)))
    }

    /// `POST …/health/llm` — teste la connectivité LLM par rôle (peut consommer une requête LLM minimale).
    public func llmHealth(_ bank: String) async throws -> BankLlmHealthResponse {
        try await send(APIRequest("POST", Self.bank(bank, "health", "llm"), timeout: 120))
    }

    // MARK: Configuration de la banque (comportement uniquement, pas les modèles LLM)

    public func bankConfig(_ bank: String) async throws -> BankConfigResponse {
        try await send(APIRequest("GET", Self.bank(bank, "config")))
    }

    /// `PATCH …/config` — n'accepte que les réglages de comportement ; le serveur répond 4xx pour le reste.
    public func updateBankConfig(_ bank: String, updates: [String: JSONValue]) async throws -> BankConfigResponse {
        try await send(
            try APIRequest.json("PATCH", Self.bank(bank, "config"), body: BankConfigUpdate(updates: updates)))
    }

    /// `DELETE …/config` — supprime tous les overrides de la banque (retour aux valeurs globales).
    public func resetBankConfig(_ bank: String) async throws -> BankConfigResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "config")))
    }

    // MARK: Banque : création / suppression / alias

    public func createOrUpdateBank(_ bank: String, request: CreateBankRequest) async throws -> BankProfileResponse {
        try await send(try APIRequest.json("PUT", Self.bank(bank), body: request))
    }

    public func updateBank(_ bank: String, request: CreateBankRequest) async throws -> BankProfileResponse {
        try await send(try APIRequest.json("PATCH", Self.bank(bank), body: request))
    }

    /// `DELETE /v1/default/banks/{bank_id}` — destructif : l'appelant doit avoir obtenu une confirmation explicite.
    public func deleteBank(_ bank: String) async throws -> DeleteResponse {
        try await send(APIRequest("DELETE", Self.bank(bank)))
    }

    public func bankAliases(_ bank: String) async throws -> BankAliasesResponse {
        try await send(APIRequest("GET", Self.bank(bank, "aliases")))
    }

    /// `POST …/aliases` : un autre identifiant pour la même banque (rien n'est copié). `primary` : l'afficher
    /// à la place de l'identifiant. 409 si le nom est déjà une banque ou un alias.
    public func createBankAlias(_ bank: String, alias: String, primary: Bool) async throws -> BankAliasesResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "aliases"), body: CreateBankAliasRequest(alias: alias, primary: primary)))
    }

    /// `PATCH …/aliases/{alias}` : afficher (ou non) la banque sous cet alias. Purement cosmétique.
    public func setBankAliasPrimary(_ bank: String, alias: String, primary: Bool) async throws -> BankAliasesResponse {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "aliases", alias), body: SetBankAliasPrimaryRequest(primary: primary)))
    }

    /// `DELETE …/aliases/{alias}` : l'alias ne mène plus à la banque (ses données ne bougent pas).
    public func deleteBankAlias(_ bank: String, alias: String) async throws -> BankAliasesResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "aliases", alias)))
    }

    /// `GET …/tags`
    public func listTags(_ bank: String, q: String? = nil, source: String? = nil, limit: Int = 100, offset: Int = 0)
        async throws -> ListTagsResponse
    {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "tags"),
                query: Q.str("q", q) +++ Q.str("source", source) +++ Q.int("limit", limit) +++ Q.int("offset", offset)))
    }

    // MARK: Directives

    public func listDirectives(_ bank: String, limit: Int = 100, offset: Int = 0) async throws -> DirectiveListResponse {
        try await send(
            APIRequest("GET", Self.bank(bank, "directives"), query: Q.int("limit", limit) +++ Q.int("offset", offset)))
    }

    public func directive(_ bank: String, id: String) async throws -> DirectiveResponse {
        try await send(APIRequest("GET", Self.bank(bank, "directives", id)))
    }

    public func createDirective(_ bank: String, _ request: CreateDirectiveRequest) async throws -> DirectiveResponse {
        try await send(try APIRequest.json("POST", Self.bank(bank, "directives"), body: request))
    }

    public func updateDirective(_ bank: String, id: String, _ request: UpdateDirectiveRequest) async throws
        -> DirectiveResponse
    {
        try await send(try APIRequest.json("PATCH", Self.bank(bank, "directives", id), body: request))
    }

    public func deleteDirective(_ bank: String, id: String) async throws -> JSONValue {
        try await send(APIRequest("DELETE", Self.bank(bank, "directives", id)))
    }
}
