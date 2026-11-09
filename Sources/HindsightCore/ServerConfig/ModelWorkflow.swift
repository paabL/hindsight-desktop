import Foundation
import HindsightAPI

/// Presentation of the launch-script draft, not a claim about the running process or bank overrides.
public struct ModelWorkflow: Encodable, Sendable {
    public struct Identity: Encodable, Sendable {
        public var provider: String
        public var model: String
        public var dynamic: Bool
    }
    public struct Decision: Encodable, Sendable {
        public var provider: String
        public var model: String
        public var source: String
        public var configured: Bool
        public var enabled: Bool
        public var uncertain: Bool
        public var shared: Bool
    }
    public var revision: String
    public var values: [String: String]
    public var dynamicNames: [String]
    public var identities: [String: Identity]
    public var decisions: [String: Decision]
    public var embeddings: String
}

extension ServerSettingsViewModel {
    public static let workflowFlags = [
        "HINDSIGHT_API_REFLECT_USE_DECISION_MODEL",
        "HINDSIGHT_API_CONSOLIDATION_USE_DECISION_MODEL",
        "HINDSIGHT_API_MENTAL_MODEL_REFRESH_USE_DECISION_MODEL",
        "HINDSIGHT_API_MENTAL_MODEL_DELTA_USE_DECISION_MODEL",
        "HINDSIGHT_API_RECALL_DECISION_MODEL_PRUNE",
        "HINDSIGHT_API_RECALL_DECISION_MODEL_DEDUP",
    ]

    /// Fournisseur de chaque usage : choisi avec son modèle dans le même menu du schéma.
    public static var workflowProviderFields: Set<String> {
        Set(ServerSettingsCatalog.roles.filter(\.isModelRole)
            .compactMap { $0.fields.first { $0.name.hasSuffix("_PROVIDER") }?.name })
    }

    public static var workflowFields: Set<String> {
        Set(workflowFlags + ["HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER"] +
            ServerSettingsCatalog.roles.filter { $0.isModelRole || $0.id == "reranker" }
                .flatMap { $0.fields.filter { $0.name.hasSuffix("_MODEL") }.map(\.name) })
            .union(workflowProviderFields)
    }

