// Généré par scripts/generate_models.py depuis docs/openapi.json (version API 1.2.0).
// NE PAS ÉDITER À LA MAIN : relancer le script.
import Foundation

/// Request model for adding/merging background information. Deprecated: use SetMissionRequest instead.
public struct AddBackgroundRequest: Codable, Sendable, Hashable {
    /// New background information to add or merge
    public var content: String
    /// Deprecated - disposition is no longer auto-inferred from mission
    public var updateDisposition: Bool

    public init(content: String, updateDisposition: Bool = true) {
        self.content = content
        self.updateDisposition = updateDisposition
    }

    enum CodingKeys: String, CodingKey {
        case content
        case updateDisposition = "update_disposition"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(String.self, forKey: .content)
        self.updateDisposition = try c.decodeIfPresent(Bool.self, forKey: .updateDisposition) ?? true
    }
}

/// Response model for submitting an async operation.
public struct AsyncOperationSubmitResponse: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String

    public init(operationId: String, status: String) {
        self.operationId = operationId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
    }
}

/// A single audit log entry with its full request/response bodies.
public struct AuditLogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var action: String
    public var transport: String
    public var bankId: String?
    public var startedAt: String?
    public var endedAt: String?
    /// Server-computed duration in milliseconds (started_at → ended_at). Null if not yet completed.
    public var durationMs: Int?
    public var metadata: [String: JSONValue]
    public var request: [String: JSONValue]?
    public var response: [String: JSONValue]?

    public init(id: String, action: String, transport: String, bankId: String? = nil, startedAt: String? = nil, endedAt: String? = nil, durationMs: Int? = nil, metadata: [String: JSONValue], request: [String: JSONValue]? = nil, response: [String: JSONValue]? = nil) {
        self.id = id
        self.action = action
        self.transport = transport
        self.bankId = bankId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.metadata = metadata
        self.request = request
        self.response = response
    }

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case transport
        case bankId = "bank_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case metadata
        case request
        case response
    }
}

/// Response model for list audit logs endpoint.
public struct AuditLogListResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var total: Int
    public var limit: Int
    public var offset: Int
    /// Entries without request/response bodies; fetch one entry by id for its bodies.
    public var items: [AuditLogSummary]

    public init(bankId: String, total: Int, limit: Int, offset: Int, items: [AuditLogSummary]) {
        self.bankId = bankId
        self.total = total
        self.limit = limit
        self.offset = offset
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case total
        case limit
        case offset
        case items
    }
}

/// A single time bucket in audit log stats.
public struct AuditLogStatsBucket: Codable, Sendable, Hashable {
    public var time: String
    public var actions: [String: Int]
    public var total: Int

    public init(time: String, actions: [String: Int], total: Int) {
        self.time = time
        self.actions = actions
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case time
        case actions
        case total
    }
}

/// Response model for audit log stats endpoint.
public struct AuditLogStatsResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var period: String
    public var trunc: String
    public var start: String
    public var buckets: [AuditLogStatsBucket]

    public init(bankId: String, period: String, trunc: String, start: String, buckets: [AuditLogStatsBucket]) {
        self.bankId = bankId
        self.period = period
        self.trunc = trunc
        self.start = start
        self.buckets = buckets
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case period
        case trunc
        case start
        case buckets
    }
}

/// An audit log entry without its request/response bodies, as the list returns it.
public struct AuditLogSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var action: String
    public var transport: String
    public var bankId: String?
    public var startedAt: String?
    public var endedAt: String?
    /// Server-computed duration in milliseconds (started_at → ended_at). Null if not yet completed.
    public var durationMs: Int?
    public var metadata: [String: JSONValue]

    public init(id: String, action: String, transport: String, bankId: String? = nil, startedAt: String? = nil, endedAt: String? = nil, durationMs: Int? = nil, metadata: [String: JSONValue]) {
        self.id = id
        self.action = action
        self.transport = transport
        self.bankId = bankId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case transport
        case bankId = "bank_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case metadata
    }
}

/// Response model for background update. Deprecated: use MissionResponse instead.
public struct BackgroundResponse: Codable, Sendable, Hashable {
    public var mission: String
    /// Deprecated: same as mission
    public var background: String?
    public var disposition: DispositionTraits?

    public init(mission: String, background: String? = nil, disposition: DispositionTraits? = nil) {
        self.mission = mission
        self.background = background
        self.disposition = disposition
    }

    enum CodingKeys: String, CodingKey {
        case mission
        case background
        case disposition
    }
}

/// One id a bank answers to.
public struct BankAliasEntry: Codable, Sendable, Hashable {
    public var alias: String
    /// Whether this alias is shown in place of the bank's own id. Display only — the bank keeps its id, and everything that names a bank still uses
    public var primary: Bool

    public init(alias: String, primary: Bool = false) {
        self.alias = alias
        self.primary = primary
    }

    enum CodingKeys: String, CodingKey {
        case alias
        case primary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.alias = try c.decode(String.self, forKey: .alias)
        self.primary = try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false
    }
}

/// Response model for a bank's aliases.
public struct BankAliasesResponse: Codable, Sendable, Hashable {
    /// The bank's own id, which an alias never replaces
    public var bankId: String
    /// Extra ids that also reach this bank, the primary one first then oldest first
    public var aliases: [BankAliasEntry]

    public init(bankId: String, aliases: [BankAliasEntry]) {
        self.bankId = bankId
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case aliases
    }
}

/// Response model for bank configuration.
public struct BankConfigResponse: Codable, Sendable, Hashable {
    /// Bank identifier
    public var bankId: String
    /// Fully resolved configuration with all hierarchical overrides applied (Python field names)
    public var config: [String: JSONValue]
    /// Bank-specific configuration overrides only (Python field names)
    public var overrides: [String: JSONValue]

    public init(bankId: String, config: [String: JSONValue], overrides: [String: JSONValue]) {
        self.bankId = bankId
        self.config = config
        self.overrides = overrides
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case config
        case overrides
    }
}

/// Request model for updating bank configuration.
public struct BankConfigUpdate: Codable, Sendable, Hashable {
    /// Configuration overrides. Keys can be in Python field format (retain_extraction_mode) or environment variable format (HINDSIGHT_API_RETAIN_EX
    public var updates: [String: JSONValue]

    public init(updates: [String: JSONValue]) {
        self.updates = updates
    }

    enum CodingKeys: String, CodingKey {
        case updates
    }
}

/// Bank list item with profile summary and stats.
public struct BankListItem: Codable, Sendable, Hashable {
    public var bankId: String
    public var name: String?
    public var disposition: DispositionTraits
    public var mission: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var factCount: Int
    /// When a document was last *ingested* into this bank. Appending to an existing document does not move this — use `last_write_at` for write act
    public var lastDocumentAt: String?
    /// When anything was last written to this bank: a document retained (including appends to an existing document) or a fact stored. Null if the b
    public var lastWriteAt: String?
    /// The alias this bank is presented under, when one was promoted. Display only: `bank_id` remains the bank's identity everywhere else. Null whe
    public var displayAlias: String?
    /// Aliases of this bank that matched the search `q`. Empty when no search was made, or when the bank matched on its own id or name — so a non-e
    public var matchedAliases: [String]?

    public init(bankId: String, name: String? = nil, disposition: DispositionTraits, mission: String? = nil, createdAt: String? = nil, updatedAt: String? = nil, factCount: Int = 0, lastDocumentAt: String? = nil, lastWriteAt: String? = nil, displayAlias: String? = nil, matchedAliases: [String]? = nil) {
        self.bankId = bankId
        self.name = name
        self.disposition = disposition
        self.mission = mission
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.factCount = factCount
        self.lastDocumentAt = lastDocumentAt
        self.lastWriteAt = lastWriteAt
        self.displayAlias = displayAlias
        self.matchedAliases = matchedAliases
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case name
        case disposition
        case mission
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case factCount = "fact_count"
        case lastDocumentAt = "last_document_at"
        case lastWriteAt = "last_write_at"
        case displayAlias = "display_alias"
        case matchedAliases = "matched_aliases"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.disposition = try c.decode(DispositionTraits.self, forKey: .disposition)
        self.mission = try c.decodeIfPresent(String.self, forKey: .mission)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        self.factCount = try c.decodeIfPresent(Int.self, forKey: .factCount) ?? 0
        self.lastDocumentAt = try c.decodeIfPresent(String.self, forKey: .lastDocumentAt)
        self.lastWriteAt = try c.decodeIfPresent(String.self, forKey: .lastWriteAt)
        self.displayAlias = try c.decodeIfPresent(String.self, forKey: .displayAlias)
        self.matchedAliases = try c.decodeIfPresent([String].self, forKey: .matchedAliases)
    }
}

/// Response model for listing banks, one page at a time.
public struct BankListResponse: Codable, Sendable, Hashable {
    public var banks: [BankListItem]
    /// Total number of banks visible to the caller, ignoring `limit`/`offset`.
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(banks: [BankListItem], total: Int, limit: Int, offset: Int) {
        self.banks = banks
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case banks
        case total
        case limit
        case offset
    }
}

/// Per-bank LLM connectivity probe across retain/consolidation/reflect. Operations
public struct BankLlmHealthResponse: Codable, Sendable, Hashable {
    /// Bank identifier
    public var bankId: String
    /// Connectivity status per operation (retain, consolidation, reflect)
    public var operations: [LlmOperationHealth]

    public init(bankId: String, operations: [LlmOperationHealth]) {
        self.bankId = bankId
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case operations
    }
}

/// Response model for bank profile.
public struct BankProfileResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var name: String
    public var disposition: DispositionTraits
    /// The agent's mission - who they are and what they're trying to accomplish
    public var mission: String
    /// Deprecated: use mission instead
    public var background: String?

    public init(bankId: String, name: String, disposition: DispositionTraits, mission: String, background: String? = nil) {
        self.bankId = bankId
        self.name = name
        self.disposition = disposition
        self.mission = mission
        self.background = background
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case name
        case disposition
        case mission
        case background
    }
}

/// Response model for bank statistics endpoint.
public struct BankStatsResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var totalNodes: Int
    public var totalLinks: Int
    public var totalDocuments: Int
    public var nodesByFactType: [String: Int]
    public var linksByLinkType: [String: Int]
    public var linksByFactType: [String: Int]
    public var linksBreakdown: [String: [String: Int]]
    public var pendingOperations: Int
    public var failedOperations: Int
    /// Async operations grouped by status (pending, processing, completed, failed, cancelled).
    public var operationsByStatus: [String: Int]?
    /// When consolidation last ran (ISO format)
    public var lastConsolidatedAt: String?
    /// When a memory was last written in this bank — stored, edited, or consolidated (ISO format). Null if the bank has no memories. A mental model
    public var lastMemoryWriteAt: String?
    /// Number of source memories (world/experience) still queued for consolidation into observations. Excludes memories whose consolidation permane
    public var pendingConsolidation: Int
    /// Number of source memories (world/experience) whose consolidation permanently failed and can be retried via the consolidation recovery endpoi
    public var failedConsolidation: Int
    /// Total number of observations
    public var totalObservations: Int

    public init(bankId: String, totalNodes: Int, totalLinks: Int, totalDocuments: Int, nodesByFactType: [String: Int], linksByLinkType: [String: Int], linksByFactType: [String: Int], linksBreakdown: [String: [String: Int]], pendingOperations: Int, failedOperations: Int, operationsByStatus: [String: Int]? = nil, lastConsolidatedAt: String? = nil, lastMemoryWriteAt: String? = nil, pendingConsolidation: Int = 0, failedConsolidation: Int = 0, totalObservations: Int = 0) {
        self.bankId = bankId
        self.totalNodes = totalNodes
        self.totalLinks = totalLinks
        self.totalDocuments = totalDocuments
        self.nodesByFactType = nodesByFactType
        self.linksByLinkType = linksByLinkType
        self.linksByFactType = linksByFactType
        self.linksBreakdown = linksBreakdown
        self.pendingOperations = pendingOperations
        self.failedOperations = failedOperations
        self.operationsByStatus = operationsByStatus
        self.lastConsolidatedAt = lastConsolidatedAt
        self.lastMemoryWriteAt = lastMemoryWriteAt
        self.pendingConsolidation = pendingConsolidation
        self.failedConsolidation = failedConsolidation
        self.totalObservations = totalObservations
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case totalNodes = "total_nodes"
        case totalLinks = "total_links"
        case totalDocuments = "total_documents"
        case nodesByFactType = "nodes_by_fact_type"
        case linksByLinkType = "links_by_link_type"
        case linksByFactType = "links_by_fact_type"
        case linksBreakdown = "links_breakdown"
        case pendingOperations = "pending_operations"
        case failedOperations = "failed_operations"
        case operationsByStatus = "operations_by_status"
        case lastConsolidatedAt = "last_consolidated_at"
        case lastMemoryWriteAt = "last_memory_write_at"
        case pendingConsolidation = "pending_consolidation"
        case failedConsolidation = "failed_consolidation"
        case totalObservations = "total_observations"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.totalNodes = try c.decode(Int.self, forKey: .totalNodes)
        self.totalLinks = try c.decode(Int.self, forKey: .totalLinks)
        self.totalDocuments = try c.decode(Int.self, forKey: .totalDocuments)
        self.nodesByFactType = try c.decode([String: Int].self, forKey: .nodesByFactType)
        self.linksByLinkType = try c.decode([String: Int].self, forKey: .linksByLinkType)
        self.linksByFactType = try c.decode([String: Int].self, forKey: .linksByFactType)
        self.linksBreakdown = try c.decode([String: [String: Int]].self, forKey: .linksBreakdown)
        self.pendingOperations = try c.decode(Int.self, forKey: .pendingOperations)
        self.failedOperations = try c.decode(Int.self, forKey: .failedOperations)
        self.operationsByStatus = try c.decodeIfPresent([String: Int].self, forKey: .operationsByStatus)
        self.lastConsolidatedAt = try c.decodeIfPresent(String.self, forKey: .lastConsolidatedAt)
        self.lastMemoryWriteAt = try c.decodeIfPresent(String.self, forKey: .lastMemoryWriteAt)
        self.pendingConsolidation = try c.decodeIfPresent(Int.self, forKey: .pendingConsolidation) ?? 0
        self.failedConsolidation = try c.decodeIfPresent(Int.self, forKey: .failedConsolidation) ?? 0
        self.totalObservations = try c.decodeIfPresent(Int.self, forKey: .totalObservations) ?? 0
    }
}

/// Bank configuration fields within a template manifest.
public struct BankTemplateConfig: Codable, Sendable, Hashable {
    /// Mission/context for Reflect operations
    public var reflectMission: String?
    /// Steers what gets extracted during retain
    public var retainMission: String?
    /// Fact extraction mode: 'concise' (default), 'verbose', 'custom', 'verbatim', or 'chunks'
    public var retainExtractionMode: String?
    /// Custom extraction prompt (when mode='custom')
    public var retainCustomInstructions: String?
    /// Target max characters for each content chunk
    public var retainChunkSize: Int?
    /// Max characters for a single JSONL line or conversation turn to keep whole; defaults to retain_chunk_size when unset
    public var retainStructuredChunkSize: Int?
    /// Toggle observation consolidation
    public var enableObservations: Bool?
    /// Controls what gets synthesised
    public var observationsMission: String?
    /// Toggle the keyword (BM25) arm during recall, leaving pure vector search
    public var enableTextSearch: Bool?
    /// Toggle the temporal arm (and its date-aware query analysis) during recall
    public var enableTemporalRetrieval: Bool?
    /// Toggle the entity/link graph arm during recall
    public var enableGraphRetrieval: Bool?
    /// Toggle cross-encoder reranking during recall
    public var enableReranking: Bool?
    /// When the server has a decision model, reflect lets it prune evidence and decide when to stop
    public var reflectUseDecisionModel: Bool?
    /// The same, for knowledge-page refreshes
    public var mentalModelRefreshUseDecisionModel: Bool?
    /// When the server has a decision model, a delta knowledge-page refresh asks it which new memories could change the page instead of running ref
    public var mentalModelDeltaUseDecisionModel: Bool?
    /// Skepticism trait (1-5)
    public var dispositionSkepticism: Int?
    /// Literalism trait (1-5)
    public var dispositionLiteralism: Int?
    /// Empathy trait (1-5)
    public var dispositionEmpathy: Int?
    /// Controlled vocabulary for entity labels
    public var entityLabels: [LabelGroupOutput]?
    /// Allow entities outside the label vocabulary
    public var entitiesAllowFreeForm: Bool?
    /// Name of the default retain strategy (key into retain_strategies map)
    public var retainDefaultStrategy: String?
    /// Map of retain strategy name to per-strategy config dict
    public var retainStrategies: [String: JSONValue]?
    /// Max chunks per streaming batch (0 disables batching)
    public var retainChunkBatchSize: Int?
    /// Hard cap on inline images in a single extraction chunk
    public var retainMaxAttachmentsPerChunk: Int?
    /// MCP tool allowlist for this bank (None = all tools)
    public var mcpEnabledTools: [String]?
    /// LLM batch size for observation consolidation
    public var consolidationLlmBatchSize: Int?
    /// Max tokens of source facts per consolidation batch
    public var consolidationSourceFactsMaxTokens: Int?
    /// Max tokens of source facts per observation
    public var consolidationSourceFactsMaxTokensPerObservation: Int?
    /// Max observations to retain per consolidation scope
    public var maxObservationsPerScope: Int?
    /// DEPRECATED — use consolidation_strategies, which carries the mission too. Still honoured, but consulted only after consolidation_strategies.
    public var observationScopeLimits: [[String: JSONValue]]?
    /// observation_scopes applied at retain to items that send none ('combined' when unset). A list of tag lists may use globs, e.g. [['topic:*']]
    public var defaultObservationScopes: JSONValue?
    /// Per-scope consolidation settings: [{"scopes": [{"tags": ["company:*"]}], "observations_mission": "Record only generalized trends.", "max_obs
    public var consolidationStrategies: [ConsolidationStrategySpec]?
    /// Max tokens of source facts per reflect call
    public var reflectSourceFactsMaxTokens: Int?
    /// Trigger fields merged over the built-in knowledge-page default when a page is created (e.g. {"refresh_cron": "0 * * * *"}). A trigger sent w
    public var knowledgePageDefaultTrigger: [String: JSONValue]?
    /// Default reflect options for this bank (e.g. {"reflect_search_observations_max_tokens": 3000, "reflect_search_observations_include_entities":
    public var reflectDefaultOptions: [String: JSONValue]?
    /// Minimum seconds between two automatic refreshes of the same mental model in this bank. 0 (the default) means no floor. Overridable per model
    public var mentalModelMinRefreshIntervalSeconds: Int?
    /// Per-bank Gemini/VertexAI safety filter settings
    public var llmGeminiSafetySettings: [JSONValue]?
    /// Recall budget mapping function: 'fixed' or 'adaptive'
    public var recallBudgetFunction: String?
    /// Fixed thinking_budget for budget=low (function='fixed')
    public var recallBudgetFixedLow: Int?
    /// Fixed thinking_budget for budget=mid (function='fixed')
    public var recallBudgetFixedMid: Int?
    /// Fixed thinking_budget for budget=high (function='fixed')
    public var recallBudgetFixedHigh: Int?
    /// Ratio of max_tokens for budget=low (function='adaptive')
    public var recallBudgetAdaptiveLow: Double?
    /// Ratio of max_tokens for budget=mid (function='adaptive')
    public var recallBudgetAdaptiveMid: Double?
    /// Ratio of max_tokens for budget=high (function='adaptive')
    public var recallBudgetAdaptiveHigh: Double?
    /// Floor for the adaptive function (after clamping)
    public var recallBudgetMin: Int?
    /// Ceiling for the adaptive function (after clamping)
    public var recallBudgetMax: Int?
    /// Enable audit logging for this bank (overrides the server default)
    public var auditLogEnabled: Bool?
    /// Persist raw source text (documents.original_text / chunks.chunk_text). Set false to keep only derived facts.
    public var storeDocumentText: Bool?
    /// IANA zone (e.g. 'Europe/Rome') a retain timestamp, or a time the LLM extracts, is read in when it carries no UTC offset.
    public var defaultTimezone: String?
    /// Automatically consolidate observations after retain
    public var enableAutoConsolidation: Bool?
    /// When the server has a decision model, consolidation lets it settle restatements and chatter before the LLM call
    public var consolidationUseDecisionModel: Bool?
    /// Max memory units fed into a single consolidation round
    public var consolidationMaxMemoriesPerRound: Int?
    /// Number of consolidation LLM batches processed concurrently
    public var consolidationLlmParallelism: Int?
    /// Include raw chunks in recall results
    public var recallIncludeChunks: Bool?
    /// Default for recall prefer_observations when the request omits it
    public var recallPreferObservations: Bool?
    /// Default for recall prune when the request omits it (decision-model reranker only)
    public var recallDecisionModelPrune: Bool?
    /// Default for recall dedup when the request omits it (decision-model reranker only)
    public var recallDecisionModelDedup: Bool?
    /// Max tokens of results returned by recall
    public var recallMaxTokens: Int?
    /// Max tokens of raw chunks returned by recall (when recall_include_chunks is set)
    public var recallChunksMaxTokens: Int?
    /// Memory Defense policy for this bank (validated against the DefensePolicy schema on write)
    public var memoryDefense: [String: JSONValue]?

    public init(reflectMission: String? = nil, retainMission: String? = nil, retainExtractionMode: String? = nil, retainCustomInstructions: String? = nil, retainChunkSize: Int? = nil, retainStructuredChunkSize: Int? = nil, enableObservations: Bool? = nil, observationsMission: String? = nil, enableTextSearch: Bool? = nil, enableTemporalRetrieval: Bool? = nil, enableGraphRetrieval: Bool? = nil, enableReranking: Bool? = nil, reflectUseDecisionModel: Bool? = nil, mentalModelRefreshUseDecisionModel: Bool? = nil, mentalModelDeltaUseDecisionModel: Bool? = nil, dispositionSkepticism: Int? = nil, dispositionLiteralism: Int? = nil, dispositionEmpathy: Int? = nil, entityLabels: [LabelGroupOutput]? = nil, entitiesAllowFreeForm: Bool? = nil, retainDefaultStrategy: String? = nil, retainStrategies: [String: JSONValue]? = nil, retainChunkBatchSize: Int? = nil, retainMaxAttachmentsPerChunk: Int? = nil, mcpEnabledTools: [String]? = nil, consolidationLlmBatchSize: Int? = nil, consolidationSourceFactsMaxTokens: Int? = nil, consolidationSourceFactsMaxTokensPerObservation: Int? = nil, maxObservationsPerScope: Int? = nil, observationScopeLimits: [[String: JSONValue]]? = nil, defaultObservationScopes: JSONValue? = nil, consolidationStrategies: [ConsolidationStrategySpec]? = nil, reflectSourceFactsMaxTokens: Int? = nil, knowledgePageDefaultTrigger: [String: JSONValue]? = nil, reflectDefaultOptions: [String: JSONValue]? = nil, mentalModelMinRefreshIntervalSeconds: Int? = nil, llmGeminiSafetySettings: [JSONValue]? = nil, recallBudgetFunction: String? = nil, recallBudgetFixedLow: Int? = nil, recallBudgetFixedMid: Int? = nil, recallBudgetFixedHigh: Int? = nil, recallBudgetAdaptiveLow: Double? = nil, recallBudgetAdaptiveMid: Double? = nil, recallBudgetAdaptiveHigh: Double? = nil, recallBudgetMin: Int? = nil, recallBudgetMax: Int? = nil, auditLogEnabled: Bool? = nil, storeDocumentText: Bool? = nil, defaultTimezone: String? = nil, enableAutoConsolidation: Bool? = nil, consolidationUseDecisionModel: Bool? = nil, consolidationMaxMemoriesPerRound: Int? = nil, consolidationLlmParallelism: Int? = nil, recallIncludeChunks: Bool? = nil, recallPreferObservations: Bool? = nil, recallDecisionModelPrune: Bool? = nil, recallDecisionModelDedup: Bool? = nil, recallMaxTokens: Int? = nil, recallChunksMaxTokens: Int? = nil, memoryDefense: [String: JSONValue]? = nil) {
        self.reflectMission = reflectMission
        self.retainMission = retainMission
        self.retainExtractionMode = retainExtractionMode
        self.retainCustomInstructions = retainCustomInstructions
        self.retainChunkSize = retainChunkSize
        self.retainStructuredChunkSize = retainStructuredChunkSize
        self.enableObservations = enableObservations
        self.observationsMission = observationsMission
        self.enableTextSearch = enableTextSearch
        self.enableTemporalRetrieval = enableTemporalRetrieval
        self.enableGraphRetrieval = enableGraphRetrieval
        self.enableReranking = enableReranking
        self.reflectUseDecisionModel = reflectUseDecisionModel
        self.mentalModelRefreshUseDecisionModel = mentalModelRefreshUseDecisionModel
        self.mentalModelDeltaUseDecisionModel = mentalModelDeltaUseDecisionModel
        self.dispositionSkepticism = dispositionSkepticism
        self.dispositionLiteralism = dispositionLiteralism
        self.dispositionEmpathy = dispositionEmpathy
        self.entityLabels = entityLabels
        self.entitiesAllowFreeForm = entitiesAllowFreeForm
        self.retainDefaultStrategy = retainDefaultStrategy
        self.retainStrategies = retainStrategies
        self.retainChunkBatchSize = retainChunkBatchSize
        self.retainMaxAttachmentsPerChunk = retainMaxAttachmentsPerChunk
        self.mcpEnabledTools = mcpEnabledTools
        self.consolidationLlmBatchSize = consolidationLlmBatchSize
        self.consolidationSourceFactsMaxTokens = consolidationSourceFactsMaxTokens
        self.consolidationSourceFactsMaxTokensPerObservation = consolidationSourceFactsMaxTokensPerObservation
        self.maxObservationsPerScope = maxObservationsPerScope
        self.observationScopeLimits = observationScopeLimits
        self.defaultObservationScopes = defaultObservationScopes
        self.consolidationStrategies = consolidationStrategies
        self.reflectSourceFactsMaxTokens = reflectSourceFactsMaxTokens
        self.knowledgePageDefaultTrigger = knowledgePageDefaultTrigger
        self.reflectDefaultOptions = reflectDefaultOptions
        self.mentalModelMinRefreshIntervalSeconds = mentalModelMinRefreshIntervalSeconds
        self.llmGeminiSafetySettings = llmGeminiSafetySettings
        self.recallBudgetFunction = recallBudgetFunction
        self.recallBudgetFixedLow = recallBudgetFixedLow
        self.recallBudgetFixedMid = recallBudgetFixedMid
        self.recallBudgetFixedHigh = recallBudgetFixedHigh
        self.recallBudgetAdaptiveLow = recallBudgetAdaptiveLow
        self.recallBudgetAdaptiveMid = recallBudgetAdaptiveMid
        self.recallBudgetAdaptiveHigh = recallBudgetAdaptiveHigh
        self.recallBudgetMin = recallBudgetMin
        self.recallBudgetMax = recallBudgetMax
        self.auditLogEnabled = auditLogEnabled
        self.storeDocumentText = storeDocumentText
        self.defaultTimezone = defaultTimezone
        self.enableAutoConsolidation = enableAutoConsolidation
        self.consolidationUseDecisionModel = consolidationUseDecisionModel
        self.consolidationMaxMemoriesPerRound = consolidationMaxMemoriesPerRound
        self.consolidationLlmParallelism = consolidationLlmParallelism
        self.recallIncludeChunks = recallIncludeChunks
        self.recallPreferObservations = recallPreferObservations
        self.recallDecisionModelPrune = recallDecisionModelPrune
        self.recallDecisionModelDedup = recallDecisionModelDedup
        self.recallMaxTokens = recallMaxTokens
        self.recallChunksMaxTokens = recallChunksMaxTokens
        self.memoryDefense = memoryDefense
    }

