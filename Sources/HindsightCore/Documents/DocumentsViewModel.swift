import Foundation
import HindsightAPI
import Observation

/// Liste des documents d'une banque (recherche par identifiant, filtre par tags, tri) + document ouvert.
@MainActor
@Observable
public final class DocumentsViewModel {
    public enum Sort: String, CaseIterable, Sendable {
        case recentFirst, oldestFirst, nameAscending, mostFacts, longest

        public var title: String {
            switch self {
            case .recentFirst: return "Plus récents d'abord"
            case .oldestFirst: return "Plus anciens d'abord"
            case .nameAscending: return "Nom (ordre naturel)"
            case .mostFacts: return "Plus de faits"
            case .longest: return "Plus longs"
            }
        }
    }

    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    public let attachmentLoader: AttachmentLoader

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var items: [DocumentListItem] = []
    public private(set) var total: Int = 0
    /// Recherche arrêtée à son plafond : `total` est un minimum, pas un compte exact.
    public private(set) var totalIsEstimate = false

    public var query: String = ""
    public var selectedTags: [String] = []
    public var tagsMatch: TagsMatch = .allStrict
    public var sort: Sort = .recentFirst

    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    @ObservationIgnored public var pauseGate: PauseGate?
    /// Un document a changé depuis le lecteur (supprimé, retraité, tags) : la liste de l'écran Documents se relit.
    @ObservationIgnored public var onDocumentChanged: (@MainActor (_ documentID: String, _ reprocessed: Bool) -> Void)?
    /// Documents supprimés depuis le lecteur pendant cette session (la liste peut mettre un instant à suivre).
    public private(set) var deletedIDs: Set<String> = []
    public private(set) var reader: DocumentReaderViewModel?
    @ObservationIgnored private var readerLoad: Task<Void, Never>?
    /// Message d'une action dont la source n'est plus affichée (document supprimé).
    public var actionMessage: String?
    public private(set) var isLoadingMore = false
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var moreID = UUID()

    /// Serveur 1.1.0 (historique et portée des documents) ; réglé par `BankSession`.
    public var serverIs110 = false

    public init(client: HindsightClient, bank: String, attachmentLoader: AttachmentLoader) {
        self.client = client
        self.bank = bank
        self.attachmentLoader = attachmentLoader
    }

    // MARK: Liste

    public func loadIfNeeded() async {
        if items.isEmpty, !state.isLoading, state.errorMessage == nil { await reload() }
    }

    /// Recharge la liste depuis le début avec les filtres courants.
    public func reload() async {
        let id = UUID()
        loadID = id
        moreID = UUID()
        isLoadingMore = false
        state = .loading
        do {
            try Task.checkCancellation()
            let page = try await client.listDocuments(
                bank, q: query.isEmpty ? nil : query, tags: TagFilter(tags: selectedTags, match: tagsMatch), limit: 100, offset: 0)
            try Task.checkCancellation()
            guard loadID == id else { return }
            items = page.items
            total = page.total
            totalIsEstimate = page.totalIsEstimate
            state = .loaded(())
        } catch {
            guard loadID == id else { return }
            state = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
        }
    }

    public var canLoadMore: Bool { items.count < total }

    public func loadMore() async {
        guard canLoadMore, !isLoadingMore, !state.isLoading else { return }
        let id = UUID(), listID = loadID
        moreID = id
        isLoadingMore = true
        defer { if moreID == id { isLoadingMore = false } }
        do {
            try Task.checkCancellation()
            let page = try await client.listDocuments(
                bank, q: query.isEmpty ? nil : query, tags: TagFilter(tags: selectedTags, match: tagsMatch), limit: 100,
                offset: items.count)
            try Task.checkCancellation()
            guard loadID == listID, moreID == id else { return }
            items += page.items
            total = page.total
            totalIsEstimate = page.totalIsEstimate
        } catch {
            guard loadID == listID, moreID == id, !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(error.userMessage)
        }
    }

    /// Charge toutes les pages (utile pour trier localement par nom sur ~100 documents).
    public func loadAll() async {
        while canLoadMore, state.errorMessage == nil {
            let before = items.count
            await loadMore()
            if items.count == before { break }
        }
    }

    public var sortedItems: [DocumentListItem] {
        switch sort {
        case .recentFirst: return items
        case .oldestFirst: return items.reversed()
        case .nameAscending:
            return items.sorted { $0.id.compare($1.id, options: [.numeric, .caseInsensitive]) == .orderedAscending }
        case .mostFacts: return items.sorted { $0.memoryUnitCount > $1.memoryUnitCount }
        case .longest: return items.sorted { $0.textLength > $1.textLength }
        }
    }

    /// Tags présents dans les documents chargés, du plus fréquent au moins fréquent.
    public var availableTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for d in items { for t in d.tags { counts[t, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { ($1.count, $0.tag) < ($0.count, $1.tag) }
    }

    public func toggleTag(_ tag: String) {
        if let i = selectedTags.firstIndex(of: tag) { selectedTags.remove(at: i) } else { selectedTags.append(tag) }
    }

    // MARK: Ouverture

    /// Ouvre un document dans le lecteur (et le charge). `chunkID` : chunk à mettre en évidence.
    @discardableResult
    public func open(documentID: String, chunkID: String? = nil) -> DocumentReaderViewModel {
        if let r = reader, r.documentID == documentID {
            if let chunkID { r.focus(chunkID: chunkID) }
            return r
        }
        readerLoad?.cancel()
        let r = DocumentReaderViewModel(client: client, bank: bank, documentID: documentID, attachmentLoader: attachmentLoader)
        r.serverIs110 = serverIs110
        r.estimate = estimate
        r.pauseGate = pauseGate
        r.onDeleted = { [weak self, weak r] in
            guard let self else { return }
            // Le lecteur disparaît avec le document : son message est repris par la liste.
            self.actionMessage = r?.actionMessage
            self.deletedIDs.insert(documentID)
            if self.reader === r { self.closeReader() }
            self.onDocumentChanged?(documentID, false)
        }
        r.onChanged = { [weak self] in
            self?.onDocumentChanged?(documentID, false)
        }
        r.onReprocessed = { [weak self] in self?.onDocumentChanged?(documentID, true) }
        r.refreshListAfterChange = { [weak self] in
            guard let self else { return }
            await self.reload()
        }
        reader = r
        readerLoad = Task { [weak r] in
            await r?.load(focusChunk: chunkID)
            guard !Task.isCancelled else { return }
            await r?.loadFacts()
        }
        return r
    }

    public func closeReader() { readerLoad?.cancel(); readerLoad = nil; reader = nil }

    // MARK: Étiquettes

    public func isTaskDocument(_ id: String) -> Bool { id.hasPrefix("codex-") && id.contains("-task-") }

    /// Numéro de tâche (`…-task-012` → 12), pour affichage/tri.
    public func taskNumber(of id: String) -> Int? {
        guard let r = id.range(of: "-task-", options: .backwards) else { return nil }
        return Int(id[r.upperBound...])
    }
}
