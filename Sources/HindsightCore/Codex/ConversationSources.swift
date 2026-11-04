import Foundation
import HindsightAPI

/// Outil dont proviennent les conversations importées.
public enum ConversationSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex
    case claudeCode = "claude-code"
    case hermes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .hermes: return "Hermes"
        }
    }

    /// Rôle de l'assistant dans le texte importé.
    public var assistantName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude"
        case .hermes: return "Hermes"
        }
    }

    /// Préfixe des identifiants de documents (`codex-<session>-task-NNN`, `claude-code-…`, `hermes-…`).
    public var documentPrefix: String { rawValue }
    /// Valeur du tag `source:` et de la métadonnée `source`.
    public var tagValue: String { rawValue }

    public func defaultRoots(home: URL) -> [URL] {
        switch self {
        case .codex, .claudeCode:
            return []  // Collected by Agent Dump in the common memory folder.
        case .hermes:
            // Base du profil par défaut, puis celles des profils nommés (~/.hermes/profiles/<nom>/state.db).
            let root = ProcessInfo.processInfo.environment["HERMES_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".hermes")
            var dbs = [root.appendingPathComponent("state.db")]
            let profiles = root.appendingPathComponent("profiles")
            if let names = try? FileManager.default.contentsOfDirectory(atPath: profiles.path) {
                dbs += names.sorted().map { profiles.appendingPathComponent($0).appendingPathComponent("state.db") }
            }
            return dbs
        }
    }
}

/// Lecture d'une session quelle que soit sa source (Codex, Claude Code ou Hermes).
public enum ConversationReader {
    public enum ReadError: Error, CustomStringConvertible {
        case collectedExternally
        public var description: String { "Les conversations Codex et Claude Code sont collectées par Agent Dump dans le dossier mémoire." }
    }

    public static func source(of file: CodexFile) -> ConversationSource {
        file.hermesSession != nil ? .hermes : file.path.contains("/.claude/") ? .claudeCode : .codex
    }
    public static func summarize(_ file: CodexFile, zstd: URL?) -> CodexSessionSummary {
        guard file.hermesSession != nil else {
            var result = CodexSessionSummary(file: file)
            result.error = ReadError.collectedExternally.description
            return result
        }
        return HermesReader.summarize(file)
    }
    public static func parse(_ file: CodexFile, zstd: URL?) throws -> CodexConversation {
        guard file.hermesSession != nil else { throw ReadError.collectedExternally }
        return try HermesReader.parse(file)
    }
}

// MARK: - Hermes

/// Sessions de Hermes Agent (Nous Research) : base SQLite `~/.hermes/state.db` (tables `sessions` et
/// `messages`), une base par profil. Lecture seule par l'outil `sqlite3` du système, base ouverte avec
/// `-readonly` : l'app n'écrit jamais dedans.
///
/// Historique complet affiché comme Hermes le fait : lignes actives, plus celles archivées par une
/// compaction (`active = 1 OR compacted = 1`) ; les résumés de compaction (`_compressed_summary`), les
/// messages observés mais non adressés (`observed`) et les messages système sont écartés.
public enum HermesReader {
    public static let sqlite3 = "/usr/bin/sqlite3"
    /// Préfixe des contenus structurés (JSON) dans `messages.content`.
    static let jsonPrefix = "\u{0}json:"
    /// Sources Hermes qui ne sont pas une conversation avec l'utilisateur.
    static let automatedSources: Set<String> = ["subagent", "cron", "kanban", "tool", "recovered", "batch"]

    public enum ReadError: Error, CustomStringConvertible {
        case sqliteMissing
        case query(String)

        public var description: String {
            switch self {
            case .sqliteMissing: return "L'outil sqlite3 est introuvable (/usr/bin/sqlite3)."
            case .query(let m): return "Lecture de la base Hermes impossible : \(m)"
            }
        }
    }