    enum CodingKeys: String, CodingKey {
        case reflectMission = "reflect_mission"
        case retainMission = "retain_mission"
        case retainExtractionMode = "retain_extraction_mode"
        case retainCustomInstructions = "retain_custom_instructions"
        case retainChunkSize = "retain_chunk_size"
        case retainStructuredChunkSize = "retain_structured_chunk_size"
        case enableObservations = "enable_observations"
        case observationsMission = "observations_mission"
        case enableTextSearch = "enable_text_search"
        case enableTemporalRetrieval = "enable_temporal_retrieval"
        case enableGraphRetrieval = "enable_graph_retrieval"
        case enableReranking = "enable_reranking"
        case reflectUseDecisionModel = "reflect_use_decision_model"
        case mentalModelRefreshUseDecisionModel = "mental_model_refresh_use_decision_model"
        case mentalModelDeltaUseDecisionModel = "mental_model_delta_use_decision_model"
        case dispositionSkepticism = "disposition_skepticism"
        case dispositionLiteralism = "disposition_literalism"
        case dispositionEmpathy = "disposition_empathy"
        case entityLabels = "entity_labels"
        case entitiesAllowFreeForm = "entities_allow_free_form"
        case retainDefaultStrategy = "retain_default_strategy"
        case retainStrategies = "retain_strategies"
        case retainChunkBatchSize = "retain_chunk_batch_size"
        case retainMaxAttachmentsPerChunk = "retain_max_attachments_per_chunk"
        case mcpEnabledTools = "mcp_enabled_tools"
        case consolidationLlmBatchSize = "consolidation_llm_batch_size"
        case consolidationSourceFactsMaxTokens = "consolidation_source_facts_max_tokens"
        case consolidationSourceFactsMaxTokensPerObservation = "consolidation_source_facts_max_tokens_per_observation"
        case maxObservationsPerScope = "max_observations_per_scope"
        case observationScopeLimits = "observation_scope_limits"
        case defaultObservationScopes = "default_observation_scopes"
        case consolidationStrategies = "consolidation_strategies"
        case reflectSourceFactsMaxTokens = "reflect_source_facts_max_tokens"
        case knowledgePageDefaultTrigger = "knowledge_page_default_trigger"
        case reflectDefaultOptions = "reflect_default_options"
        case mentalModelMinRefreshIntervalSeconds = "mental_model_min_refresh_interval_seconds"
        case llmGeminiSafetySettings = "llm_gemini_safety_settings"
        case recallBudgetFunction = "recall_budget_function"
        case recallBudgetFixedLow = "recall_budget_fixed_low"
        case recallBudgetFixedMid = "recall_budget_fixed_mid"
        case recallBudgetFixedHigh = "recall_budget_fixed_high"
        case recallBudgetAdaptiveLow = "recall_budget_adaptive_low"
        case recallBudgetAdaptiveMid = "recall_budget_adaptive_mid"
        case recallBudgetAdaptiveHigh = "recall_budget_adaptive_high"
        case recallBudgetMin = "recall_budget_min"
        case recallBudgetMax = "recall_budget_max"
        case auditLogEnabled = "audit_log_enabled"
        case storeDocumentText = "store_document_text"
        case defaultTimezone = "default_timezone"
        case enableAutoConsolidation = "enable_auto_consolidation"
        case consolidationUseDecisionModel = "consolidation_use_decision_model"
        case consolidationMaxMemoriesPerRound = "consolidation_max_memories_per_round"
        case consolidationLlmParallelism = "consolidation_llm_parallelism"
        case recallIncludeChunks = "recall_include_chunks"
        case recallPreferObservations = "recall_prefer_observations"
        case recallDecisionModelPrune = "recall_decision_model_prune"
        case recallDecisionModelDedup = "recall_decision_model_dedup"
        case recallMaxTokens = "recall_max_tokens"
        case recallChunksMaxTokens = "recall_chunks_max_tokens"
        case memoryDefense = "memory_defense"
    }
}

/// A directive definition within a bank template manifest.
public struct BankTemplateDirective: Codable, Sendable, Hashable {
    /// Human-readable name for the directive (used as match key on re-import)
    public var name: String
    /// The directive text to inject into prompts
    public var content: String
    /// Higher priority directives are injected first
    public var priority: Int
    /// Whether this directive is active
    public var isActive: Bool
    /// Tags for filtering
    public var tags: [String]

    public init(name: String, content: String, priority: Int = 0, isActive: Bool = true, tags: [String] = []) {
        self.name = name
        self.content = content
        self.priority = priority
        self.isActive = isActive
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case name
        case content
        case priority
        case isActive = "is_active"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.content = try c.decode(String.self, forKey: .content)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// Response model for the bank template import endpoint.
public struct BankTemplateImportResponse: Codable, Sendable, Hashable {
    /// Bank that was imported into
    public var bankId: String
    /// Whether bank config was updated
    public var configApplied: Bool
    /// IDs of newly created mental models
    public var mentalModelsCreated: [String]
    /// IDs of updated mental models
    public var mentalModelsUpdated: [String]
    /// Names of newly created directives
    public var directivesCreated: [String]
    /// Names of updated directives
    public var directivesUpdated: [String]
    /// Operation IDs for mental model content generation (async)
    public var operationIds: [String]
    /// True if this was a validation-only run
    public var dryRun: Bool

    public init(bankId: String, configApplied: Bool, mentalModelsCreated: [String] = [], mentalModelsUpdated: [String] = [], directivesCreated: [String] = [], directivesUpdated: [String] = [], operationIds: [String] = [], dryRun: Bool = false) {
        self.bankId = bankId
        self.configApplied = configApplied
        self.mentalModelsCreated = mentalModelsCreated
        self.mentalModelsUpdated = mentalModelsUpdated
        self.directivesCreated = directivesCreated
        self.directivesUpdated = directivesUpdated
        self.operationIds = operationIds
        self.dryRun = dryRun
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case configApplied = "config_applied"
        case mentalModelsCreated = "mental_models_created"
        case mentalModelsUpdated = "mental_models_updated"
        case directivesCreated = "directives_created"
        case directivesUpdated = "directives_updated"
        case operationIds = "operation_ids"
        case dryRun = "dry_run"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.configApplied = try c.decode(Bool.self, forKey: .configApplied)
        self.mentalModelsCreated = try c.decodeIfPresent([String].self, forKey: .mentalModelsCreated) ?? []
        self.mentalModelsUpdated = try c.decodeIfPresent([String].self, forKey: .mentalModelsUpdated) ?? []
        self.directivesCreated = try c.decodeIfPresent([String].self, forKey: .directivesCreated) ?? []
        self.directivesUpdated = try c.decodeIfPresent([String].self, forKey: .directivesUpdated) ?? []
        self.operationIds = try c.decodeIfPresent([String].self, forKey: .operationIds) ?? []
        self.dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
    }
}

/// A bank template manifest for import/export.
public struct BankTemplateManifest: Codable, Sendable, Hashable {
    /// Manifest schema version (currently '1')
    public var version: String
    /// Bank configuration to apply. Omit to leave config unchanged.
    public var bank: BankTemplateConfig?
    /// Mental models to create or update (matched by id). Omit to leave unchanged.
    public var mentalModels: [BankTemplateMentalModel]?
    /// Directives to create or update (matched by name). Omit to leave unchanged.
    public var directives: [BankTemplateDirective]?

    public init(version: String, bank: BankTemplateConfig? = nil, mentalModels: [BankTemplateMentalModel]? = nil, directives: [BankTemplateDirective]? = nil) {
        self.version = version
        self.bank = bank
        self.mentalModels = mentalModels
        self.directives = directives
    }

    enum CodingKeys: String, CodingKey {
        case version
        case bank
        case mentalModels = "mental_models"
        case directives
    }
}

/// A mental model definition within a bank template manifest.
public struct BankTemplateMentalModel: Codable, Sendable, Hashable, Identifiable {
    /// Unique ID for the mental model (alphanumeric lowercase with hyphens)
    public var id: String
    /// Human-readable name for the mental model
    public var name: String
    /// The query to run to generate content
    public var sourceQuery: String
    /// Tags for scoped visibility
    public var tags: [String]
    /// Maximum tokens for generated content
    public var maxTokens: Int
    /// Trigger settings
    public var trigger: MentalModelTriggerOutput?

    public init(id: String, name: String, sourceQuery: String, tags: [String] = [], maxTokens: Int = 2048, trigger: MentalModelTriggerOutput? = nil) {
        self.id = id
        self.name = name
        self.sourceQuery = sourceQuery
        self.tags = tags
        self.maxTokens = maxTokens
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceQuery = "source_query"
        case tags
        case maxTokens = "max_tokens"
        case trigger
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.sourceQuery = try c.decode(String.self, forKey: .sourceQuery)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        self.trigger = try c.decodeIfPresent(MentalModelTriggerOutput.self, forKey: .trigger)
    }
}

/// Response for the unified bank-transfer endpoints (202).
public struct BankTransferSubmitResponse: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String

    public init(operationId: String, status: String = "pending") {
        self.operationId = operationId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operationId = try c.decode(String.self, forKey: .operationId)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
    }
}

/// Inline attachment bytes, base64-encoded.
public struct Base64AttachmentSource: Codable, Sendable, Hashable {
    public var type: String
    /// MIME type of the attachment, e.g. 'image/png' or 'application/pdf'. Any well-formed type is accepted; whether the model can read it is the m
    public var mediaType: String
    /// Base64-encoded bytes (no data: URI prefix).
    public var data: String

    public init(type: String = "base64", mediaType: String, data: String) {
        self.type = type
        self.mediaType = mediaType
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "base64"
        self.mediaType = try c.decode(String.self, forKey: .mediaType)
        self.data = try c.decode(String.self, forKey: .data)
    }
}

/// Response model for cancel operation endpoint.
public struct CancelOperationResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var message: String
    public var operationId: String

    public init(success: Bool, message: String, operationId: String) {
        self.success = success
        self.message = message
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case operationId = "operation_id"
    }
}

/// Status of a child operation (for batch operations).
public struct ChildOperationStatus: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String
    public var subBatchIndex: Int?
    public var itemsCount: Int?
    public var errorMessage: String?

    public init(operationId: String, status: String, subBatchIndex: Int? = nil, itemsCount: Int? = nil, errorMessage: String? = nil) {
        self.operationId = operationId
        self.status = status
        self.subBatchIndex = subBatchIndex
        self.itemsCount = itemsCount
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
        case subBatchIndex = "sub_batch_index"
        case itemsCount = "items_count"
        case errorMessage = "error_message"
    }
}

/// An attachment referenced by retained text, and where to fetch it.
public struct ChunkAttachment: Codable, Sendable, Hashable, Identifiable {
    /// The id inside the text's placeholder; a prefix of the bytes' sha256.
    public var id: String
    /// Full sha256 of the attachment bytes.
    public var `hash`: String
    /// 'image' or 'file', as the caller sent it.
    public var kind: String
    /// MIME type of the attachment.
    public var mediaType: String
    /// Size of the attachment in bytes.
    public var byteSize: Int
    /// Original filename, when the caller supplied one.
    public var filename: String?
    /// Bank-scoped API path serving the bytes. Requires the same authorization as the bank.
    public var url: String

    public init(id: String, `hash`: String, kind: String, mediaType: String, byteSize: Int, filename: String? = nil, url: String) {
        self.id = id
        self.`hash` = `hash`
        self.kind = kind
        self.mediaType = mediaType
        self.byteSize = byteSize
        self.filename = filename
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case `hash`
        case kind
        case mediaType = "media_type"
        case byteSize = "byte_size"
        case filename
        case url
    }
}

/// Chunk data for a single chunk.
public struct ChunkData: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var chunkIndex: Int
    /// Whether the chunk text was truncated due to token limits
    public var truncated: Bool
    /// Attachments this chunk's text references, in order of first appearance, when it was retained with inline content. The text keeps each attach
    public var attachments: [ChunkAttachment]?

    public init(id: String, text: String, chunkIndex: Int, truncated: Bool = false, attachments: [ChunkAttachment]? = nil) {
        self.id = id
        self.text = text
        self.chunkIndex = chunkIndex
        self.truncated = truncated
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case chunkIndex = "chunk_index"
        case truncated
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.chunkIndex = try c.decode(Int.self, forKey: .chunkIndex)
        self.truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        self.attachments = try c.decodeIfPresent([ChunkAttachment].self, forKey: .attachments)
    }
}

/// Options for including chunks in recall results.
public struct ChunkIncludeOptions: Codable, Sendable, Hashable {
    /// Maximum tokens for chunks (chunks may be truncated)
    public var maxTokens: Int

    public init(maxTokens: Int = 8192) {
        self.maxTokens = maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 8192
    }
}

/// Response model for get chunk endpoint.
public struct ChunkResponse: Codable, Sendable, Hashable {
    public var chunkId: String
    public var documentId: String
    public var bankId: String
    public var chunkIndex: Int
    public var chunkText: String
    public var createdAt: String
    /// Attachments referenced by this chunk's text, when it was retained with inline content. Each carries a bank-scoped `url` serving the original
    public var attachments: [ChunkAttachment]?

    public init(chunkId: String, documentId: String, bankId: String, chunkIndex: Int, chunkText: String, createdAt: String, attachments: [ChunkAttachment]? = nil) {
        self.chunkId = chunkId
        self.documentId = documentId
        self.bankId = bankId
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
        self.createdAt = createdAt
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case documentId = "document_id"
        case bankId = "bank_id"
        case chunkIndex = "chunk_index"
        case chunkText = "chunk_text"
        case createdAt = "created_at"
        case attachments
    }
}

/// Response model for clearing observations for a specific memory.
public struct ClearMemoryObservationsResponse: Codable, Sendable, Hashable {
    public var deletedCount: Int

    public init(deletedCount: Int) {
        self.deletedCount = deletedCount
    }

    enum CodingKeys: String, CodingKey {
        case deletedCount = "deleted_count"
    }
}

/// Request model for consolidation trigger endpoint.
public struct ConsolidationRequest: Codable, Sendable, Hashable {
    /// Optional list of tag scopes to consolidate. Each scope is a list of tags. Only unconsolidated memories whose tags contain all tags in at lea
    public var observationScopes: [[String]]?

    public init(observationScopes: [[String]]? = nil) {
        self.observationScopes = observationScopes
    }

    enum CodingKeys: String, CodingKey {
        case observationScopes = "observation_scopes"
    }
}

/// Response model for consolidation trigger endpoint.
public struct ConsolidationResponse: Codable, Sendable, Hashable {
    /// ID of the async consolidation operation
    public var operationId: String
    /// True if an existing pending task was reused
    public var deduplicated: Bool

    public init(operationId: String, deduplicated: Bool = false) {
        self.operationId = operationId
        self.deduplicated = deduplicated
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case deduplicated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operationId = try c.decode(String.self, forKey: .operationId)
        self.deduplicated = try c.decodeIfPresent(Bool.self, forKey: .deduplicated) ?? false
    }
}

/// One rule of a consolidation strategy: tags, and how they must match.
public struct ConsolidationScopePattern: Codable, Sendable, Hashable {
    /// fnmatch tag patterns, e.g. company:*
    public var tags: [String]?
    /// "all" (the default when omitted): the scope has every tag in the rule, other tags allowed. "exact": exactly these tags and no others.
    public var tagsMatch: String?

    public init(tags: [String]? = nil, tagsMatch: String? = nil) {
        self.tags = tags
        self.tagsMatch = tagsMatch
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case tagsMatch = "tags_match"
    }
}

/// Which existing observation scopes each consolidation strategy would apply to.
public struct ConsolidationStrategiesPreview: Codable, Sendable, Hashable {
    public var strategies: [StrategyPreview]
    public var `default`: DefaultScopesPreview
    /// Distinct scopes the preview was computed over
    public var scopesScanned: Int
    /// False when the bank has more distinct scopes than the preview scans; counts are then lower bounds
    public var complete: Bool

    public init(strategies: [StrategyPreview], `default`: DefaultScopesPreview, scopesScanned: Int, complete: Bool) {
        self.strategies = strategies
        self.`default` = `default`
        self.scopesScanned = scopesScanned
        self.complete = complete
    }

    enum CodingKeys: String, CodingKey {
        case strategies
        case `default`
        case scopesScanned = "scopes_scanned"
        case complete
    }
}

/// A draft consolidation_strategies value to preview against existing scopes.
public struct ConsolidationStrategiesPreviewRequest: Codable, Sendable, Hashable {
    /// Draft consolidation_strategies value
    public var strategies: [ConsolidationStrategySpec]
    /// Example scopes returned per rule
    public var sampleLimit: Int

    public init(strategies: [ConsolidationStrategySpec], sampleLimit: Int = 5) {
        self.strategies = strategies
        self.sampleLimit = sampleLimit
    }

    enum CodingKeys: String, CodingKey {
        case strategies
        case sampleLimit = "sample_limit"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.strategies = try c.decode([ConsolidationStrategySpec].self, forKey: .strategies)
        self.sampleLimit = try c.decodeIfPresent(Int.self, forKey: .sampleLimit) ?? 5
    }
}

/// One `consolidation_strategies` entry: the rules it claims scopes with, and
public struct ConsolidationStrategySpec: Codable, Sendable, Hashable {
    /// Alternatives: the strategy claims a scope when any rule matches it
    public var scopes: [ConsolidationScopePattern]?
    public var observationsMission: String?
    public var maxObservationsPerScope: Int?
    public var consolidationSourceFactsMaxTokens: Int?
    public var consolidationSourceFactsMaxTokensPerObservation: Int?

    public init(scopes: [ConsolidationScopePattern]? = nil, observationsMission: String? = nil, maxObservationsPerScope: Int? = nil, consolidationSourceFactsMaxTokens: Int? = nil, consolidationSourceFactsMaxTokensPerObservation: Int? = nil) {
        self.scopes = scopes
        self.observationsMission = observationsMission
        self.maxObservationsPerScope = maxObservationsPerScope
        self.consolidationSourceFactsMaxTokens = consolidationSourceFactsMaxTokens
        self.consolidationSourceFactsMaxTokensPerObservation = consolidationSourceFactsMaxTokensPerObservation
    }

    enum CodingKeys: String, CodingKey {
        case scopes
        case observationsMission = "observations_mission"
        case maxObservationsPerScope = "max_observations_per_scope"
        case consolidationSourceFactsMaxTokens = "consolidation_source_facts_max_tokens"
        case consolidationSourceFactsMaxTokensPerObservation = "consolidation_source_facts_max_tokens_per_observation"
    }
}

/// Request model for adding an alias to a bank.
public struct CreateBankAliasRequest: Codable, Sendable, Hashable {
    /// The extra bank id. Same rules as a bank id (non-empty, at most 192 bytes of UTF-8, no control characters, no leading underscore), and it mus
    public var alias: String
    /// Also show the bank under this alias, replacing whichever alias is shown today.
    public var primary: Bool

    public init(alias: String, primary: Bool = false) {
        self.alias = alias
        self.primary = primary
    }

    enum CodingKeys: String, CodingKey {
        case alias
        case primary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.alias = try c.decode(String.self, forKey: .alias)
        self.primary = try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false
    }
}

/// Request model for creating/updating a bank.
public struct CreateBankRequest: Codable, Sendable, Hashable {
    /// Deprecated: display label only, not advertised
    public var name: String?
    /// Deprecated: use update_bank_config instead
    public var disposition: DispositionTraits?
    /// Deprecated: use update_bank_config instead
    public var dispositionSkepticism: Int?
    /// Deprecated: use update_bank_config instead
    public var dispositionLiteralism: Int?
    /// Deprecated: use update_bank_config instead
    public var dispositionEmpathy: Int?
    /// Deprecated: use update_bank_config with reflect_mission instead
    public var mission: String?
    /// Deprecated: use update_bank_config with reflect_mission instead
    public var background: String?
    /// Mission/context for Reflect operations. Guides how Reflect interprets and uses memories.
    public var reflectMission: String?
    /// Steers what gets extracted during retain(). Injected alongside built-in extraction rules.
    public var retainMission: String?
    /// Fact extraction mode: 'concise' (default), 'verbose', 'custom', 'verbatim', or 'chunks'.
    public var retainExtractionMode: String?
    /// Custom extraction prompt. Only active when retain_extraction_mode is 'custom'.
    public var retainCustomInstructions: String?
    /// Target maximum characters for each content chunk during retain.
    public var retainChunkSize: Int?
    /// Maximum characters for a single JSONL line or conversation turn to keep whole during retain. Defaults to retain_chunk_size when unset.
    public var retainStructuredChunkSize: Int?
    /// Maximum inline attachments one extraction chunk may carry. retain_chunk_size budgets text only — a placeholder costs the characters it occup
    public var retainMaxAttachmentsPerChunk: Int?
    /// Toggle automatic observation consolidation after retain().
    public var enableObservations: Bool?
    /// Controls what gets synthesised into observations. Replaces built-in consolidation rules entirely.
    public var observationsMission: String?
    /// Toggle the keyword (BM25) retrieval arm during recall. Disabling leaves pure vector search: the arm is left out of the query entirely rather
    public var enableTextSearch: Bool?
    /// Toggle the temporal retrieval arm during recall, together with the date-aware query analysis that feeds it. Useful for banks whose content c
    public var enableTemporalRetrieval: Bool?
    /// Toggle the entity/link graph traversal arm during recall. Disabling trades relational recall for latency on banks whose content has little e
    public var enableGraphRetrieval: Bool?
    /// Toggle cross-encoder reranking during recall. Disabling returns the RRF-fused ordering directly, which is faster but less precise.
    public var enableReranking: Bool?

    public init(name: String? = nil, disposition: DispositionTraits? = nil, dispositionSkepticism: Int? = nil, dispositionLiteralism: Int? = nil, dispositionEmpathy: Int? = nil, mission: String? = nil, background: String? = nil, reflectMission: String? = nil, retainMission: String? = nil, retainExtractionMode: String? = nil, retainCustomInstructions: String? = nil, retainChunkSize: Int? = nil, retainStructuredChunkSize: Int? = nil, retainMaxAttachmentsPerChunk: Int? = nil, enableObservations: Bool? = nil, observationsMission: String? = nil, enableTextSearch: Bool? = nil, enableTemporalRetrieval: Bool? = nil, enableGraphRetrieval: Bool? = nil, enableReranking: Bool? = nil) {
        self.name = name
        self.disposition = disposition
        self.dispositionSkepticism = dispositionSkepticism
        self.dispositionLiteralism = dispositionLiteralism
        self.dispositionEmpathy = dispositionEmpathy
        self.mission = mission
        self.background = background
        self.reflectMission = reflectMission
        self.retainMission = retainMission
        self.retainExtractionMode = retainExtractionMode
        self.retainCustomInstructions = retainCustomInstructions
        self.retainChunkSize = retainChunkSize
        self.retainStructuredChunkSize = retainStructuredChunkSize
        self.retainMaxAttachmentsPerChunk = retainMaxAttachmentsPerChunk
        self.enableObservations = enableObservations
        self.observationsMission = observationsMission
        self.enableTextSearch = enableTextSearch
        self.enableTemporalRetrieval = enableTemporalRetrieval
        self.enableGraphRetrieval = enableGraphRetrieval
        self.enableReranking = enableReranking
    }

    enum CodingKeys: String, CodingKey {
        case name
        case disposition
        case dispositionSkepticism = "disposition_skepticism"
        case dispositionLiteralism = "disposition_literalism"
        case dispositionEmpathy = "disposition_empathy"
        case mission
        case background
        case reflectMission = "reflect_mission"
        case retainMission = "retain_mission"
        case retainExtractionMode = "retain_extraction_mode"
        case retainCustomInstructions = "retain_custom_instructions"
        case retainChunkSize = "retain_chunk_size"
        case retainStructuredChunkSize = "retain_structured_chunk_size"
        case retainMaxAttachmentsPerChunk = "retain_max_attachments_per_chunk"
        case enableObservations = "enable_observations"
        case observationsMission = "observations_mission"
        case enableTextSearch = "enable_text_search"
        case enableTemporalRetrieval = "enable_temporal_retrieval"
        case enableGraphRetrieval = "enable_graph_retrieval"
        case enableReranking = "enable_reranking"
    }
}

/// Request model for creating a directive.
public struct CreateDirectiveRequest: Codable, Sendable, Hashable {
    /// Human-readable name for the directive
    public var name: String
    /// The directive text to inject into prompts
    public var content: String
    /// Higher priority directives are injected first
    public var priority: Int
    /// Whether this directive is active
    public var isActive: Bool
    /// Directive execution scope. Empty means global; non-empty requires a matching reflect scope.
    public var tags: [String]

