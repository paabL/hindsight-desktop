import Foundation
import HindsightAPI

/// Un dossier analysé et ses options, mémorisés par banque.
public struct CoverageRoot: Codable, Sendable, Hashable, Identifiable {
    public var path: String
    /// Tous les fichiers texte (code, JSON…), pas seulement les documents.
    public var allFiles = false
    /// Envoyer sans confirmation ce qui manque ou a changé, dans la limite de coût réglée.
    public var autoSync = false

    public init(path: String, allFiles: Bool = false, autoSync: Bool = false) {
        self.path = path
        self.allFiles = allFiles
        self.autoSync = autoSync
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
}

/// Un fichier de document trouvé dans un dépôt.
public struct ScannedFile: Sendable, Hashable {
    /// Nom du dossier du dépôt (tag `repo:`).
    public let repo: String
    /// Chemin relatif au dépôt.
    public let path: String
    public let url: URL
    public let size: Int
    public let modified: Date

    public init(repo: String, path: String, url: URL, size: Int, modified: Date) {
        self.repo = repo
        self.path = path
        self.url = url
        self.size = size
        self.modified = modified
    }

    public var key: String { repo + "/" + path }
}

/// Ce que la mémoire contient d'un fichier.
public enum CoverageStatus: String, Sendable, CaseIterable, Identifiable {
    /// En mémoire, identique au fichier (ou envoyé après sa dernière modification), avec des faits extraits.
    case current
    /// En mémoire, mais le fichier a changé depuis l'envoi.
    case modified
    /// En mémoire, mais aucun fait n'en a été extrait.
    case noFacts
    /// Absent de la mémoire.
    case missing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .current: return "À jour"
        case .modified: return "Modifié depuis"
        case .noFacts: return "Sans fait"
        case .missing: return "Absent"
        }
    }

    public var symbol: String {
        switch self {
        case .current: return "checkmark.circle.fill"
        case .modified: return "arrow.triangle.2.circlepath.circle.fill"
        case .noFacts: return "exclamationmark.circle.fill"
        case .missing: return "circle.dashed"
        }
    }
}

/// Un fichier et les documents de la banque qui en proviennent.
public struct CoverageEntry: Identifiable, Sendable {
    /// Clé du fichier ; pour une conversation, sa session (deux conversations peuvent porter le même titre).
    public var id: String { session.map { "session:" + $0.id } ?? file.key }
    public let file: ScannedFile
    public let documents: [DocumentListItem]
    public let status: CoverageStatus
    /// Conversation (Codex, Claude Code, Hermes) plutôt que fichier ; elle s'envoie par « Importer ».
    public var session: CodexSessionSummary?

    public var facts: Int { documents.reduce(0) { $0 + $1.memoryUnitCount } }
    /// Fichier découpé en plusieurs documents par un autre outil (par exemple `campaigns.md` par `sync.py`).
    public var isSplit: Bool { documents.count > 1 }
    /// Envoyable depuis l'app : pas à jour, et ni découpé ni journal de campagnes (que `sync.py` envoie entrée par entrée).
    public var canSend: Bool { session == nil && status != .current && !isSplit && FileCoverage.strategy(for: file.path) != "campaign" }
    public var lastSent: Date? { documents.compactMap { HSDate.parse($0.updatedAt) }.max() }
}

public struct CoverageReport: Sendable {
    public let entries: [CoverageEntry]
    /// Documents rattachés à un dépôt analysé dont le fichier n'a pas été trouvé (supprimé, déplacé, non suivi).
    public let orphans: [DocumentListItem]
    /// Documents sans source analysée : dépôt non suivi, session absente de ce Mac, ou ni chemin ni session.
    public let others: [DocumentListItem]
    /// Parmi eux, ceux qui n'ont pas de chemin de fichier (conversations, synthèses…).
    public let unfiled: Int

    public init(entries: [CoverageEntry], orphans: [DocumentListItem], others: [DocumentListItem] = [], unfiled: Int) {
        self.entries = entries
        self.orphans = orphans
        self.others = others
        self.unfiled = unfiled
    }

    public func count(_ status: CoverageStatus) -> Int { entries.filter { $0.status == status }.count }
}