    /// Exécute une requête en lecture seule et décode la sortie JSON de `sqlite3 -json`.
    ///
    /// `sqlite3 -json` écrit les colonnes TEXT jusqu'au premier octet nul : les contenus structurés de
    /// Hermes (préfixe `\0json:`) arriveraient vides. Les requêtes les lisent donc en `hex(...)`, décodé
    /// par `unhex(_:)`.
    static func query(_ db: URL, _ sql: String) throws -> [[String: JSONValue]] {
        guard FileManager.default.isExecutableFile(atPath: sqlite3) else { throw ReadError.sqliteMissing }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: sqlite3)
        p.arguments = ["-readonly", "-json", databaseArgument(db), sql]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { throw ReadError.query(error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ReadError.query(errText.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if data.allSatisfy({ $0 == 0x0A || $0 == 0x20 }) { return [] }
        guard case .array(let rows) = try JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return rows.compactMap { if case .object(let o) = $0 { return o } else { return nil } }
    }

    /// Chemin passé à sqlite3. Sans journal WAL présent, la base est ouverte `immutable` : SQLite ne crée
    /// alors ni `-wal` ni `-shm` à côté — l'app ne dépose aucun fichier dans `~/.hermes`. Quand Hermes
    /// a déjà ses fichiers de journal, l'ouverture en lecture seule classique voit les dernières écritures.
    static func databaseArgument(_ db: URL) -> String {
        let wal = db.path + "-wal"
        guard !FileManager.default.fileExists(atPath: wal) else { return db.path }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%")
        let encoded = db.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? db.path
        return "file:\(encoded)?immutable=1&mode=ro"
    }

    /// Décode une colonne lue en `hex(...)`.
    static func unhex(_ s: String) -> String? {
        guard s.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Texte d'une colonne : `<name>_hex` si la requête l'a lue en hexadécimal, sinon la colonne brute.
    static func text(_ row: [String: JSONValue], _ name: String) -> String? {
        if let h = row[name + "_hex"]?.stringValue { return unhex(h) }
        return row[name]?.stringValue
    }

    static func columns(_ db: URL, table: String) throws -> Set<String> {
        Set(try query(db, "PRAGMA table_info(\(table));").compactMap { $0["name"]?.stringValue })
    }

    /// Identifiant de session utilisable dans une requête (les ids Hermes sont alphanumériques).
    static func quoted(_ id: String) -> String? {
        guard id.range(of: #"^[A-Za-z0-9._:@-]+$"#, options: .regularExpression) != nil else { return nil }
        return "'" + id.replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: Liste des sessions

    public static func summaries(database db: URL) -> [CodexSessionSummary] {
        guard FileManager.default.fileExists(atPath: db.path) else { return [] }
        let modified = ((try? FileManager.default.attributesOfItem(atPath: db.path))?[.modificationDate] as? Date) ?? .distantPast
        do {
            let cols = try columns(db, table: "sessions")
            let want = ["id", "source", "model", "title", "started_at", "ended_at", "parent_session_id", "message_count", "cwd", "user_id"]
            let select = want.filter(cols.contains).joined(separator: ", ")
            let firstUser =
                // substr(TEXT) s'arrête à l'octet nul du préfixe structuré ; BLOB conserve les octets.
                "(SELECT hex(substr(CAST(content AS BLOB), 1, 600)) FROM messages m WHERE m.session_id = s.id AND m.role = 'user' ORDER BY m.timestamp, m.id LIMIT 1) AS first_user_hex"
            let rows = try query(db, "SELECT \(select), \(firstUser) FROM sessions s ORDER BY started_at DESC;")
            return rows.map { summary($0, db: db, modified: modified) }
        } catch {
            var s = CodexSessionSummary(file: CodexFile(database: db, session: "?", modified: modified))
            s.error = "\(error)"
            return [s]
        }
    }

    static func meta(_ row: [String: JSONValue]) -> CodexSessionMeta {
        let source = row["source"]?.stringValue ?? "?"
        return CodexSessionMeta(
            id: row["id"]?.stringValue ?? "?", rootID: row["parent_session_id"]?.stringValue,
            timestamp: row["started_at"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }, cwd: row["cwd"]?.stringValue,
            originator: "hermes (\(source))", threadSource: automatedSources.contains(source) ? "subagent" : "user",
            modelProvider: row["model"]?.stringValue, parentThreadID: row["parent_session_id"]?.stringValue, sourceKind: .hermes,
            title: row["title"]?.stringValue)
    }

    static func summary(_ row: [String: JSONValue], db: URL, modified: Date) -> CodexSessionSummary {
        let m = meta(row)
        var s = CodexSessionSummary(file: CodexFile(database: db, session: m.id, modified: modified))
        s.meta = m
        if let raw = text(row, "first_user") {
            // Un contenu JSON tronqué à 600 caractères ne se décode pas : on en extrait les textes à la main.
            let text = userBlocks(raw).compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: " ")
            let fallback = raw.hasPrefix(jsonPrefix) ? Self.textFragments(raw) : ""
            let best = text.isEmpty ? fallback : text
            s.firstUserText = best.isEmpty ? m.title : String(best.prefix(240))
        } else {
            s.firstUserText = m.title
        }
        return s
    }

    // MARK: Conversation

    public static func summarize(_ file: CodexFile) -> CodexSessionSummary {
        summaries(database: file.url).first { $0.file.hermesSession == file.hermesSession }
            ?? {
                var s = CodexSessionSummary(file: file)
                s.error = "Session introuvable dans la base."
                return s
            }()
    }

    public static func parse(_ file: CodexFile) throws -> CodexConversation {
        guard let session = file.hermesSession, let q = quoted(session) else { throw ReadError.query("identifiant de session invalide") }
        let db = file.url
        let sessionRow = try query(db, "SELECT * FROM sessions WHERE id = \(q);").first ?? ["id": .string(session)]
        let cols = try columns(db, table: "messages")
        let want = [
            "id", "role", "tool_call_id", "tool_calls", "tool_name", "timestamp", "reasoning", "active", "compacted",
            "observed", "_compressed_summary",
        ]
        var filter = "session_id = \(q)"
        if cols.contains("active") && cols.contains("compacted") { filter += " AND (active = 1 OR compacted = 1)" }
        let select = (want.filter(cols.contains) + ["hex(content) AS content_hex"]).joined(separator: ", ")
        let rows = try query(db, "SELECT \(select) FROM messages WHERE \(filter) ORDER BY timestamp, id;")
        return conversation(session: sessionRow, messages: rows)
    }

    /// Valeurs `"text": "…"` d'un JSON éventuellement tronqué (aperçu du premier message).
    static func textFragments(_ raw: String) -> String {
        var out: [String] = []
        var rest = Substring(raw)
        while let r = rest.range(of: "\"text\"") {
            rest = rest[r.upperBound...]
            guard let colon = rest.firstIndex(of: ":") else { break }
            var s = rest[rest.index(after: colon)...].drop(while: { $0 == " " })
            guard s.first == "\"" else { continue }
            s = s.dropFirst()
            var value = ""
            var escaped = false
            var closed = false
            for c in s {
                if escaped {
                    value.append(c == "n" ? "\n" : c)
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    closed = true
                    break
                } else {
                    value.append(c)
                }
            }
            if !value.isEmpty { out.append(value) }
            if !closed { break }
            rest = s
        }
        return out.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Construit la conversation depuis les lignes (séparé de la lecture SQLite pour les tests).
    static func conversation(session: [String: JSONValue], messages rows: [[String: JSONValue]]) -> CodexConversation {
        var conv = CodexConversation(meta: meta(session))
        var seen = Set<String>()
        for (i, r) in rows.enumerated() {
            let role = r["role"]?.stringValue ?? "?"
            let date = r["timestamp"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
            let content = text(r, "content") ?? ""
            if r["_compressed_summary"]?.intValue == 1 {
                conv.skipped["résumé de compaction", default: 0] += 1
                continue
            }
            if r["observed"]?.intValue == 1 {
                conv.skipped["message observé", default: 0] += 1
                continue
            }
            // Une compaction peut garder une copie identique d'un message (même rôle, texte et horodatage).
            let fingerprint = "\(role)|\(r["timestamp"]?.doubleValue ?? 0)|\(content.hashValue)|\(r["tool_call_id"]?.stringValue ?? "")"
            guard seen.insert(fingerprint).inserted else {
                conv.skipped["doublon de compaction", default: 0] += 1
                continue
            }
            switch role {
            case "user":
                let blocks = userBlocks(content)
                if !blocks.isEmpty { conv.events.append(.user(ordinal: i, date: date, blocks: blocks)) }
            case "assistant":
                if let reasoning = r["reasoning"]?.stringValue, !reasoning.isEmpty {
                    conv.events.append(.reasoning(ordinal: i, date: date, summary: reasoning))
                }
                let text = plainText(content)
                if !text.isEmpty { conv.events.append(.assistant(ordinal: i, date: date, text: text, phase: nil)) }
                if let calls = r["tool_calls"]?.stringValue,
                    case .array(let list)? = try? JSONDecoder().decode(JSONValue.self, from: Data(calls.utf8))
                {
                    for c in list {
                        let fn = c["function"]
                        conv.events.append(
                            .toolCall(
                                ordinal: i, date: date, name: fn?["name"]?.stringValue ?? c["name"]?.stringValue ?? "?",
                                input: fn?["arguments"]?.stringValue ?? "", callID: c["id"]?.stringValue))
                    }
                }
            case "tool":
                conv.events.append(.toolOutput(ordinal: i, date: date, callID: r["tool_call_id"]?.stringValue, output: plainText(content)))
            default:
                conv.skipped[role, default: 0] += 1  // system…
            }
        }
        return conv
    }

    /// Contenu « user » : texte simple, ou parties JSON au format chat (`text`, `image_url` en data URI).
    static func userBlocks(_ content: String) -> [CodexBlock] {
        guard content.hasPrefix(jsonPrefix) else {
            let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [.text(t)]
        }
        // Contenu structuré illisible (tronqué, corrompu) : rien plutôt que du JSON brut dans la conversation.
        guard case .array(let parts)? = try? JSONDecoder().decode(JSONValue.self, from: Data(content.dropFirst(jsonPrefix.count).utf8)) else {
            return []
        }
        var out: [CodexBlock] = []
        for p in parts {
            switch p["type"]?.stringValue {
            case "text", "input_text":
                if let t = p["text"]?.stringValue, !t.isEmpty { out.append(.text(t)) }
            case "image_url", "input_image":
                let url = p["image_url"]?["url"]?.stringValue ?? p["image_url"]?.stringValue ?? ""
                if let (mime, data) = ConversationEncoding.dataURI(url) { out.append(.image(mediaType: mime, base64: data, name: nil)) }
            default:
                continue
            }
        }
        return out
    }

    static func plainText(_ content: String) -> String {
        userBlocks(content).compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
    }
}

private enum ConversationEncoding {
    static func dataURI(_ value: String) -> (String, String)? {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return nil }
        let header = value[value.index(value.startIndex, offsetBy: 5)..<comma]
        guard header.hasSuffix(";base64") else { return nil }
        let mime = String(header.dropLast(7))
        return (mime.isEmpty ? "application/octet-stream" : mime, String(value[value.index(after: comma)...]))
    }
}