    public init(name: String, content: String, priority: Int = 0, isActive: Bool = true, tags: [String] = []) {
        self.name = name
        self.content = content
        self.priority = priority
        self.isActive = isActive
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case name
        case content
        case priority
        case isActive = "is_active"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.content = try c.decode(String.self, forKey: .content)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// Create a folder under an optional parent folder.
public struct CreateFolderRequest: Codable, Sendable, Hashable {
    public var name: String
    public var parentId: String?

    public init(name: String, parentId: String? = nil) {
        self.name = name
        self.parentId = parentId
    }

    enum CodingKeys: String, CodingKey {
        case name
        case parentId = "parent_id"
    }
}

/// Result of creating a page: the node id, its mental model, and the refresh op.
public struct CreateKnowledgePageResponse: Codable, Sendable, Hashable {
    public var pageId: String
    public var mentalModelId: String
    public var operationId: String?

    public init(pageId: String, mentalModelId: String, operationId: String? = nil) {
        self.pageId = pageId
        self.mentalModelId = mentalModelId
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case mentalModelId = "mental_model_id"
        case operationId = "operation_id"
    }
}

/// Request model for creating a mental model.
public struct CreateMentalModelRequest: Codable, Sendable, Hashable {
    /// Optional custom ID for the mental model (alphanumeric lowercase with hyphens)
    public var id: String?
    /// Human-readable name for the mental model
    public var name: String
    /// The query to run to generate content
    public var sourceQuery: String
    /// Tags for scoped visibility
    public var tags: [String]
    /// Maximum tokens for generated content
    public var maxTokens: Int
    /// Trigger settings
    public var trigger: MentalModelTriggerInput?

    public init(id: String? = nil, name: String, sourceQuery: String, tags: [String] = [], maxTokens: Int = 2048, trigger: MentalModelTriggerInput? = nil) {
        self.id = id
        self.name = name
        self.sourceQuery = sourceQuery
        self.tags = tags
        self.maxTokens = maxTokens
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceQuery = "source_query"
        case tags
        case maxTokens = "max_tokens"
        case trigger
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.sourceQuery = try c.decode(String.self, forKey: .sourceQuery)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        self.trigger = try c.decodeIfPresent(MentalModelTriggerInput.self, forKey: .trigger)
    }
}

/// Response model for mental model creation.
public struct CreateMentalModelResponse: Codable, Sendable, Hashable {
    /// ID of the created mental model
    public var mentalModelId: String?
    /// Operation ID to track refresh progress
    public var operationId: String

    public init(mentalModelId: String? = nil, operationId: String) {
        self.mentalModelId = mentalModelId
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case mentalModelId = "mental_model_id"
        case operationId = "operation_id"
    }
}

/// Create a page (a mental model + tree node) under an optional parent folder.
public struct CreatePageRequest: Codable, Sendable, Hashable {
    public var name: String
    public var sourceQuery: String
    public var parentId: String?
    /// Tags that SCOPE which memories this page is built from — not labels. Every tag here, including a `type:<x>` tag used to set the page's rende
    public var tags: [String]?
    public var maxTokens: Int?
    public var trigger: MentalModelTriggerInput?

    public init(name: String, sourceQuery: String, parentId: String? = nil, tags: [String]? = nil, maxTokens: Int? = nil, trigger: MentalModelTriggerInput? = nil) {
        self.name = name
        self.sourceQuery = sourceQuery
        self.parentId = parentId
        self.tags = tags
        self.maxTokens = maxTokens
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case name
        case sourceQuery = "source_query"
        case parentId = "parent_id"
        case tags
        case maxTokens = "max_tokens"
        case trigger
    }
}

/// Request model for registering a webhook.
public struct CreateWebhookRequest: Codable, Sendable, Hashable {
    /// HTTP(S) endpoint URL to deliver events to
    public var url: String
    /// HMAC-SHA256 signing secret (optional)
    public var secret: String?
    /// List of event types to deliver. Supported: 'retain.completed', 'consolidation.completed', 'memory_defense.triggered'.
    public var eventTypes: [String]?
    /// Whether this webhook is active
    public var enabled: Bool
    /// HTTP delivery configuration (method, timeout, headers, params)
    public var httpConfig: WebhookHttpConfig?

    public init(url: String, secret: String? = nil, eventTypes: [String]? = nil, enabled: Bool = true, httpConfig: WebhookHttpConfig? = nil) {
        self.url = url
        self.secret = secret
        self.eventTypes = eventTypes
        self.enabled = enabled
        self.httpConfig = httpConfig
    }

    enum CodingKeys: String, CodingKey {
        case url
        case secret
        case eventTypes = "event_types"
        case enabled
        case httpConfig = "http_config"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.secret = try c.decodeIfPresent(String.self, forKey: .secret)
        self.eventTypes = try c.decodeIfPresent([String].self, forKey: .eventTypes)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.httpConfig = try c.decodeIfPresent(WebhookHttpConfig.self, forKey: .httpConfig)
    }
}

/// The scopes no strategy claims — they consolidate under the bank-wide settings.
public struct DefaultScopesPreview: Codable, Sendable, Hashable {
    public var matchCount: Int
    public var observationCount: Int
    public var samples: [StrategyScopePreview]

    public init(matchCount: Int, observationCount: Int, samples: [StrategyScopePreview]) {
        self.matchCount = matchCount
        self.observationCount = observationCount
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case matchCount = "match_count"
        case observationCount = "observation_count"
        case samples
    }
}

/// Response model for delete document endpoint.
public struct DeleteDocumentResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var message: String
    public var documentId: String
    public var memoryUnitsDeleted: Int

    public init(success: Bool, message: String, documentId: String, memoryUnitsDeleted: Int) {
        self.success = success
        self.message = message
        self.documentId = documentId
        self.memoryUnitsDeleted = memoryUnitsDeleted
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case documentId = "document_id"
        case memoryUnitsDeleted = "memory_units_deleted"
    }
}

/// Response model for delete operation endpoint.
public struct DeleteOperationResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var message: String
    public var operationId: String

    public init(success: Bool, message: String, operationId: String) {
        self.success = success
        self.message = message
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case operationId = "operation_id"
    }
}

/// Response model for delete operations.
public struct DeleteResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var message: String?
    public var deletedCount: Int?

    public init(success: Bool, message: String? = nil, deletedCount: Int? = nil) {
        self.success = success
        self.message = message
        self.deletedCount = deletedCount
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case deletedCount = "deleted_count"
    }
}

/// Response model for listing directives.
public struct DirectiveListResponse: Codable, Sendable, Hashable {
    public var items: [DirectiveResponse]
    /// Total number of directives matching the filter (not just this page)
    public var total: Int
    /// Page size that was applied
    public var limit: Int
    /// Offset that was applied
    public var offset: Int

    public init(items: [DirectiveResponse], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// Response model for a directive.
public struct DirectiveResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bankId: String
    public var name: String
    public var content: String
    public var priority: Int
    public var isActive: Bool
    public var tags: [String]
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String, bankId: String, name: String, content: String, priority: Int = 0, isActive: Bool = true, tags: [String] = [], createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.bankId = bankId
        self.name = name
        self.content = content
        self.priority = priority
        self.isActive = isActive
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case name
        case content
        case priority
        case isActive = "is_active"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.name = try c.decode(String.self, forKey: .name)
        self.content = try c.decode(String.self, forKey: .content)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// Disposition traits that influence how memories are formed and interpreted.
public struct DispositionTraits: Codable, Sendable, Hashable {
    /// How skeptical vs trusting (1=trusting, 5=skeptical)
    public var skepticism: Int
    /// How literally to interpret information (1=flexible, 5=literal)
    public var literalism: Int
    /// How much to consider emotional context (1=detached, 5=empathetic)
    public var empathy: Int

    public init(skepticism: Int, literalism: Int, empathy: Int) {
        self.skepticism = skepticism
        self.literalism = literalism
        self.empathy = empathy
    }

    enum CodingKeys: String, CodingKey {
        case skepticism
        case literalism
        case empathy
    }
}

/// One change to a document, and its effect on the facts and observations built from it.
public struct DocumentEvent: Codable, Sendable, Hashable {
    public var documentId: String
    public var kind: String
    public var createdAt: String?
    /// The operation this event was recorded on (filled in when read).
    public var operationId: String?
    /// The fact a fact_* event changed.
    public var factId: String?
    public var factsAdded: Int
    public var factsRemoved: Int
    public var observationsCreated: ObservationIdSample?
    public var observationsUpdated: ObservationIdSample?
    public var observationsRemoved: ObservationIdSample?

    public init(documentId: String, kind: String, createdAt: String? = nil, operationId: String? = nil, factId: String? = nil, factsAdded: Int = 0, factsRemoved: Int = 0, observationsCreated: ObservationIdSample? = nil, observationsUpdated: ObservationIdSample? = nil, observationsRemoved: ObservationIdSample? = nil) {
        self.documentId = documentId
        self.kind = kind
        self.createdAt = createdAt
        self.operationId = operationId
        self.factId = factId
        self.factsAdded = factsAdded
        self.factsRemoved = factsRemoved
        self.observationsCreated = observationsCreated
        self.observationsUpdated = observationsUpdated
        self.observationsRemoved = observationsRemoved
    }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case kind
        case createdAt = "created_at"
        case operationId = "operation_id"
        case factId = "fact_id"
        case factsAdded = "facts_added"
        case factsRemoved = "facts_removed"
        case observationsCreated = "observations_created"
        case observationsUpdated = "observations_updated"
        case observationsRemoved = "observations_removed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.documentId = try c.decode(String.self, forKey: .documentId)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.operationId = try c.decodeIfPresent(String.self, forKey: .operationId)
        self.factId = try c.decodeIfPresent(String.self, forKey: .factId)
        self.factsAdded = try c.decodeIfPresent(Int.self, forKey: .factsAdded) ?? 0
        self.factsRemoved = try c.decodeIfPresent(Int.self, forKey: .factsRemoved) ?? 0
        self.observationsCreated = try c.decodeIfPresent(ObservationIdSample.self, forKey: .observationsCreated)
        self.observationsUpdated = try c.decodeIfPresent(ObservationIdSample.self, forKey: .observationsUpdated)
        self.observationsRemoved = try c.decodeIfPresent(ObservationIdSample.self, forKey: .observationsRemoved)
    }
}

/// Response for the async document-export endpoint (202).
public struct DocumentExportSubmitResponse: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String

    public init(operationId: String, status: String = "pending") {
        self.operationId = operationId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operationId = try c.decode(String.self, forKey: .operationId)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
    }
}

/// A document's change history, newest first. ``total``, ``limit`` and ``offset`` count operations:
public struct DocumentHistoryResponse: Codable, Sendable, Hashable {
    public var documentId: String
    public var total: Int
    public var limit: Int
    public var offset: Int
    public var items: [DocumentEvent]

    public init(documentId: String, total: Int, limit: Int, offset: Int, items: [DocumentEvent]) {
        self.documentId = documentId
        self.total = total
        self.limit = limit
        self.offset = offset
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case total
        case limit
        case offset
        case items
    }
}

/// Response for the async document-import endpoint (202).
public struct DocumentImportSubmitResponse: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String

    public init(operationId: String, status: String = "pending") {
        self.operationId = operationId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operationId = try c.decode(String.self, forKey: .operationId)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
    }
}

/// One row of the document listing — a document's metadata without its text.
public struct DocumentListItem: Codable, Sendable, Hashable, Identifiable {
    /// Document ID
    public var id: String
    /// Bank the document belongs to
    public var bankId: String
    /// Hash of the document text, for idempotent retain
    public var contentHash: String?
    /// When the document was first retained (ISO 8601)
    public var createdAt: String
    /// When the document was last written (ISO 8601)
    public var updatedAt: String
    /// Length of the stored document text in characters
    public var textLength: Int
    /// Number of memory units extracted from this document
    public var memoryUnitCount: Int
    /// Parameters used during retain
    public var retainParams: [String: JSONValue]?
    /// Document metadata
    public var documentMetadata: [String: JSONValue]?
    /// Tags associated with this document
    public var tags: [String]
    /// Which fields matched the `q` search: 'id', 'original_text', or both. Empty when no `q` is given.
    public var matchedFields: [String]

    public init(id: String, bankId: String = "", contentHash: String? = nil, createdAt: String = "", updatedAt: String = "", textLength: Int = 0, memoryUnitCount: Int = 0, retainParams: [String: JSONValue]? = nil, documentMetadata: [String: JSONValue]? = nil, tags: [String] = [], matchedFields: [String] = []) {
        self.id = id
        self.bankId = bankId
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.textLength = textLength
        self.memoryUnitCount = memoryUnitCount
        self.retainParams = retainParams
        self.documentMetadata = documentMetadata
        self.tags = tags
        self.matchedFields = matchedFields
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case contentHash = "content_hash"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case textLength = "text_length"
        case memoryUnitCount = "memory_unit_count"
        case retainParams = "retain_params"
        case documentMetadata = "document_metadata"
        case tags
        case matchedFields = "matched_fields"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.bankId = try c.decodeIfPresent(String.self, forKey: .bankId) ?? ""
        self.contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self.textLength = try c.decodeIfPresent(Int.self, forKey: .textLength) ?? 0
        self.memoryUnitCount = try c.decodeIfPresent(Int.self, forKey: .memoryUnitCount) ?? 0
        self.retainParams = try c.decodeIfPresent([String: JSONValue].self, forKey: .retainParams)
        self.documentMetadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .documentMetadata)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.matchedFields = try c.decodeIfPresent([String].self, forKey: .matchedFields) ?? []
    }
}

/// Response model for get document endpoint.
public struct DocumentResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bankId: String
    public var originalText: String?
    public var contentHash: String?
    public var createdAt: String
    public var updatedAt: String
    public var memoryUnitCount: Int
    /// Memory count per fact type (world, experience, observation)
    public var nodesByFactType: [String: Int]?
    /// Tags associated with this document
    public var tags: [String]
    /// Document metadata
    public var documentMetadata: [String: JSONValue]?
    /// Parameters used during retain
    public var retainParams: [String: JSONValue]?
    /// The observation_scopes spec configured at retain time (e.g. 'all_combinations', 'per_tag', or explicit tag-set lists), captured into retain_
    public var observationScopes: JSONValue?
    /// Attachments referenced by this document, when it was retained with inline content. Each carries a bank-scoped `url` serving the original byt
    public var attachments: [ChunkAttachment]?

    public init(id: String, bankId: String, originalText: String? = nil, contentHash: String? = nil, createdAt: String, updatedAt: String, memoryUnitCount: Int, nodesByFactType: [String: Int]? = nil, tags: [String] = [], documentMetadata: [String: JSONValue]? = nil, retainParams: [String: JSONValue]? = nil, observationScopes: JSONValue? = nil, attachments: [ChunkAttachment]? = nil) {
        self.id = id
        self.bankId = bankId
        self.originalText = originalText
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.memoryUnitCount = memoryUnitCount
        self.nodesByFactType = nodesByFactType
        self.tags = tags
        self.documentMetadata = documentMetadata
        self.retainParams = retainParams
        self.observationScopes = observationScopes
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case originalText = "original_text"
        case contentHash = "content_hash"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case memoryUnitCount = "memory_unit_count"
        case nodesByFactType = "nodes_by_fact_type"
        case tags
        case documentMetadata = "document_metadata"
        case retainParams = "retain_params"
        case observationScopes = "observation_scopes"
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.originalText = try c.decodeIfPresent(String.self, forKey: .originalText)
        self.contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        self.createdAt = try c.decode(String.self, forKey: .createdAt)
        self.updatedAt = try c.decode(String.self, forKey: .updatedAt)
        self.memoryUnitCount = try c.decode(Int.self, forKey: .memoryUnitCount)
        self.nodesByFactType = try c.decodeIfPresent([String: Int].self, forKey: .nodesByFactType)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.documentMetadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .documentMetadata)
        self.retainParams = try c.decodeIfPresent([String: JSONValue].self, forKey: .retainParams)
        self.observationScopes = try c.decodeIfPresent(JSONValue.self, forKey: .observationScopes)
        self.attachments = try c.decodeIfPresent([ChunkAttachment].self, forKey: .attachments)
    }
}

/// Request to run fact extraction ONLY (no resolution/links/embeddings/persistence).
public struct DryRunExtractRequest: Codable, Sendable, Hashable {
    /// The raw content to extract facts from. Either a plain string, or an ordered list of content blocks (text, image, file) so images/attachments
    public var content: HSContent
    /// Optional context about the content.
    public var context: String
    /// Reference timestamp for resolving relative times (ISO 8601).
    public var timestamp: String?
    /// Deprecated: describe the speaker in `context` instead. Narrator override (memory owner) primed in the prompt; still honored for backwards co
    public var agentName: String?
    /// Name of a retain strategy to extract under (a key of the bank's `retain_strategies`). Omit it and the bank's `retain_default_strategy` appli
    public var strategy: String?
    public var retainMission: String?
    public var retainExtractionMode: String?
    public var retainCustomInstructions: String?
    public var retainExtractCausalLinks: Bool?
    public var retainChunkSize: Int?
    /// Controlled vocabulary for entity labels (overrides the bank's config for this call)
    public var entityLabels: [LabelGroupInput]?
    public var entitiesAllowFreeForm: Bool?
    public var llmOutputLanguage: String?

    public init(content: HSContent, context: String = "", timestamp: String? = nil, agentName: String? = nil, strategy: String? = nil, retainMission: String? = nil, retainExtractionMode: String? = nil, retainCustomInstructions: String? = nil, retainExtractCausalLinks: Bool? = nil, retainChunkSize: Int? = nil, entityLabels: [LabelGroupInput]? = nil, entitiesAllowFreeForm: Bool? = nil, llmOutputLanguage: String? = nil) {
        self.content = content
        self.context = context
        self.timestamp = timestamp
        self.agentName = agentName
        self.strategy = strategy
        self.retainMission = retainMission
        self.retainExtractionMode = retainExtractionMode
        self.retainCustomInstructions = retainCustomInstructions
        self.retainExtractCausalLinks = retainExtractCausalLinks
        self.retainChunkSize = retainChunkSize
        self.entityLabels = entityLabels
        self.entitiesAllowFreeForm = entitiesAllowFreeForm
        self.llmOutputLanguage = llmOutputLanguage
    }

    enum CodingKeys: String, CodingKey {
        case content
        case context
        case timestamp
        case agentName = "agent_name"
        case strategy
        case retainMission = "retain_mission"
        case retainExtractionMode = "retain_extraction_mode"
        case retainCustomInstructions = "retain_custom_instructions"
        case retainExtractCausalLinks = "retain_extract_causal_links"
        case retainChunkSize = "retain_chunk_size"
        case entityLabels = "entity_labels"
        case entitiesAllowFreeForm = "entities_allow_free_form"
        case llmOutputLanguage = "llm_output_language"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(HSContent.self, forKey: .content)
        self.context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        self.agentName = try c.decodeIfPresent(String.self, forKey: .agentName)
        self.strategy = try c.decodeIfPresent(String.self, forKey: .strategy)
        self.retainMission = try c.decodeIfPresent(String.self, forKey: .retainMission)
        self.retainExtractionMode = try c.decodeIfPresent(String.self, forKey: .retainExtractionMode)
        self.retainCustomInstructions = try c.decodeIfPresent(String.self, forKey: .retainCustomInstructions)
        self.retainExtractCausalLinks = try c.decodeIfPresent(Bool.self, forKey: .retainExtractCausalLinks)
        self.retainChunkSize = try c.decodeIfPresent(Int.self, forKey: .retainChunkSize)
        self.entityLabels = try c.decodeIfPresent([LabelGroupInput].self, forKey: .entityLabels)
        self.entitiesAllowFreeForm = try c.decodeIfPresent(Bool.self, forKey: .entitiesAllowFreeForm)
        self.llmOutputLanguage = try c.decodeIfPresent(String.self, forKey: .llmOutputLanguage)
    }
}

/// Result of dry-run fact extraction: candidate facts, the chunks they came from,
public struct DryRunExtractionResult: Codable, Sendable, Hashable {
    /// Candidate facts the retain step would extract.
    public var facts: [ExtractedFact]?
    /// The chunks the input was cut into before extraction. Already computed on every path; returned because `retain_chunk_size` is otherwise a num
    public var chunks: [ExtractionChunk]?
    /// Aggregated token usage across the extraction LLM calls.
    public var usage: TokenUsage?

    public init(facts: [ExtractedFact]? = nil, chunks: [ExtractionChunk]? = nil, usage: TokenUsage? = nil) {
        self.facts = facts
        self.chunks = chunks
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case facts
        case chunks
        case usage
    }
}

/// Response model for entity detail endpoint.
public struct EntityDetailResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var canonicalName: String
    public var mentionCount: Int
    public var firstSeen: String?
    public var lastSeen: String?
    public var metadata: [String: JSONValue]?
    public var observations: [EntityObservationResponse]

    public init(id: String, canonicalName: String, mentionCount: Int, firstSeen: String? = nil, lastSeen: String? = nil, metadata: [String: JSONValue]? = nil, observations: [EntityObservationResponse]) {
        self.id = id
        self.canonicalName = canonicalName
        self.mentionCount = mentionCount
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.metadata = metadata
        self.observations = observations
    }

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case mentionCount = "mention_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case metadata
        case observations
    }
}

/// A co-occurrence edge, in the Cytoscape ``{"data": {...}}`` envelope the graph uses.
public struct EntityGraphEdge: Codable, Sendable, Hashable {
    public var data: EntityGraphEdgeData

    public init(data: EntityGraphEdgeData) {
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

/// The payload of one co-occurrence edge.
public struct EntityGraphEdgeData: Codable, Sendable, Hashable, Identifiable {
    /// Edge ID (``<source>-<target>``)
    public var id: String
    /// Source entity ID
    public var source: String
    /// Target entity ID
    public var target: String
    /// Kind of relationship this edge represents
    public var linkType: String
    /// Number of co-occurrences between the two entities
    public var weight: Int
    /// Suggested edge colour for rendering
    public var color: String?
    /// Suggested edge line style for rendering
    public var lineStyle: String?
    /// ISO 8601 timestamp of the most recent co-occurrence
    public var lastCooccurred: String?

    public init(id: String, source: String, target: String, linkType: String = "cooccurrence", weight: Int = 0, color: String? = nil, lineStyle: String? = nil, lastCooccurred: String? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.linkType = linkType
        self.weight = weight
        self.color = color
        self.lineStyle = lineStyle
        self.lastCooccurred = lastCooccurred
    }

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case target
        case linkType
        case weight
        case color
        case lineStyle
        case lastCooccurred
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.source = try c.decode(String.self, forKey: .source)
        self.target = try c.decode(String.self, forKey: .target)
        self.linkType = try c.decodeIfPresent(String.self, forKey: .linkType) ?? "cooccurrence"
        self.weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        self.color = try c.decodeIfPresent(String.self, forKey: .color)
        self.lineStyle = try c.decodeIfPresent(String.self, forKey: .lineStyle)
        self.lastCooccurred = try c.decodeIfPresent(String.self, forKey: .lastCooccurred)
    }
}

/// An entity node, in the Cytoscape ``{"data": {...}}`` envelope the graph uses.
public struct EntityGraphNode: Codable, Sendable, Hashable {
    public var data: EntityGraphNodeData

