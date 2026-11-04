import Foundation

/// Une affectation de variable d'environnement trouvée dans le script (`export NOM=valeur`).
public struct EnvAssignment: Sendable, Hashable {
    public let name: String
    /// Valeur après interprétation des guillemets shell.
    public let value: String
    public let line: Int
    public let exported: Bool
    /// Contient une expansion (`$VAR`, `$(…)`, `` `…` ``) : la valeur réelle dépend de l'exécution.
    public let isDynamic: Bool
}

/// Script de lancement du serveur (shell), lu et modifié ligne par ligne : seules les lignes d'affectation
/// touchées sont réécrites, tout le reste (commentaires, commandes, mise en forme) est conservé à l'identique.
public struct LaunchScript: Sendable, Equatable {
    public private(set) var lines: [String]
    /// Le fichier se terminait par un retour à la ligne.
    private let trailingNewline: Bool

    public init(text: String) {
        trailingNewline = text.hasSuffix("\n")
        var l = text.components(separatedBy: "\n")
        if trailingNewline { l.removeLast() }
        lines = l
    }

    public var text: String { lines.joined(separator: "\n") + (trailingNewline ? "\n" : "") }

    // MARK: Lecture

    struct ParsedLine {
        let indent: String
        let exported: Bool
        let name: String
        let rawValue: String
        let value: String
        let isDynamic: Bool
        let trailing: String
        let quote: Character?
    }

    static func parse(_ line: String) -> ParsedLine? {
        var rest = Substring(line)
        let indent = String(rest.prefix { $0 == " " || $0 == "\t" })
        rest = rest.dropFirst(indent.count)
        var exported = false
        if rest.hasPrefix("export ") || rest.hasPrefix("export\t") {
            exported = true
            rest = rest.dropFirst(7)
            rest = rest.drop { $0 == " " || $0 == "\t" }
        }
        guard let eq = rest.firstIndex(of: "=") else { return nil }
        let name = String(rest[..<eq])
        guard let first = name.first, first == "_" || first.isLetter, name.allSatisfy({ $0 == "_" || $0.isLetter || $0.isNumber }),
            name.unicodeScalars.allSatisfy({ $0.isASCII })
        else { return nil }
        let afterEq = rest[rest.index(after: eq)...]
        guard let word = ShellWord.read(afterEq) else { return nil }
        let trailing = String(afterEq[word.end...])
        // Une seconde affectation ou une commande sur la même ligne : ligne trop complexe, laissée telle quelle.
        let t = trailing.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, !t.hasPrefix("#") { return nil }
        return ParsedLine(
            indent: indent, exported: exported, name: name, rawValue: String(afterEq[..<word.end]), value: word.value,
            isDynamic: word.isDynamic, trailing: trailing, quote: word.quote)
    }

    /// Toutes les affectations, dans l'ordre du fichier.
    public var assignments: [EnvAssignment] {
        lines.enumerated().compactMap { i, l in
            guard let p = Self.parse(l) else { return nil }
            return EnvAssignment(name: p.name, value: p.value, line: i, exported: p.exported, isDynamic: p.isDynamic)
        }
    }

    /// Dernière affectation de `name` (celle qui l'emporte à l'exécution).
    public func assignment(_ name: String) -> EnvAssignment? { assignments.last { $0.name == name } }

    public func value(_ name: String) -> String? { assignment(name)?.value }

    public func occurrences(_ name: String) -> Int { assignments.filter { $0.name == name }.count }

    /// Variables `HINDSIGHT_API_*` présentes (dernière valeur), triées par nom.
    public var hindsightVariables: [EnvAssignment] {
        var last: [String: EnvAssignment] = [:]
        for a in assignments where a.name.hasPrefix("HINDSIGHT_API_") { last[a.name] = a }
        return last.values.sorted { $0.name < $1.name }
    }

