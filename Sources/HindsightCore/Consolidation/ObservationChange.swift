import Foundation
import HindsightAPI

/// Un fait source tel que le serveur le renvoie avec une observation ou son historique.
public struct SourceFactSummary: Sendable, Equatable, Encodable {
    public let id: String
    public let text: String
    public let type: String?
    public let context: String?

    init?(_ value: JSONValue) {
        guard let id = value["id"]?.stringValue, let text = value["text"]?.stringValue else { return nil }
        self.id = id
        self.text = text
        type = value["type"]?.stringValue ?? value["fact_type"]?.stringValue
        context = value["context"]?.stringValue
    }
}

/// Ce que la consolidation a fait d'une observation pendant la période, lu dans son historique
/// (`GET …/memories/{id}/history`), avec les mots de Hindsight : une observation est créée ou mise à jour.
/// Une mise à jour garde le texte quand le fait ne fait que la confirmer : il devient un fait source de plus.
public struct ObservationChange: Sendable, Equatable, Encodable, Identifiable {
    public enum Kind: String, Sendable, Encodable {
        /// Aucune mise à jour depuis sa création.
        case created
        /// Au moins une mise à jour : texte réécrit, ou fait source ajouté.
        case updated
    }

    public let id: String
    /// Nil si l'historique n'a pas pu être lu : la ligne ne prétend alors rien.
    public let kind: Kind?
    public let text: String
    public let updatedAt: String?
    public let tags: [String]
    /// Faits qui soutiennent l'observation (`proof_count`).
    public let proofCount: Int
    /// Faits sources de l'observation (`source_memory_ids`).
    public let sourceCount: Int
    /// Mises à jour enregistrées pendant la période.
    public let updates: Int
    /// Texte avant la première mise à jour de la période.
    public let previousText: String?
    public let textChanged: Bool
    /// Faits sources ajoutés pendant la période (les premiers ; leur nombre total dans `newSourceCount`).
    public let newSources: [SourceFactSummary]
    public let newSourceCount: Int
    /// Nombres, identifiants, chemins et dates présents avant la période et absents du texte actuel.
    public let removedValues: [String]
    public let diff: [DiffSegment]?

    static let maxNewSources = 8

    /// `history` : réponse brute du serveur (liste d'instantanés pris avant chaque mise à jour) ; nil si illisible.
    public init(item: MemoryUnitListItem, history: JSONValue?, since: Date) {
        id = item.id
        text = item.text
        updatedAt = item.updatedAt
        tags = item.tags
        proofCount = item.proofCount
        sourceCount = item.sourceMemoryIds.count
        guard let entries = history?.arrayValue else {
            kind = nil; updates = 0; previousText = nil; textChanged = false
            newSources = []; newSourceCount = 0; removedValues = []; diff = nil
            return
        }
        let dated = entries.compactMap { entry -> (Date, JSONValue)? in
            guard let at = HSDate.parse(entry["changed_at"]?.stringValue) else { return nil }
            return (at, entry)
        }.sorted { $0.0 < $1.0 }
        let inPeriod = dated.filter { $0.0 >= since }.map(\.1)
        kind = entries.isEmpty ? .created : .updated
        updates = inPeriod.count
        let before = inPeriod.first?["previous_text"]?.stringValue
        previousText = before
        let changed = before.map { Self.flattened($0) != Self.flattened(item.text) } ?? false
        textChanged = changed
        var seen = Set<String>(), added: [SourceFactSummary] = [], addedIDs = Set<String>()
        for entry in inPeriod {
            for id in entry["new_source_memory_ids"]?.arrayValue?.compactMap(\.stringValue) ?? [] { addedIDs.insert(id) }
            for fact in entry["source_facts"]?.arrayValue ?? [] where fact["is_new"]?.boolValue == true {
                guard let summary = SourceFactSummary(fact), seen.insert(summary.id).inserted else { continue }
                addedIDs.insert(summary.id)
                if added.count < Self.maxNewSources { added.append(summary) }
            }
        }
        newSources = added
        newSourceCount = addedIDs.count
        if changed, let before {
            removedValues = ObservationValues.removed(from: before, to: item.text)
            diff = TextDiff.words(before, item.text)
        } else {
            removedValues = []
            diff = nil
        }
    }

    static func flattened(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Nombre d'observations créées et mises à jour pendant la période, lus sur le serveur.
public struct ObservationChangeCounts: Sendable, Equatable, Encodable {
    public let created: Int
    /// Observations touchées pendant la période sans y avoir été créées.
    public let updated: Int

    public init(created: Int, touched: Int) {
        self.created = created
        updated = max(0, touched - created)
    }
}

// MARK: - Différences mot à mot

public struct DiffSegment: Sendable, Equatable, Encodable {
    public enum Kind: String, Sendable, Encodable { case same, added, removed }
    public let kind: Kind
    public let text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum TextDiff {
    /// Au-delà, le calcul serait trop long pour l'affichage : ancien texte retiré, nouveau ajouté.
    static let maxCells = 1_500_000

    /// Différences mot à mot ; chaque mot garde l'espace qui le suit, pour que les segments recollés redonnent les textes.
    public static func words(_ old: String, _ new: String) -> [DiffSegment] {
        let a = tokens(old), b = tokens(new)
        if a.isEmpty && b.isEmpty { return [] }
        guard a.count * b.count <= maxCells else {
            return [DiffSegment(.removed, old), DiffSegment(.added, new)].filter { !$0.text.isEmpty }
        }
        let n = a.count, m = b.count
        let keyA = a.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let keyB = b.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Longueur de la plus longue sous-suite commune des suffixes.
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        let width = m + 1
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i * width + j] = keyA[i] == keyB[j]
                        ? table[(i + 1) * width + j + 1] + 1
                        : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
        }
        var segments: [DiffSegment] = []
        func push(_ kind: DiffSegment.Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = DiffSegment(kind, last.text + text)
            } else {
                segments.append(DiffSegment(kind, text))
            }
        }
        var i = 0, j = 0
        while i < n && j < m {
            if keyA[i] == keyB[j] {
                push(.same, b[j]); i += 1; j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                push(.removed, a[i]); i += 1
            } else {
                push(.added, b[j]); j += 1
            }
        }
        while i < n { push(.removed, a[i]); i += 1 }
        while j < m { push(.added, b[j]); j += 1 }
        return segments
    }

