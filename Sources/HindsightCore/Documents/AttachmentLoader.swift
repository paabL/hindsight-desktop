import Foundation
import HindsightAPI

/// Chargement et cache mémoire des pièces jointes (images, PDF…). Déduplique les requêtes simultanées.
public actor AttachmentLoader {
    private let client: HindsightClient
    private let byteLimit: Int
    private var cache: [String: AttachmentData] = [:]
    private var order: [String] = []
    private var totalBytes = 0
    private var inFlight: [String: Task<AttachmentData, Error>] = [:]

    public init(client: HindsightClient, byteLimit: Int = 256 * 1024 * 1024) {
        self.client = client
        self.byteLimit = byteLimit
    }

    public func load(_ attachment: ChunkAttachment) async throws -> AttachmentData {
        let key = attachment.url
        if let hit = cache[key] { return hit }
        if let task = inFlight[key] { return try await task.value }
        let client = self.client
        let task = Task { try await client.attachment(url: attachment.url) }
        inFlight[key] = task
        do {
            let data = try await task.value
            inFlight[key] = nil
            store(key, data)
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    public var cachedCount: Int { cache.count }

    private func store(_ key: String, _ data: AttachmentData) {
        cache[key] = data
        order.append(key)
        totalBytes += data.data.count
        while totalBytes > byteLimit, order.count > 1 {
            let oldest = order.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) { totalBytes -= removed.data.count }
        }
    }
}