    public init(data: EntityGraphNodeData) {
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

/// The payload of one entity node in the co-occurrence graph.
public struct EntityGraphNodeData: Codable, Sendable, Hashable, Identifiable {
    /// Entity ID
    public var id: String
    /// Entity canonical name
    public var label: String
    /// How many times this entity was mentioned
    public var mentionCount: Int
    /// Suggested node colour for rendering
    public var color: String?

    public init(id: String, label: String = "", mentionCount: Int = 0, color: String? = nil) {
        self.id = id
        self.label = label
        self.mentionCount = mentionCount
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case mentionCount
        case color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.mentionCount = try c.decodeIfPresent(Int.self, forKey: .mentionCount) ?? 0
        self.color = try c.decodeIfPresent(String.self, forKey: .color)
    }
}

/// Response model for entity co-occurrence graph endpoint.
public struct EntityGraphResponse: Codable, Sendable, Hashable {
    public var nodes: [EntityGraphNode]
    public var edges: [EntityGraphEdge]
    public var totalEntities: Int
    public var totalEdges: Int
    public var limit: Int

    public init(nodes: [EntityGraphNode], edges: [EntityGraphEdge], totalEntities: Int, totalEdges: Int, limit: Int) {
        self.nodes = nodes
        self.edges = edges
        self.totalEntities = totalEntities
        self.totalEdges = totalEdges
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case nodes
        case edges
        case totalEntities = "total_entities"
        case totalEdges = "total_edges"
        case limit
    }
}

/// Options for including entity observations in recall results.
public struct EntityIncludeOptions: Codable, Sendable, Hashable {
    /// Maximum tokens for entity observations
    public var maxTokens: Int

    public init(maxTokens: Int = 500) {
        self.maxTokens = maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 500
    }
}

/// Entity to associate with retained content.
public struct EntityInput: Codable, Sendable, Hashable {
    /// The entity name/text
    public var text: String
    /// Optional entity type (e.g., 'PERSON', 'ORG', 'CONCEPT')
    public var type: String?

    public init(text: String, type: String? = nil) {
        self.text = text
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case text
        case type
    }
}

/// Entity list item with summary.
public struct EntityListItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var canonicalName: String
    public var mentionCount: Int
    public var firstSeen: String?
    public var lastSeen: String?
    public var metadata: [String: JSONValue]?

    public init(id: String, canonicalName: String, mentionCount: Int, firstSeen: String? = nil, lastSeen: String? = nil, metadata: [String: JSONValue]? = nil) {
        self.id = id
        self.canonicalName = canonicalName
        self.mentionCount = mentionCount
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case mentionCount = "mention_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case metadata
    }
}

/// Response model for entity list endpoint.
public struct EntityListResponse: Codable, Sendable, Hashable {
    public var items: [EntityListItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(items: [EntityListItem], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// An observation about an entity.
public struct EntityObservationResponse: Codable, Sendable, Hashable {
    public var text: String
    public var mentionedAt: String?

    public init(text: String, mentionedAt: String? = nil) {
        self.text = text
        self.mentionedAt = mentionedAt
    }

    enum CodingKeys: String, CodingKey {
        case text
        case mentionedAt = "mentioned_at"
    }
}

/// Current mental model of an entity.
public struct EntityStateResponse: Codable, Sendable, Hashable {
    public var entityId: String
    public var canonicalName: String
    public var observations: [EntityObservationResponse]

    public init(entityId: String, canonicalName: String, observations: [EntityObservationResponse]) {
        self.entityId = entityId
        self.canonicalName = canonicalName
        self.observations = observations
    }

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case canonicalName = "canonical_name"
        case observations
    }
}

/// A single candidate fact produced by dry-run extraction (no resolution/links/persistence).
public struct ExtractedFact: Codable, Sendable, Hashable {
    /// The extracted fact text.
    public var text: String
    /// Perspective classification: 'world' or 'experience'.
    public var factType: String
    /// ISO timestamp the fact's event started, if dated.
    public var occurredStart: String?
    /// ISO timestamp the fact's event ended, if dated.
    public var occurredEnd: String?
    /// Raw (unresolved) entity names mentioned in the fact.
    public var entities: [String]?
    /// Index into `chunks` of the chunk this fact came from; null if it could not be attributed.
    public var chunkIndex: Int?
    /// Attachments from user input that this fact is attributed to / associated with.
    public var attachments: [ExtractedFactAttachment]?

    public init(text: String, factType: String, occurredStart: String? = nil, occurredEnd: String? = nil, entities: [String]? = nil, chunkIndex: Int? = nil, attachments: [ExtractedFactAttachment]? = nil) {
        self.text = text
        self.factType = factType
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.entities = entities
        self.chunkIndex = chunkIndex
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case text
        case factType = "fact_type"
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case entities
        case chunkIndex = "chunk_index"
        case attachments
    }
}

/// An attachment from multimodal input associated with an extracted fact.
public struct ExtractedFactAttachment: Codable, Sendable, Hashable {
    /// Index of the content block in user's input (0-based)
    public var blockIndex: Int
    /// Content block type ('image' or 'file')
    public var type: String
    /// MIME media type of the attachment, e.g. 'image/png'
    public var mediaType: String

    public init(blockIndex: Int, type: String, mediaType: String) {
        self.blockIndex = blockIndex
        self.type = type
        self.mediaType = mediaType
    }

    enum CodingKeys: String, CodingKey {
        case blockIndex = "block_index"
        case type
        case mediaType = "media_type"
    }
}

/// One chunk the extractor was handed, and how much it yielded.
public struct ExtractionChunk: Codable, Sendable, Hashable {
    /// The chunk as the extractor saw it.
    public var text: String
    /// How many facts came out of this chunk.
    public var factCount: Int

    public init(text: String, factCount: Int) {
        self.text = text
        self.factCount = factCount
    }

    enum CodingKeys: String, CodingKey {
        case text
        case factCount = "fact_count"
    }
}

/// Options for including facts (based_on) in reflect results.
public struct FactsIncludeOptions: Codable, Sendable, Hashable {
    public init() {
    }
}

/// Feature flags indicating which capabilities are enabled.
public struct FeaturesInfo: Codable, Sendable, Hashable {
    /// Whether observations (auto-consolidation) are enabled
    public var observations: Bool
    /// Whether MCP (Model Context Protocol) server is enabled
    public var mcp: Bool
    /// Whether the background worker is enabled
    public var worker: Bool
    /// Whether per-bank configuration API is enabled
    public var bankConfigApi: Bool
    /// Whether the per-bank LLM connectivity probe is enabled
    public var bankLlmHealth: Bool
    /// Whether file upload/conversion API is enabled
    public var fileUploadApi: Bool
    /// Whether the document export endpoint is enabled
    public var documentExportApi: Bool
    /// Whether the document import endpoint is enabled
    public var documentImportApi: Bool
    /// Whether audit logging is enabled by default (overridable per bank)
    public var auditLog: Bool
    /// Whether per-bank LLM request tracing is enabled
    public var llmTrace: Bool
    /// Whether raw source text is persisted. When false, document/chunk source text is not stored.
    public var storeDocumentText: Bool

    public init(observations: Bool, mcp: Bool, worker: Bool, bankConfigApi: Bool, bankLlmHealth: Bool, fileUploadApi: Bool, documentExportApi: Bool, documentImportApi: Bool, auditLog: Bool, llmTrace: Bool, storeDocumentText: Bool) {
        self.observations = observations
        self.mcp = mcp
        self.worker = worker
        self.bankConfigApi = bankConfigApi
        self.bankLlmHealth = bankLlmHealth
        self.fileUploadApi = fileUploadApi
        self.documentExportApi = documentExportApi
        self.documentImportApi = documentImportApi
        self.auditLog = auditLog
        self.llmTrace = llmTrace
        self.storeDocumentText = storeDocumentText
    }

    enum CodingKeys: String, CodingKey {
        case observations
        case mcp
        case worker
        case bankConfigApi = "bank_config_api"
        case bankLlmHealth = "bank_llm_health"
        case fileUploadApi = "file_upload_api"
        case documentExportApi = "document_export_api"
        case documentImportApi = "document_import_api"
        case auditLog = "audit_log"
        case llmTrace = "llm_trace"
        case storeDocumentText = "store_document_text"
    }
}

/// A non-image attachment — a PDF, a spreadsheet — in its input position.
public struct FileContentBlock: Codable, Sendable, Hashable {
    public var type: String
    public var source: Base64AttachmentSource
    /// Original filename, passed to providers that show one to the model (e.g. OpenAI).
    public var filename: String?

    public init(type: String, source: Base64AttachmentSource, filename: String? = nil) {
        self.type = type
        self.source = source
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case type
        case source
        case filename
    }
}

/// Response model for file upload endpoint.
public struct FileRetainResponse: Codable, Sendable, Hashable {
    /// Operation IDs for tracking file conversion operations. Use GET /v1/default/banks/{bank_id}/operations to list operations.
    public var operationIds: [String]

    public init(operationIds: [String]) {
        self.operationIds = operationIds
    }

    enum CodingKeys: String, CodingKey {
        case operationIds = "operation_ids"
    }
}

/// Response model for graph data endpoint.
public struct GraphDataResponse: Codable, Sendable, Hashable {
    public var nodes: [MemoryGraphNode]
    public var edges: [MemoryGraphEdge]
    public var tableRows: [MemoryGraphTableRow]
    public var totalUnits: Int
    public var limit: Int

    public init(nodes: [MemoryGraphNode], edges: [MemoryGraphEdge], tableRows: [MemoryGraphTableRow], totalUnits: Int, limit: Int) {
        self.nodes = nodes
        self.edges = edges
        self.tableRows = tableRows
        self.totalUnits = totalUnits
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case nodes
        case edges
        case tableRows = "table_rows"
        case totalUnits = "total_units"
        case limit
    }
}

public struct HTTPValidationError: Codable, Sendable, Hashable {
    public var detail: [ValidationError]?

    public init(detail: [ValidationError]? = nil) {
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case detail
    }
}

/// An image within a multimodal item, in the position the caller wrote it.
public struct ImageContentBlock: Codable, Sendable, Hashable {
    public var type: String
    public var source: Base64AttachmentSource

    public init(type: String, source: Base64AttachmentSource) {
        self.type = type
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case type
        case source
    }
}

/// Options for including additional data in recall results.
public struct IncludeOptions: Codable, Sendable, Hashable {
    /// Include entity observations. Set to null to disable entity inclusion.
    public var entities: EntityIncludeOptions?
    /// Include raw chunks. Set to {} to enable, null to disable (default: disabled).
    public var chunks: ChunkIncludeOptions?
    /// Include source facts for observation-type results. Set to {} to enable, null to disable (default: disabled).
    public var sourceFacts: SourceFactsIncludeOptions?

    public init(entities: EntityIncludeOptions? = nil, chunks: ChunkIncludeOptions? = nil, sourceFacts: SourceFactsIncludeOptions? = nil) {
        self.entities = entities
        self.chunks = chunks
        self.sourceFacts = sourceFacts
    }

    enum CodingKeys: String, CodingKey {
        case entities
        case chunks
        case sourceFacts = "source_facts"
    }
}

/// A node in the knowledge-base tree — a folder or a page.
public struct KnowledgeNode: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: String
    public var name: String
    public var parentId: String?
    /// Backing mental model id (pages only).
    public var mentalModelId: String?
    /// Client-set flag: true = system-owned, false = hand-authored.
    public var managed: Bool
    /// Page source query (the page's `description`).
    public var `description`: String?
    public var tags: [String]
    /// Last refresh (page) or last update (folder).
    public var timestamp: String?
    /// Pages only, populated by the tree endpoint. True when a memory in *this page's* scope — its tags and fact types — has been written since the
    public var isStale: Bool?
    /// Pages only: when this page's most recent refresh failed, in ISO format, or null when the last one succeeded. While it is set the page does n
    public var lastRefreshFailedAt: String?
    /// Pages only: the page's refresh settings — when it rebuilds itself (`refresh_after_consolidation` or `refresh_cron`, plus any `full_refresh_c
    public var trigger: MentalModelTriggerOutput?
    public var children: [KnowledgeNode]

    public init(id: String, kind: String, name: String, parentId: String? = nil, mentalModelId: String? = nil, managed: Bool = false, `description`: String? = nil, tags: [String] = [], timestamp: String? = nil, isStale: Bool? = nil, lastRefreshFailedAt: String? = nil, trigger: MentalModelTriggerOutput? = nil, children: [KnowledgeNode] = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parentId = parentId
        self.mentalModelId = mentalModelId
        self.managed = managed
        self.`description` = `description`
        self.tags = tags
        self.timestamp = timestamp
        self.isStale = isStale
        self.lastRefreshFailedAt = lastRefreshFailedAt
        self.trigger = trigger
        self.children = children
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case parentId = "parent_id"
        case mentalModelId = "mental_model_id"
        case managed
        case `description`
        case tags
        case timestamp
        case isStale = "is_stale"
        case lastRefreshFailedAt = "last_refresh_failed_at"
        case trigger
        case children
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.name = try c.decode(String.self, forKey: .name)
        self.parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        self.mentalModelId = try c.decodeIfPresent(String.self, forKey: .mentalModelId)
        self.managed = try c.decodeIfPresent(Bool.self, forKey: .managed) ?? false
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        self.isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale)
        self.lastRefreshFailedAt = try c.decodeIfPresent(String.self, forKey: .lastRefreshFailedAt)
        self.trigger = try c.decodeIfPresent(MentalModelTriggerOutput.self, forKey: .trigger)
        self.children = try c.decodeIfPresent([KnowledgeNode].self, forKey: .children) ?? []
    }
}

/// One file in a portable markdown bundle.
public struct KnowledgePageBundleFile: Codable, Sendable, Hashable {
    public var path: String
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case path
        case content
    }
}

/// A portable markdown bundle — a flat set of markdown files (index + pages + logs).
public struct KnowledgePageBundleResponse: Codable, Sendable, Hashable {
    public var files: [KnowledgePageBundleFile]

    public init(files: [KnowledgePageBundleFile]) {
        self.files = files
    }

    enum CodingKeys: String, CodingKey {
        case files
    }
}

/// A knowledge page rendered as a markdown document.
public struct KnowledgePageResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Page type — from a `type:<x>` tag, else 'knowledge-page'.
    public var type: String
    /// The source query that rebuilds the page.
    public var `description`: String?
    public var tags: [String]
    /// Last refresh time (falls back to creation).
    public var timestamp: String?
    /// The page's synthesized markdown body, exactly as stored. Empty until a refresh writes one — unlike `markdown`, which says so in words. Build
    public var body: String?
    /// The full markdown document: YAML frontmatter + markdown body. A page with no body yet renders 'No content yet.' as its body rather than fron
    public var markdown: String

    public init(id: String, name: String, type: String, `description`: String? = nil, tags: [String] = [], timestamp: String? = nil, body: String? = nil, markdown: String) {
        self.id = id
        self.name = name
        self.type = type
        self.`description` = `description`
        self.tags = tags
        self.timestamp = timestamp
        self.body = body
        self.markdown = markdown
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case `description`
        case tags
        case timestamp
        case body
        case markdown
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(String.self, forKey: .type)
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.markdown = try c.decode(String.self, forKey: .markdown)
    }
}

/// Ranked knowledge-page search results (BM25 + vector, RRF-fused).
public struct KnowledgePageSearchResponse: Codable, Sendable, Hashable {
    public var results: [KnowledgePageSearchResult]
    public var total: Int

    public init(results: [KnowledgePageSearchResult], total: Int) {
        self.results = results
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case results
        case total
    }
}

/// One hybrid-search hit: a knowledge page and its fused relevance score.
public struct KnowledgePageSearchResult: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var mentalModelId: String?
    /// The question the page answers.
    public var sourceQuery: String?
    /// The page's opening text. A page whose body is still empty says so in words — 'No content yet.' — rather than coming back blank, so a caller
    public var snippet: String
    /// Rank-fusion score in 0..1, where 1.0 means every search arm placed this page first. It reflects where the page ranked for this query, not ho
    public var score: Double
    public var updatedAt: String?

    public init(id: String, name: String, mentalModelId: String? = nil, sourceQuery: String? = nil, snippet: String, score: Double, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.mentalModelId = mentalModelId
        self.sourceQuery = sourceQuery
        self.snippet = snippet
        self.score = score
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mentalModelId = "mental_model_id"
        case sourceQuery = "source_query"
        case snippet
        case score
        case updatedAt = "updated_at"
    }
}

/// The knowledge base as a nested folder/page tree.
public struct KnowledgeTreeResponse: Codable, Sendable, Hashable {
    public var roots: [KnowledgeNode]

    public init(roots: [KnowledgeNode]) {
        self.roots = roots
    }

    enum CodingKeys: String, CodingKey {
        case roots
    }
}

/// A single LLM call made during reflect.
public struct LLMCallTrace: Codable, Sendable, Hashable {
    /// Call scope: agent_1, agent_2, final, etc.
    public var scope: String
    /// Execution time in milliseconds
    public var durationMs: Int

    public init(scope: String, durationMs: Int) {
        self.scope = scope
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case durationMs = "duration_ms"
    }
}

/// A single LLM request trace row, as returned by the read API.
public struct LLMRequestEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bankId: String?
    public var operation: String?
    public var scope: String?
    public var traceId: String?
    public var spanId: String?
    public var parentSpanId: String?
    public var provider: String?
    public var model: String?
    public var status: String
    public var startedAt: String?
    public var endedAt: String?
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var thoughtsTokens: Int?
    public var totalTokens: Int?
    public var input: JSONValue?
    public var output: JSONValue?
    public var error: String?
    public var llmInfo: [String: JSONValue]
    public var metadata: [String: JSONValue]

    public init(id: String, bankId: String? = nil, operation: String? = nil, scope: String? = nil, traceId: String? = nil, spanId: String? = nil, parentSpanId: String? = nil, provider: String? = nil, model: String? = nil, status: String, startedAt: String? = nil, endedAt: String? = nil, durationMs: Int? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, cachedTokens: Int? = nil, thoughtsTokens: Int? = nil, totalTokens: Int? = nil, input: JSONValue? = nil, output: JSONValue? = nil, error: String? = nil, llmInfo: [String: JSONValue], metadata: [String: JSONValue]) {
        self.id = id
        self.bankId = bankId
        self.operation = operation
        self.scope = scope
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.provider = provider
        self.model = model
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.thoughtsTokens = thoughtsTokens
        self.totalTokens = totalTokens
        self.input = input
        self.output = output
        self.error = error
        self.llmInfo = llmInfo
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case operation
        case scope
        case traceId = "trace_id"
        case spanId = "span_id"
        case parentSpanId = "parent_span_id"
        case provider
        case model
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cachedTokens = "cached_tokens"
        case thoughtsTokens = "thoughts_tokens"
        case totalTokens = "total_tokens"
        case input
        case output
        case error
        case llmInfo = "llm_info"
        case metadata
    }
}

/// Paginated list of LLM request traces for a bank.
public struct LLMRequestListResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var total: Int
    public var limit: Int
    public var offset: Int
    public var items: [LLMRequestEntry]
    public var retentionDays: Int?

    public init(bankId: String, total: Int, limit: Int, offset: Int, items: [LLMRequestEntry], retentionDays: Int? = nil) {
        self.bankId = bankId
        self.total = total
        self.limit = limit
        self.offset = offset
        self.items = items
        self.retentionDays = retentionDays
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case total
        case limit
        case offset
        case items
        case retentionDays = "retention_days"
    }
}

/// Calls and tokens (total + reasoning) of one model or operation within a time bucket.
public struct LLMRequestSeriesSums: Codable, Sendable, Hashable {
    public var calls: Int
    public var tokens: Int

    public init(calls: Int, tokens: Int) {
        self.calls = calls
        self.tokens = tokens
    }

    enum CodingKeys: String, CodingKey {
        case calls
        case tokens
    }
}

/// A single time bucket in LLM request stats.
public struct LLMRequestStatsBucket: Codable, Sendable, Hashable {
    public var time: String
    public var statuses: [String: Int]
    public var total: Int
    public var tokens: LLMRequestTokenSums
    public var series: [String: LLMRequestSeriesSums]?

    public init(time: String, statuses: [String: Int], total: Int, tokens: LLMRequestTokenSums, series: [String: LLMRequestSeriesSums]? = nil) {
        self.time = time
        self.statuses = statuses
        self.total = total
        self.tokens = tokens
        self.series = series
    }

    enum CodingKeys: String, CodingKey {
        case time
        case statuses
        case total
        case tokens
        case series
    }
}

/// LLM request counts and token sums grouped by time bucket.
public struct LLMRequestStatsResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var period: String
    public var trunc: String
    public var start: String
    public var buckets: [LLMRequestStatsBucket]
    public var retentionDays: Int?

    public init(bankId: String, period: String, trunc: String, start: String, buckets: [LLMRequestStatsBucket], retentionDays: Int? = nil) {
        self.bankId = bankId
        self.period = period
        self.trunc = trunc
        self.start = start
        self.buckets = buckets
        self.retentionDays = retentionDays
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case period
        case trunc
        case start
        case buckets
        case retentionDays = "retention_days"
    }
}

/// Token totals for a time bucket.
public struct LLMRequestTokenSums: Codable, Sendable, Hashable {
    public var input: Int
    public var output: Int
    public var cached: Int
    public var thoughts: Int?
    public var total: Int

    public init(input: Int, output: Int, cached: Int, thoughts: Int? = nil, total: Int) {
        self.input = input
        self.output = output
        self.cached = cached
        self.thoughts = thoughts
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cached
        case thoughts
        case total
    }
}

/// A label group (dimension) with its type and allowed values.
public struct LabelGroupInput: Codable, Sendable, Hashable {
    public var key: String
    public var `description`: String
    public var type: String
    public var optional: Bool
    public var tag: Bool
    public var values: [LabelValue]
    public var fields: [String: MapFieldInput]

    public init(key: String, `description`: String = "", type: String = "value", optional: Bool = true, tag: Bool = false, values: [LabelValue] = [], fields: [String: MapFieldInput] = [:]) {
        self.key = key
        self.`description` = `description`
        self.type = type
        self.optional = optional
        self.tag = tag
        self.values = values
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case key
        case `description`
        case type
        case optional
        case tag
        case values
        case fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try c.decode(String.self, forKey: .key)
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`) ?? ""
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "value"
        self.optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? true
        self.tag = try c.decodeIfPresent(Bool.self, forKey: .tag) ?? false
        self.values = try c.decodeIfPresent([LabelValue].self, forKey: .values) ?? []
        self.fields = try c.decodeIfPresent([String: MapFieldInput].self, forKey: .fields) ?? [:]
    }
}

/// A label group (dimension) with its type and allowed values.
public struct LabelGroupOutput: Codable, Sendable, Hashable {
    public var key: String
    public var `description`: String
    public var type: String
    public var optional: Bool
    public var tag: Bool
    public var values: [LabelValue]
    public var fields: [String: MapFieldOutput]

    public init(key: String, `description`: String = "", type: String = "value", optional: Bool = true, tag: Bool = false, values: [LabelValue] = [], fields: [String: MapFieldOutput] = [:]) {
        self.key = key
        self.`description` = `description`
        self.type = type
        self.optional = optional
        self.tag = tag
        self.values = values
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case key
        case `description`
        case type
        case optional
        case tag
        case values
        case fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try c.decode(String.self, forKey: .key)
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`) ?? ""
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "value"
        self.optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? true
        self.tag = try c.decodeIfPresent(Bool.self, forKey: .tag) ?? false
        self.values = try c.decodeIfPresent([LabelValue].self, forKey: .values) ?? []
        self.fields = try c.decodeIfPresent([String: MapFieldOutput].self, forKey: .fields) ?? [:]
    }
}

/// A single allowed value for a label group.
public struct LabelValue: Codable, Sendable, Hashable {
    public var value: String
    public var `description`: String

    public init(value: String, `description`: String = "") {
        self.value = value
        self.`description` = `description`
    }

    enum CodingKeys: String, CodingKey {
        case value
        case `description`
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try c.decode(String.self, forKey: .value)
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`) ?? ""
    }
}

/// Response model for listing chunks of a document.
public struct ListChunksResponse: Codable, Sendable, Hashable {
    public var items: [ChunkResponse]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(items: [ChunkResponse], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// Response model for list documents endpoint.
public struct ListDocumentsResponse: Codable, Sendable, Hashable {
    public var items: [DocumentListItem]
    public var total: Int
    public var limit: Int
    public var offset: Int
    /// True when a `q` search stopped at its match cap, so `total` is a lower bound rather than an exact count. Always false without `q`.
    public var totalIsEstimate: Bool

    public init(items: [DocumentListItem], total: Int, limit: Int, offset: Int, totalIsEstimate: Bool = false) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
        self.totalIsEstimate = totalIsEstimate
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
        case totalIsEstimate = "total_is_estimate"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decode([DocumentListItem].self, forKey: .items)
        self.total = try c.decode(Int.self, forKey: .total)
        self.limit = try c.decode(Int.self, forKey: .limit)
        self.offset = try c.decode(Int.self, forKey: .offset)
        self.totalIsEstimate = try c.decodeIfPresent(Bool.self, forKey: .totalIsEstimate) ?? false
    }
}

/// Response model for list memory units endpoint.
public struct ListMemoryUnitsResponse: Codable, Sendable, Hashable {
    public var items: [MemoryUnitListItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(items: [MemoryUnitListItem], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// Response model for list tags endpoint.
public struct ListTagsResponse: Codable, Sendable, Hashable {
    public var items: [TagItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(items: [TagItem], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// Payload for the API's DB-free liveness probe.
public struct LivenessResponse: Codable, Sendable, Hashable {
    /// Always "alive" — reaching this handler is the check
    public var status: String
    /// Hindsight version this process is running
    public var version: String
    /// Seconds since the process started
    public var uptimeSeconds: Double

    public init(status: String, version: String, uptimeSeconds: Double) {
        self.status = status
        self.version = version
        self.uptimeSeconds = uptimeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case uptimeSeconds = "uptime_seconds"
    }
}

/// LLM connectivity status for a single operation. Status only — no provider/model/
public struct LlmOperationHealth: Codable, Sendable, Hashable {
    /// Operation whose LLM was probed
    public var operation: String
    /// True only when the probe connected successfully
    public var ok: Bool
    /// 'connected'; 'not_configured' (provider is 'none'); 'auth_failed' (rejected — usually a wrong/expired API key); 'unreachable' (call failed);
    public var status: String
    /// Round-trip latency of the probe call
    public var latencyMs: Double?

    public init(operation: String, ok: Bool, status: String, latencyMs: Double? = nil) {
        self.operation = operation
        self.ok = ok
        self.status = status
        self.latencyMs = latencyMs
    }

    enum CodingKeys: String, CodingKey {
        case operation
        case ok
        case status
        case latencyMs = "latency_ms"
    }
}

/// A field within a map-type entity label group. Supports recursion via type='map'.
public struct MapFieldInput: Codable, Sendable, Hashable {
    public var type: String
    public var `description`: String
    public var values: [LabelValue]
    public var fields: [String: MapFieldInput]

    public init(type: String = "text", `description`: String = "", values: [LabelValue] = [], fields: [String: MapFieldInput] = [:]) {
        self.type = type
        self.`description` = `description`
        self.values = values
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case type
        case `description`
        case values
        case fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`) ?? ""
        self.values = try c.decodeIfPresent([LabelValue].self, forKey: .values) ?? []
        self.fields = try c.decodeIfPresent([String: MapFieldInput].self, forKey: .fields) ?? [:]
    }
}

/// A field within a map-type entity label group. Supports recursion via type='map'.
public struct MapFieldOutput: Codable, Sendable, Hashable {
    public var type: String
    public var `description`: String
    public var values: [LabelValue]
    public var fields: [String: MapFieldOutput]

    public init(type: String = "text", `description`: String = "", values: [LabelValue] = [], fields: [String: MapFieldOutput] = [:]) {
        self.type = type
        self.`description` = `description`
        self.values = values
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case type
        case `description`
        case values
        case fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        self.`description` = try c.decodeIfPresent(String.self, forKey: .`description`) ?? ""
        self.values = try c.decodeIfPresent([LabelValue].self, forKey: .values) ?? []
        self.fields = try c.decodeIfPresent([String: MapFieldOutput].self, forKey: .fields) ?? [:]
    }
}

/// Time-series of memory ingestion bucketed by time and fact type.
public struct MemoriesTimeseriesResponse: Codable, Sendable, Hashable {
    public var bankId: String
    /// One of: 1h, 12h, 1d, 7d, 30d, 90d.
    public var period: String
    /// Bucket granularity: minute, hour, day.
    public var trunc: String
    /// Timestamp column used to assign each row to a bucket. `created_at` shows ingest time; `mentioned_at` / `occurred_start` show event time (fal
    public var timeField: String
    /// Per-bucket counts, always returned fully padded for the requested period.
    public var buckets: [MemoryTimeseriesBucket]?

    public init(bankId: String, period: String, trunc: String, timeField: String = "created_at", buckets: [MemoryTimeseriesBucket]? = nil) {
        self.bankId = bankId
        self.period = period
        self.trunc = trunc
        self.timeField = timeField
        self.buckets = buckets
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case period
        case trunc
        case timeField = "time_field"
        case buckets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.period = try c.decode(String.self, forKey: .period)
        self.trunc = try c.decode(String.self, forKey: .trunc)
        self.timeField = try c.decodeIfPresent(String.self, forKey: .timeField) ?? "created_at"
        self.buckets = try c.decodeIfPresent([MemoryTimeseriesBucket].self, forKey: .buckets)
    }
}

