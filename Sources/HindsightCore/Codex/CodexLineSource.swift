import Foundation

public struct CodexFile: Sendable, Hashable, Codable {
    public let path: String
    public let size: Int
    public let modified: Date
    /// Session d'une base Hermes (`state.db` contient toutes les sessions) ; `nil` pour un fichier JSONL.
    public var hermesSession: String?

    /// Identifiant unique (chemin, plus la session pour une base Hermes).
    public var key: String { hermesSession.map { "\(path)#\($0)" } ?? path }

    public var url: URL { URL(fileURLWithPath: path) }
    public var isCompressed: Bool { path.hasSuffix(".zst") }

    public init(url: URL) {
        path = url.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        modified = (attrs?[.modificationDate] as? Date) ?? .distantPast
    }

    public init(database: URL, session: String, size: Int = 0, modified: Date) {
        path = database.path
        self.size = size
        self.modified = modified
        hermesSession = session
    }
}
