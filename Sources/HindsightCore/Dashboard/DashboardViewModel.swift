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
    /// Dernier test des modèles et son heure, gardés à part du tableau : un rechargement raté ne les efface pas,
    /// et un test qui échoue ne laisse jamais l'ancien résultat passer pour le nouveau.
    public private(set) var llmHealth: BankLlmHealthResponse?
    public private(set) var llmTestedAt: Date?
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
                try await client.listOperations(bank, status: "failed", limit: 5, excludeParents: true)
            }
            async let configReq = Self.capture { try await client.bankConfig(bank) }
            async let activeConsolidationsReq = ConsolidationStatus.activeOperations(client, bank)
            // Mêmes compteurs que Traitements (une ligne lue par statut), pas ceux mis en cache par `/stats`.
            async let pendingReq = Self.capture { try await client.listOperations(bank, status: "pending", limit: 1, excludeParents: true).total }
            async let processingReq = Self.capture { try await client.listOperations(bank, status: "processing", limit: 1, excludeParents: true).total }
            async let modeReq = try? client.isConsultationOnly()
            // Totaux vivants (une ligne lue par requête) : les mêmes que Faits et Documents, quel que soit le cache de `/stats`.
            async let factTotalReq = Self.capture { try await client.listMemories(bank, MemoryListQuery(limit: 1)).total }
            async let worldReq = Self.capture { try await client.listMemories(bank, MemoryListQuery(type: "world", limit: 1)).total }
            async let experienceReq = Self.capture { try await client.listMemories(bank, MemoryListQuery(type: "experience", limit: 1)).total }
            async let observationReq = Self.capture { try await client.listMemories(bank, MemoryListQuery(type: "observation", limit: 1)).total }

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
            let documents = take(await docsReq, "documents")
            snap.recentDocuments = documents?.items ?? []
            snap.liveDocumentTotal = documents?.total
            snap.liveFactTotal = try? (await factTotalReq).get()
            if let world = try? (await worldReq).get(), let experience = try? (await experienceReq).get(),
               let observation = try? (await observationReq).get() {
                snap.liveFactTypes = ["world": world, "experience": experience, "observation": observation]
            }
            snap.topTags = take(await tagsReq, "tags")?.items ?? []
            let failures = take(await failuresReq, "échecs")
            snap.recentFailures = failures?.operations ?? []
            snap.config = take(await configReq, "configuration")
            if let failed = failures?.total, let pending = try? (await pendingReq).get(),
               let processing = try? (await processingReq).get() {
                snap.operationCounts = ["pending": pending, "processing": processing, "failed": failed]
            }
            let active = await activeConsolidationsReq ?? ActiveConsolidations()
            snap.activeConsolidations = active.running + active.queued
            snap.consolidation = ConsolidationStatus(
                stats: snap.stats, config: snap.config, serverObservations: snap.version?.features.observations, operations: active)
            snap.llmHealth = llmHealth  // conservé d'un test précédent
            partialErrors = errors
            state = .loaded(snap)
            insights = DashboardInsights.compute(snap)
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }

    static let llmTestDisabledMessage = "Le test des LLM est désactivé sur ce serveur. La relance des opérations reste disponible. Pour activer ce diagnostic, ajoutez HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true au script de lancement, puis redémarrez le serveur."

    /// Pourquoi le test des modèles ne peut pas partir ; nil quand il le peut (ou que l'état du serveur est inconnu :
    /// le serveur répondra alors lui-même).
    public var llmTestRefusal: String? {
        guard let snap = state.value else { return nil }
        if snap.consultationOnly { return "Le serveur est en mode consultation : le test des modèles est désactivé." }
        if snap.version?.features.bankLlmHealth == false { return Self.llmTestDisabledMessage }
        return nil
    }

    /// Teste la connectivité LLM par rôle (retain / consolidation / reflect). Un petit appel LLM par rôle.
    /// Ne revient jamais sans rien dire : un test qui ne part pas ou échoue laisse sa raison dans `llmTestMessage`.
    public func testLLM() async {
        guard !isTestingLLM else { return }
        if let refusal = llmTestRefusal {
            llmTestMessage = refusal
            return
        }
        llmTestMessage = nil
        llmHealth = nil
        llmTestedAt = nil
        if var snap = state.value {
            snap.llmHealth = nil
            state = .loaded(snap)
            insights = DashboardInsights.compute(snap)
        }
        isTestingLLM = true
        defer { isTestingLLM = false }
        do {
            let health = try await client.llmHealth(bank)
            llmHealth = health
            llmTestedAt = Date()
            if var snap = state.value {
                snap.llmHealth = health
                state = .loaded(snap)
                insights = DashboardInsights.compute(snap)
            }
        } catch is CancellationError {
        } catch {
            if case HindsightError.http(404, let detail, _) = error,
               detail?.contains("Bank LLM health check is disabled") == true {
                llmTestMessage = Self.llmTestDisabledMessage
            } else {
                llmTestMessage = "Le test des LLM n'a pas abouti : \(error.userMessage)"
            }
        }
    }

    private static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
