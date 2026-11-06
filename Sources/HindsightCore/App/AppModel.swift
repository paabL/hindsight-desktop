import Foundation
import HindsightAPI
import Observation

/// État global de l'app : connexion au serveur, banques, banque et section sélectionnées.
@MainActor
@Observable
public final class AppModel {
    public enum Connection: Sendable {
        case unknown
        case connecting
        case connected(VersionResponse)
        case failed(String)

        public var version: VersionResponse? {
            if case .connected(let v) = self { return v }
            return nil
        }
        public var isConnected: Bool { version != nil }
    }

    public static let defaultServerURL = "http://127.0.0.1:8888"

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private let transport: any HTTPTransport

    public private(set) var serverURL: URL
    public private(set) var client: HindsightClient
    public private(set) var connection: Connection = .unknown
    public private(set) var banks: [BankListItem] = []
    @ObservationIgnored private var connectionRevision = UUID()
    @ObservationIgnored private var banksRevision = UUID()
    public private(set) var session: BankSession?
    public var selectedSection: AppSection = .sources
    /// Dernière erreur à afficher dans une bannière globale.
    public var bannerError: String?
    /// Réglages serveur (script de lancement) : indépendants de la banque sélectionnée.
    public private(set) var serverSettings: ServerSettingsViewModel!
    public private(set) var memoryFolder: MemoryFolderViewModel!
    /// Documents de la banque sélectionnée et leurs sources (dossiers suivis, conversations) : la liste de
    /// l'écran « Documents ».
    public private(set) var coverage: FileCoverageViewModel!
    public private(set) var projectSync: ProjectSyncViewModel!
    /// Service launchd qui exécute le serveur Hindsight (démarrer / arrêter depuis l'app).
    public private(set) var service: HindsightServiceViewModel!
    /// Modèle de décision servi sur ce Mac (son installation et son service launchd).
    public private(set) var localDecision: LocalDecisionModel!
    /// Renommer / fusionner des banques.
    public private(set) var bankManagement: BankManagementViewModel!
    /// Mises à jour de l'app depuis son dépôt git.
    public private(set) var updates: AppUpdateViewModel!
    /// Consommation LLM de toutes les banques, plafonds de coût.
    public private(set) var consumption: ConsumptionMonitor!
    /// Pause des envois, gel et vidage de la file.
    public private(set) var pause: PauseController!
    public let automaticActions: Bool
    public let appInfo: AppInfo
    /// Estimations de coût et historique local de consommation, partagés entre banques.
    public let services: AppServices
    /// Avertissement sur l'URL du serveur (HTTP non chiffré sur le réseau local…).
    public private(set) var serverURLNotice: String?
    public var confirmation: ConfirmationRequest?

