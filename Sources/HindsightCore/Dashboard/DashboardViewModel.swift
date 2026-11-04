import Foundation
import HindsightAPI
import Observation

/// Tableau de bord d'une banque : chiffres utiles, évolution, alertes actionnables.
@MainActor
@Observable
public final class DashboardViewModel {
    public let bank: String
    @ObservationIgnored private let client: HindsightClient

    public private(set) var state: LoadState<DashboardSnapshot> = .idle
    public private(set) var insights: [Insight] = []
    /// Erreurs des sources secondaires (le tableau reste affiché sans elles).
    public private(set) var partialErrors: [String] = []
    public private(set) var isTestingLLM = false
    public private(set) var llmTestMessage: String?
    public var timeseriesPeriod = "30d"

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    public var snapshot: DashboardSnapshot? { state.value }

    /// Charge au premier affichage, puis recharge si les données ont plus de 2 minutes (retour sur l'écran).
    public func loadIfNeeded(now: Date = Date()) async {
        guard !state.isLoading else { return }
        if let snap = state.value, now.timeIntervalSince(snap.fetchedAt) < 120 { return }
        await reload()
    }

    /// `refreshStats` force le recalcul serveur des statistiques (plus lent sur ~500 000 liens).
    public func reload(refreshStats: Bool = false) async {
        if state.value == nil { state = .loading }
        let client = self.client, bank = self.bank, period = timeseriesPeriod
        do {
            async let statsReq = client.bankStats(bank, refresh: refreshStats)
            async let versionReq = Self.capture { try await client.version() }
            async let entitiesReq = Self.capture { try await client.listEntities(bank, limit: 1) }
            async let seriesReq = Self.capture { try await client.memoriesTimeseries(bank, period: period) }
            async let docsReq = Self.capture { try await client.listDocuments(bank, limit: 5) }
            async let tagsReq = Self.capture { try await client.listTags(bank, limit: 15) }
            async let failuresReq = Self.capture {
                try await client.listOperations(bank, status: "failed", limit: 5)
            }
            async let configReq = Self.capture { try await client.bankConfig(bank) }
            async let consolidatingReq = Self.capture {
                try await client.listOperations(bank, status: "processing", type: "consolidation", limit: 1).total
            }
            async let queuedConsolidationReq = Self.capture {
                try await client.listOperations(bank, status: "pending", type: "consolidation", limit: 1).total
            }
            async let modeReq = try? client.isConsultationOnly()

            var snap = DashboardSnapshot(stats: try await statsReq)
            snap.consultationOnly = await modeReq ?? false
            var errors: [String] = []
            func take<T>(_ r: Result<T, Error>, _ label: String) -> T? {
                switch r {
                case .success(let v): return v
                case .failure(let e):
                    if !(e is CancellationError) { errors.append("\(label) : \(e.userMessage)") }
                    return nil
                }
            }
            snap.version = take(await versionReq, "version")
            snap.entityTotal = take(await entitiesReq, "entités")?.total
            snap.timeseries = take(await seriesReq, "série temporelle")
            snap.recentDocuments = take(await docsReq, "documents")?.items ?? []
            snap.topTags = take(await tagsReq, "tags")?.items ?? []
            snap.recentFailures = take(await failuresReq, "échecs")?.operations ?? []
            snap.config = take(await configReq, "configuration")
            let consolidating = (try? (await consolidatingReq).get()) ?? 0
            let queuedConsolidation = (try? (await queuedConsolidationReq).get()) ?? 0
            snap.activeConsolidations = consolidating + queuedConsolidation
            snap.llmHealth = state.value?.llmHealth  // conservé d'un test précédent
            partialErrors = errors
            state = .loaded(snap)
            insights = DashboardInsights.compute(snap)
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }

    /// Teste la connectivité LLM par rôle (retain / consolidation / reflect). Un petit appel LLM par rôle.
    public func testLLM() async {
        guard var snap = state.value, !isTestingLLM else { return }
        guard !snap.consultationOnly else { return }
        llmTestMessage = nil
        snap.llmHealth = nil
        state = .loaded(snap)
        insights = DashboardInsights.compute(snap)
        isTestingLLM = true
        defer { isTestingLLM = false }
        do {
            snap.llmHealth = try await client.llmHealth(bank)
            state = .loaded(snap)
            insights = DashboardInsights.compute(snap)
        } catch is CancellationError {
        } catch {
            if case HindsightError.http(404, let detail, _) = error,
               detail?.contains("Bank LLM health check is disabled") == true {
                llmTestMessage = "Le test des LLM est désactivé sur ce serveur. La relance des opérations reste disponible. Pour activer ce diagnostic, ajoutez HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true au script de lancement, puis redémarrez le serveur."
            } else {
                llmTestMessage = "Le test des LLM n'a pas abouti : \(error.userMessage)"
            }
        }
    }

    private static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