    /// Mots suivis de leurs espaces ; un espace initial forme son propre mot.
    static func tokens(_ s: String) -> [String] {
        var out: [String] = [], current = ""
        var inSpace = false
        for ch in s {
            if ch.isWhitespace {
                current.append(ch); inSpace = true
            } else {
                if inSpace, !current.isEmpty { out.append(current); current = "" }
                inSpace = false
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

// MARK: - Valeurs d'un texte

/// Les valeurs qu'une réécriture ne devrait pas perdre sans raison : nombres, identifiants (run, job, empreinte),
/// chemins, clés de configuration et dates. Une valeur retirée n'est pas forcément perdue (une nouvelle mesure
/// remplace l'ancienne, gardée dans l'historique et les faits sources) : l'app la montre, l'utilisateur juge.
public enum ObservationValues {
    /// Valeurs du texte ancien absentes du nouveau, dans leur ordre d'apparition (forme du texte ancien, dates en ISO).
    public static func removed(from old: String, to new: String) -> [String] {
        let after = values(new)
        let afterKeys = Set(after.map(\.key))
        let afterText = normalized(withISODates(new))
        var seen = Set<String>(), out: [String] = []
        for value in values(old) where !afterKeys.contains(value.key) && !afterText.contains(value.key) {
            if seen.insert(value.key).inserted { out.append(value.display) }
        }
        return out
    }

    struct Value: Equatable {
        let display: String
        let key: String
    }

    static func values(_ text: String) -> [Value] {
        var out: [Value] = []
        let separators: (Character) -> Bool = { $0.isWhitespace || $0 == "–" || $0 == "—" }
        for raw in withISODates(text).split(whereSeparator: separators) {
            let word = trim(String(raw))
            guard keep(word) else { continue }
            out.append(Value(display: word, key: normalized(word)))
        }
        return out
    }

    private static let leading = Set("([{«\"'“‘<")
    private static let trailing = Set(")]}»\"'”’>,;:!?….%")

    static func trim(_ word: String) -> String {
        var w = Substring(word)
        while let c = w.first, leading.contains(c) { w = w.dropFirst() }
        while let c = w.last, trailing.contains(c) { w = w.dropLast() }
        return String(w)
    }

    /// Un nombre d'au moins deux caractères, ou un identifiant composé (`source_horloge`, `essai-3/web`, `a.json`).
    static func keep(_ word: String) -> Bool {
        guard word.count >= 2 else { return false }
        if word.contains(where: \.isNumber) { return true }
        let chars = Array(word)
        guard chars.count >= 3 else { return false }
        for k in 1..<(chars.count - 1) where "_/.".contains(chars[k]) {
            if chars[k - 1].isLetter || chars[k - 1].isNumber, chars[k + 1].isLetter || chars[k + 1].isNumber { return true }
        }
        return false
    }

    /// Minuscules, signe moins unique, virgule décimale en point, espaces insécables retirés.
    static func normalized(_ s: String) -> String {
        var out = ""
        let chars = Array(s.lowercased().replacingOccurrences(of: "−", with: "-"))
        for (k, c) in chars.enumerated() {
            if c == "\u{00A0}" || c == "\u{202F}" { continue }
            if c == ",", k > 0, k + 1 < chars.count, chars[k - 1].isNumber, chars[k + 1].isNumber {
                out.append(".")
            } else {
                out.append(c)
            }
        }
        return out
    }

    private static let months: [String: Int] = [
        "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7,
        "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
    ]
    private static let dayMonthYear = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?:er)?\s+([A-Za-zÀ-ÿ]+)\s+(\d{4})\b"#)
    private static let monthDayYear = try! NSRegularExpression(
        pattern: #"\b([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})\b"#)

    /// Dates écrites en toutes lettres (« 21 octobre 2026 », « October 21, 2026 ») remplacées par leur forme ISO,
    /// pour qu'une date reformulée ne passe pas pour retirée.
    static func withISODates(_ text: String) -> String {
        var result = text
        for (regex, dayGroup, monthGroup) in [(dayMonthYear, 1, 2), (monthDayYear, 2, 1)] {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let monthName = ns.substring(with: match.range(at: monthGroup)).lowercased()
                guard let month = months[monthName], let day = Int(ns.substring(with: match.range(at: dayGroup))),
                      (1...31).contains(day) else { continue }
                let year = ns.substring(with: match.range(at: 3))
                let iso = year + String(format: "-%02d-%02d", month, day)
                result = (result as NSString).replacingCharacters(in: match.range, with: iso)
            }
        }
        return result
    }
}
