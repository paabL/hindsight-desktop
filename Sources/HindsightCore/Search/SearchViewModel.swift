import Foundation
import HindsightAPI
import Observation

/// Recherche dans une banque : recall (sémantique), texte (liste filtrée), reflect (réponse rédigée).
@MainActor
@Observable
public final class SearchViewModel {
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        case recall, text, reflect
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .recall: return "Recall"
            case .text: return "Texte"
            case .reflect: return "Reflect"
            }
        }
        public var help: String {
            switch self {
            case .recall: return "Recherche sémantique + mots-clés + graphe + temps (pas de LLM)"
            case .text: return "Recherche plein texte dans les faits, avec tous les filtres"
            case .reflect: return "Réponse rédigée par le LLM de la banque à partir des faits (consomme du LLM)"
            }
        }
    }

    public static let budgets = ["low", "mid", "high"]

    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public var query = ""
    public var mode: Mode = .recall
    public var filter = FactFilter()
    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    /// Coût estimé d'un reflect avec le budget choisi (recall et recherche texte n'appellent pas de LLM génératif).
    public var reflectEstimate: CostEstimate? { mode == .reflect ? estimate?(.reflect(budget: budget)) : nil }
    public var budget = "mid"
    /// Recall : nil = défaut de la banque ; true/false = choix explicite pour cette recherche.
    public var prune: Bool?
    public var dedup: Bool?
    /// Serveur 1.2.0 : seul à accepter `rerank` dans recall (réglé par `BankSession`).
    public var serverIs120 = false

    /// Options `rerank` de recall, ou `nil` pour laisser la banque décider.
    var rerankOptions: RerankOptions? {
        guard serverIs120, prune != nil || dedup != nil else { return nil }
        return RerankOptions(prune: prune, dedup: dedup)
    }

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var hits: [FactHit] = []
    /// Nombre de résultats côté serveur (mode texte) ; en recall, nombre avant filtres locaux.
    public private(set) var total = 0
    /// Résultats écartés par les filtres appliqués localement (entité, période en recall).
    public private(set) var locallyFiltered = 0
    public private(set) var chunks: [String: ChunkData] = [:]
    public private(set) var answer: ReflectResponse?
    public private(set) var isLoadingMore = false
    public private(set) var selected: FactDetailViewModel?
    @ObservationIgnored private var lastRun: (Mode, String, FactFilter)?

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    public var canRun: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .text: return !q.isEmpty || !filter.isEmpty
        case .recall, .reflect: return !q.isEmpty
        }
    }

    public func run() async {
        guard canRun else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .loading
        answer = nil
        chunks = [:]
        locallyFiltered = 0
        selected = nil
        lastRun = (mode, q, filter)
        do {
            switch mode {
            case .recall:
                let r = try await client.recall(bank, filter.recallRequest(query: q, budget: budget, rerank: rerankOptions))
                let all = r.results.map(FactHit.init)
                hits = all.filter { filter.matchesLocally($0) }
                locallyFiltered = all.count - hits.count
                total = all.count
                chunks = r.chunks ?? [:]
            case .text:
                let page = try await client.listMemories(bank, filter.memoryListQuery(q: q, limit: 100, offset: 0))
                apply(page: page, replacing: true)
            case .reflect:
                let r = try await client.reflect(bank, filter.reflectRequest(query: q, budget: budget))
                answer = r
                hits = (r.basedOn?.memories ?? []).map(FactHit.init)
                total = hits.count
            }
            state = .loaded(())
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func apply(page: ListMemoryUnitsResponse, replacing: Bool) {
        let all = page.items.map(FactHit.init)
        let kept = filter.needsLocalTypeFilter ? all.filter { filter.matchesLocally($0) } : all
        locallyFiltered += all.count - kept.count
        hits = replacing ? kept : hits + kept
        total = page.total
    }

    public var canLoadMore: Bool {
        guard let last = lastRun, last.0 == .text else { return false }
        return hits.count + locallyFiltered < total
    }

    public func loadMore() async {
        guard canLoadMore, !isLoadingMore, let last = lastRun else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.listMemories(
                bank, last.2.memoryListQuery(q: last.1, limit: 100, offset: hits.count + locallyFiltered))
            apply(page: page, replacing: false)
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }

    public func select(_ hit: FactHit?) {
        guard let hit else {
            selected = nil
            return
        }
        if selected?.factID == hit.id { return }
        let vm = FactDetailViewModel(client: client, bank: bank, hit: hit)
        selected = vm
        Task { await vm.load() }
    }

    /// Extrait du chunk renvoyé par recall pour un résultat.
    public func chunkText(for hit: FactHit) -> String? {
        hit.chunkID.flatMap { chunks[$0]?.text }
    }
}
