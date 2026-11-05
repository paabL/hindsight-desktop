import Foundation

public struct CodexFile: Sendable, Hashable, Codable {
    public let path: String
    public let size: Int
    public let modified: Date
    /// Identifiant unique du fichier de conversation.
    public var key: String { path }

    public var url: URL { URL(fileURLWithPath: path) }
    public var isCompressed: Bool { path.hasSuffix(".zst") }

    public init(url: URL) {
        path = url.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        modified = (attrs?[.modificationDate] as? Date) ?? .distantPast
    }
}
