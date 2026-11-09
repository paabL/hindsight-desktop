import Foundation
import HindsightAPI

/// Groupe d'étiquettes d'entités (vocabulaire contrôlé) : une dimension, son type et ses valeurs permises.
/// Les champs non édités ici (ex. `fields` des groupes `map`) sont conservés tels quels.
public struct EntityLabelGroup: Sendable, Hashable, Identifiable {
    public static let types = ["value", "multi-values", "text", "multi-text", "map"]

    public var id = UUID()
    public var key: String
    public var description: String
    /// value | multi-values | text | multi-text | map
    public var type: String
    public var optional: Bool
    /// La valeur devient aussi un tag `clé:valeur` du fait (filtrable, et périmètre de consolidation).
    public var tag: Bool
    public var values: [LabelValue]
    public var extra: [String: JSONValue]

    public init(
        key: String, description: String = "", type: String = "value", optional: Bool = true, tag: Bool = false,
        values: [LabelValue] = [], extra: [String: JSONValue] = [:]
    ) {
        self.key = key
        self.description = description
        self.type = type
        self.optional = optional
        self.tag = tag
        self.values = values
        self.extra = extra
    }

    public static func == (a: Self, b: Self) -> Bool { a.json == b.json }
    public func hash(into h: inout Hasher) { h.combine(json) }

    init?(json: JSONValue) {
        guard case .object(let o) = json, let key = o["key"]?.stringValue else { return nil }
        var values: [LabelValue] = []
        if case .array(let vs)? = o["values"] {
            for v in vs {
                if case .object(let vo) = v, let value = vo["value"]?.stringValue {
                    values.append(LabelValue(value: value, description: vo["description"]?.stringValue ?? ""))
                }
            }
        }
        var extra = o
        for k in ["key", "description", "type", "optional", "tag", "values"] { extra[k] = nil }
        self.init(
            key: key, description: o["description"]?.stringValue ?? "", type: o["type"]?.stringValue ?? "value",
            optional: o["optional"]?.boolValue ?? true, tag: o["tag"]?.boolValue ?? false, values: values, extra: extra)
    }

    public var json: JSONValue {
        var o = extra
        o["key"] = .string(key)
        o["description"] = .string(description)
        o["type"] = .string(type)
        o["optional"] = .bool(optional)
        o["tag"] = .bool(tag)
        o["values"] = .array(values.map { .object(["value": .string($0.value), "description": .string($0.description)]) })
        return .object(o)
    }

    /// Valeurs éditées en texte : une par ligne, « valeur — description » (description facultative).
    public var valuesText: String {
        get { values.map { $0.description.isEmpty ? $0.value : "\($0.value) — \($0.description)" }.joined(separator: "\n") }
        set {
            values = newValue.split(separator: "\n").compactMap { line in
                let parts = line.components(separatedBy: " — ")
                let v = parts[0].trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { return nil }
                return LabelValue(value: v, description: parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces))
            }
        }
    }

    var labelGroupInput: LabelGroupInput? {
        guard let data = try? JSONEncoder().encode(json) else { return nil }
        return try? JSONDecoder().decode(LabelGroupInput.self, from: data)
    }
}

/// Tous les réglages qui décident de ce que la banque retient, de ce qu'elle juge important, de la façon
/// dont elle consolide et raisonne. Ce sont des surcharges de banque (`PATCH …/config`), lues dans
/// `GET …/config` (valeurs résolues : serveur → banque).
public struct MemoryDesign: Sendable, Hashable {
    public static let extractionModes = ["concise", "verbose", "custom", "verbatim", "chunks"]

