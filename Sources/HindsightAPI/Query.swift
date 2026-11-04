import Foundation

typealias QueryItems = [(String, String?)]

infix operator +++: AdditionPrecedence

/// Concaténation de paramètres de requête. Opérateur dédié : `+` sur des tableaux de tuples rend
/// la vérification de types du compilateur extrêmement lente.
func +++ (l: QueryItems, r: QueryItems) -> QueryItems { l + r }

/// Aides pour construire les paramètres de requête.
enum Q {
    static func int(_ n: String, _ v: Int?) -> [(String, String?)] { [(n, v.map(String.init))] }
    static func bool(_ n: String, _ v: Bool?) -> [(String, String?)] { [(n, v.map { $0 ? "true" : "false" })] }
    static func str(_ n: String, _ v: String?) -> [(String, String?)] {
        guard let v, !v.isEmpty else { return [] }
        return [(n, v)]
    }
    /// Paramètre répété (`tags=a&tags=b`), comme FastAPI l'attend pour les listes.
    static func list(_ n: String, _ v: [String]?) -> [(String, String?)] {
        (v ?? []).map { (n, $0) }
    }
}

/// Filtre de tags commun à plusieurs listes (mémoires, documents, entités, graphe).
public struct TagFilter: Sendable, Hashable {
    public var tags: [String]
    public var match: TagsMatch

    public init(tags: [String] = [], match: TagsMatch = .any) {
        self.tags = tags
        self.match = match
    }

    public var isEmpty: Bool { tags.isEmpty }
}

/// Fenêtre temporelle ISO 8601 pour les listes filtrables par date.
public struct TimeWindow: Sendable, Hashable {
    /// `created_at`, `updated_at`, `mentioned_at`, `occurred_start`, `occurred_end`.
    public var field: String?
    public var start: Date?
    public var end: Date?

    public init(field: String? = nil, start: Date? = nil, end: Date? = nil) {
        self.field = field
        self.start = start
        self.end = end
    }

    var queryItems: [(String, String?)] {
        Q.str("time_field", field) +++ Q.str("start_date", start.map(HSDate.format))
            +++ Q.str("end_date", end.map(HSDate.format))
    }
}
