import Foundation
import HindsightAPI
import Observation

/// Suivi des opérations asynchrones d'une banque : file d'attente, échecs, consolidation, relance.
@MainActor
@Observable
public final class OperationsViewModel {
    public enum StatusFilter: String, CaseIterable, Sendable, Identifiable {
        case all, pending, processing, failed, completed, cancelled
        public var id: String { rawValue }
        public var title: String { self == .all ? "Toutes" : OperationStatusKind(rawValue).title }
        var apiValue: String? { self == .all ? nil : rawValue }
    }

    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var rows: [OperationRow] = []
    public private(set) var total = 0
    public private(set) var stats: BankStatsResponse?
    /// Live bank-wide totals. `/stats` caches its operation counts alongside expensive memory aggregates.
    public private(set) var operationCounts: [String: Int]?
    /// Réglages résolus de la banque : rechargés à chaque ouverture de l'écran, gardés pendant les sondages.
    public private(set) var bankConfig: BankConfigResponse?
    /// Consolidations en cours et en attente (lu à chaque rechargement, une ligne par statut).
    public private(set) var activeConsolidations: ActiveConsolidations?
    /// Drapeau `features.observations` du serveur (réglé par `BankSession`).
    public var serverObservations: Bool?

    /// Même état que la Vue d'ensemble : désactivée, en cours, faits à consolider ou à jour.
    public var consolidation: ConsolidationStatus? {
        stats.map {
            ConsolidationStatus(
                stats: $0, config: bankConfig, serverObservations: serverObservations,
                operations: activeConsolidations ?? ActiveConsolidations())
        }
    }
    public private(set) var selectedDetail: LoadState<OperationStatusResponse> = .idle
    public private(set) var selectedID: String?
    public private(set) var isLoadingMore = false

    public var statusFilter: StatusFilter = .all { didSet { if oldValue != statusFilter { invalidateList() } } }
    public var typeFilter: String? { didSet { if oldValue != typeFilter { invalidateList() } } }
    /// Lots parents masqués par défaut : leurs opérations filles portent le travail, et « Relancer les échecs »
    /// ne relance qu'elles. Liste, compteurs et relance comptent ainsi les mêmes opérations.
    public var excludeParents = true { didSet { if oldValue != excludeParents { invalidateList() } } }
    public private(set) var isRefreshing = false
    @ObservationIgnored private var listRevision = UUID()
    @ObservationIgnored private var moreRevision: UUID?
    @ObservationIgnored private var detailRevision = UUID()
    @ObservationIgnored private var nextOffset = 0
    @ObservationIgnored private var exhausted = false