    // Rétention : ce qui devient un fait
    public var retainMission = ""
    public var extractionMode = "concise"
    public var customInstructions = ""
    public var chunkSize = 3000
    public var entityLabels: [EntityLabelGroup] = []
    public var entitiesAllowFreeForm = true
    public var storeDocumentText = true
    // Observations : ce qui est consolidé
    public var enableObservations = true
    public var enableAutoConsolidation = true
    public var observationsMission = ""
    public var maxObservationsPerScope = -1
    /// Portée des documents envoyés sans portée (serveur 1.1.0) ; vide = défaut du serveur (« combinée »).
    public var defaultObservationScopes = ""
    // Raisonnement : comment reflect répond
    public var reflectMission = ""
    public var skepticism = 3
    public var literalism = 3
    public var empathy = 3
    // Lecture : comment recall cherche
    public var enableTextSearch = true
    public var enableTemporalRetrieval = true
    public var enableGraphRetrieval = true
    public var enableReranking = true
    // Le modèle de décision de chaque fonction se règle pour tout le serveur, dans Modèles ; la
    // banque n'en porte pas d'exception (un seul endroit pour ce réglage).
    /// Défauts de recall quand la requête ne dit rien (serveur 1.2.0).
    public var recallDecisionModelPrune = false
    public var recallDecisionModelDedup = false
    /// Un fait déjà résumé par une observation présente dans les mêmes résultats en est retiré.
    public var recallPreferObservations = false
    // Avancé (JSON brut ; vide = aucun)
    public var retainStrategies = ""
    public var retainDefaultStrategy = ""
    public var consolidationStrategies = ""
    public var memoryDefense = ""

    public init() {}

    /// Lecture de la configuration résolue.
    public init(config c: [String: JSONValue]) {
        func str(_ k: String) -> String? { if case .string(let s)? = c[k] { return s } else { return nil } }
        func int(_ k: String) -> Int? { c[k]?.intValue }
        func bool(_ k: String) -> Bool? { c[k]?.boolValue }
        func json(_ k: String) -> String {
            guard let v = c[k], v != .null else { return "" }
            return v.prettyString()
        }
        retainMission = str("retain_mission") ?? ""
        extractionMode = str("retain_extraction_mode") ?? "concise"
        customInstructions = str("retain_custom_instructions") ?? ""
        chunkSize = int("retain_chunk_size") ?? 3000
        if case .array(let groups)? = c["entity_labels"] { entityLabels = groups.compactMap(EntityLabelGroup.init(json:)) }
        entitiesAllowFreeForm = bool("entities_allow_free_form") ?? true
        storeDocumentText = bool("store_document_text") ?? true
        enableObservations = bool("enable_observations") ?? true
        enableAutoConsolidation = bool("enable_auto_consolidation") ?? true
        observationsMission = str("observations_mission") ?? ""
        maxObservationsPerScope = int("max_observations_per_scope") ?? -1
        defaultObservationScopes = str("default_observation_scopes") ?? ""
        reflectMission = str("reflect_mission") ?? ""
        skepticism = int("disposition_skepticism") ?? 3
        literalism = int("disposition_literalism") ?? 3
        empathy = int("disposition_empathy") ?? 3
        enableTextSearch = bool("enable_text_search") ?? true
        enableTemporalRetrieval = bool("enable_temporal_retrieval") ?? true
        enableGraphRetrieval = bool("enable_graph_retrieval") ?? true
        enableReranking = bool("enable_reranking") ?? true
        recallDecisionModelPrune = bool("recall_decision_model_prune") ?? false
        recallDecisionModelDedup = bool("recall_decision_model_dedup") ?? false
        recallPreferObservations = bool("recall_prefer_observations") ?? false
        retainStrategies = json("retain_strategies")
        retainDefaultStrategy = str("retain_default_strategy") ?? ""
        consolidationStrategies = json("consolidation_strategies")
        memoryDefense = json("memory_defense")
    }