    public var modelWorkflow: ModelWorkflow? {
        guard let draft else { return nil }
        func value(_ name: String) -> String { draft.value(name) ?? "" }
        func dynamic(_ name: String) -> Bool { draft.assignment(name)?.isDynamic ?? false }
        func flag(_ name: String, default defaultValue: Bool = true) -> Bool {
            let raw = value(name).lowercased()
            return raw.isEmpty ? defaultValue : ["true", "1", "yes"].contains(raw)
        }
        func identity(_ roleID: String) -> ModelWorkflow.Identity {
            func isDynamic(_ id: String, suffix: String) -> Bool {
                guard let role = ServerSettingsCatalog.roles.first(where: { $0.id == id }) else { return false }
                if let field = role.fields.first(where: { $0.name.hasSuffix(suffix) }),
                   let assignment = draft.assignment(field.name), !assignment.value.isEmpty { return assignment.isDynamic }
                return role.fallback.map { isDynamic($0, suffix: suffix) } ?? false
            }
            let unresolved = isDynamic(roleID, suffix: "_PROVIDER") || isDynamic(roleID, suffix: "_MODEL")
            let provider = resolvedValue(for: roleID, suffix: "PROVIDER") ?? ""
            return .init(provider: provider, model: resolvedValue(for: roleID, suffix: "MODEL") ?? ServerSettingsCatalog.defaultModel(for: provider) ?? "", dynamic: unresolved)
        }
        /// `pages` : régénération complète d'une page ; `pagesDelta` : mise à jour depuis les nouveaux faits.
        /// Les deux passent par le client de décision de reflect, mais s'activent chacune de leur côté.
        func decision(_ operation: String) -> ModelWorkflow.Decision {
            let op = operation.hasPrefix("pages") ? "reflect" : operation
            let prefix = "HINDSIGHT_API_\(op.uppercased())_DECISION_MODEL_"
            let global = "HINDSIGHT_API_DECISION_MODEL_"
            let own = value(prefix + "PROVIDER")
            let globalProvider = value(global + "PROVIDER").lowercased()
            let provider = (own.isEmpty ? globalProvider : own.lowercased())
            let inherits = provider == globalProvider
            func setting(_ suffix: String) -> String {
                let local = value(prefix + suffix)
                return local.isEmpty && inherits ? value(global + suffix) : local
            }
            let model = setting("MODEL")
            let url = setting("BASE_URL")
            let source = provider == "hindsight" ? (url == LocalDecisionModel.baseURL ? "local" : url.isEmpty || url == HindsightInference.url ? "cloud" : "other") : "other"
            let supported = op == "reflect" ? ["hindsight", "typesafe"].contains(provider) : ["hindsight", "typesafe", "cloudflare", "openai"].contains(provider)
            let configured = supported && !(op == "recall" && provider == "hindsight" && own.isEmpty)
            let flagNames = operation == "pages" ? ["HINDSIGHT_API_MENTAL_MODEL_REFRESH_USE_DECISION_MODEL"]
                : operation == "pagesDelta" ? ["HINDSIGHT_API_MENTAL_MODEL_DELTA_USE_DECISION_MODEL"]
                : operation == "recall" ? [] : ["HINDSIGHT_API_\(op.uppercased())_USE_DECISION_MODEL"]
            let uncertain = [prefix + "PROVIDER", prefix + "MODEL", prefix + "BASE_URL", global + "PROVIDER", global + "MODEL", global + "BASE_URL"].contains(where: dynamic) || flagNames.contains(where: dynamic)
            // Key overrides are never sent to the renderer; even their presence makes sharing non-equivalent.
            let shared = inherits && ["MODEL", "BASE_URL", "API_KEY"].allSatisfy { value(prefix + $0).isEmpty }
            return .init(provider: provider, model: model.isEmpty && provider == "hindsight" ? "hs-decide-1-flash" : model,
                         source: source, configured: configured, enabled: configured && flagNames.allSatisfy { flag($0) }, uncertain: uncertain, shared: shared)
        }
        let embeddingProvider = resolvedValue(for: "embeddings", suffix: "PROVIDER") ?? "local"
        let embeddingModel = resolvedValue(for: "embeddings", suffix: "MODEL") ?? ""
        let dimensions = embeddingProvider == "google" ? value("HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY") : ""
        let embedding = embeddingModel.isEmpty ? embeddingProvider : embeddingModel + (dimensions.isEmpty ? "" : " · \(dimensions)")
        return ModelWorkflow(
            revision: SHA256.hex(Data((scriptPath + "\n" + draft.text).utf8)),
            values: Dictionary(uniqueKeysWithValues: Self.workflowFields.compactMap { name in draft.value(name).map { (name, $0) } }),
            dynamicNames: Self.workflowFields.filter(dynamic).sorted(),
            identities: Dictionary(uniqueKeysWithValues: ["default", "retain", "consolidation", "reflect", "mental_model", "vlm"].map { ($0, identity($0)) }),
            decisions: Dictionary(uniqueKeysWithValues: ["recall", "reflect", "consolidation", "pages", "pagesDelta"].map { ($0, decision($0)) }),
            embeddings: embedding)
    }

    /// All fields are checked before changing the draft. No embeddings, keys, endpoint, file write or restart.
    public func prepareModelWorkflow(_ changes: [String: String], revision: String) throws {
        guard let current = modelWorkflow, current.revision == revision, var next = draft else {
            throw WorkflowError("Les réglages ont changé. Actualisez avant de réessayer.")
        }
        for (name, raw) in changes {
            guard Self.workflowFields.contains(name), !current.dynamicNames.contains(name) else {
                throw WorkflowError("Ce réglage doit être modifié dans les options avancées.")
            }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.workflowFlags.contains(name), !["", "true", "false"].contains(value) {
                throw WorkflowError("Valeur d'activation invalide.")
            }
            let knownProviders = providerChoices.map(\.id) + ServerSettingsCatalog.providerDefaultModels.map(\.provider)
            if Self.workflowProviderFields.contains(name), !value.isEmpty, !knownProviders.contains(value) {
                throw WorkflowError("Fournisseur de modèle inconnu.")
            }
            if name == "HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER",
               !["", "none", "hindsight", "typesafe", "openai", "cloudflare"].contains(value) {
                throw WorkflowError("Fournisseur de décision inconnu.")
            }
            guard !value.contains("\n"), !value.contains("\r"), value.count < 512 else {
                throw WorkflowError("Nom de modèle invalide.")
            }
            if value.isEmpty { next.unset(name) } else { next.set(name, to: value) }
        }
        restoreDraft(next)
    }

    public struct WorkflowError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }
}
