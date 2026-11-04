import Foundation
import HindsightAPI
import Observation

/// Tout ce qui concerne la banque sélectionnée : un client, les ViewModels de chaque section.
@MainActor
@Observable
public final class BankSession {
    public let bank: String
    public let client: HindsightClient
    public let attachmentLoader: AttachmentLoader

    public let dashboard: DashboardViewModel
    public let documents: DocumentsViewModel
    public let operations: OperationsViewModel
    public let search: SearchViewModel
    public let timeline: TimelineViewModel
    public let graph: GraphViewModel
    public let audit: AuditViewModel
    public let usage: UsageViewModel
    public let reads: ReadsViewModel
    public let catalog: BankCatalog
    public let admin: BankAdminViewModel
    public let memoryDesign: MemoryDesignViewModel
    public let services: AppServices?

    public init(client: HindsightClient, bank: String, features: FeaturesInfo? = nil, services: AppServices? = nil, apiVersion: String? = nil) {
        self.services = services
        self.bank = bank
        self.client = client
        let loader = AttachmentLoader(client: client)
        self.attachmentLoader = loader
        self.dashboard = DashboardViewModel(client: client, bank: bank)
        self.documents = DocumentsViewModel(client: client, bank: bank, attachmentLoader: loader)
        self.operations = OperationsViewModel(client: client, bank: bank)
        self.search = SearchViewModel(client: client, bank: bank)
        self.timeline = TimelineViewModel(client: client, bank: bank)
        self.graph = GraphViewModel(client: client, bank: bank)
        self.audit = AuditViewModel(client: client, bank: bank, features: features)
        self.usage = UsageViewModel(client: client, bank: bank, services: services, features: features)
        self.reads = ReadsViewModel(client: client, bank: bank)
        self.reads.callers = services?.callers
        self.audit.callers = services?.callers
        self.catalog = BankCatalog(client: client, bank: bank)
        self.admin = BankAdminViewModel(client: client, bank: bank)
        self.memoryDesign = MemoryDesignViewModel(client: client, bank: bank, estimator: services?.estimator)
        let is110 = ServerCapabilities.is110(apiVersion)
        self.operations.serverIs110 = is110
        self.documents.serverIs110 = is110
        self.memoryDesign.serverIs110 = is110
        let is120 = ServerCapabilities.is120(apiVersion)
        self.memoryDesign.serverIs120 = is120
        self.search.serverIs120 = is120
        let estimate: @MainActor (EstimateKind) -> CostEstimate? = { [weak services] kind in
            services?.estimator.estimate(kind, bank: bank)
        }
        let dashboard = self.dashboard
        // Un tableau de bord jamais ouvert n'a rien à recharger : `loadIfNeeded` s'en chargera.
        let configChanged: @MainActor () async -> Void = { [weak dashboard] in
            guard let dashboard, dashboard.snapshot != nil else { return }
            await dashboard.reload()
        }
        self.audit.onConfigChanged = configChanged
        self.memoryDesign.onConfigChanged = configChanged
        self.admin.onConfigChanged = configChanged
        self.operations.estimate = estimate
        self.documents.estimate = estimate
        self.search.estimate = estimate
        self.admin.estimate = estimate
    }
}