/// An edge between two memory units, in the Cytoscape ``{"data": {...}}`` envelope.
public struct MemoryGraphEdge: Codable, Sendable, Hashable {
    public var data: MemoryGraphEdgeData

    public init(data: MemoryGraphEdgeData) {
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

/// The payload of one edge between two memory units.
public struct MemoryGraphEdgeData: Codable, Sendable, Hashable, Identifiable {
    /// Edge ID (``<source>-<target>-<linkType>``)
    public var id: String
    /// Source memory unit ID
    public var source: String
    /// Target memory unit ID
    public var target: String
    /// Link kind: 'entity', 'semantic', 'temporal', ...
    public var linkType: String
    /// Link strength
    public var weight: Double
    /// Shared entity for an 'entity' link, empty otherwise
    public var entityName: String
    /// Suggested edge colour for rendering
    public var color: String?
    /// Suggested edge line style for rendering
    public var lineStyle: String?

    public init(id: String, source: String, target: String, linkType: String = "", weight: Double = 0.0, entityName: String = "", color: String? = nil, lineStyle: String? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.linkType = linkType
        self.weight = weight
        self.entityName = entityName
        self.color = color
        self.lineStyle = lineStyle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case target
        case linkType
        case weight
        case entityName
        case color
        case lineStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.source = try c.decode(String.self, forKey: .source)
        self.target = try c.decode(String.self, forKey: .target)
        self.linkType = try c.decodeIfPresent(String.self, forKey: .linkType) ?? ""
        self.weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 0.0
        self.entityName = try c.decodeIfPresent(String.self, forKey: .entityName) ?? ""
        self.color = try c.decodeIfPresent(String.self, forKey: .color)
        self.lineStyle = try c.decodeIfPresent(String.self, forKey: .lineStyle)
    }
}

/// A memory-unit node, in the Cytoscape ``{"data": {...}}`` envelope the graph uses.
public struct MemoryGraphNode: Codable, Sendable, Hashable {
    public var data: MemoryGraphNodeData

    public init(data: MemoryGraphNodeData) {
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

/// The payload of one memory-unit node in the memory graph.
public struct MemoryGraphNodeData: Codable, Sendable, Hashable, Identifiable {
    /// Memory unit ID
    public var id: String
    /// Short display label (the text, truncated)
    public var label: String
    /// Full memory unit text
    public var text: String
    /// Event date (ISO 8601), empty when unknown
    public var date: String
    /// Context the memory was captured in
    public var context: String
    /// Comma-separated entity names, 'None' when there are none
    public var entities: String
    /// Suggested node colour for rendering
    public var color: String?

    public init(id: String, label: String = "", text: String = "", date: String = "", context: String = "", entities: String = "", color: String? = nil) {
        self.id = id
        self.label = label
        self.text = text
        self.date = date
        self.context = context
        self.entities = entities
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case text
        case date
        case context
        case entities
        case color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        self.entities = try c.decodeIfPresent(String.self, forKey: .entities) ?? ""
        self.color = try c.decodeIfPresent(String.self, forKey: .color)
    }
}

/// One row of the flat table view that accompanies the memory graph.
public struct MemoryGraphTableRow: Codable, Sendable, Hashable, Identifiable {
    /// Memory unit ID
    public var id: String
    /// Memory unit text
    public var text: String
    /// Context the memory was captured in ('N/A' when absent)
    public var context: String
    /// Start of the event interval (ISO 8601)
    public var occurredStart: String?
    /// End of the event interval (ISO 8601)
    public var occurredEnd: String?
    /// When the memory was mentioned (ISO 8601)
    public var mentionedAt: String?
    /// Deprecated: formatted event date, kept for backwards compatibility
    public var date: String?
    /// Comma-separated entity names, 'None' when there are none
    public var entities: String
    /// Source document ID
    public var documentId: String?
    /// Source chunk ID
    public var chunkId: String?
    /// Fact type: world, experience or observation
    public var factType: String?
    /// Tags on this memory unit
    public var tags: [String]
    /// When the memory unit was created (ISO 8601)
    public var createdAt: String?
    /// How many times the fact was independently seen
    public var proofCount: Int?

    public init(id: String, text: String = "", context: String = "", occurredStart: String? = nil, occurredEnd: String? = nil, mentionedAt: String? = nil, date: String? = nil, entities: String = "", documentId: String? = nil, chunkId: String? = nil, factType: String? = nil, tags: [String] = [], createdAt: String? = nil, proofCount: Int? = nil) {
        self.id = id
        self.text = text
        self.context = context
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.mentionedAt = mentionedAt
        self.date = date
        self.entities = entities
        self.documentId = documentId
        self.chunkId = chunkId
        self.factType = factType
        self.tags = tags
        self.createdAt = createdAt
        self.proofCount = proofCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case context
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case mentionedAt = "mentioned_at"
        case date
        case entities
        case documentId = "document_id"
        case chunkId = "chunk_id"
        case factType = "fact_type"
        case tags
        case createdAt = "created_at"
        case proofCount = "proof_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        self.occurredStart = try c.decodeIfPresent(String.self, forKey: .occurredStart)
        self.occurredEnd = try c.decodeIfPresent(String.self, forKey: .occurredEnd)
        self.mentionedAt = try c.decodeIfPresent(String.self, forKey: .mentionedAt)
        self.date = try c.decodeIfPresent(String.self, forKey: .date)
        self.entities = try c.decodeIfPresent(String.self, forKey: .entities) ?? ""
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId)
        self.chunkId = try c.decodeIfPresent(String.self, forKey: .chunkId)
        self.factType = try c.decodeIfPresent(String.self, forKey: .factType)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.proofCount = try c.decodeIfPresent(Int.self, forKey: .proofCount)
    }
}

/// Single memory item for retain.
public struct MemoryItem: Codable, Sendable, Hashable {
    /// The raw content to retain. Either a plain string, or an ordered list of content blocks so images sit inline where they actually appear:
    public var content: HSContent
    /// When the content occurred. Accepts an ISO 8601 datetime string (e.g. '2024-01-15T10:30:00Z'), null/omitted (defaults to now), or the special
    public var timestamp: JSONValue?
    public var context: String?
    public var metadata: [String: String]?
    /// Optional document ID for this memory item. Provide a distinct document_id per source document — items sharing a document_id are grouped into
    public var documentId: String?
    /// Optional entities to combine with auto-extracted entities.
    public var entities: [EntityInput]?
    /// Whether the names in 'entities' are resolved against the entities already in the bank. True (default) matches each name to a similar existin
    public var resolveEntities: Bool
    /// Optional tags for visibility scoping. Memories with tags can be filtered during recall.
    public var tags: [String]?
    /// How to scope observations during consolidation. 'per_tag' runs one consolidation pass per individual tag, creating separate observations for
    public var observationScopes: JSONValue?
    /// Named retain strategy for this item. Overrides the bank's default strategy for this item only. Strategies are defined in the bank config und
    public var strategy: String?
    /// How to handle an existing document with the same document_id. 'replace' (default) deletes old data and reprocesses from scratch. 'append' co
    public var updateMode: String?

    public init(content: HSContent, timestamp: JSONValue? = nil, context: String? = nil, metadata: [String: String]? = nil, documentId: String? = nil, entities: [EntityInput]? = nil, resolveEntities: Bool = true, tags: [String]? = nil, observationScopes: JSONValue? = nil, strategy: String? = nil, updateMode: String? = nil) {
        self.content = content
        self.timestamp = timestamp
        self.context = context
        self.metadata = metadata
        self.documentId = documentId
        self.entities = entities
        self.resolveEntities = resolveEntities
        self.tags = tags
        self.observationScopes = observationScopes
        self.strategy = strategy
        self.updateMode = updateMode
    }

    enum CodingKeys: String, CodingKey {
        case content
        case timestamp
        case context
        case metadata
        case documentId = "document_id"
        case entities
        case resolveEntities = "resolve_entities"
        case tags
        case observationScopes = "observation_scopes"
        case strategy
        case updateMode = "update_mode"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(HSContent.self, forKey: .content)
        self.timestamp = try c.decodeIfPresent(JSONValue.self, forKey: .timestamp)
        self.context = try c.decodeIfPresent(String.self, forKey: .context)
        self.metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata)
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId)
        self.entities = try c.decodeIfPresent([EntityInput].self, forKey: .entities)
        self.resolveEntities = try c.decodeIfPresent(Bool.self, forKey: .resolveEntities) ?? true
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.observationScopes = try c.decodeIfPresent(JSONValue.self, forKey: .observationScopes)
        self.strategy = try c.decodeIfPresent(String.self, forKey: .strategy)
        self.updateMode = try c.decodeIfPresent(String.self, forKey: .updateMode)
    }
}

/// One bucket in the memory ingestion time-series.
public struct MemoryTimeseriesBucket: Codable, Sendable, Hashable {
    /// Bucket start timestamp in ISO-8601 (UTC).
    public var time: String
    /// World-fact memories ingested in this bucket.
    public var world: Int
    /// Experience memories ingested in this bucket.
    public var experience: Int
    /// Observations recorded in this bucket.
    public var observation: Int

    public init(time: String, world: Int = 0, experience: Int = 0, observation: Int = 0) {
        self.time = time
        self.world = world
        self.experience = experience
        self.observation = observation
    }

    enum CodingKeys: String, CodingKey {
        case time
        case world
        case experience
        case observation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.time = try c.decode(String.self, forKey: .time)
        self.world = try c.decodeIfPresent(Int.self, forKey: .world) ?? 0
        self.experience = try c.decodeIfPresent(Int.self, forKey: .experience) ?? 0
        self.observation = try c.decodeIfPresent(Int.self, forKey: .observation) ?? 0
    }
}

/// One row of the memory-unit listing.
public struct MemoryUnitListItem: Codable, Sendable, Hashable, Identifiable {
    /// Memory unit ID
    public var id: String
    /// The fact text
    public var text: String
    /// Context the memory was captured in
    public var context: String
    /// Event date (ISO 8601), empty when unknown
    public var date: String
    /// Fact type: world, experience or observation
    public var factType: String?
    /// Source document ID
    public var documentId: String?
    /// When the memory was mentioned (ISO 8601)
    public var mentionedAt: String?
    /// Start of the event interval (ISO 8601)
    public var occurredStart: String?
    /// End of the event interval (ISO 8601)
    public var occurredEnd: String?
    /// Comma-separated canonical entity names
    public var entities: String
    /// Source chunk ID
    public var chunkId: String?
    /// How many times the fact was independently seen
    public var proofCount: Int
    /// Tags on this memory unit
    public var tags: [String]
    /// Arbitrary metadata stored with the memory
    public var metadata: [String: JSONValue]
    /// When consolidation last succeeded (ISO 8601)
    public var consolidatedAt: String?
    /// When consolidation last failed permanently (ISO 8601)
    public var consolidationFailedAt: String?
    /// Curation state: 'valid' or 'invalidated'
    public var state: String
    /// Why the fact was invalidated, if it was
    public var invalidationReason: String?
    /// When the fact was invalidated (ISO 8601)
    public var invalidatedAt: String?
    /// When the fact was last edited by hand (ISO 8601)
    public var editedAt: String?
    /// Write watermark for this row (ISO 8601)
    public var updatedAt: String?
    /// An observation's source facts; empty for a source fact
    public var sourceMemoryIds: [String]

    public init(id: String, text: String = "", context: String = "", date: String = "", factType: String? = nil, documentId: String? = nil, mentionedAt: String? = nil, occurredStart: String? = nil, occurredEnd: String? = nil, entities: String = "", chunkId: String? = nil, proofCount: Int = 1, tags: [String] = [], metadata: [String: JSONValue] = [:], consolidatedAt: String? = nil, consolidationFailedAt: String? = nil, state: String = "valid", invalidationReason: String? = nil, invalidatedAt: String? = nil, editedAt: String? = nil, updatedAt: String? = nil, sourceMemoryIds: [String] = []) {
        self.id = id
        self.text = text
        self.context = context
        self.date = date
        self.factType = factType
        self.documentId = documentId
        self.mentionedAt = mentionedAt
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.entities = entities
        self.chunkId = chunkId
        self.proofCount = proofCount
        self.tags = tags
        self.metadata = metadata
        self.consolidatedAt = consolidatedAt
        self.consolidationFailedAt = consolidationFailedAt
        self.state = state
        self.invalidationReason = invalidationReason
        self.invalidatedAt = invalidatedAt
        self.editedAt = editedAt
        self.updatedAt = updatedAt
        self.sourceMemoryIds = sourceMemoryIds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case context
        case date
        case factType = "fact_type"
        case documentId = "document_id"
        case mentionedAt = "mentioned_at"
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case entities
        case chunkId = "chunk_id"
        case proofCount = "proof_count"
        case tags
        case metadata
        case consolidatedAt = "consolidated_at"
        case consolidationFailedAt = "consolidation_failed_at"
        case state
        case invalidationReason = "invalidation_reason"
        case invalidatedAt = "invalidated_at"
        case editedAt = "edited_at"
        case updatedAt = "updated_at"
        case sourceMemoryIds = "source_memory_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        self.date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.factType = try c.decodeIfPresent(String.self, forKey: .factType)
        self.documentId = try c.decodeIfPresent(String.self, forKey: .documentId)
        self.mentionedAt = try c.decodeIfPresent(String.self, forKey: .mentionedAt)
        self.occurredStart = try c.decodeIfPresent(String.self, forKey: .occurredStart)
        self.occurredEnd = try c.decodeIfPresent(String.self, forKey: .occurredEnd)
        self.entities = try c.decodeIfPresent(String.self, forKey: .entities) ?? ""
        self.chunkId = try c.decodeIfPresent(String.self, forKey: .chunkId)
        self.proofCount = try c.decodeIfPresent(Int.self, forKey: .proofCount) ?? 1
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.metadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .metadata) ?? [:]
        self.consolidatedAt = try c.decodeIfPresent(String.self, forKey: .consolidatedAt)
        self.consolidationFailedAt = try c.decodeIfPresent(String.self, forKey: .consolidationFailedAt)
        self.state = try c.decodeIfPresent(String.self, forKey: .state) ?? "valid"
        self.invalidationReason = try c.decodeIfPresent(String.self, forKey: .invalidationReason)
        self.invalidatedAt = try c.decodeIfPresent(String.self, forKey: .invalidatedAt)
        self.editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt)
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        self.sourceMemoryIds = try c.decodeIfPresent([String].self, forKey: .sourceMemoryIds) ?? []
    }
}

/// Structured operations a delta refresh emitted against the existing document.
public struct MentalModelDeltaOperations: Codable, Sendable, Hashable {
    /// Operations applied to the document, in order.
    public var applied: [[String: JSONValue]]?
    /// Operations dropped as invalid, each with a reason.
    public var skipped: [[String: JSONValue]]?

    public init(applied: [[String: JSONValue]]? = nil, skipped: [[String: JSONValue]]? = nil) {
        self.applied = applied
        self.skipped = skipped
    }

    enum CodingKeys: String, CodingKey {
        case applied
        case skipped
    }
}

/// Preview of what a mental model refresh would do, having changed nothing.
public struct MentalModelDryRunRefreshResult: Codable, Sendable, Hashable {
    /// The mental model previewed.
    public var mentalModelId: String
    /// Display name of the mental model.
    public var name: String
    /// The mode asked for (from the model's trigger, or overridden).
    public var requestedMode: String
    /// The mode the refresh actually ran in.
    public var effectiveMode: String
    /// Why delta was requested but not applied, if that happened.
    public var modeFallbackReason: String?
    /// What a real refresh would do with the document.
    public var outcome: String
    /// Whether a real refresh would write new content.
    public var wouldPersist: Bool
    /// The resolved memory scope.
    public var scope: MentalModelRefreshScope
    /// The snapshot window read from.
    public var window: MentalModelRefreshWindow
    /// Facts retrieved versus actually used.
    public var facts: MentalModelFactCounts
    /// The evidence this run would ground the document on, keyed by fact type — the same shape a refresh persists under reflect_response.based_on.
    public var basedOn: [String: [[String: JSONValue]]]?
    /// The model's content as it stands now.
    public var currentContent: String
    /// Raw reflect synthesis, before any delta operations.
    public var candidateContent: String
    /// The content a real refresh would store: the delta-edited document, or the candidate in full mode.
    public var previewContent: String
    /// Unified diff from current_content to preview_content. Empty when identical.
    public var diff: String
    /// Structured operations emitted, in delta mode.
    public var deltaOperations: MentalModelDeltaOperations?
    /// Facts the document cites that no longer exist, and what a real refresh would do about them.
    public var retraction: MentalModelRetraction?
    /// Execution trace of the run, always included for a dry run.
    public var trace: MentalModelRefreshTrace
    /// Token usage across the run's LLM calls.
    public var usage: TokenUsage?
    /// Wall-clock duration of the run.
    public var durationMs: Int
    /// Conditions worth a human's attention, in plain language.
    public var warnings: [String]?

    public init(mentalModelId: String, name: String, requestedMode: String, effectiveMode: String, modeFallbackReason: String? = nil, outcome: String, wouldPersist: Bool, scope: MentalModelRefreshScope, window: MentalModelRefreshWindow, facts: MentalModelFactCounts, basedOn: [String: [[String: JSONValue]]]? = nil, currentContent: String, candidateContent: String, previewContent: String, diff: String, deltaOperations: MentalModelDeltaOperations? = nil, retraction: MentalModelRetraction? = nil, trace: MentalModelRefreshTrace, usage: TokenUsage? = nil, durationMs: Int = 0, warnings: [String]? = nil) {
        self.mentalModelId = mentalModelId
        self.name = name
        self.requestedMode = requestedMode
        self.effectiveMode = effectiveMode
        self.modeFallbackReason = modeFallbackReason
        self.outcome = outcome
        self.wouldPersist = wouldPersist
        self.scope = scope
        self.window = window
        self.facts = facts
        self.basedOn = basedOn
        self.currentContent = currentContent
        self.candidateContent = candidateContent
        self.previewContent = previewContent
        self.diff = diff
        self.deltaOperations = deltaOperations
        self.retraction = retraction
        self.trace = trace
        self.usage = usage
        self.durationMs = durationMs
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case mentalModelId = "mental_model_id"
        case name
        case requestedMode = "requested_mode"
        case effectiveMode = "effective_mode"
        case modeFallbackReason = "mode_fallback_reason"
        case outcome
        case wouldPersist = "would_persist"
        case scope
        case window
        case facts
        case basedOn = "based_on"
        case currentContent = "current_content"
        case candidateContent = "candidate_content"
        case previewContent = "preview_content"
        case diff
        case deltaOperations = "delta_operations"
        case retraction
        case trace
        case usage
        case durationMs = "duration_ms"
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mentalModelId = try c.decode(String.self, forKey: .mentalModelId)
        self.name = try c.decode(String.self, forKey: .name)
        self.requestedMode = try c.decode(String.self, forKey: .requestedMode)
        self.effectiveMode = try c.decode(String.self, forKey: .effectiveMode)
        self.modeFallbackReason = try c.decodeIfPresent(String.self, forKey: .modeFallbackReason)
        self.outcome = try c.decode(String.self, forKey: .outcome)
        self.wouldPersist = try c.decode(Bool.self, forKey: .wouldPersist)
        self.scope = try c.decode(MentalModelRefreshScope.self, forKey: .scope)
        self.window = try c.decode(MentalModelRefreshWindow.self, forKey: .window)
        self.facts = try c.decode(MentalModelFactCounts.self, forKey: .facts)
        self.basedOn = try c.decodeIfPresent([String: [[String: JSONValue]]].self, forKey: .basedOn)
        self.currentContent = try c.decode(String.self, forKey: .currentContent)
        self.candidateContent = try c.decode(String.self, forKey: .candidateContent)
        self.previewContent = try c.decode(String.self, forKey: .previewContent)
        self.diff = try c.decode(String.self, forKey: .diff)
        self.deltaOperations = try c.decodeIfPresent(MentalModelDeltaOperations.self, forKey: .deltaOperations)
        self.retraction = try c.decodeIfPresent(MentalModelRetraction.self, forKey: .retraction)
        self.trace = try c.decode(MentalModelRefreshTrace.self, forKey: .trace)
        self.usage = try c.decodeIfPresent(TokenUsage.self, forKey: .usage)
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        self.warnings = try c.decodeIfPresent([String].self, forKey: .warnings)
    }
}

/// Facts the refresh saw, keyed by fact type.
public struct MentalModelFactCounts: Codable, Sendable, Hashable {
    /// Facts the reflect agent's tool calls returned, by fact type.
    public var retrieved: [String: Int]?
    /// Facts the agent declared it actually based the answer on, by fact type.
    public var used: [String: Int]?

    public init(retrieved: [String: Int]? = nil, used: [String: Int]? = nil) {
        self.retrieved = retrieved
        self.used = used
    }

    enum CodingKeys: String, CodingKey {
        case retrieved
        case used
    }
}

/// Response model for listing mental models.
public struct MentalModelListResponse: Codable, Sendable, Hashable {
    public var items: [MentalModelResponse]
    /// Total number of mental models matching the filter (not just this page)
    public var total: Int
    /// Page size that was applied
    public var limit: Int
    /// Offset that was applied
    public var offset: Int

    public init(items: [MentalModelResponse], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// The memory scope a refresh actually resolved to.
public struct MentalModelRefreshScope: Codable, Sendable, Hashable {
    /// Flat tags used to filter memories (null when unused).
    public var tags: [String]?
    /// Resolved tag match mode.
    public var tagsMatch: String
    /// Compound tag expressions used instead of flat tags, when set.
    public var tagGroups: [TagGroup]?
    /// Fact types retrieved (null means all).
    public var factTypes: [String]?
    /// Whether other mental models were excluded from the reflect loop.
    public var excludeMentalModels: Bool
    /// Mental models excluded by ID (always includes the model being refreshed).
    public var excludeMentalModelIds: [String]?

    public init(tags: [String]? = nil, tagsMatch: String, tagGroups: [TagGroup]? = nil, factTypes: [String]? = nil, excludeMentalModels: Bool, excludeMentalModelIds: [String]? = nil) {
        self.tags = tags
        self.tagsMatch = tagsMatch
        self.tagGroups = tagGroups
        self.factTypes = factTypes
        self.excludeMentalModels = excludeMentalModels
        self.excludeMentalModelIds = excludeMentalModelIds
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case tagsMatch = "tags_match"
        case tagGroups = "tag_groups"
        case factTypes = "fact_types"
        case excludeMentalModels = "exclude_mental_models"
        case excludeMentalModelIds = "exclude_mental_model_ids"
    }
}

/// Execution trace of a mental model refresh, recorded when trigger.keep_trace is on.
public struct MentalModelRefreshTrace: Codable, Sendable, Hashable {
    /// When this trace was recorded.
    public var recordedAt: String?
    /// Whether the refresh ran as full or delta.
    public var effectiveMode: String
    /// Why delta was requested but not applied, if that happened.
    public var modeFallbackReason: String?
    /// What the refresh did with the document.
    public var outcome: String
    /// Reflect tool calls made during the refresh.
    public var toolCalls: [MentalModelTraceToolCall]?
    /// LLM calls made during the refresh.
    public var llmCalls: [LLMCallTrace]?
    /// Structured operations emitted, in delta mode.
    public var deltaOperations: MentalModelDeltaOperations?
    /// Facts the document cited that no longer exist, when the refresh found any.
    public var retraction: MentalModelRetraction?
    /// Token usage across the refresh's LLM calls.
    public var usage: TokenUsage?
    /// Wall-clock duration of the refresh.
    public var durationMs: Int
    /// Conditions worth a human's attention, in plain language.
    public var warnings: [String]?

    public init(recordedAt: String? = nil, effectiveMode: String, modeFallbackReason: String? = nil, outcome: String, toolCalls: [MentalModelTraceToolCall]? = nil, llmCalls: [LLMCallTrace]? = nil, deltaOperations: MentalModelDeltaOperations? = nil, retraction: MentalModelRetraction? = nil, usage: TokenUsage? = nil, durationMs: Int = 0, warnings: [String]? = nil) {
        self.recordedAt = recordedAt
        self.effectiveMode = effectiveMode
        self.modeFallbackReason = modeFallbackReason
        self.outcome = outcome
        self.toolCalls = toolCalls
        self.llmCalls = llmCalls
        self.deltaOperations = deltaOperations
        self.retraction = retraction
        self.usage = usage
        self.durationMs = durationMs
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case effectiveMode = "effective_mode"
        case modeFallbackReason = "mode_fallback_reason"
        case outcome
        case toolCalls = "tool_calls"
        case llmCalls = "llm_calls"
        case deltaOperations = "delta_operations"
        case retraction
        case usage
        case durationMs = "duration_ms"
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.recordedAt = try c.decodeIfPresent(String.self, forKey: .recordedAt)
        self.effectiveMode = try c.decode(String.self, forKey: .effectiveMode)
        self.modeFallbackReason = try c.decodeIfPresent(String.self, forKey: .modeFallbackReason)
        self.outcome = try c.decode(String.self, forKey: .outcome)
        self.toolCalls = try c.decodeIfPresent([MentalModelTraceToolCall].self, forKey: .toolCalls)
        self.llmCalls = try c.decodeIfPresent([LLMCallTrace].self, forKey: .llmCalls)
        self.deltaOperations = try c.decodeIfPresent(MentalModelDeltaOperations.self, forKey: .deltaOperations)
        self.retraction = try c.decodeIfPresent(MentalModelRetraction.self, forKey: .retraction)
        self.usage = try c.decodeIfPresent(TokenUsage.self, forKey: .usage)
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        self.warnings = try c.decodeIfPresent([String].self, forKey: .warnings)
    }
}

/// The time window a refresh read memories from.
public struct MentalModelRefreshWindow: Codable, Sendable, Hashable {
    /// Lower bound on when a memory last changed. Set only in delta mode, where it is the model's last_memory_seen_at — so a delta refresh only see
    public var createdAfter: String?
    /// Database-time snapshot bounding the refresh. Memories written or edited after this are not read, so they stay newer than the persisted water
    public var createdBefore: String
    /// The last_memory_seen_at a real refresh would persist: the newest in-scope memory visible at the snapshot, not now(). Null means no in-scope
    public var watermark: String?

    public init(createdAfter: String? = nil, createdBefore: String, watermark: String? = nil) {
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.watermark = watermark
    }

    enum CodingKeys: String, CodingKey {
        case createdAfter = "created_after"
        case createdBefore = "created_before"
        case watermark
    }
}

/// Response model for a mental model (stored reflect response).
public struct MentalModelResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bankId: String
    public var name: String
    public var sourceQuery: String?
    /// The mental model content as well-formatted markdown (auto-generated from reflect endpoint)
    public var content: String?
    public var tags: [String]
    public var maxTokens: Int?
    public var trigger: MentalModelTriggerOutput?
    /// When a refresh last finished for this model — wall-clock, in ISO format. Advances on every refresh that completes, including one that found
    public var lastRefreshedAt: String?
    /// How far through the bank's memories this model is written — the newest in-scope memory the last refresh saw, in ISO format. Stands still whe
    public var lastMemorySeenAt: String?
    /// When this model's most recent refresh failed, in ISO format, or null when the last one succeeded. While this is set the automatic triggers (
    public var lastRefreshFailedAt: String?
    /// When a refresh last ran in full mode for this model, in ISO format — requested (`mode: 'full'`, a `full_refresh_cron` tick, a full-mode mode
    public var lastFullRefreshedAt: String?
    public var createdAt: String?
    /// True when this model holds a knowledge page's content rather than being a standalone mental model. Set by the list and get endpoints.
    public var isKnowledgePage: Bool?
    /// Full reflect API response payload including based_on facts and observations. On a single-model read, each world/experience/observation entry
    public var reflectResponse: [String: JSONValue]?
    /// True when memories matching this mental model's tag/fact_type scope have been written since last_memory_seen_at — the same check that decide
    public var isStale: Bool?

    public init(id: String, bankId: String, name: String, sourceQuery: String? = nil, content: String? = nil, tags: [String] = [], maxTokens: Int? = nil, trigger: MentalModelTriggerOutput? = nil, lastRefreshedAt: String? = nil, lastMemorySeenAt: String? = nil, lastRefreshFailedAt: String? = nil, lastFullRefreshedAt: String? = nil, createdAt: String? = nil, isKnowledgePage: Bool? = nil, reflectResponse: [String: JSONValue]? = nil, isStale: Bool? = nil) {
        self.id = id
        self.bankId = bankId
        self.name = name
        self.sourceQuery = sourceQuery
        self.content = content
        self.tags = tags
        self.maxTokens = maxTokens
        self.trigger = trigger
        self.lastRefreshedAt = lastRefreshedAt
        self.lastMemorySeenAt = lastMemorySeenAt
        self.lastRefreshFailedAt = lastRefreshFailedAt
        self.lastFullRefreshedAt = lastFullRefreshedAt
        self.createdAt = createdAt
        self.isKnowledgePage = isKnowledgePage
        self.reflectResponse = reflectResponse
        self.isStale = isStale
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case name
        case sourceQuery = "source_query"
        case content
        case tags
        case maxTokens = "max_tokens"
        case trigger
        case lastRefreshedAt = "last_refreshed_at"
        case lastMemorySeenAt = "last_memory_seen_at"
        case lastRefreshFailedAt = "last_refresh_failed_at"
        case lastFullRefreshedAt = "last_full_refreshed_at"
        case createdAt = "created_at"
        case isKnowledgePage = "is_knowledge_page"
        case reflectResponse = "reflect_response"
        case isStale = "is_stale"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.bankId = try c.decode(String.self, forKey: .bankId)
        self.name = try c.decode(String.self, forKey: .name)
        self.sourceQuery = try c.decodeIfPresent(String.self, forKey: .sourceQuery)
        self.content = try c.decodeIfPresent(String.self, forKey: .content)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        self.trigger = try c.decodeIfPresent(MentalModelTriggerOutput.self, forKey: .trigger)
        self.lastRefreshedAt = try c.decodeIfPresent(String.self, forKey: .lastRefreshedAt)
        self.lastMemorySeenAt = try c.decodeIfPresent(String.self, forKey: .lastMemorySeenAt)
        self.lastRefreshFailedAt = try c.decodeIfPresent(String.self, forKey: .lastRefreshFailedAt)
        self.lastFullRefreshedAt = try c.decodeIfPresent(String.self, forKey: .lastFullRefreshedAt)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.isKnowledgePage = try c.decodeIfPresent(Bool.self, forKey: .isKnowledgePage)
        self.reflectResponse = try c.decodeIfPresent([String: JSONValue].self, forKey: .reflectResponse)
        self.isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale)
    }
}