    private struct Query: Equatable, Sendable {
        let status: StatusFilter
        let type: String?
        let excludeParents: Bool
    }
    private var query: Query { Query(status: statusFilter, type: typeFilter, excludeParents: excludeParents) }
    private func invalidateList() {
        listRevision = UUID()
        moreRevision = nil
        rows = []; total = 0; nextOffset = 0; exhausted = false; operationCounts = nil
        isLoadingMore = false; isRefreshing = false; state = .idle
    }
    private func uniqueRows(_ values: [OperationResponse]) -> [OperationRow] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.map(OperationRow.init)
    }

    /// Dernier résultat d'action (« 3 opérations relancées »), à afficher puis effacer.
    public var actionMessage: String?
    /// Demande de confirmation en attente ; l'UI la présente puis appelle `perform()`.
    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    /// Refus pendant une pause de la banque (relances et consolidations consomment du LLM).
    @ObservationIgnored public var pauseGate: PauseGate?
    /// Worker du serveur arrêté (file gelée) : rien ne serait « lancé maintenant ».
    @ObservationIgnored public var workerOff: @MainActor () -> Bool = { false }
    public var confirmation: ConfirmationRequest?
    public private(set) var isBusy = false
    public private(set) var activityMessage: String?
    public private(set) var consultationOnly = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Serveur 1.1.0 : une opération différée peut être lancée tout de suite (réglé par `BankSession`).
    public var serverIs110 = false

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    // MARK: Chargement

    public func loadIfNeeded() async {
        if rows.isEmpty, !state.isLoading { await reload() }
    }

    public func reload(silently: Bool = false) async {
        guard !Task.isCancelled else { return }
        let revision = UUID(), requested = query
        listRevision = revision
        moreRevision = nil; isLoadingMore = false; isRefreshing = true
        defer { if listRevision == revision { isRefreshing = false } }
        if !silently { state = .loading }
        do {
            let visibleCount = silently ? max(100, nextOffset) : 100
            async let list = fetchWindow(requested, visibleCount: visibleCount)
            async let st = try? client.bankStats(bank)
            async let mode = try? client.isConsultationOnly()
            // Un réglage change dans un autre écran : relu à chaque ouverture, pas à chaque sondage.
            let readConfig = !silently || bankConfig == nil
            async let cfg = Self.readConfig(client, bank, when: readConfig)
            async let consolidating = ConsolidationStatus.activeOperations(client, bank)
            let l = try await list
            let statistics = await st
            let isConsultation = await mode
            let config = await cfg
            let active = await consolidating
            try Task.checkCancellation()
            guard revision == listRevision, requested == query else { return }
            consultationOnly = isConsultation ?? consultationOnly
            rows = uniqueRows(l.operations.filter { matches($0, requested) })
            nextOffset = l.nextOffset
            total = l.total
            exhausted = l.exhausted
            stats = statistics
            if let config { bankConfig = config }
            activeConsolidations = active
            operationCounts = l.counts
            state = .loaded(())
            if let id = selectedID { await refreshDetail(id, silently: true) }
        } catch is CancellationError {
            if revision == listRevision, state.isLoading { state = .idle }
        } catch {
            guard revision == listRevision, requested == query else { return }
            state = .failed(error.userMessage)
        }
    }

    public var canLoadMore: Bool { !exhausted && nextOffset < total }

    public func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isRefreshing else { return }
        let token = UUID(), revision = listRevision, requested = query, offset = nextOffset
        moreRevision = token
        isLoadingMore = true
        defer { if moreRevision == token { isLoadingMore = false; moreRevision = nil } }
        do {
            let l = try await client.listOperations(
                bank, status: requested.status.apiValue, type: requested.type, limit: 100, offset: offset,
                excludeParents: requested.excludeParents)
            try Task.checkCancellation()
            guard revision == listRevision, moreRevision == token, requested == query else { return }
            var seen = Set(rows.map(\.id))
            rows += l.operations.filter { matches($0, requested) && seen.insert($0.id).inserted }.map(OperationRow.init)
            nextOffset = offset + l.operations.count
            total = l.total
            exhausted = l.operations.isEmpty
            if requested.type == nil, requested.excludeParents, requested.status != .all {
                operationCounts?[requested.status.rawValue] = l.total
            }
        } catch is CancellationError {
        } catch {
            if revision == listRevision, requested == query { actionMessage = error.userMessage }
        }
    }

    private struct Window: Sendable {
        let operations: [OperationResponse]
        let total: Int
        let nextOffset: Int
        let exhausted: Bool
        let counts: [String: Int]?
    }
    private struct WindowPage: Sendable {
        let offset: Int
        let page: OperationsListResponse
    }
    private struct StatusCount: Sendable {
        let status: String
        let total: Int
    }
    /// Read only one row per counter, and reuse the displayed page's total when its scope matches.
    /// This avoids forcing `/stats` to rescan the bank's memories on every operation poll.
    private func fetchOperationCounts(_ query: Query, first: OperationsListResponse) async throws -> [String: Int] {
        let statuses: [StatusFilter] = [.pending, .processing, .failed]
        // Compteurs de toute la banque, lots parents exclus (même règle que la liste par défaut et la relance).
        let bankWide = query.type == nil && query.excludeParents
        var counts = Dictionary(uniqueKeysWithValues: statuses.map { ($0.rawValue, 0) })
        if bankWide, query.status == .all, first.operations.count == first.total {
            for row in first.operations { counts[row.status, default: 0] += 1 }
            return counts
        }
        if bankWide, query.status != .all { counts[query.status.rawValue] = first.total }
        let client = self.client, bank = self.bank
        return try await withThrowingTaskGroup(of: StatusCount.self) { group in
            for status in statuses where !(bankWide && query.status == status) {
                group.addTask {
                    let page = try await client.listOperations(bank, status: status.rawValue, limit: 1, excludeParents: true)
                    return StatusCount(status: status.rawValue, total: page.total)
                }
            }
            for try await result in group { counts[result.status] = result.total }
            return counts
        }
    }
    private static func readConfig(_ client: HindsightClient, _ bank: String, when read: Bool) async -> BankConfigResponse? {
        guard read else { return nil }
        return try? await client.bankConfig(bank)
    }
    private func matches(_ row: OperationResponse, _ query: Query) -> Bool {
        query.status == .all || OperationStatusKind(row.status).rawValue == query.status.rawValue
    }
    /// A quiet refresh preserves the already opened pages. Keep at most four HTTP reads in flight.
    private func fetchWindow(_ query: Query, visibleCount: Int) async throws -> Window {
        let client = self.client, bank = self.bank
        let first = try await client.listOperations(bank, status: query.status.apiValue, type: query.type,
            limit: 100, offset: 0, excludeParents: query.excludeParents)
        async let counts = fetchOperationCounts(query, first: first)
        var values = first.operations
        var end = values.count
        var exhausted = values.isEmpty
        let target = min(visibleCount, first.total)
        if !exhausted, target > end {
            let step = min(100, max(1, first.limit))
            let offsets = Array(stride(from: end, to: target, by: step))
            for start in stride(from: 0, to: offsets.count, by: 4) {
                try Task.checkCancellation()
                let batch = Array(offsets[start..<min(start + 4, offsets.count)])
                let pages = try await withThrowingTaskGroup(of: WindowPage.self) { group in
                    for offset in batch {
                        group.addTask {
                            let page = try await client.listOperations(bank, status: query.status.apiValue, type: query.type,
                                limit: step, offset: offset, excludeParents: query.excludeParents)
                            return WindowPage(offset: offset, page: page)
                        }
                    }
                    var results: [WindowPage] = []
                    for try await result in group { results.append(result) }
                    return results.sorted { $0.offset < $1.offset }
                }
                for result in pages {
                    if result.page.operations.isEmpty { exhausted = true; break }
                    values += result.page.operations
                    end = result.offset + result.page.operations.count
                }
                if exhausted { break }
            }
        }
        return Window(operations: values, total: first.total, nextOffset: end, exhausted: exhausted, counts: try? await counts)
    }

    /// Sélection depuis une liste : l'identifiant change tout de suite (la liste suit), le détail arrive ensuite.
    public func choose(_ id: String?) {
        selectedID = id
        detailRevision = UUID()
        let revision = detailRevision
        selectedDetail = id == nil ? .idle : .loading
        Task { [weak self] in
            guard let self, self.detailRevision == revision, let id else { return }
            await self.refreshDetail(id, silently: false)
        }
    }

    public func select(_ id: String?) async {
        selectedID = id
        detailRevision = UUID()
        guard let id else {
            selectedDetail = .idle
            return
        }
        await refreshDetail(id, silently: false)
    }

    private func refreshDetail(_ id: String, silently: Bool) async {
        let revision = UUID()
        detailRevision = revision
        if !silently { selectedDetail = .loading }
        do {
            let d = try await client.operation(bank, id: id)
            try Task.checkCancellation()
            if selectedID == id, detailRevision == revision { selectedDetail = .loaded(d) }
        } catch is CancellationError {
        } catch {
            if selectedID == id, detailRevision == revision, !silently { selectedDetail = .failed(error.userMessage) }
        }
    }

    // MARK: Indicateurs

    public var activeCount: Int { rows.filter { $0.status.isActive }.count }
    public var failedRows: [OperationRow] { rows.filter { $0.status == .failed } }

    /// Opérations échouées regroupées par cause, de la plus fréquente à la plus rare.
    public var failureGroups: [FailureGroup] {
        var buckets: [String: (sample: String, ids: [String])] = [:]
        for r in failedRows {
            let sig = r.failureSignature ?? "(aucun message d'erreur)"
            var b = buckets[sig] ?? (r.errorMessage ?? sig, [])
            b.ids.append(r.id)
            buckets[sig] = b
        }
        return buckets.map { FailureGroup(signature: $0.key, sampleMessage: $0.value.sample, operationIDs: $0.value.ids) }
            .sorted { ($1.count, $0.signature) < ($0.count, $1.signature) }
    }

    public var knownTypes: [String] {
        Array(Set(rows.map(\.typeKey))).sorted()
    }

    // MARK: Suivi automatique

    /// Rafraîchit périodiquement tant que la vue est visible : toutes les `seconds` secondes quand des
    /// opérations sont actives, `idleFactor` fois moins souvent sinon (la liste et `/stats` coûtent sur une
    /// grosse banque).
    public func startAutoRefresh(every seconds: Double = 4, idleFactor: Double = 5) {
        stopAutoRefresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let active = (self?.activeCount ?? 0) > 0
                try? await Task.sleep(for: .seconds(active ? seconds : seconds * idleFactor))
                if Task.isCancelled { break }
                await self?.reload(silently: true)
            }
        }
    }

    public func stopAutoRefresh() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Actions (toutes passent par une confirmation)

    /// Vrai si la pause interdit l'action (le message est alors affiché).
    private func blockedByPause() -> Bool {
        guard let reason = pauseGate?(bank) else { return false }
        actionMessage = reason
        return true
    }

    public func requestRetry(_ row: OperationRow) {
        guard !consultationOnly, !blockedByPause() else { return }
        confirmation = ConfirmationRequest(
            title: "Relancer cette opération ?",
            message:
                "« \(row.title) »\(row.target.map { " — \($0)" } ?? "") sera remise en file. Selon son type, cela peut consommer des appels LLM.",
            confirmTitle: "Relancer", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            await self.retry(row.id)
        }
    }

    /// Opération en attente d'une nouvelle tentative (`next_retry_at` futur) : le serveur 1.1.0 la lance tout de suite.
    public func canRunNow(_ row: OperationRow, now: Date = Date()) -> Bool {
        serverIs110 && !consultationOnly && !workerOff() && row.status == .pending && (row.nextRetryAt.map { $0 > now } ?? false)
    }

    public func requestRunNow(_ row: OperationRow) {
        guard canRunNow(row), !blockedByPause() else { return }
        confirmation = ConfirmationRequest(
            title: "Exécuter cette opération maintenant ?",
            message:
                "« \(row.title) » attend sa prochaine tentative\(row.nextRetryAt.map { " (\(Format.dateTime($0)))" } ?? ""). Elle sera exécutée tout de suite ; selon son type, cela peut consommer des appels LLM.",
            confirmTitle: "Exécuter maintenant", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            await self.retry(row.id)
        }
    }

    /// Prépare une liste figée avant toute écriture : paginer après chaque relance ferait sauter
    /// des entrées, puisque les opérations remises en file quittent le filtre « failed ».
    public func requestRetryAllFailed() async {
        guard !isBusy, !consultationOnly, !blockedByPause() else { return }
        isBusy = true
        activityMessage = "Recherche des opérations en échec…"
        defer { isBusy = false; activityMessage = nil }
        let ids: [String]
        do {
            var found: [String] = []
            var seen: Set<String> = []
            var offset = 0
            var target: Int?
            repeat {
                // Les parents de lots sont des agrégateurs ; relancer leurs enfants suffit.
                let page = try await client.listOperations(bank, status: "failed", limit: 100,
                                                           offset: offset, excludeParents: true)
                if target == nil { target = page.total }
                guard !page.operations.isEmpty else {
                    if offset < (target ?? 0) {
                        throw HindsightError.refused("La liste des échecs a changé pendant le chargement. Réessayez.")
                    }
                    break
                }
                for row in page.operations where row.status == "failed" && seen.insert(row.id).inserted {
                    found.append(row.id)
                }
                offset += page.operations.count
                activityMessage = "Recherche des échecs : \(Format.count(found.count, "trouvé"))…"
            } while offset < (target ?? 0)
            ids = found
        } catch is CancellationError {
            return
        } catch {
            actionMessage = "Impossible de préparer la relance : \(error.userMessage)"
            return
        }
        guard !ids.isEmpty else {
            actionMessage = "Aucune opération en échec à relancer."
            await reload(silently: true)
            return
        }
        confirmation = ConfirmationRequest(
            title: "Relancer \(Format.count(ids.count, "opération échouée", "opérations échouées")) ?",
            message: "Tous les échecs de la banque ont été recherchés, indépendamment des filtres de l'écran. Les sous-opérations seront remises en file ; les lots parents suivront leur progression. Cela peut consommer des appels LLM. Vérifiez d'abord les réglages des modèles : la relance ne corrige pas un quota épuisé ou une erreur de connexion.",
            confirmTitle: "Tout relancer", severity: .normal
        ) { [weak self] in
            guard let self, !self.isBusy, !self.blockedByPause() else { return }
            self.isBusy = true
            defer { self.isBusy = false; self.activityMessage = nil }
            var ok = 0
            var failures: [String] = []
            for (index, id) in ids.enumerated() {
                self.activityMessage = "Relance : \(Format.number(index + 1)) sur \(Format.number(ids.count))…"
                do {
                    try Task.checkCancellation()
                    let r = try await self.client.retryOperation(self.bank, id: id)
                    if r.success { ok += 1 } else { failures.append(r.message) }
                } catch is CancellationError {
                    self.actionMessage = "Relance interrompue : \(Format.count(ok, "opération remise", "opérations remises")) en file."
                    await self.reload(silently: true)
                    return
                } catch {
                    failures.append(error.userMessage)
                }
            }
            self.actionMessage = failures.isEmpty
                ? "\(Format.count(ok, "opération relancée", "opérations relancées"))."
                : "\(Format.count(ok, "opération relancée", "opérations relancées")), \(Format.count(failures.count, "refusée", "refusées")) : \(failures.first!)"
            await self.reload(silently: true)
        }
    }

    public func requestCancel(_ row: OperationRow) {
        confirmation = ConfirmationRequest(
            title: "Annuler cette opération ?",
            message: "« \(row.title) » sera interrompue si elle est en attente ou en cours.", confirmTitle: "Annuler l'opération"
        ) { [weak self] in
            await self?.run("Opération annulée.") { c, b in
                let r = try await c.cancelOperation(b, id: row.id)
                guard r.success else { throw HindsightError.refused(r.message) }
                return ""
            }
        }
    }

    public func requestDelete(_ row: OperationRow) {
        confirmation = ConfirmationRequest(
            title: "Supprimer cette entrée ?",
            message: "L'entrée d'historique « \(row.title) » sera supprimée du serveur. Les faits déjà créés ne sont pas touchés.",
            confirmTitle: "Supprimer"
        ) { [weak self] in
            await self?.run("Entrée supprimée.") { c, b in
                let r = try await c.deleteOperation(b, id: row.id)
                guard r.success else { throw HindsightError.refused(r.message) }
                return ""
            }
        }
    }

    /// Refusée sans confirmation quand elle ne peut rien faire : banque sans observations (le serveur
    /// terminerait l'opération aussitôt, sans rien traiter), consolidation déjà en cours, rien à consolider.
    public func requestConsolidation() {
        guard !consultationOnly, !blockedByPause() else { return }
        if let refusal = consolidation?.refusal { actionMessage = refusal; return }
        let pending = stats?.pendingConsolidation ?? 0
        confirmation = ConfirmationRequest(
            title: "Consolider les faits ?",
            message: Self.consolidationMessage(pending: pending)
                + (estimate?(.consolidation(facts: pending)).map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Consolider", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            if let refusal = self.consolidation?.refusal { self.actionMessage = refusal; return }
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
        if consolidation?.enabled == false { actionMessage = ConsolidationStatus.disabledMessage; return }
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

    private func retry(_ id: String) async {
        await run("Opération relancée.") { c, b in
            let r = try await c.retryOperation(b, id: id)
            guard r.success else { throw HindsightError.refused(r.message) }
            return ""
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
        // A refusal can mean another client already completed or retried the operation.
        await reload(silently: true)
    }
}
