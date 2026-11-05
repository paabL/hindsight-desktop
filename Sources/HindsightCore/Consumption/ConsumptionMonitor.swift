import Foundation
import HindsightAPI
import Observation

/// Un dépassement (ou une approche) de plafond, à notifier.
public struct ConsumptionAlert: Sendable, Hashable, Identifiable {
    public let id = UUID()
    public let gauge: BudgetGauge
    public let date: Date

    public var title: String {
        gauge.level == .exceeded ? "Plafond atteint : \(gauge.title)" : "Plafond bientôt atteint : \(gauge.title)"
    }
    public var message: String { "\(gauge.usedText) sur \(gauge.limitText)" + (gauge.note.map { " (\($0))" } ?? "") }
}

/// Suivi de la consommation LLM de toutes les banques : lit les nouvelles traces du serveur à intervalle
/// régulier (plus souvent quand un écran de suivi est visible), les verse dans l'historique local, calcule
/// rythme, totaux et plafonds, et signale les dépassements.
///
/// Les traces ne sont lues que depuis la dernière vue (avec un recouvrement de 10 min, une trace n'étant écrite
/// qu'à la fin de son appel) : un suivi qui tourne coûte quelques requêtes par minute.
@MainActor
@Observable
public final class ConsumptionMonitor {
    /// Une opération en cours sur le serveur.
    public struct RunningOperation: Sendable, Hashable, Identifiable {
        public let id: String
        public let bank: String
        public let row: OperationRow
    }

    /// File d'une banque.
    public struct BankQueue: Sendable, Hashable, Identifiable {
        public var id: String { bank }
        public let bank: String
        public var pending: Int
        public var processing: Int
    }

    /// Période des répartitions.
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case hour = "1 h", day = "24 h", week = "7 jours", month = "30 jours"
        public var id: String { rawValue }
        public var seconds: TimeInterval {
            switch self {
            case .hour: return 3_600
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }
    }

    /// Sommes des fenêtres affichées, recalculées après chaque relevé.
    public struct Summary: Sendable, Hashable {
        public var rate = ConsumptionMath.Rate()
        public var lastHour = ConsumptionTotals()
        public var today = ConsumptionTotals()
        public var last5h = ConsumptionTotals()
        public var week = ConsumptionTotals()
        public init() {}
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let banksProvider: @MainActor () -> [String]
    @ObservationIgnored private let ledger: UsageLedger?
    @ObservationIgnored private let pricesProvider: @MainActor () -> PriceBook
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Traces activées sur le serveur (`/version`) ; nil si inconnu.
    @ObservationIgnored public var traceEnabled: (@MainActor () -> Bool?)?
    /// Notification d'un plafond approché ou dépassé (fournie par l'interface).
    @ObservationIgnored public var onAlert: (@MainActor (ConsumptionAlert) -> Void)?
    /// Plafond dépassé : action automatique (pause), décidée par `PauseController`.
    @ObservationIgnored public var onExceeded: (@MainActor ([BudgetGauge], ConsumptionBudgets.Action) async -> Void)?

    /// Appels des 35 derniers jours, triés par date croissante.
    public private(set) var events: [ConsumptionEvent] = []
    public private(set) var summary = Summary()
    public private(set) var gauges: [BudgetGauge] = []
    public private(set) var queues: [BankQueue] = []
    public private(set) var running: [RunningOperation] = []
    public private(set) var lastPoll: Date?
    public private(set) var pollError: String?
    public private(set) var isPolling = false
    /// Banques dont le rattrapage initial a été tronqué (trop de traces d'un coup).
    public private(set) var truncatedBanks: Set<String> = []
    /// Dernière alerte émise (bandeau de l'écran Consommation).
    public var latestAlert: ConsumptionAlert?
    /// Appels de décision, rerank et embeddings sur la période, toutes banques (serveur 1.2.0 ; vide sinon).
    public private(set) var services: [ModelServiceUsage] = []
    /// Un relevé partiel reste visible, accompagné des banques qui n'ont pas pu être lues.
    public private(set) var servicesError: String?

    public var budgets: ConsumptionBudgets {
        didSet {
            guard budgets != oldValue else { return }
            budgets.save(to: settings)
            recompute(evaluate: true)
        }
    }