/// Facts the document cited that no longer exist, and what was done about them.
public struct MentalModelRetraction: Codable, Sendable, Hashable {
    /// Ids the document's based_on cites that no longer exist in the bank.
    public var factIds: [String]?
    /// What those facts said, as the document recorded them. The rows themselves are gone — an observation swept away with its source keeps no hist
    public var factTexts: [String]?
    /// Whether the pass that removes them ran to completion (zero edits still counts).
    public var applied: Bool
    /// Why removal was postponed, when it was. Re-ingested facts return under new ids once consolidation catches up, so a retraction seen while fac
    public var deferredReason: String?

    public init(factIds: [String]? = nil, factTexts: [String]? = nil, applied: Bool, deferredReason: String? = nil) {
        self.factIds = factIds
        self.factTexts = factTexts
        self.applied = applied
        self.deferredReason = deferredReason
    }

    enum CodingKeys: String, CodingKey {
        case factIds = "fact_ids"
        case factTexts = "fact_texts"
        case applied
        case deferredReason = "deferred_reason"
    }
}

/// One reflect tool call made during a refresh.
public struct MentalModelTraceToolCall: Codable, Sendable, Hashable {
    /// Tool name: recall, search_observations, get_mental_model, expand, …
    public var tool: String
    /// The agent's stated reason for the call.
    public var reason: String?
    /// Tool input parameters.
    public var input: [String: JSONValue]?
    /// What the tool returned. Present on a dry run, which stores nothing; omitted from the trace persisted by a real refresh to keep that row boun
    public var output: [String: JSONValue]?
    /// The refresh window's lower bound as given to this call — the delta watermark. Named for what it actually filters: the predicate is on the me
    public var updatedAt: String?
    /// Number of items the tool returned, when countable.
    public var resultCount: Int?
    /// Execution time in milliseconds.
    public var durationMs: Int
    /// Agent loop iteration (1-based) this call belongs to.
    public var iteration: Int

    public init(tool: String, reason: String? = nil, input: [String: JSONValue]? = nil, output: [String: JSONValue]? = nil, updatedAt: String? = nil, resultCount: Int? = nil, durationMs: Int, iteration: Int = 0) {
        self.tool = tool
        self.reason = reason
        self.input = input
        self.output = output
        self.updatedAt = updatedAt
        self.resultCount = resultCount
        self.durationMs = durationMs
        self.iteration = iteration
    }

    enum CodingKeys: String, CodingKey {
        case tool
        case reason
        case input
        case output
        case updatedAt = "updated_at"
        case resultCount = "result_count"
        case durationMs = "duration_ms"
        case iteration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tool = try c.decode(String.self, forKey: .tool)
        self.reason = try c.decodeIfPresent(String.self, forKey: .reason)
        self.input = try c.decodeIfPresent([String: JSONValue].self, forKey: .input)
        self.output = try c.decodeIfPresent([String: JSONValue].self, forKey: .output)
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        self.resultCount = try c.decodeIfPresent(Int.self, forKey: .resultCount)
        self.durationMs = try c.decode(Int.self, forKey: .durationMs)
        self.iteration = try c.decodeIfPresent(Int.self, forKey: .iteration) ?? 0
    }
}

/// Trigger settings for a mental model.
public struct MentalModelTriggerInput: Codable, Sendable, Hashable {
    /// How many agent iterations a refresh may spend, as a multiple of reflect_max_iterations: 'low' halves it, 'mid' keeps it, 'high' doubles it.
    public var budget: String?
    /// Refresh mode. 'full' (default) regenerates the mental model content from scratch on each refresh. 'delta' performs surgical edits against th
    public var mode: String
    /// If true, refresh this mental model after observations consolidation (real-time mode)
    public var refreshAfterConsolidation: Bool
    /// Cron expression (UTC, standard 5-field syntax, e.g. '0 3 * * *' for daily at 03:00 UTC) for refreshing this mental model on a fixed schedule
    public var refreshCron: String?
    /// Cron expression (UTC, standard 5-field syntax, e.g. '0 3 * * 0' for Sundays at 03:00 UTC) for a scheduled full refresh: on this schedule the
    public var fullRefreshCron: String?
    /// Minimum seconds between two automatic refreshes of this mental model. A triggered refresh that arrives sooner is not dropped: it is queued a
    public var minRefreshIntervalSeconds: Int?
    /// Filter which fact types are retrieved during reflect. None means all types (world, experience, observation).
    public var factTypes: [String]?
    /// If true, exclude all mental models from the reflect loop (skip search_mental_models tool).
    public var excludeMentalModels: Bool
    /// Exclude specific mental models by ID from the reflect loop.
    public var excludeMentalModelIds: [String]?
    /// Override how the model's tags filter memories during refresh. If not set, defaults to 'all_strict' when the model has tags (security isolati
    public var tagsMatch: String?
    /// Compound boolean tag expressions to use during refresh instead of the model's own tags. When set, these tag groups are passed to reflect and
    public var tagGroups: [TagGroup]?
    /// Override whether the internal recall used during refresh returns raw chunk text. None means use the bank/global config default (recall_inclu
    public var includeChunks: Bool?
    /// Override the token budget for facts returned by the internal recall during refresh. None means use the bank/global config default (recall_ma
    public var recallMaxTokens: Int?
    /// Override the token budget for raw chunks returned by the internal recall during refresh. None means use the bank/global config default (reca
    public var recallChunksMaxTokens: Int?
    /// Override the token budget for the refresh's search_observations calls. Observation evidence is often the largest contributor to the reflect
    public var reflectSearchObservationsMaxTokens: Int?
    /// Override whether search_observations attaches resolved entity names to each observation. Entities can be more than half the serialized tool
    public var reflectSearchObservationsIncludeEntities: Bool?
    /// Optional JSON Schema for structured output. When set, each refresh runs the same structured-output extraction as reflect's response_schema a
    public var responseSchema: [String: JSONValue]?
    /// If true, every refresh of this mental model records how it reached its result under reflect_response.trace: the mode it ran in and why, the
    public var keepTrace: Bool

    public init(budget: String? = nil, mode: String = "full", refreshAfterConsolidation: Bool = false, refreshCron: String? = nil, fullRefreshCron: String? = nil, minRefreshIntervalSeconds: Int? = nil, factTypes: [String]? = nil, excludeMentalModels: Bool = false, excludeMentalModelIds: [String]? = nil, tagsMatch: String? = nil, tagGroups: [TagGroup]? = nil, includeChunks: Bool? = nil, recallMaxTokens: Int? = nil, recallChunksMaxTokens: Int? = nil, reflectSearchObservationsMaxTokens: Int? = nil, reflectSearchObservationsIncludeEntities: Bool? = nil, responseSchema: [String: JSONValue]? = nil, keepTrace: Bool = false) {
        self.budget = budget
        self.mode = mode
        self.refreshAfterConsolidation = refreshAfterConsolidation
        self.refreshCron = refreshCron
        self.fullRefreshCron = fullRefreshCron
        self.minRefreshIntervalSeconds = minRefreshIntervalSeconds
        self.factTypes = factTypes
        self.excludeMentalModels = excludeMentalModels
        self.excludeMentalModelIds = excludeMentalModelIds
        self.tagsMatch = tagsMatch
        self.tagGroups = tagGroups
        self.includeChunks = includeChunks
        self.recallMaxTokens = recallMaxTokens
        self.recallChunksMaxTokens = recallChunksMaxTokens
        self.reflectSearchObservationsMaxTokens = reflectSearchObservationsMaxTokens
        self.reflectSearchObservationsIncludeEntities = reflectSearchObservationsIncludeEntities
        self.responseSchema = responseSchema
        self.keepTrace = keepTrace
    }

    enum CodingKeys: String, CodingKey {
        case budget
        case mode
        case refreshAfterConsolidation = "refresh_after_consolidation"
        case refreshCron = "refresh_cron"
        case fullRefreshCron = "full_refresh_cron"
        case minRefreshIntervalSeconds = "min_refresh_interval_seconds"
        case factTypes = "fact_types"
        case excludeMentalModels = "exclude_mental_models"
        case excludeMentalModelIds = "exclude_mental_model_ids"
        case tagsMatch = "tags_match"
        case tagGroups = "tag_groups"
        case includeChunks = "include_chunks"
        case recallMaxTokens = "recall_max_tokens"
        case recallChunksMaxTokens = "recall_chunks_max_tokens"
        case reflectSearchObservationsMaxTokens = "reflect_search_observations_max_tokens"
        case reflectSearchObservationsIncludeEntities = "reflect_search_observations_include_entities"
        case responseSchema = "response_schema"
        case keepTrace = "keep_trace"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.budget = try c.decodeIfPresent(String.self, forKey: .budget)
        self.mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "full"
        self.refreshAfterConsolidation = try c.decodeIfPresent(Bool.self, forKey: .refreshAfterConsolidation) ?? false
        self.refreshCron = try c.decodeIfPresent(String.self, forKey: .refreshCron)
        self.fullRefreshCron = try c.decodeIfPresent(String.self, forKey: .fullRefreshCron)
        self.minRefreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .minRefreshIntervalSeconds)
        self.factTypes = try c.decodeIfPresent([String].self, forKey: .factTypes)
        self.excludeMentalModels = try c.decodeIfPresent(Bool.self, forKey: .excludeMentalModels) ?? false
        self.excludeMentalModelIds = try c.decodeIfPresent([String].self, forKey: .excludeMentalModelIds)
        self.tagsMatch = try c.decodeIfPresent(String.self, forKey: .tagsMatch)
        self.tagGroups = try c.decodeIfPresent([TagGroup].self, forKey: .tagGroups)
        self.includeChunks = try c.decodeIfPresent(Bool.self, forKey: .includeChunks)
        self.recallMaxTokens = try c.decodeIfPresent(Int.self, forKey: .recallMaxTokens)
        self.recallChunksMaxTokens = try c.decodeIfPresent(Int.self, forKey: .recallChunksMaxTokens)
        self.reflectSearchObservationsMaxTokens = try c.decodeIfPresent(Int.self, forKey: .reflectSearchObservationsMaxTokens)
        self.reflectSearchObservationsIncludeEntities = try c.decodeIfPresent(Bool.self, forKey: .reflectSearchObservationsIncludeEntities)
        self.responseSchema = try c.decodeIfPresent([String: JSONValue].self, forKey: .responseSchema)
        self.keepTrace = try c.decodeIfPresent(Bool.self, forKey: .keepTrace) ?? false
    }
}

/// Trigger settings for a mental model.
public struct MentalModelTriggerOutput: Codable, Sendable, Hashable {
    /// How many agent iterations a refresh may spend, as a multiple of reflect_max_iterations: 'low' halves it, 'mid' keeps it, 'high' doubles it.
    public var budget: String?
    /// Refresh mode. 'full' (default) regenerates the mental model content from scratch on each refresh. 'delta' performs surgical edits against th
    public var mode: String
    /// If true, refresh this mental model after observations consolidation (real-time mode)
    public var refreshAfterConsolidation: Bool
    /// Cron expression (UTC, standard 5-field syntax, e.g. '0 3 * * *' for daily at 03:00 UTC) for refreshing this mental model on a fixed schedule
    public var refreshCron: String?
    /// Cron expression (UTC, standard 5-field syntax, e.g. '0 3 * * 0' for Sundays at 03:00 UTC) for a scheduled full refresh: on this schedule the
    public var fullRefreshCron: String?
    /// Minimum seconds between two automatic refreshes of this mental model. A triggered refresh that arrives sooner is not dropped: it is queued a
    public var minRefreshIntervalSeconds: Int?
    /// Filter which fact types are retrieved during reflect. None means all types (world, experience, observation).
    public var factTypes: [String]?
    /// If true, exclude all mental models from the reflect loop (skip search_mental_models tool).
    public var excludeMentalModels: Bool
    /// Exclude specific mental models by ID from the reflect loop.
    public var excludeMentalModelIds: [String]?
    /// Override how the model's tags filter memories during refresh. If not set, defaults to 'all_strict' when the model has tags (security isolati
    public var tagsMatch: String?
    /// Compound boolean tag expressions to use during refresh instead of the model's own tags. When set, these tag groups are passed to reflect and
    public var tagGroups: [TagGroup]?
    /// Override whether the internal recall used during refresh returns raw chunk text. None means use the bank/global config default (recall_inclu
    public var includeChunks: Bool?
    /// Override the token budget for facts returned by the internal recall during refresh. None means use the bank/global config default (recall_ma
    public var recallMaxTokens: Int?
    /// Override the token budget for raw chunks returned by the internal recall during refresh. None means use the bank/global config default (reca
    public var recallChunksMaxTokens: Int?
    /// Override the token budget for the refresh's search_observations calls. Observation evidence is often the largest contributor to the reflect
    public var reflectSearchObservationsMaxTokens: Int?
    /// Override whether search_observations attaches resolved entity names to each observation. Entities can be more than half the serialized tool
    public var reflectSearchObservationsIncludeEntities: Bool?
    /// Optional JSON Schema for structured output. When set, each refresh runs the same structured-output extraction as reflect's response_schema a
    public var responseSchema: [String: JSONValue]?
    /// If true, every refresh of this mental model records how it reached its result under reflect_response.trace: the mode it ran in and why, the
    public var keepTrace: Bool

    public init(budget: String? = nil, mode: String = "full", refreshAfterConsolidation: Bool = false, refreshCron: String? = nil, fullRefreshCron: String? = nil, minRefreshIntervalSeconds: Int? = nil, factTypes: [String]? = nil, excludeMentalModels: Bool = false, excludeMentalModelIds: [String]? = nil, tagsMatch: String? = nil, tagGroups: [TagGroup]? = nil, includeChunks: Bool? = nil, recallMaxTokens: Int? = nil, recallChunksMaxTokens: Int? = nil, reflectSearchObservationsMaxTokens: Int? = nil, reflectSearchObservationsIncludeEntities: Bool? = nil, responseSchema: [String: JSONValue]? = nil, keepTrace: Bool = false) {
        self.budget = budget
        self.mode = mode
        self.refreshAfterConsolidation = refreshAfterConsolidation
        self.refreshCron = refreshCron
        self.fullRefreshCron = fullRefreshCron
        self.minRefreshIntervalSeconds = minRefreshIntervalSeconds
        self.factTypes = factTypes
        self.excludeMentalModels = excludeMentalModels
        self.excludeMentalModelIds = excludeMentalModelIds
        self.tagsMatch = tagsMatch
        self.tagGroups = tagGroups
        self.includeChunks = includeChunks
        self.recallMaxTokens = recallMaxTokens
        self.recallChunksMaxTokens = recallChunksMaxTokens
        self.reflectSearchObservationsMaxTokens = reflectSearchObservationsMaxTokens
        self.reflectSearchObservationsIncludeEntities = reflectSearchObservationsIncludeEntities
        self.responseSchema = responseSchema
        self.keepTrace = keepTrace
    }

    enum CodingKeys: String, CodingKey {
        case budget
        case mode
        case refreshAfterConsolidation = "refresh_after_consolidation"
        case refreshCron = "refresh_cron"
        case fullRefreshCron = "full_refresh_cron"
        case minRefreshIntervalSeconds = "min_refresh_interval_seconds"
        case factTypes = "fact_types"
        case excludeMentalModels = "exclude_mental_models"
        case excludeMentalModelIds = "exclude_mental_model_ids"
        case tagsMatch = "tags_match"
        case tagGroups = "tag_groups"
        case includeChunks = "include_chunks"
        case recallMaxTokens = "recall_max_tokens"
        case recallChunksMaxTokens = "recall_chunks_max_tokens"
        case reflectSearchObservationsMaxTokens = "reflect_search_observations_max_tokens"
        case reflectSearchObservationsIncludeEntities = "reflect_search_observations_include_entities"
        case responseSchema = "response_schema"
        case keepTrace = "keep_trace"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.budget = try c.decodeIfPresent(String.self, forKey: .budget)
        self.mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "full"
        self.refreshAfterConsolidation = try c.decodeIfPresent(Bool.self, forKey: .refreshAfterConsolidation) ?? false
        self.refreshCron = try c.decodeIfPresent(String.self, forKey: .refreshCron)
        self.fullRefreshCron = try c.decodeIfPresent(String.self, forKey: .fullRefreshCron)
        self.minRefreshIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .minRefreshIntervalSeconds)
        self.factTypes = try c.decodeIfPresent([String].self, forKey: .factTypes)
        self.excludeMentalModels = try c.decodeIfPresent(Bool.self, forKey: .excludeMentalModels) ?? false
        self.excludeMentalModelIds = try c.decodeIfPresent([String].self, forKey: .excludeMentalModelIds)
        self.tagsMatch = try c.decodeIfPresent(String.self, forKey: .tagsMatch)
        self.tagGroups = try c.decodeIfPresent([TagGroup].self, forKey: .tagGroups)
        self.includeChunks = try c.decodeIfPresent(Bool.self, forKey: .includeChunks)
        self.recallMaxTokens = try c.decodeIfPresent(Int.self, forKey: .recallMaxTokens)
        self.recallChunksMaxTokens = try c.decodeIfPresent(Int.self, forKey: .recallChunksMaxTokens)
        self.reflectSearchObservationsMaxTokens = try c.decodeIfPresent(Int.self, forKey: .reflectSearchObservationsMaxTokens)
        self.reflectSearchObservationsIncludeEntities = try c.decodeIfPresent(Bool.self, forKey: .reflectSearchObservationsIncludeEntities)
        self.responseSchema = try c.decodeIfPresent([String: JSONValue].self, forKey: .responseSchema)
        self.keepTrace = try c.decodeIfPresent(Bool.self, forKey: .keepTrace) ?? false
    }
}

/// Optional per-stage score floors for recall. Every floor is inclusive (``>=``).
public struct MinScores: Codable, Sendable, Hashable {
    /// Retrieval-level, semantic arm only: minimum vector similarity (0-1). A result the semantic arm did not surface reports `semantic: null` and
    public var semantic: Double?
    /// Retrieval-level, keyword arm only: minimum keyword/full-text (BM25) score. A result the keyword arm did not surface reports `keyword: null`
    public var keyword: Double?
    /// Post-query: minimum normalized reranker score (0-1). Applied to every returned result. Rejected with HTTP 400 when the reranker scores by ra
    public var reranker: Double?
    /// Post-query: minimum final ranking score. Applied to every returned result.
    public var `final`: Double?

    public init(semantic: Double? = nil, keyword: Double? = nil, reranker: Double? = nil, `final`: Double? = nil) {
        self.semantic = semantic
        self.keyword = keyword
        self.reranker = reranker
        self.`final` = `final`
    }

    enum CodingKeys: String, CodingKey {
        case semantic
        case keyword
        case reranker
        case `final`
    }
}

/// How many observations an event touched, and (up to ``MAX_IDS``) which.
public struct ObservationIdSample: Codable, Sendable, Hashable {
    public var count: Int
    public var ids: [String]?

    public init(count: Int = 0, ids: [String]? = nil) {
        self.count = count
        self.ids = ids
    }

    enum CodingKeys: String, CodingKey {
        case count
        case ids
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.ids = try c.decodeIfPresent([String].self, forKey: .ids)
    }
}

/// A distinct observation scope: an exact tag set plus its observation count.
public struct ObservationScope: Codable, Sendable, Hashable {
    /// The exact tag set defining this scope (normalized order). Empty list is the global/untagged scope.
    public var tags: [String]
    /// Number of observations that live under this scope
    public var count: Int

    public init(tags: [String], count: Int) {
        self.tags = tags
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case count
    }
}

/// Response model for the observation scopes enumeration endpoint.
public struct ObservationScopesResponse: Codable, Sendable, Hashable {
    /// Distinct observation scopes, most populous first
    public var scopes: [ObservationScope]
    /// Total number of distinct scopes in the bank (ignores limit/offset)
    public var total: Int
    /// Maximum number of scopes returned in this page
    public var limit: Int
    /// Offset this page started at
    public var offset: Int

    public init(scopes: [ObservationScope], total: Int, limit: Int, offset: Int) {
        self.scopes = scopes
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case scopes
        case total
        case limit
        case offset
    }
}

/// Last-known progress snapshot for a long-running async operation.
public struct OperationProgress: Codable, Sendable, Hashable {
    /// Coarse phase the operation last reported (e.g. 'processing_batch').
    public var stage: String
    /// ISO-8601 timestamp when this snapshot was written.
    public var at: String
    /// Units of work finished so far (sub-batches, memories), when known.
    public var processed: Int?
    /// Total units of work for the operation, when known.
    public var total: Int?
    /// Operation-specific counters (e.g. observations_created, round, items_in_sub_batch).
    public var detail: [String: Int]?

    public init(stage: String, at: String, processed: Int? = nil, total: Int? = nil, detail: [String: Int]? = nil) {
        self.stage = stage
        self.at = at
        self.processed = processed
        self.total = total
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case stage
        case at
        case processed
        case total
        case detail
    }
}

/// Response model for a single async operation.
public struct OperationResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var taskType: String
    /// Same as `id`; the name the single-operation read uses.
    public var operationId: String?
    /// Same as `task_type`; the name the single-operation read uses.
    public var operationType: String?
    public var itemsCount: Int
    public var documentId: String?
    /// Original filename for file-conversion operations (file_convert_retain); null for other task types.
    public var filename: String?
    /// Mental model this operation acted on (refresh_mental_model); null for other task types. Without it the list cannot say which model an operat
    public var mentalModelId: String?
    /// Typed, per-operation-type outcome detail, discriminated by its own `operation_type`. Populated for `refresh_mental_model` operations that ha
    public var details: RefreshMentalModelOperationDetails?
    public var createdAt: String
    /// When this operation's row last changed (claim, progress heartbeat, or completion).
    public var updatedAt: String?
    public var status: String
    public var errorMessage: String?
    /// Number of times this operation has been retried after failure.
    public var retryCount: Int?
    /// When the worker will next attempt this operation. For a pending operation, a value in the future indicates the task is waiting rather than a
    public var nextRetryAt: String?
    /// Last-known progress snapshot for a running operation; null if none was recorded.
    public var progress: OperationProgress?

    public init(id: String, taskType: String, operationId: String? = nil, operationType: String? = nil, itemsCount: Int, documentId: String? = nil, filename: String? = nil, mentalModelId: String? = nil, details: RefreshMentalModelOperationDetails? = nil, createdAt: String, updatedAt: String? = nil, status: String, errorMessage: String? = nil, retryCount: Int? = nil, nextRetryAt: String? = nil, progress: OperationProgress? = nil) {
        self.id = id
        self.taskType = taskType
        self.operationId = operationId
        self.operationType = operationType
        self.itemsCount = itemsCount
        self.documentId = documentId
        self.filename = filename
        self.mentalModelId = mentalModelId
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.progress = progress
    }

    enum CodingKeys: String, CodingKey {
        case id
        case taskType = "task_type"
        case operationId = "operation_id"
        case operationType = "operation_type"
        case itemsCount = "items_count"
        case documentId = "document_id"
        case filename
        case mentalModelId = "mental_model_id"
        case details
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case errorMessage = "error_message"
        case retryCount = "retry_count"
        case nextRetryAt = "next_retry_at"
        case progress
    }
}