    /// Valeurs à envoyer, par clé de configuration (`nil` = JSON avancé invalide).
    func values() -> [String: JSONValue]? {
        func text(_ s: String) -> JSONValue {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? .null : .string(t)
        }
        func raw(_ s: String) -> JSONValue? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return .null }
            return try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8))
        }
        guard let rs = raw(retainStrategies), let cs = raw(consolidationStrategies), let md = raw(memoryDefense) else { return nil }
        return [
            "retain_mission": text(retainMission),
            "retain_extraction_mode": .string(extractionMode),
            "retain_custom_instructions": text(customInstructions),
            "retain_chunk_size": .int(chunkSize),
            "entity_labels": entityLabels.isEmpty ? .null : .array(entityLabels.map(\.json)),
            "entities_allow_free_form": .bool(entitiesAllowFreeForm),
            "store_document_text": .bool(storeDocumentText),
            "enable_observations": .bool(enableObservations),
            "enable_auto_consolidation": .bool(enableAutoConsolidation),
            "observations_mission": text(observationsMission),
            "max_observations_per_scope": .int(maxObservationsPerScope),
            // Envoyé seulement s'il change (`updates(from:)`) : un serveur 1.0.0 ne connaît pas la clé.
            "default_observation_scopes": defaultObservationScopes.isEmpty ? .null : .string(defaultObservationScopes),
            "reflect_mission": text(reflectMission),
            "disposition_skepticism": .int(skepticism),
            "disposition_literalism": .int(literalism),
            "disposition_empathy": .int(empathy),
            "enable_text_search": .bool(enableTextSearch),
            "enable_temporal_retrieval": .bool(enableTemporalRetrieval),
            "enable_graph_retrieval": .bool(enableGraphRetrieval),
            "enable_reranking": .bool(enableReranking),
            // Envoyés seulement s'ils changent : inconnus d'un serveur 1.1.0.
            "recall_decision_model_prune": .bool(recallDecisionModelPrune),
            "recall_decision_model_dedup": .bool(recallDecisionModelDedup),
            "recall_prefer_observations": .bool(recallPreferObservations),
            "retain_strategies": rs,
            "retain_default_strategy": text(retainDefaultStrategy),
            "consolidation_strategies": cs,
            "memory_defense": md,
        ]
    }

    /// Modifications par rapport à `old`, prêtes pour `PATCH …/config` (`nil` si JSON avancé invalide).
    public func updates(from old: MemoryDesign) -> [String: JSONValue]? {
        guard let new = values(), let before = old.values() else { return nil }
        return new.filter { before[$0.key] != $0.value }
    }

    /// Nom de chaque réglage tel que la page « Comportement de la mémoire » l'affiche : la confirmation
    /// d'enregistrement et les problèmes parlent comme la page, pas avec les clés du serveur.
    public static let labels: [String: String] = [
        "retain_mission": "Mission de mémorisation",
        "retain_extraction_mode": "Style d'extraction",
        "retain_custom_instructions": "Instructions d'extraction",
        "retain_chunk_size": "Taille des segments en caractères",
        "store_document_text": "Conserver le texte des documents",
        "entities_allow_free_form": "Autoriser les entités libres",
        "entity_labels": "Étiquettes d'entités",
        "enable_observations": "Créer des observations",
        "enable_auto_consolidation": "Consolider automatiquement",
        "observations_mission": "Mission de consolidation",
        "max_observations_per_scope": "Maximum d'observations par portée",
        "default_observation_scopes": "Portée des observations par défaut",
        "reflect_mission": "Mission de réponse",
        "disposition_skepticism": "Esprit critique",
        "disposition_literalism": "Interprétation littérale",
        "disposition_empathy": "Empathie",
        "enable_text_search": "Recherche textuelle",
        "enable_temporal_retrieval": "Recherche temporelle",
        "enable_graph_retrieval": "Recherche par relations",
        "enable_reranking": "Réordonner les résultats",
        "recall_decision_model_prune": "Écarter les faits inutiles",
        "recall_decision_model_dedup": "Retirer les doublons",
        "recall_prefer_observations": "Préférer les observations",
    ]

    /// Clés de configuration que cette structure relit et enregistre ; une autre clé y serait ignorée.
    public static let editableKeys: Set<String> = Set(MemoryDesign().values()?.keys.map { $0 } ?? [])

    /// Problèmes bloquants (ou à signaler) avant l'enregistrement.
    public var problems: [String] {
        var p: [String] = []
        if values() == nil { p.append("Un réglage avancé n'est pas du JSON valide.") }
        if extractionMode == "custom" && customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.append("Le style d'extraction « Personnalisé » demande des instructions d'extraction.")
        }
        if chunkSize < 100 { p.append("Taille des segments trop petite (au moins 100 caractères).") }
        for (name, v) in [("Esprit critique", skepticism), ("Interprétation littérale", literalism), ("Empathie", empathy)] where !(1...5).contains(v) {
            p.append("\(name) : choisissez une valeur de 1 à 5.")
        }
        var seen = Set<String>()
        for g in entityLabels {
            // Le contrat n'impose aucun format de clé : on refuse seulement le vide et les espaces,
            // pour ne pas bloquer une banque dont le vocabulaire existant est en majuscules ou avec tirets.
            let k = g.key.trimmingCharacters(in: .whitespaces)
            if k.isEmpty || k.contains(where: \.isWhitespace) {
                p.append("Clé d'étiquette invalide « \(g.key) » (non vide, sans espace).")
            }
            if !seen.insert(k).inserted { p.append("Clé d'étiquette en double : \(k).") }
            if (g.type == "value" || g.type == "multi-values") && g.values.isEmpty {
                p.append("L'étiquette « \(k) » de type \(g.type) n'a aucune valeur permise.")
            }
        }
        return p
    }
}