    public var period: Period = .day
    public var dimension: ConsumptionMath.Dimension = .bank

    @ObservationIgnored private var knownIDs: Set<String> = []
    @ObservationIgnored private var cursors: [String: Date] = [:]
    @ObservationIgnored private var loadedHistory = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Écrans de suivi visibles, comptés : une vue recréée peut apparaître avant que l'ancienne disparaisse.
    @ObservationIgnored private var liveViewers: [String: Int] = [:]
    @ObservationIgnored private var lastLivePoll: Date?
    /// Durée du plus long appel vu récemment : une trace n'est écrite qu'à la fin de son appel, datée de son
    /// début ; la relecture remonte d'autant (bornée).
    @ObservationIgnored private var longestCall: TimeInterval = 120
    /// Calculs dérivés (histogrammes, répartitions), valables pour une révision des appels et une grille.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var derived: [String: Any] = [:]
    /// Niveau déjà signalé par jauge (pour ne notifier qu'au franchissement d'un seuil).
    @ObservationIgnored private var alerted: [String: Int]

    public static let keepDays: Double = 35
    /// Intervalle de relevé : en fond, et quand un écran de suivi est ouvert.
    public var backgroundInterval: Duration = .seconds(60)
    public var liveInterval: Duration = .seconds(10)

    public init(
        settings: SettingsStore, client: @escaping @MainActor () -> HindsightClient, banks: @escaping @MainActor () -> [String],
        ledger: UsageLedger?, prices: @escaping @MainActor () -> PriceBook, now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.clientProvider = client
        self.banksProvider = banks
        self.ledger = ledger
        self.pricesProvider = prices
        self.now = now
        self.budgets = ConsumptionBudgets.load(from: settings)
        self.alerted =
            settings.string(forKey: Self.alertedKey).flatMap { try? JSONDecoder().decode([String: Int].self, from: Data($0.utf8)) } ?? [:]
    }

    static let alertedKey = "consumptionAlerted"

    // MARK: Boucle

    /// Relevés en tâche de fond, tant que l'app est ouverte.
    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                guard let self else { return }
                let interval = self.liveViewers.isEmpty ? self.backgroundInterval : self.liveInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Un écran de suivi (Consommation, barre des menus) est visible : relevés plus fréquents, file comprise.
    public func setLive(_ viewer: String, _ active: Bool) {
        let wasIdle = !isLive
        liveViewers[viewer, default: 0] += active ? 1 : -1
        if (liveViewers[viewer] ?? 0) <= 0 { liveViewers[viewer] = nil }
        // Reprend tout de suite au lieu d'attendre la fin de l'intervalle de fond.
        if active, wasIdle, loop != nil { start() }
    }

    public var isLive: Bool { !liveViewers.isEmpty }

    /// Autre serveur : tout repart de zéro (les banques peuvent porter les mêmes noms).
    public func reset() {
        servicesGeneration = UUID()
        servicesLoadID = nil
        lastServicesLoad = nil
        servicesBanks = []
        serviceStats = []
        services = []
        servicesError = nil
        events = []
        knownIDs = []
        cursors = [:]
        loadedHistory = false
        queues = []
        running = []
        truncatedBanks = []
        lastLivePoll = nil
        revision += 1
        derived = [:]
        recompute(evaluate: false)
    }

    // MARK: Relevé

    public func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        if !loadedHistory { await loadHistory() }
        let banks = banksProvider()
        let client = clientProvider()
        var errors: [String] = []
        if traceEnabled?() != false {
            for bank in banks {
                do {
                    try await fetchTraces(bank: bank, client: client)
                } catch is CancellationError {
                    return
                } catch {
                    errors.append("\(bank) : \(error.userMessage)")
                }
            }
        }
        // La file : toutes les 20 s quand un écran de suivi est ouvert, toutes les 5 min sinon.
        if lastLivePoll == nil || now().timeIntervalSince(lastLivePoll!) >= (isLive ? 20 : 300) {
            await pollQueues(banks: banks, client: client)
            lastLivePoll = now()
        }
        await ledger?.flushIfDue(now: now())
        pollError = errors.isEmpty ? nil : "Traces illisibles pour " + errors.joined(separator: " ; ")
        lastPoll = now()
        recompute(evaluate: true)
    }