    public init(
        settings: SettingsStore, transport: any HTTPTransport = URLSessionTransport(),
        runner: CommandRunner = ShellCommandRunner(),
        processRunner: ProcessRunning = SystemProcessRunner(), servicePaths: ServicePaths = .standard,
        appInfo: AppInfo = AppInfo(version: "dev", build: "0"), ledger: UsageLedger? = UsageLedger(),
        automaticActions: Bool = true
    ) {
        self.automaticActions = automaticActions
        self.appInfo = appInfo
        var clientRef: (@MainActor () -> HindsightClient)?
        self.services = AppServices(estimator: CostEstimator(settings: settings, client: { clientRef!() }), ledger: ledger, callers: CallerDirectory(settings: settings))
        self.settings = settings
        self.memoryFolder = MemoryFolderViewModel(settings: settings, runner: processRunner, discoverAutomatically: automaticActions)
        self.transport = transport
        let storedAddress = settings.string(forKey: SettingsKey.serverURL)
        let acceptedURL = storedAddress.flatMap(HindsightClient.normalizedBaseURL(from:)).flatMap {
            ServerURLPolicy.evaluate($0).isAccepted ? $0 : nil
        }
        let url = acceptedURL ?? HindsightClient.normalizedBaseURL(from: Self.defaultServerURL)!
        self.serverURL = url
        self.client = HindsightClient(baseURL: url, transport: transport)
        self.serverSettings = ServerSettingsViewModel(
            settings: settings, runner: runner, client: { [unowned self] in self.client }, bank: { [unowned self] in self.selectedBankID })
        self.coverage = FileCoverageViewModel(settings: settings, client: { [unowned self] in self.client }, bank: { [unowned self] in self.selectedBankID })
        self.coverage.memoryPolicyURL = { [unowned self] in self.memoryFolder.repository?.appendingPathComponent("memory-policy.json") }
        self.coverage.estimate = { @MainActor @Sendable [unowned self] bank, kind in self.services.estimator.estimate(kind, bank: bank) }
        self.coverage.priceBook = { @MainActor [unowned self] in self.services.estimator.priceBook }
        self.coverage.openOperations = { @MainActor [unowned self] in self.selectedSection = .operations }
        self.coverage.openDocument = { @MainActor [unowned self] id in self.openDocument(id: id) }
        self.service = HindsightServiceViewModel(
            settings: settings, runner: processRunner, paths: servicePaths,
            client: { [unowned self] in self.client }, scriptPath: { [unowned self] in self.serverSettings.scriptPath })
        // Après un (re)démarrage, l'API peut annoncer d'autres réglages (worker, traces) : les relire.
        self.service.onServerStarted = { @MainActor @Sendable [unowned self] in
            self.serverSettings.acknowledgeStartedScript(self.service.startedScriptHash)
            if self.connection.isConnected { await self.refreshServerInfo() } else { await self.connect() }
        }
        self.serverSettings.service = self.service
        self.localDecision = LocalDecisionModel(runner: processRunner, paths: .standard(service: servicePaths))
        self.pause = PauseController(
            settings: settings, client: { [unowned self] in self.client }, banks: { [unowned self] in self.banks.map(\.bankId) },
            service: { [unowned self] in self.service }, server: { [unowned self] in self.serverURL.absoluteString },
            automaticSweeping: automaticActions)
        self.pause.workerEnabled = { @MainActor @Sendable [unowned self] in self.connection.version?.features.worker }
        self.pause.refreshServerInfo = { @MainActor @Sendable [unowned self] in await self.refreshServerInfo() }
        self.consumption = ConsumptionMonitor(
            settings: settings, client: { [unowned self] in self.client }, banks: { [unowned self] in self.banks.map(\.bankId) },
            ledger: ledger, prices: { [unowned self] in self.services.estimator.priceBook })
        self.consumption.traceEnabled = { @MainActor @Sendable [unowned self] in self.connection.version?.features.llmTrace }
        if automaticActions, let ledger { Task { await ledger.setSaveInterval(300) } }
        self.consumption.onExceeded = { @MainActor @Sendable [unowned self] gauges, action in
            let reason = gauges.map { "\($0.title) : \($0.usedText) sur \($0.limitText)" }.joined(separator: " ; ")
            await self.pause.apply(action, reason: "Plafond atteint — " + reason)
        }
        self.coverage.pauseGate = self.pause.gate
        self.projectSync = ProjectSyncViewModel(settings: settings, runner: processRunner, bank: { [unowned self] in self.selectedBankID })
        self.projectSync.pauseGate = self.pause.gate
        self.projectSync.estimate = { @MainActor [unowned self] bank, kind in self.services.estimator.estimate(kind, bank: bank) }
        self.projectSync.pendingRetains = { @MainActor [unowned self] bank in
            var n = 0
            for status in ["pending", "processing"] {
                guard let ops = try? await self.pause.listOperations(bank, status: status) else { return nil }
                n += ops.filter { $0.taskType.contains("retain") }.count
            }
            return n
        }
        self.coverage.historicalCost = { @MainActor @Sendable [unowned self] bank, ids in self.consumption.documentCost(ids, bank: bank) }
        clientRef = { [unowned self] in self.client }
        self.services.estimator.roleModel = { [unowned self] role in self.serverSettings.providerAndModel(forRole: role) }
        self.updates = AppUpdateViewModel(settings: settings, runner: processRunner, appInfo: appInfo)
        self.bankManagement = BankManagementViewModel(
            client: { [unowned self] in self.client }, banks: { [unowned self] in self.banks },
            refreshBanks: { [unowned self] in await self.refreshBanks() }, selectBank: { [unowned self] id in self.selectBank(id) })
        self.serverURLNotice = storedAddress != nil && acceptedURL == nil
            ? "L'adresse du serveur enregistrée a été refusée. Vérifiez son adresse dans les réglages ; le serveur local est utilisé en attendant."
            : ServerURLPolicy.evaluate(url).message
    }

    public var selectedBankID: String? { session?.bank }

    // MARK: Serveur

