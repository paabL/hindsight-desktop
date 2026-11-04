import Foundation

/// Native import remains available for Hermes only. Codex/Claude are collected by Agent Dump.
public actor CodexIndex {
    public static var defaultRoots: [URL] {
        ConversationSource.hermes.defaultRoots(home: URL(fileURLWithPath: NSHomeDirectory()))
    }
    public init(cacheURL: URL? = nil) {}
    public func scan(roots: [URL], zstd: URL?, parallelism: Int = 6,
                     progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async -> [CodexSessionSummary] {
        var results: [CodexSessionSummary] = []
        for root in roots where root.pathExtension == "db" { results += HermesReader.summaries(database: root) }
        await progress(results.count, results.count)
        return results.sorted { $0.sortDate > $1.sortDate }
    }
}