    /// Relevé des appels non génératifs sur 7 jours : trois statistiques par banque, au plus toutes les 5 min.
    /// Un serveur 1.1.0 ne sait pas ventiler par modèle. Les échecs restent visibles et peuvent être réessayés.
    public func loadServices(serverIs120: Bool) async {
        guard serverIs120, traceEnabled?() != false else {
            servicesGeneration = UUID()
            servicesLoadID = nil
            lastServicesLoad = nil
            serviceStats = []
            services = []
            servicesError = nil
            return
        }
        let banks = banksProvider().sorted()
        if servicesBanks == banks, let last = lastServicesLoad, now().timeIntervalSince(last) < 300 {
            services = ModelServiceUsage.rows(serviceStats, prices: prices)
            return
        }
        guard servicesLoadID == nil else { return }
        let loadID = UUID(), generation = servicesGeneration
        servicesLoadID = loadID
        defer { if servicesLoadID == loadID { servicesLoadID = nil } }
        let client = clientProvider()
        var stats: [(kind: ModelCallKind, response: LLMRequestStatsResponse)] = []
        var errors: [String] = []
        for bank in banks {
            for kind in ModelServiceUsage.kinds {
                do {
                    stats.append((kind, try await client.llmRequestStats(bank, period: "7d", callType: kind.rawValue, splitBy: "model")))
                } catch is CancellationError {
                    return
                } catch {
                    errors.append("\(bank) (\(kind.rawValue)) : \(error.userMessage)")
                }
                guard servicesGeneration == generation else { return }
            }
        }
        servicesBanks = banks
        serviceStats = stats
        services = ModelServiceUsage.rows(stats, prices: prices)
        servicesError = errors.isEmpty ? nil : "Relevé des services incomplet : " + errors.joined(separator: " ; ")
        lastServicesLoad = errors.isEmpty ? now() : nil
    }
    @ObservationIgnored private var lastServicesLoad: Date?
    @ObservationIgnored private var servicesBanks: [String] = []
    @ObservationIgnored private var serviceStats: [(kind: ModelCallKind, response: LLMRequestStatsResponse)] = []
    @ObservationIgnored private var servicesGeneration = UUID()
    @ObservationIgnored private var servicesLoadID: UUID?

    /// Historique local des 35 derniers jours (une fois).
    func loadHistory() async {
        loadedHistory = true
        guard let ledger else { return }
        let since = now().addingTimeInterval(-Self.keepDays * 86_400)
        let records = await ledger.records(bank: nil, since: since)
        let loaded = records.compactMap(ConsumptionEvent.init)
        insert(loaded)
        for e in loaded { cursors[e.bank] = max(cursors[e.bank] ?? .distantPast, e.date) }
    }

    /// Nouvelles traces d'une banque depuis la dernière vue.
    func fetchTraces(bank: String, client: HindsightClient) async throws {
        let cursor = cursors[bank]
        // Une trace n'est écrite qu'à la fin de son appel, datée de son début : on relit la durée du plus long
        // appel récent (au moins 2 min, au plus 15).
        let overlap = min(max(120, longestCall * 1.5 + 60), 900)
        let since = cursor.map { $0.addingTimeInterval(-overlap) } ?? now().addingTimeInterval(-7 * 86_400)
        let cap = cursor == nil ? 2_000 : 20_000
        var entries: [LLMRequestEntry] = []
        var offset = 0
        while entries.count < cap {
            // Appels LLM seulement : depuis 1.1.0, les traces comptent aussi embeddings, rerank et décision.
            let page = try await client.llmRequests(bank, callType: ModelCallKind.generativeFilter, start: since, limit: 200, offset: offset)
            entries += page.items.filter(\.isGenerative)
            offset += page.items.count
            if page.items.count < 200 || offset >= page.total { break }
        }
        if entries.count >= cap { truncatedBanks.insert(bank) }
        if let longest = entries.compactMap(\.durationMs).max() {
            longestCall = max(Double(longest) / 1000, longestCall * 0.9)
        }
        let fresh = entries.filter { !knownIDs.contains($0.id) }
        if !fresh.isEmpty, let ledger { await ledger.merge(fresh, bank: bank, now: now()) }
        let added = fresh.compactMap { ConsumptionEvent(UsageRecord($0, bank: bank)) }
        insert(added)
        let latest = added.map(\.date).max()
        cursors[bank] = max(cursor ?? latest ?? now(), latest ?? .distantPast)
    }

