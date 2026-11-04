import Foundation
import HindsightAPI
import Observation

/// Page préchargée et sa position. Une structure plutôt qu'un tuple : avec Swift 6.4 en -O, un tuple
/// renvoyé depuis un `do`/`catch` dans une tâche fille arrivait avec un index faux (pages mélangées).
private struct PrefetchedPage: Sendable {
    let index: Int
    let page: Result<ListMemoryUnitsResponse, Error>
}

/// Frise chronologique : charge les faits de la banque (pages de 1 000) selon les filtres, puis les
/// range par jour / semaine / mois sur l'axe temporel choisi.
@MainActor
@Observable
public final class TimelineViewModel {
    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    @ObservationIgnored private let calendar: Calendar

    public var filter = FactFilter()
    public var text = ""
    public var axis: TimeAxis = .event {
        didSet { if oldValue != axis { rebuild() } }
    }
    public var granularity: TimelineGranularity = .day {
        didSet { if oldValue != granularity { rebuild() } }
    }
    /// Plafond de faits chargés (garde-fou mémoire / temps).
    public var maxFacts = 20_000
    public let pageSize: Int

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var facts: [FactHit] = []
    public private(set) var totalAvailable = 0
    public private(set) var periods: [TimelinePeriod] = []
    public private(set) var bars: [TimelineBar] = []
    public private(set) var undated: [FactHit] = []
    public private(set) var selectedPeriod: Date?
    public private(set) var selectedFact: FactDetailViewModel?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(client: HindsightClient, bank: String, pageSize: Int = 1000, calendar: Calendar = .current) {
        self.client = client
        self.bank = bank
        self.pageSize = pageSize
        self.calendar = calendar
    }

    public var isTruncated: Bool { totalAvailable > facts.count && facts.count >= maxFacts }
    public var progress: Double? {
        guard state.isLoading, totalAvailable > 0 else { return nil }
        return min(1, Double(facts.count) / Double(min(totalAvailable, maxFacts)))
    }

    public func loadIfNeeded() async {
        if facts.isEmpty, !state.isLoading, state.errorMessage == nil { await reload() }
    }

    /// Recharge tous les faits correspondant aux filtres (annule un chargement en cours).
    public func reload() async {
        loadTask?.cancel()
        let task = Task { await self.loadAll() }
        loadTask = task
        await task.value
    }

    private func loadAll() async {
        state = .loading
        facts = []
        totalAvailable = 0
        selectedPeriod = nil
        selectedFact = nil
        var offset = 0
        do {
            var ahead: [Result<ListMemoryUnitsResponse, Error>] = []
            while !Task.isCancelled {
                let page = try await ahead.isEmpty
                    ? client.listMemories(bank, filter.memoryListQuery(q: text, axis: axis, limit: pageSize, offset: offset))
                    : ahead.removeFirst().get()
                totalAvailable = page.total
                let hits = page.items.map(FactHit.init)
                facts += filter.needsLocalTypeFilter ? hits.filter { filter.matchesLocally($0, axis: axis) } : hits
                offset += page.items.count
                if page.items.isEmpty || offset >= page.total || facts.count >= maxFacts { break }
                // Une page incomplète décale la suite : on reprend page par page à partir du vrai décalage.
                if page.items.count != pageSize { ahead = [] }
                // Sans filtre local, les pages restantes sont connues d'avance : mêmes requêtes qu'en série,
                // envoyées ensemble, puis traitées dans l'ordre avec les mêmes conditions d'arrêt.
                else if ahead.isEmpty, !filter.needsLocalTypeFilter {
                    ahead = await pages(at: Array(stride(from: offset, to: min(page.total, maxFacts), by: pageSize)))
                }
            }
            if Task.isCancelled { return }
            if facts.count > maxFacts { facts = Array(facts.prefix(maxFacts)) }
            rebuild()
            state = .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }

    /// Pages demandées quatre à la fois, rendues dans l'ordre des décalages. Un échec arrête les nouvelles
    /// requêtes : les pages qui le précèdent sont traitées, puis l'erreur est levée à sa place, comme en série.
    private func pages(at offsets: [Int]) async -> [Result<ListMemoryUnitsResponse, Error>] {
        let client = client, bank = bank
        let queries = offsets.map { filter.memoryListQuery(q: text, axis: axis, limit: pageSize, offset: $0) }
        var results = [Result<ListMemoryUnitsResponse, Error>?](repeating: nil, count: queries.count)
        await withTaskGroup(of: PrefetchedPage.self) { group in
            var failed = false
            for (i, query) in queries.enumerated() {
                if i >= 4, let done = await group.next() {
                    results[done.index] = done.page
                    if case .failure = done.page { failed = true }
                }
                if failed { break }
                group.addTask {
                    do { return PrefetchedPage(index: i, page: .success(try await client.listMemories(bank, query))) } catch {
                        return PrefetchedPage(index: i, page: .failure(error))
                    }
                }
            }
            for await done in group { results[done.index] = done.page }
        }
        // Les pages demandées forment un préfixe ; celles qu'un échec a empêchées restent vides.
        return results.prefix { $0 != nil }.compactMap { $0 }
    }

    private func rebuild() {
        let r = TimelineBuilder.build(facts, axis: axis, granularity: granularity, calendar: calendar)
        periods = r.periods
        undated = r.undated
        bars = TimelineBuilder.bars(r.periods)
        if let s = selectedPeriod, !periods.contains(where: { $0.start == s }) { selectedPeriod = nil }
    }

    public var dateRange: ClosedRange<Date>? {
        guard let first = periods.first?.start, let last = periods.last?.start else { return nil }
        return first...last
    }

    public func selectPeriod(_ start: Date?) { selectedPeriod = start }

    /// Sélectionne la période contenant `date` (ou la plus proche).
    public func jump(to date: Date) {
        guard !periods.isEmpty else { return }
        let target = calendar.dateInterval(of: granularity.component, for: date)?.start ?? date
        selectedPeriod = periods.min { abs($0.start.timeIntervalSince(target)) < abs($1.start.timeIntervalSince(target)) }?.start
    }

    public var factsOfSelectedPeriod: [FactHit] {
        guard let s = selectedPeriod else { return [] }
        return periods.first { $0.start == s }?.facts ?? []
    }

    public func selectFact(_ hit: FactHit?) {
        guard let hit else {
            selectedFact = nil
            return
        }
        let vm = FactDetailViewModel(client: client, bank: bank, hit: hit)
        selectedFact = vm
        Task { await vm.load() }
    }
}
