import Foundation
import HindsightAPI
import Observation

/// Services partagés entre les banques : estimations de coût et historique local de consommation.
@MainActor
public final class AppServices {
    public let estimator: CostEstimator
    public let ledger: UsageLedger?
    public let callers: CallerDirectory?

    public init(estimator: CostEstimator, ledger: UsageLedger?, callers: CallerDirectory? = nil) {
        self.estimator = estimator
        self.ledger = ledger
        self.callers = callers
    }
}

/// Consommation LLM (jetons, coût estimé, part d'abonnement) par opération et par modèle.
/// Source : traces LLM du serveur, versées dans l'historique local à chaque chargement.
@MainActor
@Observable
public final class UsageViewModel {
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case day = "24 h", week = "7 jours", month = "30 jours", all = "Tout l'historique"
        public var id: String { rawValue }
        var days: Double? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    @ObservationIgnored private let services: AppServices?
    @ObservationIgnored private let now: () -> Date

    public var period: Period = .week
    /// Toutes les banques de l'historique local (pas seulement celle-ci).
    public var allBanks = false
    public private(set) var state: LoadState<Void> = .idle
    public private(set) var rows: [UsageRow] = []
    public private(set) var totals = UsageTotals()
    public private(set) var daily: [DailyUsage] = []
    /// Traces lues sur le serveur lors du dernier chargement.
    public private(set) var fetchedTraces = 0
    public private(set) var oldestTrace: String?

    private let features: FeaturesInfo?

    public init(
        client: HindsightClient, bank: String, services: AppServices?, features: FeaturesInfo? = nil, now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.bank = bank
        self.services = services
        self.features = features
        self.now = now
    }

    /// Le serveur n'enregistre pas ses appels LLM : rien à compter.
    public var llmTraceEnabled: Bool { features?.llmTrace ?? true }

    public var priceBook: PriceBook { services?.estimator.priceBook ?? .defaults }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    public func reload() async {
        guard llmTraceEnabled else {
            state = .failed(
                "Le serveur n'enregistre pas ses appels LLM : ajoutez \(AuditViewModel.llmTraceEnvVar)=true à son environnement, puis redémarrez-le.")
            return
        }
        state = .loading
        do {
            // Jusqu'à 2 000 traces récentes (4 pages) : de quoi couvrir la rétention serveur par défaut.
            var entries: [LLMRequestEntry] = []
            var offset = 0
            while offset < 2000 {
                let page = try await client.llmRequests(bank, callType: ModelCallKind.generativeFilter, limit: 500, offset: offset)
                entries += page.items.filter(\.isGenerative)
                offset += page.items.count
                if page.items.count < 500 || offset >= page.total { break }
            }
            fetchedTraces = entries.count
            oldestTrace = entries.compactMap(\.startedAt).min()
            services?.estimator.setProfile(UsageProfile.from(entries), bank: bank)
            let since = period.days.map { now().addingTimeInterval(-$0 * 86_400) }
            var records: [UsageRecord]
            if let ledger = services?.ledger {
                await ledger.merge(entries, bank: bank, now: now())
                records = await ledger.records(bank: allBanks ? nil : bank, since: since)
            } else {
                records = entries.map { UsageRecord($0, bank: bank) }
                if let since { records = records.filter { $0.isAfter(since) } }
            }
            rows = UsageSummary.rows(records, prices: priceBook)
            totals = UsageSummary.totals(rows)
            daily = UsageSummary.daily(records)
            state = .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
