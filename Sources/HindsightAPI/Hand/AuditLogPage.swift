import Foundation

/// Page du journal d'audit, lue telle que les deux versions du serveur la renvoient : avec les corps de
/// requête et de réponse en 1.0.0, sans eux en 1.1.0 (`AuditLogSummary` ; le détail se lit par
/// `auditLog(_:id:)`). Les corps absents restent nil.
public struct AuditLogPage: Decodable, Sendable, Hashable {
    public var total: Int
    public var items: [AuditLogEntry]

    public init(total: Int, items: [AuditLogEntry]) {
        self.total = total
        self.items = items
    }
}
