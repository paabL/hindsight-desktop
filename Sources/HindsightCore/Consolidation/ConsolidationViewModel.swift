import Foundation
import HindsightAPI
import Observation

/// Mémoire › Consolidation : où en est la consolidation de la banque, à quel rythme, dans quelles portées,
/// et ce qu'elle a changé dans les observations. C'est aussi le seul endroit qui la lance.
@MainActor
@Observable
public final class ConsolidationViewModel {
    /// Période des changements montrés.
    public enum Period: String, CaseIterable, Sendable, Encodable {
        case hour, day, week
        public var seconds: TimeInterval {
            switch self {
            case .hour: return 3600
            case .day: return 86_400
            case .week: return 604_800
            }
        }
    }

    public static let pageSize = 25
    /// Portées détaillées ; les suivantes sont regroupées.
    public static let scopeLimit = 6
    /// Lectures d'historique simultanées (une par observation affichée).
    static let historyConcurrency = 6
    /// Une actualisation silencieuse relit au plus ce nombre de changements déjà affichés.
    static let refreshLimit = 100
    static let cacheLimit = 400

    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var stats: BankStatsResponse?
    public private(set) var bankConfig: BankConfigResponse?
    public private(set) var activeConsolidations: ActiveConsolidations?
    /// Drapeau `features.observations` du serveur (réglé par `BankSession`).
    public var serverObservations: Bool?
    public private(set) var pace: ConsolidationPace?
    public private(set) var scopes: ObservationScopesResponse?
    public private(set) var period: Period = .day
    public private(set) var counts: ObservationChangeCounts?
    public private(set) var changes: [ObservationChange] = []
    public private(set) var canLoadMore = false
    public private(set) var isLoadingMore = false
    /// Sources secondaires en échec (la vue reste affichée sans elles).
    public private(set) var partialErrors: [String] = []
    public private(set) var consultationOnly = false

    /// Même état que la Vue d'ensemble.
    public var status: ConsolidationStatus? {
        stats.map {
            ConsolidationStatus(
                stats: $0, config: bankConfig, serverObservations: serverObservations,
                operations: activeConsolidations ?? ActiveConsolidations())
        }
    }

    /// Faits world + experience : ceux que la consolidation traite.
    public var rawFacts: Int? {
        stats.map { ($0.nodesByFactType["world"] ?? 0) + ($0.nodesByFactType["experience"] ?? 0) }
    }

    /// Faits déjà consolidés : ni en attente, ni en échec.
    public var consolidatedFacts: Int? {
        guard let stats, let raw = rawFacts else { return nil }
        return max(0, raw - stats.pendingConsolidation - stats.failedConsolidation)
    }

    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?
    public private(set) var isBusy = false
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    @ObservationIgnored public var pauseGate: PauseGate?

    @ObservationIgnored private var revision = UUID()
    /// Fin de la fenêtre des changements, fixée au chargement : les pages suivantes lisent la même fenêtre.
    @ObservationIgnored private var windowEnd = Date()
    @ObservationIgnored private var listTotal = 0
    /// Historique lu par observation, réutilisé tant que l'observation n'a pas changé.
    @ObservationIgnored private var historyCache: [String: CachedHistory] = [:]

    private struct CachedHistory {
        let updatedAt: String?
        let history: JSONValue
    }

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    // MARK: Chargement

    public func loadIfNeeded() async {
        if state.value == nil, !state.isLoading { await reload() }
    }

    public func setPeriod(_ value: Period) async {
        guard value != period else { return }
        period = value
        changes = []
        counts = nil
        await reload()
    }