/// Règles qui relient un fichier de dépôt à un document de la banque. Un document porte les métadonnées
/// `repo` (nom du dossier du dépôt) et `path` (chemin relatif), comme ceux de `nomad-memory/sync.py`.
public enum FileCoverage {
    /// Extensions retenues comme documents par défaut ; le code et les données n'en sont pas.
    public static let extensions: Set<String> = ["md", "markdown", "tex", "txt", "rst", "html", "htm", "pdf", "docx", "pptx", "xlsx"]
    /// Convertis en texte par le serveur (`files/retain`) ; les autres partent tels quels par `retain`.
    static let convertedExtensions: Set<String> = ["html", "htm", "pdf", "docx", "pptx", "xlsx"]
    /// Ignorés même avec « tous les fichiers » : binaires sans texte exploitable.
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "svg", "mp3", "mp4", "mov", "wav", "zip", "gz", "tgz", "zst", "tar", "whl",
        "pkl", "pt", "pth", "ckpt", "npz", "npy", "h5", "parquet", "db", "sqlite", "so", "dylib", "o", "a", "pyc", "bin", "lock",
    ]

    static func ext(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }
    public static func isDocument(_ path: String) -> Bool { extensions.contains(ext(path)) }
    /// Envoyé en texte : son empreinte se compare au `content_hash` du serveur.
    public static func isText(_ path: String) -> Bool { !convertedExtensions.contains(ext(path)) }

    public static func includes(_ path: String, allFiles: Bool) -> Bool {
        allFiles ? !binaryExtensions.contains(ext(path)) : isDocument(path)
    }

    /// Stratégie de rétention de la banque selon l'emplacement du fichier.
    public static func strategy(for path: String) -> String {
        if path == "docs/campaigns.md" { return "campaign" }
        if path.hasPrefix("rapports/") { return "report" }
        if path.hasPrefix("board/") { return "board" }
        if ext(path) == "pdf" { return "paper" }
        return "doc"
    }

    /// Même forme que `sync.py` pour la documentation : `doc:<repo>:<chemin>`.
    public static func documentID(repo: String, path: String) -> String { "\(strategy(for: path)):\(repo):\(path)" }

    public static func tags(repo: String, path: String) -> [String] { ["source:\(strategy(for: path))", "repo:\(repo)"] }

    /// `repo/chemin` d'un document, lu dans ses métadonnées.
    static func key(_ d: DocumentListItem) -> String? {
        repoAndPath(d).map { $0.repo + "/" + $0.path }
    }

    public static func repoAndPath(_ d: DocumentListItem) -> (repo: String, path: String)? {
        guard case .string(let repo)? = d.documentMetadata?["repo"], case .string(let path)? = d.documentMetadata?["path"] else { return nil }
        return (repo, path)
    }

    /// Compare les fichiers aux documents. `textHash` donne le SHA-256 hexadécimal d'un fichier texte.
    public static func report(
        files: [ScannedFile], sessions: [CodexSessionSummary] = [], documents: [DocumentListItem], textHash: (ScannedFile) -> String?
    ) -> CoverageReport {
        var byKey: [String: [DocumentListItem]] = [:]
        var bySession: [String: [DocumentListItem]] = [:]
        for d in documents {
            if let k = key(d) { byKey[k, default: []].append(d) }
            else if let sid = sessionID(d) { bySession[sid, default: []].append(d) }
        }
        var entries = files.map { f -> CoverageEntry in
            let docs = byKey[f.key] ?? []
            return CoverageEntry(file: f, documents: docs, status: status(f, docs, textHash))
        }
        for s in sessions where s.error == nil && (s.meta?.isUserConversation ?? false) {
            guard let meta = s.meta else { continue }
            let docs = bySession.removeValue(forKey: meta.id) ?? []
            let title = (meta.title ?? s.firstUserText ?? meta.id).split(separator: "\n").first.map(String.init) ?? meta.id
            let f = ScannedFile(
                repo: "Conversations \(s.source.title)", path: "\(meta.projectName ?? "?") · \(title.prefix(90))", url: s.file.url,
                size: s.file.size, modified: s.file.modified)
            entries.append(CoverageEntry(file: f, documents: docs, status: status(f, docs, { _ in nil }), session: s))
        }
        let repos = Set(files.map(\.repo)), keys = Set(files.map(\.key))
        let orphans = documents.filter { d in
            guard let k = key(d), case .string(let repo)? = d.documentMetadata?["repo"] else { return false }
            return repos.contains(repo) && !keys.contains(k)
        }
        // Tout document apparaît une fois : rattaché à un fichier, à une conversation, orphelin, ou à part.
        var placed = Set(entries.flatMap { $0.documents.map(\.id) })
        placed.formUnion(orphans.map(\.id))
        let others = documents.filter { !placed.contains($0.id) }
        return CoverageReport(entries: entries, orphans: orphans, others: others, unfiled: others.filter { key($0) == nil }.count)
    }

    /// Session d'un document de conversation : métadonnée `session_id` (plugin de mémoire) ou identifiant
    /// `<outil>-<session>[-task-NNN]` de l'import de l'app.
    static func sessionID(_ d: DocumentListItem) -> String? {
        if case .string(let sid)? = d.documentMetadata?["session_id"] { return sid }
        for source in ConversationSource.allCases where d.id.hasPrefix(source.documentPrefix + "-") {
            var rest = String(d.id.dropFirst(source.documentPrefix.count + 1))
            if let r = rest.range(of: "-task-", options: .backwards) { rest = String(rest[..<r.lowerBound]) }
            return rest
        }
        return nil
    }

    static func status(_ f: ScannedFile, _ docs: [DocumentListItem], _ textHash: (ScannedFile) -> String?) -> CoverageStatus {
        guard !docs.isEmpty else { return .missing }
        if docs.allSatisfy({ $0.memoryUnitCount == 0 }) { return .noFacts }
        if docs.count == 1, isText(f.path), let sent = docs[0].contentHash, let hash = textHash(f) {
            return sent == hash ? .current : .modified
        }
        // Binaire converti par le serveur ou fichier découpé : seule la date permet de comparer.
        let lastSent = docs.compactMap { HSDate.parse($0.updatedAt) }.max() ?? .distantPast
        return f.modified > lastSent ? .modified : .current
    }

    // MARK: Envoi

    public static func mimeType(_ path: String) -> String {
        switch ext(path) {
        case "pdf": return "application/pdf"
        case "html", "htm": return "text/html"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default: return "text/plain"
        }
    }

    /// Retire les images intégrées (`data:` URI) d'un HTML : converties en texte, elles coûteraient des
    /// millions de jetons sans rien apporter à la mémoire.
    public static func strippingDataURIs(_ html: String) -> String {
        html.replacingOccurrences(of: #"data:[A-Za-z0-9.+/-]+;base64,[A-Za-z0-9+/=\s]+"#, with: "", options: .regularExpression)
    }

    /// Document texte, avec les mêmes champs que `sync.py`.
    public static func memoryItem(_ f: ScannedFile, text: String) -> MemoryItem {
        MemoryItem(
            content: .text(text), timestamp: .string(HSDate.format(f.modified)), context: "\(f.repo)/\(f.path)",
            metadata: ["repo": f.repo, "path": f.path], documentId: documentID(repo: f.repo, path: f.path),
            tags: tags(repo: f.repo, path: f.path), observationScopes: .string("shared"), strategy: strategy(for: f.path),
            updateMode: "replace")
    }

    /// Fichier converti par le serveur (PDF, HTML, Office).
    public static func upload(_ f: ScannedFile, data: Data) -> (file: UploadFile, metadata: FileRetainMetadata) {
        var data = data
        if ["html", "htm"].contains(ext(f.path)) {
            data = Data(strippingDataURIs(String(decoding: data, as: UTF8.self)).utf8)
        }
        let meta = FileRetainMetadata(
            documentId: documentID(repo: f.repo, path: f.path), context: "\(f.repo)/\(f.path)", metadata: ["repo": f.repo, "path": f.path],
            tags: tags(repo: f.repo, path: f.path), timestamp: HSDate.format(f.modified), strategy: strategy(for: f.path))
        return (UploadFile(filename: (f.path as NSString).lastPathComponent, mimeType: mimeType(f.path), data: data), meta)
    }
}