    /// Valide, enregistre et applique une nouvelle URL de serveur, puis se reconnecte.
    /// Retourne `false` (sans rien changer) si l'URL est invalide ou refusée par `ServerURLPolicy`
    /// (`serverURLNotice` dit alors pourquoi).
    @discardableResult
    public func applyServerURL(_ text: String) async -> Bool {
        guard let url = HindsightClient.normalizedBaseURL(from: text) else { return false }
        let verdict = ServerURLPolicy.evaluate(url)
        serverURLNotice = verdict.message
        guard verdict.isAccepted else { return false }
        connectionRevision = UUID()
        banksRevision = UUID()
        session?.operations.stopAutoRefresh()
        session?.documents.closeReader()
        session?.graph.stopAnimation()
        serverURL = url
        settings.set(url.absoluteString, forKey: SettingsKey.serverURL)
        client = HindsightClient(baseURL: url, transport: transport)
        session = nil
        banks = []
        coverage?.invalidateContext()
        // Autre serveur : les relevés de consommation repartent de zéro (les banques peuvent porter les mêmes noms).
        consumption.reset()
        await connect()
        return true
    }

    /// Vérifie le serveur (`/version`), charge les banques et sélectionne la dernière utilisée.
    public func connect() async {
        let revision = UUID()
        connectionRevision = revision
        let client = self.client
        connection = .connecting
        bannerError = nil
        do {
            let version = try await client.version()
            try Task.checkCancellation()
            guard connectionRevision == revision else { return }
            connection = .connected(version)
            await refreshBanks()
        } catch is CancellationError {
            if connectionRevision == revision { connection = .unknown }
        } catch {
            if connectionRevision == revision { connection = .failed(error.userMessage) }
        }
    }

    /// Relit `/version` sans recharger les banques (après un redémarrage du serveur).
    public func refreshServerInfo() async {
        let revision = connectionRevision, client = self.client
        if let v = try? await client.version(), revision == connectionRevision { connection = .connected(v) }
    }

    public func refreshBanks() async {
        let revision = UUID(), connection = connectionRevision, client = self.client
        banksRevision = revision
        do {
            let list = try await client.listBanks(limit: 200)
            try Task.checkCancellation()
            guard banksRevision == revision, connection == connectionRevision else { return }
            banks = list.banks
            // Rattrape ce que la pause n'a pas pu faire serveur injoignable (couper ou rétablir la consolidation,
            // annuler les rafraîchissements de pages arrivés entre-temps).
            if automaticActions {
                Task {
                    await pause.reconcile()
                    await pause.sweepRefreshes()
                }
            }
            let preferred = session?.bank ?? settings.string(forKey: SettingsKey.lastBank)
            if let preferred, banks.contains(where: { $0.bankId == preferred }) {
                if session?.bank != preferred { selectBank(preferred) }
            } else if let first = banks.first {
                selectBank(first.bankId)
            } else {
                session = nil
                coverage?.invalidateContext()
            }
        } catch is CancellationError {
        } catch {
            if banksRevision == revision, connection == connectionRevision {
                bannerError = "Impossible de lister les banques : \(error.userMessage)"
            }
        }
    }

    public func selectBank(_ id: String) {
        guard session?.bank != id else { return }
        session?.operations.stopAutoRefresh()
        session?.documents.closeReader()
        session?.graph.stopAnimation()
        let s = BankSession(
            client: client, bank: id, features: connection.version?.features, services: services, apiVersion: connection.version?.apiVersion)
        if automaticActions { Task { await services.estimator.refreshProfile(bank: id) } }
        s.admin.onBanksChanged = { [weak self] in await self?.refreshBanks() }
        // La suppression de la banque remplace cette session : son message passe par la gestion des banques.
        s.admin.onAppMessage = { [weak self] text in self?.bankManagement.message = text }
        s.operations.pauseGate = pause.gate
        s.documents.pauseGate = pause.gate
        // Supprimé, retraité ou retagué depuis le lecteur : la liste de l'écran Documents suit.
        s.documents.onDocumentChanged = { [weak self, weak s] documentID, reprocessed in
            guard let self, let s, self.session === s else { return }
            if reprocessed { self.coverage.markQueued(documentID) }
            if self.automaticActions { Task { await self.coverage.refreshMemory() } }
        }
        s.admin.pauseGate = pause.gate
        session = s
        coverage?.invalidateContext()
        settings.set(id, forKey: SettingsKey.lastBank)
    }