    /// Points d'attention : fichiers inclus, variables posées sur une ligne de commande, valeurs dynamiques.
    public var warnings: [String] {
        var out: [String] = []
        for (i, raw) in lines.enumerated() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("#") || l.isEmpty { continue }
            if l.hasPrefix("source ") || l.hasPrefix(". ") {
                out.append("Ligne \(i + 1) : « \(l) » charge un autre fichier ; des variables peuvent y être définies (non éditées ici).")
            } else if Self.parse(raw) == nil, l.range(of: #"HINDSIGHT_API_[A-Z0-9_]+="#, options: .regularExpression) != nil {
                out.append("Ligne \(i + 1) : une variable HINDSIGHT_API_ est posée sur une ligne de commande ; elle n'est pas éditable ici.")
            }
        }
        for a in hindsightVariables where a.isDynamic {
            out.append("\(a.name) (ligne \(a.line + 1)) dépend de l'environnement (« $… ») ; la modifier la remplace par une valeur fixe.")
        }
        return out
    }

    // MARK: Modification

    /// Pose `name = value`. Modifie la dernière affectation existante, sinon ajoute une ligne `export`.
    public mutating func set(_ name: String, to value: String) {
        if let a = assignment(name), let p = Self.parse(lines[a.line]) {
            if p.value == value { return }
            lines[a.line] = p.indent + (p.exported ? "export " : "") + name + "=" + ShellWord.quote(value, preferring: p.quote) + p.trailing
            return
        }
        // Un éventuel ancien `# export NAME=` commenté par nous est réactivé à sa place.
        let commented = "# " + "export \(name)="
        if let i = lines.firstIndex(where: { $0.hasPrefix(commented) }) {
            lines[i] = "export \(name)=" + ShellWord.quote(value, preferring: nil)
            return
        }
        lines.insert("export \(name)=" + ShellWord.quote(value, preferring: nil), at: insertionIndex())
    }

    /// Désactive toutes les affectations de `name` en les commentant (réversible, rien n'est effacé).
    public mutating func unset(_ name: String) {
        for a in assignments where a.name == name {
            lines[a.line] = "# " + lines[a.line]
        }
    }

    /// Restaure les lignes d'origine, expansions et guillemets compris. Réécrire seulement la
    /// valeur interprétée transformerait par exemple "$TOKEN" en une chaîne littérale.
    public mutating func restore(_ name: String, from original: LaunchScript) {
        func matches(_ line: String) -> Bool {
            if Self.parse(line)?.name == name { return true }
            return line.hasPrefix("# ") && Self.parse(String(line.dropFirst(2)))?.name == name
        }
        let originals = original.lines.filter(matches)
        let positions = lines.indices.filter { matches(lines[$0]) }
        // Garder la position de chaque occurrence et les lignes intermédiaires.
        for (offset, index) in positions.enumerated().reversed() {
            if offset < originals.count { lines[index] = originals[offset] }
            else { lines.remove(at: index) }
        }
        if positions.count < originals.count {
            lines.insert(contentsOf: originals.dropFirst(positions.count), at: insertionIndex())
        }
    }

    /// Après la dernière affectation HINDSIGHT_API_, sinon avant la première commande, sinon à la fin.
    func insertionIndex() -> Int {
        if let last = assignments.last(where: { $0.name.hasPrefix("HINDSIGHT_API_") }) { return last.line + 1 }
        for (i, raw) in lines.enumerated() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || Self.parse(raw) != nil || l.hasPrefix("set ") { continue }
            return i
        }
        return lines.count
    }

    // MARK: Masquage des secrets

    public static func isSecret(_ name: String) -> Bool {
        // Un nombre de jetons (…_MAX_REQUEST_TOKENS) ou un tokenizer n'est pas un jeton d'accès.
        let n = name.uppercased().replacingOccurrences(of: "TOKENS", with: "").replacingOccurrences(of: "TOKENIZER", with: "")
        return ["KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL"].contains { n.contains($0) }
            || n.hasSuffix("DATABASE_URL")
    }

    /// La ligne, avec la valeur masquée si la variable est un secret (pour l'affichage et le diff).
    public static func masked(_ line: String) -> String {
        if line.hasPrefix("# ") { return "# " + masked(String(line.dropFirst(2))) }
        guard let p = parse(line), isSecret(p.name) else { return line }
        let shown = p.value.isEmpty ? "" : "••••" + (p.value.count > 8 ? String(p.value.suffix(2)) : "")
        return p.indent + (p.exported ? "export " : "") + p.name + "=" + shown + p.trailing
    }

    public static func maskValue(_ name: String, _ value: String) -> String {
        guard isSecret(name), !value.isEmpty else { return value }
        return "••••" + (value.count > 8 ? String(value.suffix(2)) : "")
    }
}

/// Lecture / écriture d'un « mot » shell (valeur d'affectation).
enum ShellWord {
    struct Read {
        let value: String
        let end: Substring.Index
        let isDynamic: Bool
        let quote: Character?
    }

    /// Lit un mot au début de `s` : suites de '…', "…" et caractères nus, jusqu'à un blanc ou `;` non protégé.
    static func read(_ s: Substring) -> Read? {
        var value = ""
        var i = s.startIndex
        var dynamic = false
        var firstQuote: Character?
        while i < s.endIndex {
            let c = s[i]
            if c == " " || c == "\t" || c == ";" { break }
            if c == "'" {
                firstQuote = firstQuote ?? "'"
                guard let close = s[s.index(after: i)...].firstIndex(of: "'") else { return nil }
                value += s[s.index(after: i)..<close]
                i = s.index(after: close)
            } else if c == "\"" {
                firstQuote = firstQuote ?? "\""
                i = s.index(after: i)
                var closed = false
                while i < s.endIndex {
                    let d = s[i]
                    if d == "\"" {
                        closed = true
                        i = s.index(after: i)
                        break
                    }
                    if d == "\\", s.index(after: i) < s.endIndex, "\"\\$`".contains(s[s.index(after: i)]) {
                        value.append(s[s.index(after: i)])
                        i = s.index(i, offsetBy: 2)
                        continue
                    }
                    if d == "$" || d == "`" { dynamic = true }
                    value.append(d)
                    i = s.index(after: i)
                }
                if !closed { return nil }
            } else if c == "\\" {
                let n = s.index(after: i)
                guard n < s.endIndex else { return nil }
                value.append(s[n])
                i = s.index(after: n)
            } else {
                if c == "$" || c == "`" { dynamic = true }
                value.append(c)
                i = s.index(after: i)
            }
        }
        return Read(value: value, end: i, isDynamic: dynamic, quote: firstQuote)
    }

    static let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:@%+,-=")

    /// Valeur littérale protégée : nue si sûre, sinon entre guillemets (doubles si c'était le style et que
    /// rien n'est interprétable, simples sinon).
    static func quote(_ v: String, preferring: Character?) -> String {
        if !v.isEmpty, v.unicodeScalars.allSatisfy({ safe.contains($0) }), preferring == nil { return v }
        if preferring == "\"", !v.contains(where: { "\"\\$`".contains($0) }) { return "\"\(v)\"" }
        return "'" + v.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