/// Response model for getting a single operation status.
public struct OperationStatusResponse: Codable, Sendable, Hashable {
    public var operationId: String
    public var status: String
    public var operationType: String?
    /// Same as `operation_id`; the name the operations list uses.
    public var id: String?
    /// Same as `operation_type`; the name the operations list uses.
    public var taskType: String?
    /// Mental model this operation acted on (refresh_mental_model); null for other task types.
    public var mentalModelId: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var completedAt: String?
    public var errorMessage: String?
    /// Number of times this operation has been retried after failure.
    public var retryCount: Int?
    /// When the worker will next attempt this operation. For a pending operation, a value in the future indicates the task is parked — a refresh_me
    public var nextRetryAt: String?
    /// Last-known progress snapshot for a running operation; null if none was recorded.
    public var progress: OperationProgress?
    /// Internal metadata for debugging. Structure may change without notice. Not for production use.
    public var resultMetadata: [String: JSONValue]?
    /// Typed, per-operation-type outcome detail, discriminated by its own `operation_type`. Populated for `refresh_mental_model` operations that ha
    public var details: RefreshMentalModelOperationDetails?
    /// Child operations for batch operations (if applicable)
    public var childOperations: [ChildOperationStatus]?
    /// Raw task payload (params the operation was submitted with). Only populated when include_payload=true.
    public var taskPayload: [String: JSONValue]?

    public init(operationId: String, status: String, operationType: String? = nil, id: String? = nil, taskType: String? = nil, mentalModelId: String? = nil, createdAt: String? = nil, updatedAt: String? = nil, completedAt: String? = nil, errorMessage: String? = nil, retryCount: Int? = nil, nextRetryAt: String? = nil, progress: OperationProgress? = nil, resultMetadata: [String: JSONValue]? = nil, details: RefreshMentalModelOperationDetails? = nil, childOperations: [ChildOperationStatus]? = nil, taskPayload: [String: JSONValue]? = nil) {
        self.operationId = operationId
        self.status = status
        self.operationType = operationType
        self.id = id
        self.taskType = taskType
        self.mentalModelId = mentalModelId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.progress = progress
        self.resultMetadata = resultMetadata
        self.details = details
        self.childOperations = childOperations
        self.taskPayload = taskPayload
    }

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
        case operationType = "operation_type"
        case id
        case taskType = "task_type"
        case mentalModelId = "mental_model_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case retryCount = "retry_count"
        case nextRetryAt = "next_retry_at"
        case progress
        case resultMetadata = "result_metadata"
        case details
        case childOperations = "child_operations"
        case taskPayload = "task_payload"
    }
}

/// Response model for list operations endpoint.
public struct OperationsListResponse: Codable, Sendable, Hashable {
    public var bankId: String
    public var total: Int
    public var limit: Int
    public var offset: Int
    public var operations: [OperationResponse]

    public init(bankId: String, total: Int, limit: Int, offset: Int, operations: [OperationResponse]) {
        self.bankId = bankId
        self.total = total
        self.limit = limit
        self.offset = offset
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case bankId = "bank_id"
        case total
        case limit
        case offset
        case operations
    }
}

/// One block of a message: its text, and the setting that decides it.
public struct PromptBlockModel: Codable, Sendable, Hashable {
    /// The block's text; empty when the block is inactive.
    public var text: String
    /// `config` — produced by a setting (`field` names it); `builtin` — Hindsight's own wording.
    public var source: String
    /// Config field behind this block; empty when no single field owns it.
    public var field: String
    /// Slug for a part the preview names itself and no field owns: `bank_identity`, `disposition`, `directives`. Empty otherwise.
    public var section: String
    /// The section heading the prompt text carries at this point, extracted from the prompt itself. Empty when it carries none.
    public var heading: String
    /// Whether this block is in the prompt as configured.
    public var active: Bool
    /// The field's effective value; null when unset.
    public var value: String?
    /// Shape of the value, so a client can offer the right control for editing it.
    public var kind: String
    /// Allowed values, when `kind` is `choice`.
    public var choices: [String]?
    /// Whether this bank may override the field via the bank config API. Server-level fields shape the prompt but cannot be set per bank, and offer
    public var editable: Bool

    public init(text: String, source: String, field: String = "", section: String = "", heading: String = "", active: Bool = true, value: String? = nil, kind: String, choices: [String]? = nil, editable: Bool = false) {
        self.text = text
        self.source = source
        self.field = field
        self.section = section
        self.heading = heading
        self.active = active
        self.value = value
        self.kind = kind
        self.choices = choices
        self.editable = editable
    }

    enum CodingKeys: String, CodingKey {
        case text
        case source
        case field
        case section
        case heading
        case active
        case value
        case kind
        case choices
        case editable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.source = try c.decode(String.self, forKey: .source)
        self.field = try c.decodeIfPresent(String.self, forKey: .field) ?? ""
        self.section = try c.decodeIfPresent(String.self, forKey: .section) ?? ""
        self.heading = try c.decodeIfPresent(String.self, forKey: .heading) ?? ""
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        self.value = try c.decodeIfPresent(String.self, forKey: .value)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.choices = try c.decodeIfPresent([String].self, forKey: .choices)
        self.editable = try c.decodeIfPresent(Bool.self, forKey: .editable) ?? false
    }
}

/// One message of the request, as the blocks it is built from.
public struct PromptMessageModel: Codable, Sendable, Hashable {
    public var role: String
    public var blocks: [PromptBlockModel]?

    public init(role: String, blocks: [PromptBlockModel]? = nil) {
        self.role = role
        self.blocks = blocks
    }

    enum CodingKeys: String, CodingKey {
        case role
        case blocks
    }
}

/// Request to render the prompts an operation would send, without calling an LLM.
public struct PromptPreviewRequest: Codable, Sendable, Hashable {
    /// Which operation's prompts to render.
    public var operation: String
    /// Name of a retain strategy to render under (a key of the bank's `retain_strategies`). Retain only. Omit it and the bank's `retain_default_str
    public var strategy: String?

    public init(operation: String = "retain", strategy: String? = nil) {
        self.operation = operation
        self.strategy = strategy
    }

    enum CodingKeys: String, CodingKey {
        case operation
        case strategy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operation = try c.decodeIfPresent(String.self, forKey: .operation) ?? "retain"
        self.strategy = try c.decodeIfPresent(String.self, forKey: .strategy)
    }
}

/// The messages one call of the requested operation would send.
public struct PromptPreviewResponse: Codable, Sendable, Hashable {
    /// Request messages, in send order. Each is given as the blocks it is built from.
    public var messages: [PromptMessageModel]?
    /// The retain strategy these prompts were rendered under, if any.
    public var strategy: String?
    /// Names of the bank's retain strategies, so a client can offer them without a second call.
    public var strategies: [String]?
    /// Settings that shape the operation without appearing in its prompt, such as chunk sizes.
    public var runSettings: [RunSettingModel]?
    /// JSON schema the response is constrained to, when the operation constrains it.
    public var responseSchema: [String: JSONValue]?
    /// Why no prompt is sent, when the configuration means none is.
    public var skippedReason: String?

    public init(messages: [PromptMessageModel]? = nil, strategy: String? = nil, strategies: [String]? = nil, runSettings: [RunSettingModel]? = nil, responseSchema: [String: JSONValue]? = nil, skippedReason: String? = nil) {
        self.messages = messages
        self.strategy = strategy
        self.strategies = strategies
        self.runSettings = runSettings
        self.responseSchema = responseSchema
        self.skippedReason = skippedReason
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case strategy
        case strategies
        case runSettings = "run_settings"
        case responseSchema = "response_schema"
        case skippedReason = "skipped_reason"
    }
}

/// Request model for recall endpoint.
public struct RecallRequest: Codable, Sendable, Hashable {
    public var query: String
    /// List of fact types to recall: 'world', 'experience', 'observation'. Defaults to all fact types if not specified.
    public var types: [String]?
    /// When recalling raw facts ('world'/'experience') together with 'observation', drop any raw fact that an observation in the results was consol
    public var preferObservations: Bool?
    /// What the decision-model reranker does beyond ordering: drop results that do not help (`prune`) or that repeat a better-ranked one (`dedup`).
    public var rerank: RerankOptions?
    public var budget: String
    public var maxTokens: Int
    public var trace: Bool
    /// ISO format date string (e.g., '2023-05-30T23:40:00'). Used as the query-time anchor for relative temporal expressions and recency scoring.
    public var queryTimestamp: String?
    /// Options for including additional data (entities are included by default)
    public var include: IncludeOptions?
    /// Filter memories by tags. If not specified, all memories are returned. Omitting tags (or passing []) together with tags_match='exact' filters
    public var tags: [String]?
    /// How to match tags: 'any' (OR, includes untagged), 'all' (AND, includes untagged), 'any_strict' (OR, excludes untagged), 'all_strict' (AND, e
    public var tagsMatch: String
    /// Compound tag filter using boolean groups. Groups in the list are AND-ed. Each group is a leaf {tags, match} or compound {and: [...]}, {or: [
    public var tagGroups: [TagGroup]?
    /// Optional per-stage score floors, each inclusive (`>=`). `semantic` and `keyword` are retrieval-level cutoffs pushed into the SQL arm they na
    public var minScores: MinScores?
    /// Window for the temporal retrieval arm, supplied instead of extracting dates from `query`. Set this when you already know the range you mean
    public var temporalWindow: TemporalWindow?

    public init(query: String, types: [String]? = nil, preferObservations: Bool? = nil, rerank: RerankOptions? = nil, budget: String = "mid", maxTokens: Int = 4096, trace: Bool = false, queryTimestamp: String? = nil, include: IncludeOptions? = nil, tags: [String]? = nil, tagsMatch: String = "any", tagGroups: [TagGroup]? = nil, minScores: MinScores? = nil, temporalWindow: TemporalWindow? = nil) {
        self.query = query
        self.types = types
        self.preferObservations = preferObservations
        self.rerank = rerank
        self.budget = budget
        self.maxTokens = maxTokens
        self.trace = trace
        self.queryTimestamp = queryTimestamp
        self.include = include
        self.tags = tags
        self.tagsMatch = tagsMatch
        self.tagGroups = tagGroups
        self.minScores = minScores
        self.temporalWindow = temporalWindow
    }

    enum CodingKeys: String, CodingKey {
        case query
        case types
        case preferObservations = "prefer_observations"
        case rerank
        case budget
        case maxTokens = "max_tokens"
        case trace
        case queryTimestamp = "query_timestamp"
        case include
        case tags
        case tagsMatch = "tags_match"
        case tagGroups = "tag_groups"
        case minScores = "min_scores"
        case temporalWindow = "temporal_window"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.query = try c.decode(String.self, forKey: .query)
        self.types = try c.decodeIfPresent([String].self, forKey: .types)
        self.preferObservations = try c.decodeIfPresent(Bool.self, forKey: .preferObservations)
        self.rerank = try c.decodeIfPresent(RerankOptions.self, forKey: .rerank)
        self.budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? "mid"
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        self.trace = try c.decodeIfPresent(Bool.self, forKey: .trace) ?? false
        self.queryTimestamp = try c.decodeIfPresent(String.self, forKey: .queryTimestamp)
        self.include = try c.decodeIfPresent(IncludeOptions.self, forKey: .include)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.tagsMatch = try c.decodeIfPresent(String.self, forKey: .tagsMatch) ?? "any"
        self.tagGroups = try c.decodeIfPresent([TagGroup].self, forKey: .tagGroups)
        self.minScores = try c.decodeIfPresent(MinScores.self, forKey: .minScores)
        self.temporalWindow = try c.decodeIfPresent(TemporalWindow.self, forKey: .temporalWindow)
    }
}

/// Response model for recall endpoints.
public struct RecallResponse: Codable, Sendable, Hashable {
    public var results: [RecallResult]
    public var trace: [String: JSONValue]?
    /// Entity states for entities mentioned in results
    public var entities: [String: EntityStateResponse]?
    /// Chunks for facts, keyed by chunk_id
    public var chunks: [String: ChunkData]?
    /// Source facts for observation-type results, keyed by fact ID
    public var sourceFacts: [String: RecallResult]?
    /// Whether the source_facts map was cut short by the token budget. When true, some IDs in results[].source_fact_ids have no entry in source_fac
    public var sourceFactsTruncated: Bool?

    public init(results: [RecallResult], trace: [String: JSONValue]? = nil, entities: [String: EntityStateResponse]? = nil, chunks: [String: ChunkData]? = nil, sourceFacts: [String: RecallResult]? = nil, sourceFactsTruncated: Bool? = nil) {
        self.results = results
        self.trace = trace
        self.entities = entities
        self.chunks = chunks
        self.sourceFacts = sourceFacts
        self.sourceFactsTruncated = sourceFactsTruncated
    }

    enum CodingKeys: String, CodingKey {
        case results
        case trace
        case entities
        case chunks
        case sourceFacts = "source_facts"
        case sourceFactsTruncated = "source_facts_truncated"
    }
}

/// Single recall result item.
public struct RecallResult: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var type: String?
    public var entities: [String]?
    public var context: String?
    public var occurredStart: String?
    public var occurredEnd: String?
    public var mentionedAt: String?
    public var documentId: String?
    public var metadata: [String: String]?
    public var chunkId: String?
    public var tags: [String]?
    public var sourceFactIds: [String]?
    public var scores: RecallScores?
    /// Attachments this fact was drawn from, as recorded per fact at extraction time — the same edge the memory read endpoints return, not everythi
    public var attachments: [ChunkAttachment]?

    public init(id: String, text: String, type: String? = nil, entities: [String]? = nil, context: String? = nil, occurredStart: String? = nil, occurredEnd: String? = nil, mentionedAt: String? = nil, documentId: String? = nil, metadata: [String: String]? = nil, chunkId: String? = nil, tags: [String]? = nil, sourceFactIds: [String]? = nil, scores: RecallScores? = nil, attachments: [ChunkAttachment]? = nil) {
        self.id = id
        self.text = text
        self.type = type
        self.entities = entities
        self.context = context
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.mentionedAt = mentionedAt
        self.documentId = documentId
        self.metadata = metadata
        self.chunkId = chunkId
        self.tags = tags
        self.sourceFactIds = sourceFactIds
        self.scores = scores
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case type
        case entities
        case context
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case mentionedAt = "mentioned_at"
        case documentId = "document_id"
        case metadata
        case chunkId = "chunk_id"
        case tags
        case sourceFactIds = "source_fact_ids"
        case scores
        case attachments
    }
}

/// Per-result recall scores from different stages of the pipeline.
public struct RecallScores: Codable, Sendable, Hashable {
    /// Final ranking score (combined reranker + recency/temporal/proof boosts)
    public var `final`: Double
    /// Cross-encoder relevance, normalized 0-1. None when the reranker is a passthrough (rrf/interleave modes).
    public var reranker: Double?
    /// Vector cosine similarity (0-1). None if this result was not surfaced semantically.
    public var semantic: Double?
    /// Keyword/full-text (BM25) score (>= 0, unbounded). None if this result was not surfaced by keyword search.
    public var keyword: Double?

    public init(`final`: Double, reranker: Double? = nil, semantic: Double? = nil, keyword: Double? = nil) {
        self.`final` = `final`
        self.reranker = reranker
        self.semantic = semantic
        self.keyword = keyword
    }

    enum CodingKeys: String, CodingKey {
        case `final`
        case reranker
        case semantic
        case keyword
    }
}

/// Response model for recovering failed consolidation.
public struct RecoverConsolidationResponse: Codable, Sendable, Hashable {
    public var retriedCount: Int

    public init(retriedCount: Int) {
        self.retriedCount = retriedCount
    }

    enum CodingKeys: String, CodingKey {
        case retriedCount = "retried_count"
    }
}

/// Evidence the response is based on: memories, mental models, and directives.
public struct ReflectBasedOn: Codable, Sendable, Hashable {
    /// Memory facts used to generate the response
    public var memories: [ReflectFact]
    /// Mental models used during reflection
    public var mentalModels: [ReflectMentalModel]
    /// Directives applied during reflection
    public var directives: [ReflectDirective]

    public init(memories: [ReflectFact] = [], mentalModels: [ReflectMentalModel] = [], directives: [ReflectDirective] = []) {
        self.memories = memories
        self.mentalModels = mentalModels
        self.directives = directives
    }

    enum CodingKeys: String, CodingKey {
        case memories
        case mentalModels = "mental_models"
        case directives
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.memories = try c.decodeIfPresent([ReflectFact].self, forKey: .memories) ?? []
        self.mentalModels = try c.decodeIfPresent([ReflectMentalModel].self, forKey: .mentalModels) ?? []
        self.directives = try c.decodeIfPresent([ReflectDirective].self, forKey: .directives) ?? []
    }
}

/// A directive applied during reflect.
public struct ReflectDirective: Codable, Sendable, Hashable, Identifiable {
    /// Directive ID
    public var id: String
    /// Directive name
    public var name: String
    /// Directive content
    public var content: String

    public init(id: String, name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case content
    }
}

/// A fact used in think response.
public struct ReflectFact: Codable, Sendable, Hashable {
    public var id: String?
    /// Fact text. When type='observation', this contains markdown-formatted consolidated knowledge
    public var text: String
    public var type: String?
    public var context: String?
    public var occurredStart: String?
    public var occurredEnd: String?
    public var mentionedAt: String?
    public var documentId: String?
    public var chunkId: String?
    public var tags: [String]?
    public var metadata: [String: String]?
    /// Attachments this memory was drawn from — the same per-fact edge recall reports. An observation reports those of the facts it was consolidate
    public var attachments: [ChunkAttachment]?

    public init(id: String? = nil, text: String, type: String? = nil, context: String? = nil, occurredStart: String? = nil, occurredEnd: String? = nil, mentionedAt: String? = nil, documentId: String? = nil, chunkId: String? = nil, tags: [String]? = nil, metadata: [String: String]? = nil, attachments: [ChunkAttachment]? = nil) {
        self.id = id
        self.text = text
        self.type = type
        self.context = context
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.mentionedAt = mentionedAt
        self.documentId = documentId
        self.chunkId = chunkId
        self.tags = tags
        self.metadata = metadata
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case type
        case context
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case mentionedAt = "mentioned_at"
        case documentId = "document_id"
        case chunkId = "chunk_id"
        case tags
        case metadata
        case attachments
    }
}

/// Options for including additional data in reflect results.
public struct ReflectIncludeOptions: Codable, Sendable, Hashable {
    /// Include facts that the answer is based on. Set to {} to enable, null to disable (default: disabled).
    public var facts: FactsIncludeOptions?
    /// Include tool calls trace. Set to {} for full trace (input+output), {output: false} for inputs only.
    public var toolCalls: ToolCallsIncludeOptions?

    public init(facts: FactsIncludeOptions? = nil, toolCalls: ToolCallsIncludeOptions? = nil) {
        self.facts = facts
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case facts
        case toolCalls = "tool_calls"
    }
}

/// An LLM call made during reflect agent execution.
public struct ReflectLLMCall: Codable, Sendable, Hashable {
    /// Call scope: agent_1, agent_2, final, etc.
    public var scope: String
    /// Execution time in milliseconds
    public var durationMs: Int

    public init(scope: String, durationMs: Int) {
        self.scope = scope
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case durationMs = "duration_ms"
    }
}

/// A mental model used during reflect.
public struct ReflectMentalModel: Codable, Sendable, Hashable, Identifiable {
    /// Mental model ID
    public var id: String
    /// Mental model content
    public var text: String
    /// Additional context
    public var context: String?

    public init(id: String, text: String, context: String? = nil) {
        self.id = id
        self.text = text
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case context
    }
}

/// Request model for reflect endpoint.
public struct ReflectRequest: Codable, Sendable, Hashable {
    /// Token budget for reflect's search_observations tool when the model names none. Observation evidence is often the largest contributor to the
    public var reflectSearchObservationsMaxTokens: Int?
    /// Whether search_observations attaches resolved entity names to each observation. Entities can be more than half the serialized tool payload;
    public var reflectSearchObservationsIncludeEntities: Bool?
    /// Token budget for the mental models search_mental_models returns in full, packed in rank order. The best-ranked one is always in full; the ot
    public var reflectSearchMentalModelsMaxTokens: Int?
    public var query: String
    public var budget: String
    /// DEPRECATED: Additional context is now concatenated with the query. Pass context directly in the query field instead. If provided, it will be
    public var context: String?
    /// Maximum tokens for the response
    public var maxTokens: Int
    /// Options for including additional data (disabled by default)
    public var include: ReflectIncludeOptions?
    /// Optional JSON Schema for structured output. When provided, the response will include a 'structured_output' field with the LLM response parse
    public var responseSchema: [String: JSONValue]?
    /// Scope raw facts, observations, mental models, and tagged directives during reflection. With no tags, memory retrieval is unfiltered while on
    public var tags: [String]?
    /// How to match tags: 'any' (OR, includes untagged), 'all' (AND, includes untagged), 'any_strict' (OR, excludes untagged), 'all_strict' (AND, e
    public var tagsMatch: String
    /// Compound tag filter using boolean groups. Groups in the list are AND-ed. Each group is a leaf {tags, match} or compound {and: [...]}, {or: [
    public var tagGroups: [TagGroup]?
    /// Apply every active directive regardless of tags. By default directives are scoped like memories: untagged directives always apply, and tagge
    public var applyAllDirectives: Bool
    /// Filter which fact types are retrieved during reflect. None means all types (world, experience, observation).
    public var factTypes: [String]?
    /// If true, exclude all mental models from the reflect loop (skip search_mental_models tool).
    public var excludeMentalModels: Bool
    /// Exclude specific mental models by ID from the reflect loop.
    public var excludeMentalModelIds: [String]?

    public init(reflectSearchObservationsMaxTokens: Int? = nil, reflectSearchObservationsIncludeEntities: Bool? = nil, reflectSearchMentalModelsMaxTokens: Int? = nil, query: String, budget: String = "low", context: String? = nil, maxTokens: Int = 4096, include: ReflectIncludeOptions? = nil, responseSchema: [String: JSONValue]? = nil, tags: [String]? = nil, tagsMatch: String = "any", tagGroups: [TagGroup]? = nil, applyAllDirectives: Bool = false, factTypes: [String]? = nil, excludeMentalModels: Bool = false, excludeMentalModelIds: [String]? = nil) {
        self.reflectSearchObservationsMaxTokens = reflectSearchObservationsMaxTokens
        self.reflectSearchObservationsIncludeEntities = reflectSearchObservationsIncludeEntities
        self.reflectSearchMentalModelsMaxTokens = reflectSearchMentalModelsMaxTokens
        self.query = query
        self.budget = budget
        self.context = context
        self.maxTokens = maxTokens
        self.include = include
        self.responseSchema = responseSchema
        self.tags = tags
        self.tagsMatch = tagsMatch
        self.tagGroups = tagGroups
        self.applyAllDirectives = applyAllDirectives
        self.factTypes = factTypes
        self.excludeMentalModels = excludeMentalModels
        self.excludeMentalModelIds = excludeMentalModelIds
    }

    enum CodingKeys: String, CodingKey {
        case reflectSearchObservationsMaxTokens = "reflect_search_observations_max_tokens"
        case reflectSearchObservationsIncludeEntities = "reflect_search_observations_include_entities"
        case reflectSearchMentalModelsMaxTokens = "reflect_search_mental_models_max_tokens"
        case query
        case budget
        case context
        case maxTokens = "max_tokens"
        case include
        case responseSchema = "response_schema"
        case tags
        case tagsMatch = "tags_match"
        case tagGroups = "tag_groups"
        case applyAllDirectives = "apply_all_directives"
        case factTypes = "fact_types"
        case excludeMentalModels = "exclude_mental_models"
        case excludeMentalModelIds = "exclude_mental_model_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.reflectSearchObservationsMaxTokens = try c.decodeIfPresent(Int.self, forKey: .reflectSearchObservationsMaxTokens)
        self.reflectSearchObservationsIncludeEntities = try c.decodeIfPresent(Bool.self, forKey: .reflectSearchObservationsIncludeEntities)
        self.reflectSearchMentalModelsMaxTokens = try c.decodeIfPresent(Int.self, forKey: .reflectSearchMentalModelsMaxTokens)
        self.query = try c.decode(String.self, forKey: .query)
        self.budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? "low"
        self.context = try c.decodeIfPresent(String.self, forKey: .context)
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        self.include = try c.decodeIfPresent(ReflectIncludeOptions.self, forKey: .include)
        self.responseSchema = try c.decodeIfPresent([String: JSONValue].self, forKey: .responseSchema)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.tagsMatch = try c.decodeIfPresent(String.self, forKey: .tagsMatch) ?? "any"
        self.tagGroups = try c.decodeIfPresent([TagGroup].self, forKey: .tagGroups)
        self.applyAllDirectives = try c.decodeIfPresent(Bool.self, forKey: .applyAllDirectives) ?? false
        self.factTypes = try c.decodeIfPresent([String].self, forKey: .factTypes)
        self.excludeMentalModels = try c.decodeIfPresent(Bool.self, forKey: .excludeMentalModels) ?? false
        self.excludeMentalModelIds = try c.decodeIfPresent([String].self, forKey: .excludeMentalModelIds)
    }
}