    /// `silently` : sondage pendant une consolidation ; la vue garde son contenu et relit ce qui est déjà affiché.
    public func reload(silently: Bool = false) async {
        let current = UUID()
        revision = current
        if !silently || state.value == nil { state = .loading }
        let now = Date(), since = now.addingTimeInterval(-period.seconds)
        let client = self.client, bank = self.bank
        let visible = silently ? min(max(Self.pageSize, changes.count), Self.refreshLimit) : Self.pageSize
        let created = MemoryListQuery(type: "observation", window: TimeWindow(field: "created_at", start: since, end: now), limit: 1)
        let touched = MemoryListQuery(type: "observation", window: TimeWindow(field: "updated_at", start: since, end: now), limit: 1)
        let page = MemoryListQuery(type: "observation", window: TimeWindow(field: "updated_at", start: since, end: now), limit: visible)

        async let statsReq = Self.capture { try await client.bankStats(bank) }
        async let configReq = Self.capture { try await client.bankConfig(bank) }
        async let modeReq = try? client.isConsultationOnly()
        async let runningReq = Self.capture { try await client.listOperations(bank, status: "processing", type: "consolidation", limit: 1) }
        async let queuedReq = Self.capture { try await client.listOperations(bank, status: "pending", type: "consolidation", limit: 1) }
        async let completedReq = Self.capture { try await client.listOperations(bank, status: "completed", type: "consolidation", limit: 20) }
        async let scopesReq = Self.capture { try await client.observationScopes(bank, limit: Self.scopeLimit) }
        async let createdReq = Self.capture { try await client.listMemories(bank, created).total }
        async let touchedReq = Self.capture { try await client.listMemories(bank, touched).total }
        async let pageReq = Self.capture { try await client.listMemories(bank, page) }

        let statsResult = await statsReq
        let config = await configReq, mode = await modeReq
        let running = await runningReq, queued = await queuedReq, completed = await completedReq
        let scopesResult = await scopesReq, createdTotal = await createdReq, touchedTotal = await touchedReq
        let pageResult = await pageReq
        guard revision == current else { return }

        var errors: [String] = []
        func take<T>(_ r: Result<T, Error>, _ label: String) -> T? {
            switch r {
            case .success(let v): return v
            case .failure(let e):
                let line = "\(label) : \(e.userMessage)"
                if !(e is CancellationError), !errors.contains(line) { errors.append(line) }
                return nil
            }
        }
        let freshStats: BankStatsResponse
        switch statsResult {
        case .success(let value): freshStats = value
        case .failure(let error):
            if error is CancellationError { if state.isLoading { state = .idle }; return }
            if silently, state.value != nil { return }  // un sondage raté garde la vue
            state = .failed(error.userMessage)
            return
        }
        consultationOnly = mode ?? consultationOnly
        if let value = take(config, "configuration") { bankConfig = value }
        let runningList = take(running, "consolidations")
        let queuedList = take(queued, "consolidations")
        if let runningList, let queuedList {
            activeConsolidations = ActiveConsolidations(running: runningList.total, queued: queuedList.total)
        }
        stats = freshStats
        pace = (try? completed.get()).flatMap {
            ConsolidationPace.measure(
                completed: $0.operations, running: runningList?.operations.first,
                pendingFacts: freshStats.pendingConsolidation, now: now)
        }
        switch scopesResult {
        case .success(let value): scopes = value
        case .failure(let error):
            // Un serveur qui ne liste pas les portées (404) n'a rien à signaler.
            if case HindsightError.http(404, _, _)? = error as? HindsightError { scopes = nil; break }
            _ = take(Result<Void, Error>.failure(error), "portées")
        }
        if let c = take(createdTotal, "changements"), let t = take(touchedTotal, "changements") {
            counts = ObservationChangeCounts(created: c, touched: t)
        }
        if let list = take(pageResult, "changements") {
            let analyzed = await analyze(list.items, since: since)
            guard revision == current else { return }
            windowEnd = now
            listTotal = list.total
            changes = analyzed
            canLoadMore = analyzed.count < list.total
        }
        partialErrors = errors
        state = .loaded(())
    }

