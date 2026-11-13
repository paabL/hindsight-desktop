import Foundation

/// Réglages serveur connus (variables d'environnement `HINDSIGHT_API_*`), regroupés par rôle.
///
/// Source : `hindsight-api-slim/hindsight_api/config.py` du dépôt vectorize-io/hindsight (tag v1.2.0,
/// novembre 2026). Les noms peuvent différer selon la version installée : toute variable présente dans le
/// script est de toute façon affichée et éditable, même absente de ce catalogue.
public enum ServerSettingsCatalog {
    public struct Provider: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public var account: LLMAccount? { LLMAccount(rawValue: id) }
    }

    /// Choix usuels, complétés par les fournisseurs déjà configurés.
    public static let suggestedProviders: [Provider] = [
        Provider(id: "claude-code", title: "Claude Code"),
        Provider(id: "anthropic", title: "Anthropic API"),
        Provider(id: "openai-codex", title: "ChatGPT / Codex"),
        Provider(id: "chatgpt", title: "ChatGPT (connexion du serveur, 1.1.0)"),
        Provider(id: "gemini", title: "Gemini"),
        Provider(id: "openai", title: "OpenAI API"),
        Provider(id: "ollama", title: "Ollama"),
        Provider(id: "lmstudio", title: "LM Studio"),
    ]

    public static func providerTitle(_ id: String) -> String {
        suggestedProviders.first { $0.id == id }?.title ?? id
    }

    public struct Field: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let label: String
        public let help: String
        public var isSecret: Bool { LaunchScript.isSecret(name) }
    }

    public struct Role: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let help: String
        public let fields: [Field]
        /// Rôle dont celui-ci hérite quand ses variables sont absentes (« Défaut » pour retain/consolidation/reflect).
        public let fallback: String?
        /// Avertissement affiché quand on modifie ce rôle.
        public let caution: String?
        public var isModelRole: Bool { ["default", "retain", "consolidation", "reflect", "mental_model", "vlm"].contains(id) }
    }

    /// « Extraction des faits › Modèle » : où la page Modèles montre cette variable ; nil si elle n'y figure pas.
    public static func label(forVariable name: String) -> String? {
        for role in roles {
            if let field = role.fields.first(where: { $0.name == name }) { return "\(role.title) › \(field.label)" }
        }
        return nil
    }

    static func llmFields(_ prefix: String) -> [Field] {
        [
            Field(name: "HINDSIGHT_API_\(prefix)PROVIDER", label: "Fournisseur", help: "ex. claude-code, gemini, openai, anthropic, ollama…"),
            Field(name: "HINDSIGHT_API_\(prefix)MODEL", label: "Modèle", help: "Nom exact du modèle ; vide = réglage hérité ou défaut du serveur"),
            Field(name: "HINDSIGHT_API_\(prefix)BASE_URL", label: "URL de base", help: "Pour un serveur compatible OpenAI, Ollama, LM Studio…"),
            Field(name: "HINDSIGHT_API_\(prefix)API_KEY", label: "Clé d'API", help: "Conservée dans le script de lancement ; masquée dans l'app"),
            Field(name: "HINDSIGHT_API_\(prefix)MAX_CONCURRENT", label: "Requêtes simultanées", help: "Plafond de concurrence vers ce LLM"),
            Field(name: "HINDSIGHT_API_\(prefix)TIMEOUT", label: "Timeout (s)", help: ""),
            Field(
                name: "HINDSIGHT_API_\(prefix)REASONING_EFFORT", label: "Effort de raisonnement",
                help: "Niveaux du fournisseur choisi (low, medium, high…) ; vide = réglage hérité ou défaut du fournisseur. Hindsight 1.2 sans modification l'ignore pour claude-code, anthropic, gemini et cursor : un avertissement le signale dans le journal du serveur au démarrage."),
        ]
    }

    public static let roles: [Role] = [
        Role(id: "default", title: "LLM par défaut", help: "Utilisé par tous les rôles qui n'ont pas leurs propres réglages.",
            fields: llmFields("LLM_") + [
                Field(name: "HINDSIGHT_API_LLM_CODEX_HOME", label: "Dossier de connexion Codex", help: "Vide = dossier Codex habituel sur ce Mac"),
                Field(
                    name: "HINDSIGHT_API_LLM_CHATGPT_HOME", label: "Dossier de connexion ChatGPT",
                    help: "Fournisseur chatgpt (serveur 1.1.0) ; vide = ~/.hindsight/chatgpt"),
            ], fallback: nil, caution: nil),
        Role(id: "retain", title: "Extraction des faits", help: "LLM qui lit les documents et extrait les faits.",
            fields: llmFields("RETAIN_LLM_"), fallback: "default", caution: nil),
        Role(id: "consolidation", title: "Consolidation", help: "LLM qui fusionne les faits en observations.",
            fields: llmFields("CONSOLIDATION_LLM_") + [
                Field(name: "HINDSIGHT_API_CONSOLIDATION_LLM_BATCH_SIZE", label: "Taille de lot", help: ""),
                Field(name: "HINDSIGHT_API_CONSOLIDATION_LLM_PARALLELISM", label: "Parallélisme",
                    help: "N'agit qu'entre portées d'observation différentes : les lots d'une même portée passent l'un après l'autre"),
            ], fallback: "default", caution: nil),
        Role(id: "reflect", title: "Réponses", help: "LLM qui rédige les réponses à partir de la mémoire.",
            fields: llmFields("REFLECT_LLM_"), fallback: "default", caution: nil),
        Role(id: "mental_model", title: "Connaissances", help: "LLM qui régénère les connaissances (pages de connaissance et modèles mentaux).",
            fields: llmFields("MENTAL_MODEL_REFRESH_LLM_"), fallback: "reflect", caution: nil),
        Role(id: "vlm", title: "Vision (VLM)", help: "Modèle qui décrit les images des documents.",
            fields: Array(llmFields("VLM_").prefix(4)), fallback: nil, caution: nil),
        Role(
            id: "decision", title: "Modèle de décision (1.1.0+ ; Hindsight en 1.2.0)",
            help: "Modèle qui répond à des questions typées (choix, score) à la place d'un appel LLM, partagé par la recherche, les réponses, la consolidation et les pages de connaissance. N'écrit pas de texte ; hors plafonds de dépense.",
            fields: [
                Field(
                    name: "HINDSIGHT_API_DECISION_MODEL_PROVIDER", label: "Fournisseur",
                    help: "none (défaut), hindsight (Hindsight Inference, 1.2.0), typesafe, cloudflare, openai"),
                Field(name: "HINDSIGHT_API_DECISION_MODEL_MODEL", label: "Modèle", help: "Vide = défaut du fournisseur (hindsight : hs-decide-1-flash)"),
                Field(name: "HINDSIGHT_API_DECISION_MODEL_BASE_URL", label: "URL de base", help: "Vide = défaut du fournisseur ; http://127.0.0.1:8766 pour hs-decide-1-flash installé sur ce Mac"),
                Field(
                    name: "HINDSIGHT_API_DECISION_MODEL_API_KEY", label: "Clé d'API",
                    help: "Masquée dans l'app ; hindsight : vide = clé enregistrée par « hindsight-admin cloud login »"),
                Field(name: "HINDSIGHT_API_DECISION_MODEL_MAX_CONCURRENT", label: "Requêtes simultanées", help: "Défaut 24"),
                Field(name: "HINDSIGHT_API_DECISION_MODEL_TIMEOUT", label: "Timeout (s)", help: "Défaut 60"),
                Field(name: "HINDSIGHT_API_DECISION_MODEL_MAX_REQUEST_TOKENS", label: "Jetons max par requête", help: "Défaut 26 000 (hindsight : 54 000)"),
                Field(
                    name: "HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER", label: "Recherche : fournisseur",
                    help: "Vide = celui du dessus, sauf hindsight : la recherche garde alors son reranker tant qu'il n'est pas nommé ici ; none = jamais"),
                Field(
                    name: "HINDSIGHT_API_RECALL_DECISION_MODEL_PRUNE", label: "Recherche : écarter les faits inutiles",
                    help: "true / false (défaut) ; sans requête de plus. Serveur 1.2.0"),
                Field(
                    name: "HINDSIGHT_API_RECALL_DECISION_MODEL_DEDUP", label: "Recherche : retirer les doublons",
                    help: "true / false (défaut) ; une requête de plus par recherche. Serveur 1.2.0"),
            ] + ["RECALL", "REFLECT", "CONSOLIDATION"].flatMap { operation in
                // Noms des fonctions tels que l'app les affiche partout (Recherche, Réponses, Consolidation).
                let name = ["RECALL": "Recherche", "REFLECT": "Réponses"][operation] ?? "Consolidation"
                return (operation == "RECALL" ? [] : [Field(name: "HINDSIGHT_API_\(operation)_DECISION_MODEL_PROVIDER", label: "\(name) : fournisseur", help: "Vide = héritage global ; none = désactivé")]) + [
                    Field(name: "HINDSIGHT_API_\(operation)_DECISION_MODEL_MODEL", label: "\(name) : modèle", help: "Modèle propre à cette opération"),
                    Field(name: "HINDSIGHT_API_\(operation)_DECISION_MODEL_BASE_URL", label: "\(name) : URL", help: "URL propre à cette opération"),
                    Field(name: "HINDSIGHT_API_\(operation)_DECISION_MODEL_API_KEY", label: "\(name) : clé", help: "Clé propre à cette opération, masquée"),
                ]
            } + [
                Field(name: "HINDSIGHT_API_REFLECT_USE_DECISION_MODEL", label: "Réponses : utiliser la décision", help: "true (défaut) / false ; une banque peut remplacer ce réglage"),
                Field(name: "HINDSIGHT_API_CONSOLIDATION_USE_DECISION_MODEL", label: "Consolidation : utiliser la décision", help: "true (défaut) / false"),
                Field(name: "HINDSIGHT_API_MENTAL_MODEL_REFRESH_USE_DECISION_MODEL", label: "Pages de connaissance : décision pendant la régénération", help: "true (défaut) / false ; parcours de repli"),
                Field(name: "HINDSIGHT_API_MENTAL_MODEL_DELTA_USE_DECISION_MODEL", label: "Pages de connaissance : filtrage des nouveaux faits", help: "true (défaut) / false ; régénération incrémentale"),
            ], fallback: nil,
            caution: "Ignoré par un serveur 1.0.0. Le fournisseur hindsight et les options prune/dedup demandent un serveur 1.2.0 ; sans URL locale, il envoie le contenu des faits à Hindsight Inference (Vectorize)."),
        Role(id: "embeddings", title: "Embeddings", help: "Vectorisation des faits.",
            fields: [
                Field(
                    name: "HINDSIGHT_API_EMBEDDINGS_PROVIDER", label: "Fournisseur",
                    help: "local, hindsight (hs-embed-1, 1.2.0), google (Gemini), openai, cohere, tei, litellm…"),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL", label: "Modèle Gemini", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_GEMINI_API_KEY", label: "Clé Gemini", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY", label: "Dimensions Gemini", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL", label: "Modèle OpenAI", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY", label: "Clé OpenAI", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL", label: "URL OpenAI", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_OPENAI_DIMENSIONS", label: "Dimensions OpenAI", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_COHERE_MODEL", label: "Modèle Cohere", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_COHERE_API_KEY", label: "Clé Cohere", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_COHERE_BASE_URL", label: "URL Cohere", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_TEI_URL", label: "URL TEI", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_LITELLM_MODEL", label: "Modèle LiteLLM", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_LITELLM_API_KEY", label: "Clé LiteLLM", help: ""),
                Field(name: "HINDSIGHT_API_EMBEDDINGS_LITELLM_API_BASE", label: "URL LiteLLM", help: ""),
                Field(
                    name: "HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL", label: "Modèle local",
                    help: "Vide = BAAI/bge-small-en-v1.5 ; hindsight-ai/hs-embed-1 (384 dimensions, multilingue, sur CPU)"),
                Field(
                    name: "HINDSIGHT_API_EMBEDDINGS_HINDSIGHT_API_KEY", label: "Clé Hindsight Inference",
                    help: "Vide = clé enregistrée par « hindsight-admin cloud login »"),
            ], fallback: nil,
            caution: "Changer de modèle ou de dimension d'embeddings rend les vecteurs existants incompatibles : la recherche se dégrade jusqu'à une ré-indexation complète (export puis import de la banque)."),
        Role(id: "reranker", title: "Reranker", help: "Réordonnancement des résultats de recherche.",
            fields: [
                Field(
                    name: "HINDSIGHT_API_RERANKER_PROVIDER", label: "Fournisseur",
                    help: "local, hindsight (hs-rerank-1, 1.2.0), cohere, tei, litellm, google…"),
                Field(name: "HINDSIGHT_API_RERANKER_COHERE_MODEL", label: "Modèle Cohere", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_COHERE_API_KEY", label: "Clé Cohere", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_COHERE_BASE_URL", label: "URL Cohere", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_TEI_URL", label: "URL TEI", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_LITELLM_MODEL", label: "Modèle LiteLLM", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_LITELLM_API_KEY", label: "Clé LiteLLM", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_LITELLM_API_BASE", label: "URL LiteLLM", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_GOOGLE_MODEL", label: "Modèle Google", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_GOOGLE_PROJECT_ID", label: "Projet Google", help: ""),
                Field(name: "HINDSIGHT_API_RERANKER_GOOGLE_SERVICE_ACCOUNT_KEY", label: "Clé du compte de service Google", help: ""),
                Field(
                    name: "HINDSIGHT_API_RERANKER_LOCAL_MODEL", label: "Modèle local",
                    help: "Vide = hindsight-ai/hs-rerank-1 en 1.2.0 (cross-encoder/ms-marco-MiniLM-L-6-v2 avant), sur CPU"),
                Field(
                    name: "HINDSIGHT_API_RERANKER_HINDSIGHT_API_KEY", label: "Clé Hindsight Inference",
                    help: "Vide = clé enregistrée par « hindsight-admin cloud login »"),
            ], fallback: nil,
            caution: "Le reranker ne touche pas aux vecteurs : on peut en changer sans ré-indexer. En 1.2.0, le modèle local par défaut devient hs-rerank-1."),
        Role(id: "observability", title: "Journalisation", help: "Audit des accès et traces des appels LLM.",
            fields: [
                Field(name: "HINDSIGHT_API_AUDIT_LOG_ENABLED", label: "Journal d'audit", help: "true / false"),
                Field(name: "HINDSIGHT_API_LLM_TRACE_ENABLED", label: "Traces LLM", help: "true / false"),
                Field(name: "HINDSIGHT_API_AUDIT_LOG_RETENTION_DAYS", label: "Rétention de l'audit (jours)", help: "-1 = pour toujours (défaut)"),
                Field(name: "HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS", label: "Rétention des traces LLM (jours)", help: "1 par défaut ; -1 = pour toujours. Plus long = consommation visible plus longtemps"),
            ], fallback: nil, caution: nil),
    ]

    public static var knownNames: Set<String> { Set(roles.flatMap { $0.fields.map(\.name) }) }

    /// Fournisseurs LLM connus (clés de PROVIDER_DEFAULT_MODELS côté serveur) avec leur modèle par défaut.
    public static let providerDefaultModels: [(provider: String, model: String)] = [
        ("claude-code", "claude-sonnet-4-5-20250929"), ("anthropic", "claude-haiku-4-5"), ("gemini", "gemini-3.5-flash"),
        ("openai", "gpt-4o-mini"), ("openai-responses", "gpt-5.6"), ("openai-codex", "gpt-5.4-mini"), ("chatgpt", "gpt-6-luna"),
        ("vertexai", "google/gemini-3.1-flash-lite"), ("ollama", "gemma3:12b"), ("ollama-cloud", "gemma3:12b"),
        ("lmstudio", "local-model"), ("llamacpp", "gemma-4-e2b-it"), ("litellm", "gpt-4o-mini"), ("openrouter", "qwen/qwen3.5-9b"),
        ("groq", "openai/gpt-oss-120b"), ("deepseek", "deepseek-v4-flash"), ("bedrock", "us.amazon.nova-2-lite-v1:0"),
        ("github-copilot", "gpt-5.6-terra"), ("cursor", "auto"), ("none", "none"),
    ]

    public static func defaultModel(for provider: String) -> String? {
        providerDefaultModels.first { $0.provider == provider }?.model
    }
}
