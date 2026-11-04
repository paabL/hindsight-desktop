import Foundation
import HindsightAPI
import Observation

/// Valeurs proposées dans les filtres : tags, tâches (`task:NNN`), entités les plus mentionnées.
@MainActor
@Observable
public final class BankCatalog {
    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public private(set) var tags: [TagItem] = []
    public private(set) var entities: [EntityListItem] = []
    public private(set) var state: LoadState<Void> = .idle

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    public func loadIfNeeded() async {
        guard state.value == nil, !state.isLoading else { return }
        state = .loading
        do {
            async let t = Self.allTags(client: client, bank: bank)
            async let e = client.listEntities(bank, limit: 500)
            tags = try await t
            entities = try await e.items
            state = .loaded(())
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.userMessage)
        }
    }

    static func allTags(client: HindsightClient, bank: String, cap: Int = 2000) async throws -> [TagItem] {
        var out: [TagItem] = []
        while out.count < cap {
            let page = try await client.listTags(bank, limit: 500, offset: out.count)
            out += page.items
            if page.items.isEmpty || out.count >= page.total { break }
        }
        return out
    }

    /// Tâches (`task:NNN`) triées par numéro.
    public var tasks: [String] {
        tags.map(\.tag).filter { $0.hasPrefix("task:") }.map { String($0.dropFirst(5)) }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// Tags hors `task:` (déjà proposés à part).
    public var plainTags: [TagItem] { tags.filter { !$0.tag.hasPrefix("task:") } }

    public func entities(matching q: String, limit: Int = 30) -> [EntityListItem] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(entities.prefix(limit)) }
        return Array(entities.filter { $0.canonicalName.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.prefix(limit))
    }
}