/// Points de départ (réécrivables) pour les missions et le vocabulaire d'une banque.
public struct MemoryDesignPreset: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let summary: String
    public let apply: @Sendable (inout MemoryDesign) -> Void

    public static let all: [MemoryDesignPreset] = [
        MemoryDesignPreset(
            name: "Assistant de code (Codex)",
            summary: "Décisions techniques, conventions, problèmes et leurs causes ; ignore le bavardage et les sorties d'outils."
        ) { d in
            d.retainMission =
                "Retenir ce qui servira dans les prochaines sessions de développement : décisions d'architecture et leur justification, conventions du projet, préférences de l'utilisateur, bogues rencontrés avec leur cause et leur correctif, commandes et réglages qui ont fonctionné. Ignorer les salutations, les étapes intermédiaires sans conclusion, et le contenu brut des sorties d'outils."
            d.observationsMission =
                "Synthétiser des connaissances durables sur chaque projet : architecture, conventions, préférences de l'utilisateur, pièges connus. Signaler explicitement quand une décision récente remplace une ancienne."
            d.reflectMission = "Aider l'utilisateur à reprendre son travail de développement : répondre de façon précise et sourcée, en signalant les incertitudes."
            d.entityLabels = [
                EntityLabelGroup(
                    key: "kind", description: "Nature du fait", type: "value", tag: true,
                    values: [
                        LabelValue(value: "decision", description: "Choix technique et sa justification"),
                        LabelValue(value: "convention", description: "Règle ou habitude du projet"),
                        LabelValue(value: "bug", description: "Problème rencontré, cause, correctif"),
                        LabelValue(value: "preference", description: "Préférence de l'utilisateur"),
                    ])
            ]
        },
        MemoryDesignPreset(
            name: "Recherche et lecture",
            summary: "Affirmations, méthodes, résultats chiffrés et leurs sources ; distingue les faits établis des hypothèses."
        ) { d in
            d.retainMission =
                "Retenir les affirmations et résultats importants avec leurs conditions (méthode, données, chiffres, limites), les définitions, et qui les a avancés. Distinguer les résultats établis des hypothèses et des opinions. Ignorer les formules de politesse et les répétitions."
            d.observationsMission =
                "Construire une synthèse par sujet : consensus, désaccords, résultats qui se contredisent, questions ouvertes."
            d.reflectMission = "Répondre comme un assistant de recherche rigoureux : citer les sources, séparer faits et interprétations."
            d.skepticism = 4
            d.literalism = 4
        },
        MemoryDesignPreset(
            name: "Assistant personnel",
            summary: "Personnes, engagements, préférences et échéances ; peu de détails techniques."
        ) { d in
            d.retainMission =
                "Retenir les personnes et leurs relations, les engagements et échéances, les préférences et habitudes, les événements marquants et leurs dates. Ignorer les détails techniques sans conséquence."
            d.observationsMission = "Tenir à jour un portrait de chaque personne et de chaque engagement en cours."
            d.empathy = 4
        },
    ]
}
