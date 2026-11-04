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
    public private(set) var selectedDetail: LoadState<OperationStatusResponse> = .idle
    public private(set) var selectedID: String?
    public private(set) var isLoadingMore = false

    public var statusFilter: StatusFilter = .all
    public var typeFilter: String?
    public var excludeParents = false

    /// Dernier résultat d'action (« 3 opérations relancées »), à afficher puis effacer.
    public var actionMessage: String?
    /// Demande de confirmation en attente ; l'UI la présente puis appelle `perform()`.
    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    /// Refus pendant une pause de la banque (relances et consolidations consomment du LLM).
    @ObservationIgnored public var pauseGate: PauseGate?
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
        if !silently { state = .loading }
        do {
            async let list = client.listOperations(
                bank, status: statusFilter.apiValue, type: typeFilter, limit: 100, offset: 0, excludeParents: excludeParents)
            async let st = client.bankStats(bank)
            async let mode = try? client.isConsultationOnly()
            let (l, s) = try await (list, st)
            let isConsultation = await mode ?? false
            try Task.checkCancellation()
            consultationOnly = isConsultation
            rows = l.operations.map(OperationRow.init)
            total = l.total
            stats = s
            state = .loaded(())
            if let id = selectedID { await refreshDetail(id, silently: true) }
        } catch is CancellationError {
        } catch {
            if !silently || state.value == nil { state = .failed(error.userMessage) }
        }
    }

    public var canLoadMore: Bool { rows.count < total }

    public func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let l = try await client.listOperations(
                bank, status: statusFilter.apiValue, type: typeFilter, limit: 100, offset: rows.count,
                excludeParents: excludeParents)
            rows += l.operations.map(OperationRow.init)
            total = l.total
        } catch is CancellationError {
        } catch {
            actionMessage = error.userMessage
        }
    }

    /// Sélection depuis une liste : l'identifiant change tout de suite (la liste suit), le détail arrive ensuite.
    public func choose(_ id: String?) {
        selectedID = id
        Task { await select(id) }
    }

    public func select(_ id: String?) async {
        selectedID = id
        guard let id else {
            selectedDetail = .idle
            return
        }
        await refreshDetail(id, silently: false)
    }

    private func refreshDetail(_ id: String, silently: Bool) async {
        if !silently { selectedDetail = .loading }
        do {
            let d = try await client.operation(bank, id: id)
            try Task.checkCancellation()
            if selectedID == id { selectedDetail = .loaded(d) }
        } catch is CancellationError {
        } catch {
            if selectedID == id, !silently { selectedDetail = .failed(error.userMessage) }
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
        serverIs110 && !consultationOnly && row.status == .pending && (row.nextRetryAt.map { $0 > now } ?? false)
    }

    public func requestRunNow(_ row: OperationRow) {
        guard canRunNow(row), !blockedByPause() else { return }
        confirmation = ConfirmationRequest(
            title: "Lancer cette opération maintenant ?",
            message:
                "« \(row.title) » attend sa prochaine tentative\(row.nextRetryAt.map { " (\(Format.dateTime($0)))" } ?? ""). Elle sera lancée tout de suite ; selon son type, cela peut consommer des appels LLM.",
            confirmTitle: "Lancer maintenant", severity: .normal
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
                activityMessage = "Recherche des échecs : \(found.count) trouvé(s)…"
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
            return
        }
        confirmation = ConfirmationRequest(
            title: "Relancer \(ids.count) opération(s) échouée(s) ?",
            message: "Tous les échecs de la banque ont été recherchés, indépendamment des filtres de l'écran. Les sous-opérations seront remises en file ; les lots parents suivront leur progression. Cela peut consommer des appels LLM. Vérifiez d'abord les réglages des modèles : la relance ne corrige pas un quota épuisé ou une erreur de connexion.",
            confirmTitle: "Tout relancer", severity: .normal
        ) { [weak self] in
            guard let self, !self.isBusy, !self.blockedByPause() else { return }
            self.isBusy = true
            defer { self.isBusy = false; self.activityMessage = nil }
            var ok = 0
            var failures: [String] = []
            for (index, id) in ids.enumerated() {
                self.activityMessage = "Relance : \(index + 1) sur \(ids.count)…"
                do {
                    try Task.checkCancellation()
                    let r = try await self.client.retryOperation(self.bank, id: id)
                    if r.success { ok += 1 } else { failures.append(r.message) }
                } catch is CancellationError {
                    self.actionMessage = "Relance interrompue : \(ok) opération(s) remise(s) en file."
                    await self.reload(silently: true)
                    return
                } catch {
                    failures.append(error.userMessage)
                }
            }
            self.actionMessage =
                "\(ok) relancée(s)" + (failures.isEmpty ? "" : ", \(failures.count) refusée(s) : \(failures.first!)")
            await self.reload(silently: true)
        }
    }

    public func requestCancel(_ row: OperationRow) {
        confirmation = ConfirmationRequest(
            title: "Annuler cette opération ?",
            message: "« \(row.title) » sera interrompue si elle est en attente ou en cours.", confirmTitle: "Annuler l'opération"
        ) { [weak self] in
            await self?.run("Opération annulée") { c, b in
                let r = try await c.cancelOperation(b, id: row.id)
                return r.message
            }
        }
    }

    public func requestDelete(_ row: OperationRow) {
        confirmation = ConfirmationRequest(
            title: "Supprimer cette entrée ?",
            message: "L'entrée d'historique « \(row.title) » sera supprimée du serveur. Les faits déjà créés ne sont pas touchés.",
            confirmTitle: "Supprimer"
        ) { [weak self] in
            await self?.run("Entrée supprimée") { c, b in
                let r = try await c.deleteOperation(b, id: row.id)
                return r.message
            }
        }
    }

    public func requestConsolidation() {
        guard !blockedByPause() else { return }
        let pending = stats?.pendingConsolidation ?? 0
        confirmation = ConfirmationRequest(
            title: "Lancer la consolidation ?",
            message:
                "Le serveur va créer/mettre à jour les observations à partir des faits non consolidés (\(pending) en attente). Cela appelle le LLM de consolidation."
                + " Chaque fait se fond dans les observations de sa portée (celle de son document)."
                + (estimate?(.consolidation(facts: pending)).map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Lancer", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            await self.run("Consolidation mise en file") { c, b in
                let r = try await c.triggerConsolidation(b)
                return r.deduplicated ? "Une consolidation était déjà en file (fusionnée)." : "Opération \(r.operationId) créée."
            }
        }
    }

    public func requestRecoverConsolidation() {
        guard !blockedByPause() else { return }
        let failed = stats?.failedConsolidation ?? 0
        confirmation = ConfirmationRequest(
            title: "Réessayer les faits en échec de consolidation ?",
            message:
                "\(failed) fait(s) marqués « échec définitif » seront remis dans la file de consolidation (aucune observation supprimée).",
            confirmTitle: "Remettre en file", severity: .normal
        ) { [weak self] in
            guard let self, !self.blockedByPause() else { return }
            await self.run("Faits remis en file") { c, b in
                let r = try await c.recoverConsolidation(b)
                return "\(r.retriedCount) fait(s) remis en file."
            }
        }
    }

    private func retry(_ id: String) async {
        await run("Opération relancée") { c, b in
            let r = try await c.retryOperation(b, id: id)
            guard r.success else { throw HindsightError.refused(r.message) }
            return r.message
        }
    }

    private func run(_ fallback: String, _ work: @Sendable (HindsightClient, String) async throws -> String) async {
        guard !isBusy, !consultationOnly else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let msg = try await work(client, bank)
            actionMessage = msg.isEmpty ? fallback : msg
            await reload(silently: true)
        } catch {
            actionMessage = "Échec : \(error.userMessage)"
        }
    }
}