    /// Recharge la section affichée (⌘R).
    public func refreshCurrent() async {
        if selectedSection == .sources { memoryFolder.reload(); return }
        // La consommation couvre toutes les banques : elle s'actualise même sans banque choisie.
        if selectedSection == .consumption {
            if !connection.isConnected { await connect() }
            await consumption.poll()
            return
        }
        guard let session else {
            await connect()
            return
        }
        switch selectedSection {
        case .sources: memoryFolder.reload()
        case .dashboard: await session.dashboard.reload(refreshStats: true)
        case .documents:
            await coverage.reload()
            if let reader = session.documents.reader { await reader.load() }
        case .consumption: await consumption.poll()
        case .operations: await session.operations.reload()
        case .search: await session.search.run()
        case .timeline: await session.timeline.reload()
        case .graph: await session.graph.reload()
        case .audit:
            await session.audit.reload()
            await session.reads.reload()
        case .memory: await session.memoryDesign.reload()
        case .admin: await session.admin.reload()
        case .mentalModels:
            await session.admin.reload()
            if let id = session.admin.mentalModelDetail.value?.id { await session.admin.loadMentalModel(id) }
        case .server:
            await serverSettings.load()
            await service.refresh()
        }
    }

    // MARK: Création de banque

    /// Identifiant acceptable : lettres, chiffres, `-`, `_`, `.` ; absent du serveur.
    public func validateNewBankID(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return "Identifiant invalide (lettres, chiffres, « - », « _ », « . »)."
        }
        if banks.contains(where: { $0.bankId == id }) { return "La banque « \(id) » existe déjà." }
        return nil
    }

    public func requestCreateBank(id raw: String, name: String, mission: String) {
        let id = raw.trimmingCharacters(in: .whitespaces)
        if let problem = validateNewBankID(id) {
            bannerError = problem
            return
        }
        confirmation = ConfirmationRequest(
            title: "Créer la banque « \(id) » ?", message: "Banque vide, réglages par défaut du serveur" + (mission.isEmpty ? "." : ", avec la mission indiquée."),
            confirmTitle: "Créer", severity: .normal
        ) { [weak self] in await self?.createBank(id: id, name: name, mission: mission) }
    }

    /// Crée la banque (`PUT`), puis pose la mission par `PATCH …/config` (champ `mission` obsolète).
    @discardableResult
    public func createBank(id: String, name: String, mission: String) async -> Bool {
        do {
            // Revérifie côté serveur (liste, pas une lecture de la banque qui pourrait la créer) :
            // un PUT sur une banque existante la modifierait.
            let existing = try await client.listBanks(q: id, limit: 200)
            if existing.banks.contains(where: { $0.bankId == id }) {
                bannerError = "La banque « \(id) » existe déjà."
                return false
            }
            _ = try await client.createOrUpdateBank(id, request: CreateBankRequest(name: name.isEmpty ? nil : name))
            if !mission.isEmpty { _ = try? await client.updateBankConfig(id, updates: ["reflect_mission": .string(mission)]) }
            await refreshBanks()
            selectBank(id)
            return true
        } catch {
            bannerError = "Création impossible : \(error.userMessage)"
            return false
        }
    }

    // MARK: Navigation transverse

    /// Ouvre un document dans le lecteur, en mettant éventuellement un chunk en évidence.
    public func openDocument(id: String, chunkID: String? = nil) {
        guard let session else { return }
        selectedSection = .documents
        session.documents.open(documentID: id, chunkID: chunkID)
    }

    /// Exécute l'action proposée par une alerte du tableau de bord.
    /// Ouvre la recherche plein texte sur un tag (depuis le tableau de bord).
    public func openSearch(tag: String) {
        guard let session else { return }
        selectedSection = .search
        session.search.mode = .text
        session.search.filter = FactFilter()
        session.search.filter.tags = [tag]
        Task { await session.search.run() }
    }

    public func handle(_ action: InsightAction) {
        guard let session else { return }
        switch action {
        case .openOperations(let status):
            selectedSection = .operations
            session.operations.statusFilter = OperationsViewModel.StatusFilter(rawValue: status ?? "all") ?? .all
            Task { await session.operations.reload() }
        case .recoverConsolidation:
            selectedSection = .operations
            session.operations.requestRecoverConsolidation()
        case .runConsolidation:
            selectedSection = .operations
            session.operations.requestConsolidation()
        case .openDocuments:
            selectedSection = .documents
        case .testLLM:
            Task { await session.dashboard.testLLM() }
        case .openAudit:
            selectedSection = .audit
        }
    }
}
