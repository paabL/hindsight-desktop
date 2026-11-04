import Foundation

// MARK: - Opérations asynchrones, consolidation

extension HindsightClient {
    /// `GET …/operations` (`status` : pending, processing, completed, failed, cancelled ; `type` : retain, consolidation…)
    public func listOperations(
        _ bank: String, status: String? = nil, type: String? = nil, limit: Int = 50, offset: Int = 0,
        excludeParents: Bool = false
    ) async throws -> OperationsListResponse {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "operations"),
                query: Q.str("status", status) +++ Q.str("type", type) +++ Q.int("limit", min(max(limit, 1), 100))
                    +++ Q.int("offset", offset) +++ (excludeParents ? Q.bool("exclude_parents", true) : [])))
    }

    public func operation(_ bank: String, id: String) async throws -> OperationStatusResponse {
        try await send(APIRequest("GET", Self.bank(bank, "operations", id)))
    }

    /// `POST …/operations/{id}/retry`
    public func retryOperation(_ bank: String, id: String) async throws -> RetryOperationResponse {
        try await send(APIRequest("POST", Self.bank(bank, "operations", id, "retry")))
    }

    /// `DELETE …/operations/{id}` — annule une opération en attente ou en cours.
    public func cancelOperation(_ bank: String, id: String) async throws -> CancelOperationResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "operations", id)))
    }

    /// `DELETE …/operations/{id}/delete` — supprime une opération terminée.
    public func deleteOperation(_ bank: String, id: String) async throws -> DeleteOperationResponse {
        try await send(APIRequest("DELETE", Self.bank(bank, "operations", id, "delete")))
    }

    /// `POST …/consolidate` — lance la consolidation (création/MAJ d'observations). Opération asynchrone.
    public func triggerConsolidation(_ bank: String, scopes: [[String]]? = nil) async throws -> ConsolidationResponse {
        if let scopes {
            return try await send(
                try APIRequest.json("POST", Self.bank(bank, "consolidate"), body: ConsolidationRequest(observationScopes: scopes)))
        }
        return try await send(APIRequest("POST", Self.bank(bank, "consolidate")))
    }

    /// `POST …/consolidation/recover` — remet à zéro les faits marqués « échec définitif » de consolidation.
    public func recoverConsolidation(_ bank: String) async throws -> RecoverConsolidationResponse {
        try await send(APIRequest("POST", Self.bank(bank, "consolidation", "recover")))
    }
}

// MARK: - Audit & traces LLM

extension HindsightClient {
    /// `GET …/audit-logs` — nécessite `audit_log_enabled`; sinon la liste est vide ou le serveur répond 4xx.
    public func auditLogs(
        _ bank: String, action: String? = nil, transport: String? = nil, start: Date? = nil, end: Date? = nil,
        limit: Int = 50, offset: Int = 0
    ) async throws -> AuditLogPage {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "audit-logs"),
                query: Q.str("action", action) +++ Q.str("transport", transport) +++ Q.str("start_date", start.map(HSDate.format))
                    +++ Q.str("end_date", end.map(HSDate.format)) +++ Q.int("limit", min(max(limit, 1), 500))
                    +++ Q.int("offset", offset)))
    }

    /// Une entrée complète, corps compris (serveur 1.1.0 ; absent en 1.0.0, dont la liste les porte déjà).
    public func auditLog(_ bank: String, id: String) async throws -> AuditLogEntry {
        try await send(APIRequest("GET", Self.bank(bank, "audit-logs", id)))
    }

    public func auditLogStats(_ bank: String, action: String? = nil, period: String = "7d") async throws
        -> AuditLogStatsResponse
    {
        try await send(
            APIRequest("GET", Self.bank(bank, "audit-logs", "stats"), query: Q.str("action", action) +++ Q.str("period", period)))
    }

    /// `GET …/llm-requests` — nécessite `HINDSIGHT_API_LLM_TRACE_ENABLED` côté serveur.
    public func llmRequests(
        _ bank: String, status: String? = nil, operation: String? = nil, scope: String? = nil, callType: String? = nil,
        provider: String? = nil, traceID: String? = nil, documentID: String? = nil, memoryID: String? = nil, group: Bool = false,
        start: Date? = nil, end: Date? = nil, limit: Int = 50, offset: Int = 0
    ) async throws -> LLMRequestListResponse {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "llm-requests"),
                query: Q.str("status", status) +++ Q.str("operation", operation) +++ Q.str("scope", scope)
                    +++ Q.str("call_type", callType) +++ Q.str("provider", provider) +++ Q.str("trace_id", traceID) +++ Q.str("document_id", documentID)
                    +++ Q.str("memory_id", memoryID) +++ (group ? Q.bool("group", true) : [])
                    +++ Q.str("start_date", start.map(HSDate.format)) +++ Q.str("end_date", end.map(HSDate.format))
                    +++ Q.int("limit", min(max(limit, 1), 500)) +++ Q.int("offset", offset)))
    }

    /// `splitBy` (`model` ou `operation`, serveur 1.2.0) remplit `series` dans chaque tranche.
    public func llmRequestStats(
        _ bank: String, operation: String? = nil, period: String = "7d", callType: String? = nil, splitBy: String? = nil
    ) async throws -> LLMRequestStatsResponse {
        try await send(
            APIRequest(
                "GET", Self.bank(bank, "llm-requests", "stats"),
                query: Q.str("operation", operation) +++ Q.str("period", period) +++ Q.str("call_type", callType)
                    +++ Q.str("split_by", splitBy)))
    }
}
