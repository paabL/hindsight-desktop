import HindsightAPI

/// Lots de rétention indépendants de la source des documents.
public enum RetainBatching {
    /// Respecte les limites d'items et d'octets estimés ; un item trop gros part seul.
    public static func batches(_ items: [(item: MemoryItem, bytes: Int)], byteLimit: Int, itemLimit: Int) -> [[MemoryItem]] {
        var result: [[MemoryItem]] = []
        var current: [MemoryItem] = []
        var size = 0
        for (item, bytes) in items {
            if !current.isEmpty, current.count >= itemLimit || size + bytes > byteLimit {
                result.append(current)
                current = []
                size = 0
            }
            current.append(item)
            size += bytes
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