    private func insert(_ new: [ConsumptionEvent]) {
        var fresh = new.filter { knownIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        fresh.sort { $0.date < $1.date }
        var all = events
        // Le plus souvent, les nouveaux appels sont plus récents que tous les autres : il suffit d'ajouter.
        if let last = all.last, fresh[0].date < last.date {
            all += fresh
            all.sort { $0.date < $1.date }
        } else {
            all += fresh
        }
        let first = ConsumptionMath.firstIndex(all, from: now().addingTimeInterval(-Self.keepDays * 86_400))
        if first > 0 {
            for e in all[..<first] { knownIDs.remove(e.id) }
            all.removeFirst(first)
        }
        events = all
        revision += 1
    }

    /// Pour les tests : verse des appels sans passer par le serveur.
    func ingestForTesting(_ new: [ConsumptionEvent]) {
        insert(new)
        recompute(evaluate: false)
    }

    /// File de chaque banque : opérations en attente et en cours.
    func pollQueues(banks: [String], client: HindsightClient) async {
        var queues: [BankQueue] = []
        var running: [RunningOperation] = []
        for bank in banks {
            do {
                async let pending = client.listOperations(bank, status: "pending", limit: 1, excludeParents: true)
                async let processing = client.listOperations(bank, status: "processing", limit: 20, excludeParents: true)
                let (p, r) = try await (pending, processing)
                queues.append(BankQueue(bank: bank, pending: p.total, processing: r.total))
                running += r.operations.map { RunningOperation(id: bank + "/" + $0.id, bank: bank, row: OperationRow($0)) }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
        self.queues = queues
        self.running = running
    }

    public var pendingTotal: Int { queues.reduce(0) { $0 + $1.pending } }
    public var processingTotal: Int { queues.reduce(0) { $0 + $1.processing } }

    // MARK: Calculs

    public var prices: PriceBook { pricesProvider() }

    /// Recalcule résumés et jauges ; signale les seuils franchis.
    public func recompute(evaluate: Bool) {
        revision += 1
        let t = now(), p = prices
        services = ModelServiceUsage.rows(serviceStats, prices: p)
        var s = Summary()
        s.rate = ConsumptionMath.rate(events, now: t, minutes: 5, prices: p)
        s.lastHour = ConsumptionMath.totals(ConsumptionMath.since(events, t.addingTimeInterval(-3_600)), prices: p)
        s.today = ConsumptionMath.totals(ConsumptionMath.since(events, ConsumptionMath.startOfDay(t)), prices: p)
        s.last5h = ConsumptionMath.totals(ConsumptionMath.since(events, t.addingTimeInterval(-5 * 3_600)), prices: p)
        s.week = ConsumptionMath.totals(ConsumptionMath.since(events, t.addingTimeInterval(-7 * 86_400)), prices: p)
        summary = s
        gauges = ConsumptionMath.gauges(events, budgets: budgets, prices: p, now: t)
        if evaluate { evaluateGauges() }
    }

    /// Signale chaque seuil au moment où il est franchi, pas à chaque relevé ; l'action automatique suit le même
    /// principe : reprendre à la main pendant un dépassement n'est pas annulé au relevé suivant.
    func evaluateGauges() {
        var exceeded: [BudgetGauge] = []
        var changed = false
        let configured = Self.gaugeIDs(budgets)
        for g in gauges {
            let previous = alerted[g.id] ?? 0
            if g.level.rawValue > previous {
                let alert = ConsumptionAlert(gauge: g, date: now())
                latestAlert = alert
                onAlert?(alert)
                if g.level == .exceeded { exceeded.append(g) }
            }
            if g.level.rawValue != previous {
                alerted[g.id] = g.level.rawValue
                changed = true
            }
        }
        // Retiring a budget clears its old alert state.
        for id in alerted.keys where !configured.contains(id) {
            alerted[id] = nil
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(alerted) {
            settings.set(String(decoding: data, as: UTF8.self), forKey: Self.alertedKey)
        }
        let action = budgets.effectiveAction
        if !exceeded.isEmpty, action != .alert, let onExceeded {
            Task { await onExceeded(exceeded, action) }
        }
    }

    /// Identifiants des jauges que les plafonds réglés peuvent produire.
    static func gaugeIDs(_ b: ConsumptionBudgets) -> Set<String> {
        var ids: Set<String> = []
        if b.dailyDollars != nil { ids.insert("dollars.day") }
        return ids
    }

    /// Mémorise un calcul dérivé pour la révision courante des appels et la grille de prix.
    private func memo<T>(_ key: String, _ make: () -> T) -> T {
        let k = "\(revision)|\(prices.hashValue)|\(key)"
        if let v = derived[k] as? T { return v }
        if derived.count > 64 { derived = [:] }
        let v = make()
        derived[k] = v
        return v
    }

    /// Histogramme de la période choisie (minutes, heures ou jours civils selon sa longueur).
    public func buckets(_ period: Period) -> [ConsumptionMath.Bucket] {
        memo("buckets.\(period.rawValue)") {
            let t = now()
            switch period {
            case .hour:
                let to = Self.floor(t, 60).addingTimeInterval(60)
                return ConsumptionMath.buckets(events, from: to.addingTimeInterval(-3_600), to: to, step: 60, prices: prices)
            case .day:
                let to = Self.floor(t, 3_600).addingTimeInterval(3_600)
                return ConsumptionMath.buckets(events, from: to.addingTimeInterval(-86_400), to: to, step: 3_600, prices: prices)
            case .week, .month:
                let bounds = ConsumptionMath.dayBoundaries(endingWith: t, days: period == .week ? 7 : 30)
                return ConsumptionMath.buckets(events, boundaries: bounds, prices: prices)
            }
        }
    }

    static func floor(_ d: Date, _ step: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / step).rounded(.down) * step)
    }

    public func totals(_ period: Period) -> ConsumptionTotals {
        memo("totals.\(period.rawValue)") {
            ConsumptionMath.totals(ConsumptionMath.since(events, now().addingTimeInterval(-period.seconds)), prices: prices)
        }
    }

    public func breakdown(_ period: Period, by dimension: ConsumptionMath.Dimension, limit: Int = 12) -> [ConsumptionMath.Share] {
        memo("breakdown.\(period.rawValue).\(dimension.rawValue).\(limit)") {
            ConsumptionMath.breakdown(
                ConsumptionMath.since(events, now().addingTimeInterval(-period.seconds)), by: dimension, prices: prices, limit: limit)
        }
    }

    /// Coût d'extraction d'un document sur l'historique suivi (35 jours), toutes banques.
    public func documentTotals(_ documentID: String, bank: String? = nil) -> ConsumptionTotals? {
        documentCost([documentID], bank: bank).map { c in
            var t = ConsumptionTotals()
            t.calls = c.calls
            t.tokens = c.tokens
            t.dollars = c.dollars
            return t
        }
    }

    /// Coût d'extraction de documents d'une banque (appels portant leur `document_id`) sur l'historique suivi.
    public func documentCost(_ documentIDs: [String], bank: String?) -> FileCoverageViewModel.Cost? {
        let ids = Set(documentIDs)
        let matching = events.filter { ids.contains($0.document) && (bank == nil || $0.bank == bank) }
        guard !matching.isEmpty else { return nil }
        var cache = BillingCache(prices)
        var dollars = 0.0, unpriced = 0, tokens = TokenCount()
        for e in matching {
            tokens = tokens + e.tokens
            if let d = cache.billing(e).dollars { dollars += d } else { unpriced += 1 }
        }
        return FileCoverageViewModel.Cost(calls: matching.count, tokens: tokens, dollars: dollars, unpriced: unpriced, documentsRead: ids.count)
    }

    /// Niveau le plus haut parmi les jauges.
    public var worstLevel: BudgetGauge.Level { gauges.map(\.level).max() ?? .ok }
}