    /// Page suivante des changements, dans la même fenêtre que le chargement.
    public func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = revision
        let since = windowEnd.addingTimeInterval(-period.seconds)
        let query = MemoryListQuery(
            type: "observation", window: TimeWindow(field: "updated_at", start: since, end: windowEnd),
            limit: Self.pageSize, offset: changes.count)
        do {
            let list = try await client.listMemories(bank, query)
            let known = Set(changes.map(\.id))
            let analyzed = await analyze(list.items.filter { !known.contains($0.id) }, since: since)
            guard revision == current else { return }
            changes += analyzed
            listTotal = list.total
            canLoadMore = !list.items.isEmpty && changes.count < list.total
        } catch is CancellationError {
        } catch {
            actionMessage = "Échec : \(error.userMessage)"
        }
    }

    /// Faits sources d'une observation (créée pendant la période : son historique n'en dit rien).
    public func sources(of id: String) async throws -> [SourceFactSummary] {
        let detail = try await client.memory(bank, id: id)
        return detail.raw["source_memories"]?.arrayValue?.compactMap(SourceFactSummary.init) ?? []
    }

    /// Lit l'historique des observations (au plus `historyConcurrency` à la fois) et en tire leurs changements.
    private func analyze(_ items: [MemoryUnitListItem], since: Date) async -> [ObservationChange] {
        var histories: [String: JSONValue] = [:]
        var missing: [MemoryUnitListItem] = []
        for item in items {
            if let cached = historyCache[item.id], cached.updatedAt == item.updatedAt {
                histories[item.id] = cached.history
            } else {
                missing.append(item)
            }
        }
        let client = self.client, bank = self.bank
        // Une structure, pas un tuple : un tuple renvoyé par une tâche fille peut être mal relu en -O (Swift 6.4).
        struct Fetched: Sendable { let id: String; let updatedAt: String?; let history: JSONValue? }
        let fetched = await withTaskGroup(of: Fetched.self, returning: [Fetched].self) { group in
            var next = 0, out: [Fetched] = []
            func add(_ item: MemoryUnitListItem) {
                group.addTask { Fetched(id: item.id, updatedAt: item.updatedAt, history: try? await client.observationHistory(bank, id: item.id)) }
            }
            while next < min(Self.historyConcurrency, missing.count) { add(missing[next]); next += 1 }
            while let result = await group.next() {
                out.append(result)
                if next < missing.count { add(missing[next]); next += 1 }
            }
            return out
        }
        for result in fetched {
            guard let history = result.history else { continue }
            histories[result.id] = history
            historyCache[result.id] = CachedHistory(updatedAt: result.updatedAt, history: history)
        }
        if historyCache.count > Self.cacheLimit {
            let keep = Set(items.map(\.id))
            historyCache = historyCache.filter { keep.contains($0.key) }
        }
        return items.map { ObservationChange(item: $0, history: histories[$0.id], since: since) }
    }

    // MARK: Actions

    private func blockedByPause() -> Bool {
        guard let reason = pauseGate?(bank) else { return false }
        actionMessage = reason
        return true
    }

    /// Refusée sans confirmation quand elle ne peut rien faire : banque sans observations (le serveur
    /// terminerait l'opération aussitôt, sans rien traiter), consolidation déjà en cours, rien à consolider.
    public func requestConsolidation() {
        guard !consultationOnly, !blockedByPause() else { return }
        if let refusal = status?.refusal { actionMessage = refusal; return }
        let pending = stats?.pendingConsolidation ?? 0
        confirmation = ConfirmationRequest(
            title: "Consolider les faits ?",
            message: Self.consolidationMessage(pending: pending)
                + (estimate?(.consolidation(facts: pending)).map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Consolider", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            if let refusal = self.status?.refusal { self.actionMessage = refusal; return }
            await self.run("Consolidation mise en file.") { c, b in
                let r = try await c.triggerConsolidation(b)
                return r.deduplicated ? "Une consolidation était déjà en file : cette demande l'a rejointe." : "Consolidation mise en file."
            }
        }
    }

    static func consolidationMessage(pending: Int) -> String {
        let facts = pending == 1 ? "du seul fait pas encore consolidé" : "des \(Format.number(pending)) faits pas encore consolidés"
        return "Le serveur va créer ou mettre à jour les observations à partir \(facts). Cela appelle le LLM de consolidation."
            + " Chaque fait rejoint les observations de sa portée (celle de son document)."
    }

    public func requestRecoverConsolidation() {
        guard !consultationOnly, !blockedByPause() else { return }
        // Remis en file, ces faits attendraient une consolidation qui ne vient pas.
        if status?.enabled == false { actionMessage = ConsolidationStatus.disabledMessage; return }
        let failed = stats?.failedConsolidation ?? 0
        guard failed > 0 else { actionMessage = "Aucun fait en échec de consolidation."; return }
        confirmation = ConfirmationRequest(
            title: "Reconsolider les faits en échec ?",
            message: failed == 1
                ? "Le fait en échec de consolidation sera remis dans la file. Aucune observation n'est supprimée."
                : "Les \(Format.number(failed)) faits en échec de consolidation seront remis dans la file. Aucune observation n'est supprimée.",
            confirmTitle: "Reconsolider", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            await self.run("Faits remis en file.") { c, b in
                let r = try await c.recoverConsolidation(b)
                return "\(Format.count(r.retriedCount, "fait")) remis en file."
            }
        }
    }

    private func run(_ fallback: String, _ work: @Sendable (HindsightClient, String) async throws -> String) async {
        guard !isBusy, !consultationOnly else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Message du moteur, en français et sans identifiant : jamais le texte anglais du serveur.
            let msg = try await work(client, bank)
            actionMessage = msg.isEmpty ? fallback : msg
        } catch {
            actionMessage = "Échec : \(error.userMessage)"
        }
        await reload(silently: true)
    }

    private static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