/// Response model for think endpoint.
public struct ReflectResponse: Codable, Sendable, Hashable {
    /// The reflect response as well-formatted markdown (headers, lists, bold/italic, code blocks, etc.)
    public var text: String
    /// Evidence used to generate the response. Only present when include.facts is set.
    public var basedOn: ReflectBasedOn?
    /// Structured output parsed according to the request's response_schema. Only present when response_schema was provided in the request.
    public var structuredOutput: [String: JSONValue]?
    /// Why structured output could not be produced. Present only when a response_schema was given and the extraction call failed (provider error, t
    public var structuredOutputError: String?
    /// Token usage metrics for LLM calls during reflection.
    public var usage: TokenUsage?
    /// Execution trace of tool and LLM calls. Only present when include.tool_calls is set.
    public var trace: ReflectTrace?

    public init(text: String, basedOn: ReflectBasedOn? = nil, structuredOutput: [String: JSONValue]? = nil, structuredOutputError: String? = nil, usage: TokenUsage? = nil, trace: ReflectTrace? = nil) {
        self.text = text
        self.basedOn = basedOn
        self.structuredOutput = structuredOutput
        self.structuredOutputError = structuredOutputError
        self.usage = usage
        self.trace = trace
    }

    enum CodingKeys: String, CodingKey {
        case text
        case basedOn = "based_on"
        case structuredOutput = "structured_output"
        case structuredOutputError = "structured_output_error"
        case usage
        case trace
    }
}

/// A tool call made during reflect agent execution.
public struct ReflectToolCall: Codable, Sendable, Hashable {
    /// Tool name: lookup, recall, learn, expand
    public var tool: String
    /// Tool input parameters
    public var input: [String: JSONValue]
    /// Tool output (only included when include.tool_calls.output is true)
    public var output: [String: JSONValue]?
    /// Execution time in milliseconds
    public var durationMs: Int
    /// Iteration number (1-based) when this tool was called
    public var iteration: Int

    public init(tool: String, input: [String: JSONValue], output: [String: JSONValue]? = nil, durationMs: Int, iteration: Int = 0) {
        self.tool = tool
        self.input = input
        self.output = output
        self.durationMs = durationMs
        self.iteration = iteration
    }

    enum CodingKeys: String, CodingKey {
        case tool
        case input
        case output
        case durationMs = "duration_ms"
        case iteration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tool = try c.decode(String.self, forKey: .tool)
        self.input = try c.decode([String: JSONValue].self, forKey: .input)
        self.output = try c.decodeIfPresent([String: JSONValue].self, forKey: .output)
        self.durationMs = try c.decode(Int.self, forKey: .durationMs)
        self.iteration = try c.decodeIfPresent(Int.self, forKey: .iteration) ?? 0
    }
}

/// Execution trace of LLM and tool calls during reflection.
public struct ReflectTrace: Codable, Sendable, Hashable {
    /// Tool calls made during reflection
    public var toolCalls: [ReflectToolCall]
    /// LLM calls made during reflection
    public var llmCalls: [ReflectLLMCall]

    public init(toolCalls: [ReflectToolCall] = [], llmCalls: [ReflectLLMCall] = []) {
        self.toolCalls = toolCalls
        self.llmCalls = llmCalls
    }

    enum CodingKeys: String, CodingKey {
        case toolCalls = "tool_calls"
        case llmCalls = "llm_calls"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.toolCalls = try c.decodeIfPresent([ReflectToolCall].self, forKey: .toolCalls) ?? []
        self.llmCalls = try c.decodeIfPresent([ReflectLLMCall].self, forKey: .llmCalls) ?? []
    }
}

/// What a refresh_mental_model operation did, on the operation record itself.
public struct RefreshMentalModelOperationDetails: Codable, Sendable, Hashable {
    /// Discriminator: which operation type this detail describes.
    public var operationType: String
    /// What the refresh did with the document: rewrote it (`content_written`), produced a document identical to the stored one (`content_unchanged`
    public var outcome: String
    /// Why the refresh refused to write, finer-grained than the outcome — it distinguishes an op call that failed from one whose operations were al
    public var failureReason: String?

    public init(operationType: String = "refresh_mental_model", outcome: String, failureReason: String? = nil) {
        self.operationType = operationType
        self.outcome = outcome
        self.failureReason = failureReason
    }

    enum CodingKeys: String, CodingKey {
        case operationType = "operation_type"
        case outcome
        case failureReason = "failure_reason"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.operationType = try c.decodeIfPresent(String.self, forKey: .operationType) ?? "refresh_mental_model"
        self.outcome = try c.decode(String.self, forKey: .outcome)
        self.failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
    }
}

/// Optional body of POST /mental-models/{id}/refresh.
public struct RefreshMentalModelRequest: Codable, Sendable, Hashable {
    /// 'full' regenerates the content from scratch for this refresh only, whatever `trigger.mode` says; the stored trigger is not changed. null run
    public var mode: String?

    public init(mode: String? = nil) {
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case mode
    }
}

/// Response model for reprocess document endpoint.
public struct ReprocessDocumentResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var operationId: String
    public var itemsCount: Int

    public init(success: Bool, operationId: String, itemsCount: Int) {
        self.success = success
        self.operationId = operationId
        self.itemsCount = itemsCount
    }

    enum CodingKeys: String, CodingKey {
        case success
        case operationId = "operation_id"
        case itemsCount = "items_count"
    }
}

/// What the decision-model reranker does beyond ordering. Each field left unset (null) uses the
public struct RerankOptions: Codable, Sendable, Hashable {
    /// Drop the results the decision model judges no help to the query, instead of only ranking them last. Costs no extra request. When omitted, us
    public var prune: Bool?
    /// Drop a result that repeats a better-ranked one, so the same fact comes back once. Costs one more decision-model request after the ranking on
    public var dedup: Bool?

    public init(prune: Bool? = nil, dedup: Bool? = nil) {
        self.prune = prune
        self.dedup = dedup
    }

    enum CodingKeys: String, CodingKey {
        case prune
        case dedup
    }
}

/// Request model for retain endpoint.
public struct RetainRequest: Codable, Sendable, Hashable {
    public var items: [MemoryItem]
    /// If true, process asynchronously in background. If false, wait for completion (default: false)
    public var `async`: Bool
    /// Deprecated. Use item-level tags instead.
    public var documentTags: [String]?
    /// Optional client-supplied UUID used as the identity of an async retain operation. Re-submitting with the same operation_id returns the origin
    public var operationId: String?

    public init(items: [MemoryItem], `async`: Bool = false, documentTags: [String]? = nil, operationId: String? = nil) {
        self.items = items
        self.`async` = `async`
        self.documentTags = documentTags
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case items
        case `async`
        case documentTags = "document_tags"
        case operationId = "operation_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decode([MemoryItem].self, forKey: .items)
        self.`async` = try c.decodeIfPresent(Bool.self, forKey: .`async`) ?? false
        self.documentTags = try c.decodeIfPresent([String].self, forKey: .documentTags)
        self.operationId = try c.decodeIfPresent(String.self, forKey: .operationId)
    }
}

/// Response model for retain endpoint.
public struct RetainResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var bankId: String
    public var itemsCount: Int
    /// Whether the operation was processed asynchronously
    public var `async`: Bool
    /// Operation ID for tracking async operations. Use GET /v1/default/banks/{bank_id}/operations to list operations. Only present when async=true.
    public var operationId: String?
    /// Operation IDs when items were submitted as multiple strategy groups (async=true with mixed per-item strategies). operation_id is set to the
    public var operationIds: [String]?
    /// Token usage metrics for LLM calls during fact extraction (only present for synchronous operations)
    public var usage: TokenUsage?

    public init(success: Bool, bankId: String, itemsCount: Int, `async`: Bool, operationId: String? = nil, operationIds: [String]? = nil, usage: TokenUsage? = nil) {
        self.success = success
        self.bankId = bankId
        self.itemsCount = itemsCount
        self.`async` = `async`
        self.operationId = operationId
        self.operationIds = operationIds
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case success
        case bankId = "bank_id"
        case itemsCount = "items_count"
        case `async`
        case operationId = "operation_id"
        case operationIds = "operation_ids"
        case usage
    }
}

/// Response model for retry operation endpoint.
public struct RetryOperationResponse: Codable, Sendable, Hashable {
    public var success: Bool
    public var message: String
    public var operationId: String

    public init(success: Bool, message: String, operationId: String) {
        self.success = success
        self.message = message
        self.operationId = operationId
    }

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case operationId = "operation_id"
    }
}

/// A setting that shapes the operation without appearing in its prompt.
public struct RunSettingModel: Codable, Sendable, Hashable {
    public var field: String
    /// Effective value; null when unset.
    public var value: String?
    /// Shape of the value, so a client can offer the right control.
    public var kind: String
    /// Whether this bank may override the field via the bank config API.
    public var editable: Bool

    public init(field: String, value: String? = nil, kind: String, editable: Bool = false) {
        self.field = field
        self.value = value
        self.kind = kind
        self.editable = editable
    }

    enum CodingKeys: String, CodingKey {
        case field
        case value
        case kind
        case editable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.field = try c.decode(String.self, forKey: .field)
        self.value = try c.decodeIfPresent(String.self, forKey: .value)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.editable = try c.decodeIfPresent(Bool.self, forKey: .editable) ?? false
    }
}

/// Request model for showing (or no longer showing) an alias in place of the bank id.
public struct SetBankAliasPrimaryRequest: Codable, Sendable, Hashable {
    /// True to present the bank under this alias; False to go back to its own id.
    public var primary: Bool

    public init(primary: Bool) {
        self.primary = primary
    }

    enum CodingKeys: String, CodingKey {
        case primary
    }
}

/// Options for including source facts for observation-type results.
public struct SourceFactsIncludeOptions: Codable, Sendable, Hashable {
    /// Maximum total tokens for source facts across all observations (-1 = unlimited)
    public var maxTokens: Int
    /// Maximum tokens of source facts per observation (-1 = unlimited)
    public var maxTokensPerObservation: Int

    public init(maxTokens: Int = 4096, maxTokensPerObservation: Int = -1) {
        self.maxTokens = maxTokens
        self.maxTokensPerObservation = maxTokensPerObservation
    }

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
        case maxTokensPerObservation = "max_tokens_per_observation"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        self.maxTokensPerObservation = try c.decodeIfPresent(Int.self, forKey: .maxTokensPerObservation) ?? -1
    }
}

/// Preview of one strategy, aligned by position with the request.
public struct StrategyPreview: Codable, Sendable, Hashable {
    /// False when the server would ignore this strategy (no usable rule, or no setting)
    public var active: Bool
    /// Existing scopes this strategy actually applies to
    public var claimedCount: Int
    /// One entry per rule, aligned with the request
    public var rules: [StrategyRulePreview]

    public init(active: Bool, claimedCount: Int, rules: [StrategyRulePreview]) {
        self.active = active
        self.claimedCount = claimedCount
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case active
        case claimedCount = "claimed_count"
        case rules
    }
}

/// What one rule (one entry of a strategy's `scopes`) matches among existing scopes.
public struct StrategyRulePreview: Codable, Sendable, Hashable {
    /// Existing scopes this rule matches
    public var matchCount: Int
    /// Of those, how many an earlier strategy wins, so this one has no effect
    public var takenCount: Int
    /// Observations across the matching scopes
    public var observationCount: Int
    /// The most populous matching scopes, up to sample_limit
    public var samples: [StrategyScopePreview]

    public init(matchCount: Int, takenCount: Int, observationCount: Int, samples: [StrategyScopePreview]) {
        self.matchCount = matchCount
        self.takenCount = takenCount
        self.observationCount = observationCount
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case matchCount = "match_count"
        case takenCount = "taken_count"
        case observationCount = "observation_count"
        case samples
    }
}

/// One existing observation scope in a consolidation-strategy preview.
public struct StrategyScopePreview: Codable, Sendable, Hashable {
    /// The scope's tags (sorted)
    public var tags: [String]
    /// Observations in this scope
    public var count: Int
    /// Index of the strategy that actually applies to this scope (the first that claims it), or null when no strategy does and Default applies
    public var handledBy: Int?

    public init(tags: [String], count: Int, handledBy: Int? = nil) {
        self.tags = tags
        self.count = count
        self.handledBy = handledBy
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case count
        case handledBy = "handled_by"
    }
}

/// A leaf tag filter: matches memories by tag list and match mode.
public struct TagGroupLeaf: Codable, Sendable, Hashable {
    public var tags: [String]
    public var match: String
    public var resolve: String

    public init(tags: [String], match: String = "any_strict", resolve: String = "exact") {
        self.tags = tags
        self.match = match
        self.resolve = resolve
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case match
        case resolve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tags = try c.decode([String].self, forKey: .tags)
        self.match = try c.decodeIfPresent(String.self, forKey: .match) ?? "any_strict"
        self.resolve = try c.decodeIfPresent(String.self, forKey: .resolve) ?? "exact"
    }
}

/// Single tag with usage count.
public struct TagItem: Codable, Sendable, Hashable {
    /// The tag value
    public var tag: String
    /// Number of memories with this tag
    public var count: Int

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case tag
        case count
    }
}

/// A caller-supplied window for recall's temporal arm.
public struct TemporalWindow: Codable, Sendable, Hashable {
    /// Start of the window (inclusive).
    public var start: String
    /// End of the window (inclusive).
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
    }
}

/// A run of text within a multimodal item, in the position the caller wrote it.
public struct TextContentBlock: Codable, Sendable, Hashable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

/// Token usage metrics for LLM calls.
public struct TokenUsage: Codable, Sendable, Hashable {
    /// Number of input/prompt tokens consumed
    public var inputTokens: Int
    /// Number of visible output/completion tokens generated (excludes reasoning/thoughts)
    public var outputTokens: Int
    /// Total tokens (input + output, excludes thoughts)
    public var totalTokens: Int
    /// Cached/cache-read prompt tokens, when reported by the provider
    public var cachedTokens: Int
    /// Reasoning/thinking tokens generated by the model. Billed at the output rate by some providers (e.g. Gemini 2.5+ family) but not surfaced in
    public var thoughtsTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, totalTokens: Int = 0, cachedTokens: Int = 0, thoughtsTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.thoughtsTokens = thoughtsTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
        case thoughtsTokens = "thoughts_tokens"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        self.cachedTokens = try c.decodeIfPresent(Int.self, forKey: .cachedTokens) ?? 0
        self.thoughtsTokens = try c.decodeIfPresent(Int.self, forKey: .thoughtsTokens) ?? 0
    }
}

/// Options for including tool calls in reflect results.
public struct ToolCallsIncludeOptions: Codable, Sendable, Hashable {
    /// Include tool outputs in the trace. Set to false to only include inputs (smaller payload).
    public var output: Bool

    public init(output: Bool = true) {
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case output
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.output = try c.decodeIfPresent(Bool.self, forKey: .output) ?? true
    }
}

/// Request model for updating a directive.
public struct UpdateDirectiveRequest: Codable, Sendable, Hashable {
    /// New name
    public var name: String?
    /// New content
    public var content: String?
    /// New priority
    public var priority: Int?
    /// New active status
    public var isActive: Bool?
    /// New tags
    public var tags: [String]?

    public init(name: String? = nil, content: String? = nil, priority: Int? = nil, isActive: Bool? = nil, tags: [String]? = nil) {
        self.name = name
        self.content = content
        self.priority = priority
        self.isActive = isActive
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case name
        case content
        case priority
        case isActive = "is_active"
        case tags
    }
}

/// Request model for updating disposition traits.
public struct UpdateDispositionRequest: Codable, Sendable, Hashable {
    public var disposition: DispositionTraits

    public init(disposition: DispositionTraits) {
        self.disposition = disposition
    }

    enum CodingKeys: String, CodingKey {
        case disposition
    }
}

/// Request model for updating a document's mutable fields.
public struct UpdateDocumentRequest: Codable, Sendable, Hashable {
    /// The complete new set of tags for the document and its memory units — this REPLACES the existing tags rather than adding to them, so omitting
    public var tags: [String]?
    /// New observation scoping for the document's memories, with the same values retain accepts (send 'combined' to scope by each memory's full tag
    public var observationScopes: JSONValue?

    public init(tags: [String]? = nil, observationScopes: JSONValue? = nil) {
        self.tags = tags
        self.observationScopes = observationScopes
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case observationScopes = "observation_scopes"
    }
}

/// Response model for update document endpoint.
public struct UpdateDocumentResponse: Codable, Sendable, Hashable {
    public var success: Bool

    public init(success: Bool = true) {
        self.success = success
    }

    enum CodingKeys: String, CodingKey {
        case success
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? true
    }
}

/// Request model for curating a single memory unit (edit / invalidate / revert).
public struct UpdateMemoryRequest: Codable, Sendable, Hashable {
    /// New fact text. Re-embeds the memory, drops its derived observations and links, and triggers re-consolidation.
    public var text: String?
    /// New context for the fact. '' clears it; omit to leave unchanged.
    public var context: String?
    /// New occurred-range start (ISO 8601). '' clears it; omit to leave unchanged.
    public var occurredStart: String?
    /// New occurred-range end (ISO 8601). '' clears it; omit to leave unchanged.
    public var occurredEnd: String?
    /// New mention time — when the fact was said or written (ISO 8601). '' clears it; omit to leave unchanged.
    public var mentionedAt: String?
    /// Reclassify the fact: 'world' or 'experience'. Omit to leave unchanged.
    public var factType: String?
    /// Replace the fact's entities. How each name is matched to an entity is governed by 'resolve_entities'. '[]' detaches all entities. Omit to le
    public var entities: [String]?
    /// Whether the names in 'entities' are resolved against the entities already in the bank. True (default) is what retain does: a similar existin
    public var resolveEntities: Bool
    /// Curation state: 'invalidated' to soft-retire the memory (excluded from recall/consolidation, links and derived observations pruned, moved to
    public var state: String?
    /// Optional free-text reason recorded when invalidating.
    public var reason: String?

    public init(text: String? = nil, context: String? = nil, occurredStart: String? = nil, occurredEnd: String? = nil, mentionedAt: String? = nil, factType: String? = nil, entities: [String]? = nil, resolveEntities: Bool = true, state: String? = nil, reason: String? = nil) {
        self.text = text
        self.context = context
        self.occurredStart = occurredStart
        self.occurredEnd = occurredEnd
        self.mentionedAt = mentionedAt
        self.factType = factType
        self.entities = entities
        self.resolveEntities = resolveEntities
        self.state = state
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case text
        case context
        case occurredStart = "occurred_start"
        case occurredEnd = "occurred_end"
        case mentionedAt = "mentioned_at"
        case factType = "fact_type"
        case entities
        case resolveEntities = "resolve_entities"
        case state
        case reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.context = try c.decodeIfPresent(String.self, forKey: .context)
        self.occurredStart = try c.decodeIfPresent(String.self, forKey: .occurredStart)
        self.occurredEnd = try c.decodeIfPresent(String.self, forKey: .occurredEnd)
        self.mentionedAt = try c.decodeIfPresent(String.self, forKey: .mentionedAt)
        self.factType = try c.decodeIfPresent(String.self, forKey: .factType)
        self.entities = try c.decodeIfPresent([String].self, forKey: .entities)
        self.resolveEntities = try c.decodeIfPresent(Bool.self, forKey: .resolveEntities) ?? true
        self.state = try c.decodeIfPresent(String.self, forKey: .state)
        self.reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// Request model for updating a mental model.
public struct UpdateMentalModelRequest: Codable, Sendable, Hashable {
    /// New name for the mental model
    public var name: String?
    /// New source query for the mental model
    public var sourceQuery: String?
    /// Maximum tokens for generated content
    public var maxTokens: Int?
    /// Tags for scoped visibility
    public var tags: [String]?
    /// Trigger settings
    public var trigger: MentalModelTriggerInput?

    public init(name: String? = nil, sourceQuery: String? = nil, maxTokens: Int? = nil, tags: [String]? = nil, trigger: MentalModelTriggerInput? = nil) {
        self.name = name
        self.sourceQuery = sourceQuery
        self.maxTokens = maxTokens
        self.tags = tags
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case name
        case sourceQuery = "source_query"
        case maxTokens = "max_tokens"
        case tags
        case trigger
    }
}

/// Rename/move a node and/or update a page's options. Each field applies only
public struct UpdateNodeRequest: Codable, Sendable, Hashable {
    public var name: String?
    public var parentId: String?
    public var sourceQuery: String?
    /// Replaces the page's tags, which SCOPE which memories it is built from. Pass `[]` to clear them and rebuild the page from the whole bank — th
    public var tags: [String]?
    public var maxTokens: Int?
    /// Refresh settings to change. Applied as a patch: only the fields present in this object are updated, and the rest keep the page's current val
    public var trigger: MentalModelTriggerInput?

    public init(name: String? = nil, parentId: String? = nil, sourceQuery: String? = nil, tags: [String]? = nil, maxTokens: Int? = nil, trigger: MentalModelTriggerInput? = nil) {
        self.name = name
        self.parentId = parentId
        self.sourceQuery = sourceQuery
        self.tags = tags
        self.maxTokens = maxTokens
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case name
        case parentId = "parent_id"
        case sourceQuery = "source_query"
        case tags
        case maxTokens = "max_tokens"
        case trigger
    }
}

/// Request model for updating a webhook. Only provided fields are updated.
public struct UpdateWebhookRequest: Codable, Sendable, Hashable {
    /// HTTP(S) endpoint URL
    public var url: String?
    /// HMAC-SHA256 signing secret. Omit to keep existing; send null to clear.
    public var secret: String?
    /// List of event types
    public var eventTypes: [String]?
    /// Whether this webhook is active
    public var enabled: Bool?
    /// HTTP delivery configuration
    public var httpConfig: WebhookHttpConfig?

    public init(url: String? = nil, secret: String? = nil, eventTypes: [String]? = nil, enabled: Bool? = nil, httpConfig: WebhookHttpConfig? = nil) {
        self.url = url
        self.secret = secret
        self.eventTypes = eventTypes
        self.enabled = enabled
        self.httpConfig = httpConfig
    }

    enum CodingKeys: String, CodingKey {
        case url
        case secret
        case eventTypes = "event_types"
        case enabled
        case httpConfig = "http_config"
    }
}

public struct ValidationError: Codable, Sendable, Hashable {
    public var loc: [JSONValue]
    public var msg: String
    public var type: String
    public var input: JSONValue?
    public var ctx: [String: JSONValue]?

    public init(loc: [JSONValue], msg: String, type: String, input: JSONValue? = nil, ctx: [String: JSONValue]? = nil) {
        self.loc = loc
        self.msg = msg
        self.type = type
        self.input = input
        self.ctx = ctx
    }

    enum CodingKeys: String, CodingKey {
        case loc
        case msg
        case type
        case input
        case ctx
    }
}

/// Response model for the version/info endpoint.
public struct VersionResponse: Codable, Sendable, Hashable {
    /// API version string
    public var apiVersion: String
    /// Enabled feature flags
    public var features: FeaturesInfo

    public init(apiVersion: String, features: FeaturesInfo) {
        self.apiVersion = apiVersion
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case features
    }
}

/// Response model for listing webhook deliveries.
public struct WebhookDeliveryListResponse: Codable, Sendable, Hashable {
    public var items: [WebhookDeliveryResponse]
    public var nextCursor: String?

    public init(items: [WebhookDeliveryResponse], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// Response model for a webhook delivery record.
public struct WebhookDeliveryResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var eventId: String?
    public var webhookId: String?
    public var url: String
    public var eventType: String
    public var status: String
    public var attempts: Int
    public var nextRetryAt: String?
    public var lastError: String?
    public var lastResponseStatus: Int?
    public var lastResponseBody: String?
    public var lastAttemptAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String, eventId: String? = nil, webhookId: String? = nil, url: String, eventType: String, status: String, attempts: Int, nextRetryAt: String? = nil, lastError: String? = nil, lastResponseStatus: Int? = nil, lastResponseBody: String? = nil, lastAttemptAt: String? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.eventId = eventId
        self.webhookId = webhookId
        self.url = url
        self.eventType = eventType
        self.status = status
        self.attempts = attempts
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.lastResponseStatus = lastResponseStatus
        self.lastResponseBody = lastResponseBody
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case webhookId = "webhook_id"
        case url
        case eventType = "event_type"
        case status
        case attempts
        case nextRetryAt = "next_retry_at"
        case lastError = "last_error"
        case lastResponseStatus = "last_response_status"
        case lastResponseBody = "last_response_body"
        case lastAttemptAt = "last_attempt_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// HTTP delivery configuration for a webhook.
public struct WebhookHttpConfig: Codable, Sendable, Hashable {
    /// HTTP method: GET or POST
    public var method: String
    /// HTTP request timeout in seconds
    public var timeoutSeconds: Int
    /// Custom HTTP headers
    public var headers: [String: String]?
    /// Custom HTTP query parameters
    public var params: [String: String]?

    public init(method: String = "POST", timeoutSeconds: Int = 30, headers: [String: String]? = nil, params: [String: String]? = nil) {
        self.method = method
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case method
        case timeoutSeconds = "timeout_seconds"
        case headers
        case params
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.method = try c.decodeIfPresent(String.self, forKey: .method) ?? "POST"
        self.timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 30
        self.headers = try c.decodeIfPresent([String: String].self, forKey: .headers)
        self.params = try c.decodeIfPresent([String: String].self, forKey: .params)
    }
}

/// Response model for listing webhooks.
public struct WebhookListResponse: Codable, Sendable, Hashable {
    public var items: [WebhookResponse]
    /// Total number of webhooks on the bank (ignores limit/offset)
    public var total: Int
    /// Maximum number of webhooks returned in this page
    public var limit: Int
    /// Offset this page started at
    public var offset: Int

    public init(items: [WebhookResponse], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case limit
        case offset
    }
}

/// Response model for a webhook.
public struct WebhookResponse: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var bankId: String?
    public var url: String
    /// Signing secret (redacted in responses)
    public var secret: String?
    public var eventTypes: [String]
    public var enabled: Bool
    public var httpConfig: WebhookHttpConfig?
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String, bankId: String? = nil, url: String, secret: String? = nil, eventTypes: [String], enabled: Bool, httpConfig: WebhookHttpConfig? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.bankId = bankId
        self.url = url
        self.secret = secret
        self.eventTypes = eventTypes
        self.enabled = enabled
        self.httpConfig = httpConfig
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bankId = "bank_id"
        case url
        case secret
        case eventTypes = "event_types"
        case enabled
        case httpConfig = "http_config"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
