import Foundation
import HindsightAPI
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Observation

/// Démarrage, arrêt et suivi du serveur Hindsight depuis l'app, via un agent launchd de l'utilisateur.
///
/// Sécurité :
/// - le script de lancement n'est exécuté que s'il appartient à l'utilisateur et que personne d'autre ne
///   peut le modifier (`FileSafety`) ;
/// - son empreinte SHA-256 est mémorisée quand vous l'approuvez (installation, ou enregistrement depuis
///   l'écran « Modèles & serveur ») : s'il a changé entre-temps, le démarrage redemande confirmation ;
/// - `launchctl` est appelé avec des arguments en tableau, sans shell ; le plist est produit par
///   `PropertyListSerialization` (aucune concaténation de texte) ;
/// - le journal est créé en 0600 dans un dossier 0700, et les secrets y sont masqués à l'affichage.
@MainActor
@Observable
public final class HindsightServiceViewModel {
    public enum Status: Sendable, Equatable {
        case unknown
        case notInstalled
        case stopped(lastExitCode: Int?)
        case starting
        case running(pid: Int?)
        /// L'API répond alors que le service de l'app ne tourne pas (serveur lancé autrement).
        case runningExternally
        case stopping

        public var isRunning: Bool {
            switch self {
            case .running, .runningExternally: return true
            default: return false
            }
        }
    }

    public nonisolated static let launchctl = "/bin/launchctl"
    public nonisolated static let maxLogBytes = 10 * 1024 * 1024

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let paths: ServicePaths
    @ObservationIgnored private let uid: UInt32
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let scriptPathProvider: @MainActor () -> String
    @ObservationIgnored private let startTimeout: TimeInterval
    @ObservationIgnored private let stopTimeout: TimeInterval
    @ObservationIgnored private let pollInterval: Duration

    public private(set) var status: Status = .unknown
    public private(set) var installed: LaunchAgentSpec?
    public private(set) var job: LaunchJobStatus = .notLoaded
    public private(set) var apiReachable = false
    public private(set) var issues: [FileSafety.Issue] = []
    public private(set) var scriptWarning: String?
    /// Empreinte actuelle du script, et vrai si elle diffère de la dernière approuvée.
    public private(set) var scriptHash: String?
    public private(set) var scriptChangedSinceApproval = false
    public private(set) var logTail = ""
    public private(set) var isBusy = false
    public var confirmation: ConfirmationRequest?
    public var message: String?
    public private(set) var failure: String?
    public private(set) var startedScriptHash: String?
    @ObservationIgnored private var attemptScriptHash: String?
    @ObservationIgnored private var attemptScriptURL: URL?
    @ObservationIgnored private var attemptClient: HindsightClient?
    @ObservationIgnored private var logOffsets: [URL: UInt64] = [:]
    @ObservationIgnored private var refreshRevision = UUID()

    public var phase: String {
        if failure != nil && !isBusy { return "failed" }
        switch status {
        case .starting: return "starting"
        case .stopping: return "stopping"
        default: return apiReachable ? "ready" : "stopped"
        }
    }
    /// Appelé quand le serveur vient de (re)démarrer et répond : l'app se reconnecte.
    @ObservationIgnored public var onServerStarted: (@MainActor @Sendable () async -> Void)?

    public init(
        settings: SettingsStore, runner: ProcessRunning = SystemProcessRunner(), paths: ServicePaths = .standard,
        uid: UInt32 = FileSafety.currentUID, client: @escaping @MainActor () -> HindsightClient,
        scriptPath: @escaping @MainActor () -> String,
        startTimeout: TimeInterval = 120, stopTimeout: TimeInterval = 40, pollInterval: Duration = .seconds(1)
    ) {
        self.settings = settings
        self.runner = runner
        self.paths = paths
        self.uid = uid
        self.clientProvider = client
        self.scriptPathProvider = scriptPath
        self.startTimeout = startTimeout
        self.stopTimeout = stopTimeout
        self.pollInterval = pollInterval
    }

    // MARK: Lecture de l'état

    public var scriptURL: URL { LaunchScriptStore.expand(scriptPathProvider()) }
    public var logURL: URL { paths.log }
    public var plistURL: URL { paths.plist }
    var domain: String { "gui/\(uid)" }
    var target: String { "\(domain)/\(LaunchAgentSpec.label)" }

    public var isInstalled: Bool { installed != nil }
    public var blockingIssues: [FileSafety.Issue] { issues.filter(\.isBlocking) }
    /// Le service installé exécute un autre script que celui de l'écran « Modèles & serveur ».
    public var pointsToOtherScript: Bool {
        installed.map { URL(fileURLWithPath: $0.scriptPath).resolvingSymlinksInPath() != scriptURL.resolvingSymlinksInPath() } ?? false
    }
    public var canStart: Bool {
        isInstalled && !isBusy && Self.isLocalEndpoint(clientProvider().baseURL) && !job.running && !job.pending && !apiReachable
    }
    public var canStop: Bool { isInstalled && !isBusy && (job.running || job.pending) }

    public func refresh() async {
        guard !isBusy else { return }
        let revision = UUID()
        refreshRevision = revision
        let client = clientProvider()
        let script = scriptURL
        let spec = (try? Data(contentsOf: paths.plist)).flatMap(LaunchAgentSpec.parse)
        let currentJob = spec == nil ? .notLoaded : await jobStatus()
        let reachable = await probeAPI(client)
        guard refreshRevision == revision, !isBusy, clientProvider().baseURL == client.baseURL, scriptURL == script else { return }
        installed = spec
        job = currentJob
        apiReachable = reachable
        inspectScript()
        status = computeStatus()
        loadLog()
    }

    private func beginOperation(_ next: Status) {
        refreshRevision = UUID()
        isBusy = true
        status = next
    }

    private func endOperation() {
        refreshRevision = UUID()
        isBusy = false
        status = computeStatus()
    }

    private func refreshOperationState() async {
        job = await jobStatus()
        apiReachable = await probeAPI()
        loadLog()
    }

    func computeStatus() -> Status {
        guard isInstalled else { return apiReachable ? .runningExternally : .notInstalled }
        if job.running { return apiReachable ? .running(pid: job.pid) : .starting }
        if job.pending { return .starting }
        return apiReachable ? .runningExternally : .stopped(lastExitCode: job.lastExitCode)
    }

    func jobStatus() async -> LaunchJobStatus {
        (try? await checkedJobStatus()) ?? .notLoaded
    }

    private func checkedJobStatus() async throws -> LaunchJobStatus {
        let result = try await runner.run(ProcessInvocation(Self.launchctl, ["print", target], timeout: 10))
        guard result.succeeded else {
            if !result.timedOut, result.status == 113 { return .notLoaded }
            throw ServiceError.launchctl("print", result.combined)
        }
        return LaunchJobStatus.parse(printOutput: result.stdout)
    }

    func probeAPI(_ client: HindsightClient? = nil) async -> Bool {
        let client = client ?? clientProvider()
        guard Self.isLocalEndpoint(client.baseURL) else { return false }
        let response: VersionResponse? = try? await client.send(APIRequest("GET", ["version"], timeout: 3))
        return response != nil
    }

    private static func isLocalEndpoint(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
    }

    private func requireLocalEndpoint() -> Bool {
        guard Self.isLocalEndpoint(clientProvider().baseURL) else {
            message = "Le service de ce Mac doit être vérifié avec une adresse locale. Sélectionnez le serveur local avant de le démarrer ou de modifier sa file."
            return false
        }
        return true
    }

    public func inspectScript() {
        let url = scriptURL
        issues = FileSafety.inspect(url, uid: uid)
        if let data = try? Data(contentsOf: url) {
            let hash = SHA256.hex(data)
            scriptHash = hash
            let approved = settings.string(forKey: SettingsKey.serviceScriptHash)
            scriptChangedSinceApproval = approved != hash
            scriptWarning = LaunchScriptShape.backgroundingWarning(String(decoding: data, as: UTF8.self))
        } else {
            scriptHash = nil
            scriptChangedSinceApproval = false
            scriptWarning = nil
        }
    }

    private var logURLs: [URL] {
        let text = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
        let redirected = ServiceDiagnostics.redirectedLog(in: text)
        return [paths.log] + (redirected.map { $0 != paths.log ? [$0] : [] } ?? [])
    }

    public func loadLog() {
        logTail = logURLs.compactMap { url in
            let text = ServiceDiagnostics.tail(url)
            return text.isEmpty ? nil : "[\(url.path)]\n" + text
        }.joined(separator: "\n")
    }

    private func beginAttempt() {
        attemptScriptHash = (try? Data(contentsOf: scriptURL)).map(SHA256.hex)
        attemptScriptURL = scriptURL
        attemptClient = clientProvider()
        failure = nil
        message = nil
        logOffsets = Dictionary(uniqueKeysWithValues: logURLs.map { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            return (url, size)
        })
    }

    private func fail(_ text: String) {
        loadLog()
        let current = logURLs.map { ServiceDiagnostics.tail($0, after: logOffsets[$0] ?? 0) }.joined(separator: "\n")
        failure = SecretMasker.mask(text) + (ServiceDiagnostics.error(in: current).map { "\n" + $0 } ?? "")
        message = failure
    }

    private func requireAttemptScript() throws {
        guard scriptURL == attemptScriptURL, clientProvider().baseURL == attemptClient?.baseURL,
              let data = try? Data(contentsOf: scriptURL), SHA256.hex(data) == attemptScriptHash,
              !FileSafety.inspect(scriptURL, uid: uid).contains(where: \.isBlocking) else {
            throw ServiceError.io("Le script ou l'adresse du serveur a changé pendant l'opération. Vérifiez les réglages et réessayez.")
        }
    }

    /// À appeler quand l'utilisateur a validé le contenu actuel du script (ex. enregistrement confirmé du diff).
    public func approveCurrentScript() {
        guard let data = try? Data(contentsOf: scriptURL) else { return }
        approveScript(at: scriptURL, hash: SHA256.hex(data))
    }

    /// Approval belongs to the exact file and bytes that were reviewed, including when settings edit another script.
    @discardableResult
    public func approveScript(at url: URL, hash: String) -> Bool {
        guard scriptURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath(),
              let data = try? Data(contentsOf: scriptURL), SHA256.hex(data) == hash,
              !FileSafety.inspect(scriptURL, uid: uid).contains(where: \.isBlocking) else { return false }
        settings.set(hash, forKey: SettingsKey.serviceScriptHash)
        inspectScript()
        return true
    }

    private func validateConfirmation(script url: URL, hash: String?) -> Bool {
        inspectScript()
        guard scriptURL == url, scriptHash == hash, hash != nil, blockingIssues.isEmpty else {
            message = "Le script a changé depuis la confirmation : vérifiez-le à nouveau."
            return false
        }
        return true
    }

    // MARK: Installation (confirmée)

    public func requestInstall(startAtLogin: Bool) {
        guard !isBusy, requireLocalEndpoint() else { return }
        inspectScript()
        if let problem = blockingIssues.first {
            message = "Impossible d'utiliser ce script : \(problem)"
            return
        }
        let url = scriptURL
        let hash = scriptHash
        var lines = [
            "Script exécuté : \(url.path)",
            "Empreinte SHA-256 : \(scriptHash.map { String($0.prefix(16)) + "…" } ?? "?")",
            "Agent launchd : \(paths.plist.path)",
            "Journal : \(paths.log.path)",
            "Démarrage à l'ouverture de session : \(startAtLogin ? "oui" : "non")",
        ]
        if issues.contains(where: { if case .notExecutable = $0 { return true } else { return false } }) {
            lines.append("Le script sera rendu exécutable pour vous (chmod u+x).")
        }
        if let w = scriptWarning { lines.append("Attention : \(w)") }
        if job.running { lines.append("Le service en cours sera redémarré avec cette configuration.") }
        lines.append("\nCe script s'exécutera avec vos droits. N'approuvez qu'un fichier dont vous connaissez le contenu.")
        confirmation = ConfirmationRequest(
            title: isInstalled ? "Réinstaller le service Hindsight ?" : "Installer le service Hindsight ?",
            message: lines.joined(separator: "\n"), confirmTitle: "Installer et démarrer", severity: .normal
        ) { [weak self] in
            guard let self, !self.isBusy, self.validateConfirmation(script: url, hash: hash) else { return }
            await self.install(startAtLogin: startAtLogin)
        }
    }

    func install(startAtLogin: Bool) async {
        guard !isBusy, requireLocalEndpoint() else { return }
        beginOperation(.starting)
        beginAttempt()
        defer { endOperation() }
        do {
            try ensureExecutable()
            try prepareLog()
            // Une file gelée le reste après réinstallation : seul « Reprendre la file » la dégèle.
            let spec = LaunchAgentSpec(
                scriptPath: scriptURL.path, logPath: paths.log.path, runAtLoad: startAtLogin, path: SystemProcessRunner.standardPath(),
                workerPaused: installed?.workerPaused ?? false)
            try await unloadAgent()
            try await waitUntilDown()
            guard let approvedURL = attemptScriptURL, let approvedHash = attemptScriptHash,
                  approveScript(at: approvedURL, hash: approvedHash) else {
                throw ServiceError.io("Le script a changé pendant l'installation : vérifiez-le à nouveau.")
            }
            try writePlist(spec)
            installed = spec
            let r = try await runner.run(ProcessInvocation(Self.launchctl, ["bootstrap", domain, paths.plist.path], timeout: 20))
            guard r.succeeded else { throw ServiceError.launchctl("bootstrap", r.combined) }
        } catch {
            fail("Installation impossible : \(error)")
            await refreshOperationState()
            return
        }
        await startWhileBusy(bootstrapped: true)
    }

    /// Démarrage automatique à l'ouverture de session (pris en compte à la prochaine session).
    public func setStartAtLogin(_ on: Bool) {
        guard !isBusy, var spec = installed, spec.runAtLoad != on else { return }
        spec.runAtLoad = on
        do {
            try writePlist(spec)
            installed = spec
        } catch {
            message = "Échec : \(error)"
        }
    }

    public func requestUninstall() {
        guard !isBusy else { return }
        confirmation = ConfirmationRequest(
            title: "Désinstaller le service Hindsight ?",
            message: "Le serveur sera arrêté s'il tourne, et l'agent \(paths.plist.lastPathComponent) supprimé. Le script de lancement, les données du serveur et le journal sont conservés.",
            confirmTitle: "Désinstaller"
        ) { [weak self] in
            await self?.uninstall()
        }
    }

    func uninstall() async {
        guard !isBusy else { return }
        beginOperation(.stopping)
        beginAttempt()
        defer { endOperation() }
        do {
            try await unloadAgent()
            try FileManager.default.removeItem(at: paths.plist)
            installed = nil
            job = .notLoaded
            apiReachable = await probeAPI()
            message = "Service désinstallé."
        } catch {
            fail("Désinstallation impossible : \(error)")
            await refreshOperationState()
        }
    }

    // MARK: Démarrer / arrêter / redémarrer

    public func requestStart() {
        guard !isBusy, requireLocalEndpoint() else { return }
        guard installed != nil else { message = "Installez d'abord le service Hindsight."; return }
        inspectScript()
        if let problem = blockingIssues.first {
            message = "Démarrage refusé : \(problem)"
            return
        }
        guard scriptChangedSinceApproval else {
            beginOperation(.starting)
            Task {
                defer { endOperation() }
                await startWhileBusy()
            }
            return
        }
        let url = scriptURL, hash = scriptHash
        confirmation = ConfirmationRequest(
            title: "Le script de lancement a changé",
            message:
                "\(scriptURL.path) a été modifié hors de l'app depuis votre dernière approbation (empreinte \(scriptHash.map { String($0.prefix(12)) } ?? "?")…).\n\nVérifiez son contenu avant de l'exécuter.",
            confirmTitle: "Approuver et démarrer", severity: .normal
        ) { [weak self] in
            guard let self, !self.isBusy, self.validateConfirmation(script: url, hash: hash) else { return }
            self.approveCurrentScript()
            await self.start()
        }
    }

    func start() async {
        guard !isBusy, installed != nil else { return }
        beginOperation(.starting)
        defer { endOperation() }
        await startWhileBusy()
    }

    private func startWhileBusy(bootstrapped: Bool = false) async {
        guard installed != nil, requireLocalEndpoint() else { return }
        if !bootstrapped { beginAttempt() }
        inspectScript()
        guard blockingIssues.isEmpty, !scriptChangedSinceApproval, !pointsToOtherScript else {
            fail("Vérifiez et approuvez le script du service avant de démarrer.")
            return
        }
        if !bootstrapped, await probeAPI() {
            message = "Un serveur répond déjà à cette adresse : arrêtez-le avant de démarrer le service."
            await refreshOperationState()
            return
        }
        do {
            try prepareLog()
            _ = try await loadAgentForStart()
            try requireAttemptScript()
            let r = try await runner.run(ProcessInvocation(Self.launchctl, ["kickstart", target], timeout: 20))
            guard r.succeeded else { throw ServiceError.launchctl("kickstart", r.combined) }
        } catch {
            fail("Démarrage impossible : \(error)")
            await refreshOperationState()
            return
        }
        await waitUntilUp(action: "démarré")
    }

    public func requestStop() {
        guard !isBusy else { return }
        confirmation = ConfirmationRequest(
            title: "Arrêter le serveur Hindsight ?",
            message: "Les requêtes en cours seront interrompues ; les opérations en file reprendront au prochain démarrage. L'app restera ouverte mais déconnectée.",
            confirmTitle: "Arrêter"
        ) { [weak self] in
            await self?.stop()
        }
    }

    func stop() async {
        guard !isBusy else { return }
        beginOperation(.stopping)
        beginAttempt()
        defer { endOperation() }
        do {
            // Unloading also cancels a pending spawn; SIGTERM alone can leave a scheduled launch alive.
            try await unloadAgent()
            apiReachable = await probeAPI()
            message = apiReachable
                ? "Le service est arrêté, mais l'API répond encore : un autre serveur tourne à cette adresse (lancé hors de l'app)."
                : "Serveur arrêté."
        } catch {
            fail("Arrêt impossible : \(error)")
            await refreshOperationState()
        }
        loadLog()
    }

    public func requestRestart() {
        guard !isBusy, requireLocalEndpoint() else { return }
        inspectScript()
        if let problem = blockingIssues.first {
            message = "Redémarrage refusé : \(problem)"
            return
        }
        let changed = scriptChangedSinceApproval
        let url = scriptURL, hash = scriptHash
        confirmation = ConfirmationRequest(
            title: "Redémarrer le serveur Hindsight ?",
            message: (changed ? "Le script a été modifié hors de l'app depuis votre dernière approbation : vérifiez-le.\n\n" : "")
                + "Les requêtes en cours seront interrompues ; les opérations en file reprendront au redémarrage.",
            confirmTitle: changed ? "Approuver et redémarrer" : "Redémarrer"
        ) { [weak self] in
            guard let self, !self.isBusy, self.validateConfirmation(script: url, hash: hash) else { return }
            if changed { self.approveCurrentScript() }
            _ = await self.restart()
        }
    }

    /// Redémarre (ou démarre) le job et attend l'API. Retourne vrai si l'API répond.
    @discardableResult
    public func restart() async -> Bool {
        guard installed != nil, !isBusy, requireLocalEndpoint() else { return false }
        inspectScript()
        guard blockingIssues.isEmpty, !scriptChangedSinceApproval, !pointsToOtherScript else {
            message = "Vérifiez et approuvez le script du service avant de redémarrer."
            return false
        }
        beginOperation(.starting)
        beginAttempt()
        defer { endOperation() }
        var previousPID: Int?
        do {
            try prepareLog()
            let bootstrapped = try await loadAgentForStart()
            if !bootstrapped { previousPID = try await checkedJobStatus().pid }
            try requireAttemptScript()
            let arguments = bootstrapped ? ["kickstart", target] : ["kickstart", "-k", target]
            let r = try await runner.run(ProcessInvocation(Self.launchctl, arguments, timeout: stopTimeout + 10))
            guard r.succeeded else { throw ServiceError.launchctl("kickstart -k", r.combined) }
        } catch {
            fail("Redémarrage impossible : \(error)")
            await refreshOperationState()
            return false
        }
        // Laisse à l'ancien processus le temps de libérer le port avant de sonder.
        try? await Task.sleep(for: pollInterval)
        return await waitUntilUp(action: "redémarré", replacingPID: previousPID)
    }

    private func loadAgentForStart() async throws -> Bool {
        if let spec = installed,
           let data = try? Data(contentsOf: paths.plist),
           let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           (raw["EnvironmentVariables"] as? [String: String])?["HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH"] == nil {
            try writePlist(spec)
            if try await checkedJobStatus().loaded {
                try await unloadAgent()
                try await waitUntilDown()
            }
        }
        if try await !checkedJobStatus().loaded {
            try requireAttemptScript()
            let result = try await runner.run(ProcessInvocation(Self.launchctl, ["bootstrap", domain, paths.plist.path], timeout: 20))
            guard result.succeeded else { throw ServiceError.launchctl("bootstrap", result.combined) }
            return true
        }
        return false
    }

    // MARK: Geler la file

    /// Le service démarre le serveur sans worker (file gelée).
    public var isWorkerPaused: Bool { installed?.workerPaused ?? false }

    /// Le script de lancement fixe lui-même `HINDSIGHT_API_WORKER_ENABLED` : la valeur du service serait écrasée.
    public var scriptOverridesWorker: Bool {
        guard let text = try? String(contentsOf: scriptURL, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return !l.hasPrefix("#") && l.contains(LaunchAgentSpec.workerEnabledVariable + "=")
        }
    }

    /// Gèle ou reprend la file : réécrit l'agent avec (ou sans) `HINDSIGHT_API_WORKER_ENABLED=false`, puis le
    /// recharge (launchd ne relit l'environnement qu'au chargement) et attend l'API. L'appelant a obtenu la
    /// confirmation de l'utilisateur, ou applique un plafond qu'il a confirmé.
    @discardableResult
    public func setWorkerPaused(_ paused: Bool) async -> Bool {
        guard !isBusy, requireLocalEndpoint() else { return false }
        guard var spec = installed else {
            message = "Le serveur n'est pas lancé par le service de l'app : sa file ne peut pas être gelée d'ici."
            return false
        }
        guard spec.workerPaused != paused else { return true }
        beginOperation(.stopping)
        beginAttempt()
        defer { endOperation() }
        spec.workerPaused = paused
        job = await jobStatus()
        if !job.running && !job.pending {
            // Serveur arrêté : ne pas le démarrer. L'agent réécrit et déchargé, le prochain démarrage le recharge
            // (launchd ne relit l'environnement qu'au chargement).
            do {
                try await unloadAgent()
                try writePlist(spec)
                installed = spec
                job = await jobStatus()
                status = computeStatus()
                return true
            } catch {
                fail((paused ? "Gel de la file impossible : " : "Reprise de la file impossible : ") + "\(error)")
                await refreshOperationState()
                return false
            }
        }
        guard !pointsToOtherScript else {
            fail("Le service utilise un autre script. Réinstallez-le avec le script sélectionné avant de modifier sa file.")
            return false
        }
        inspectScript()
        if let problem = blockingIssues.first {
            message = "Redémarrage refusé : \(problem)"
            return false
        }
        if scriptChangedSinceApproval {
            message = "Le script de lancement a changé depuis votre dernière approbation : redémarrez d'abord le serveur depuis « Serveur & modèles »."
            return false
        }
        status = .stopping
        do {
            try await unloadAgent()
            try await waitUntilDown()
            try writePlist(spec)
            installed = spec
            try prepareLog()
            status = .starting
            try requireAttemptScript()
            let r = try await runner.run(ProcessInvocation(Self.launchctl, ["bootstrap", domain, paths.plist.path], timeout: 20))
            guard r.succeeded else { throw ServiceError.launchctl("bootstrap", r.combined) }
            let k = try await runner.run(ProcessInvocation(Self.launchctl, ["kickstart", target], timeout: 20))
            guard k.succeeded else { throw ServiceError.launchctl("kickstart", k.combined) }
        } catch {
            fail((paused ? "Gel de la file impossible : " : "Reprise de la file impossible : ") + "\(error)")
            await refreshOperationState()
            return false
        }
        try? await Task.sleep(for: pollInterval)
        return await waitUntilUp(action: paused ? "redémarré, file gelée" : "redémarré, file reprise")
    }

    private func unloadAgent() async throws {
        job = try await checkedJobStatus()
        guard job.loaded else { return }
        let result = try await runner.run(ProcessInvocation(Self.launchctl, ["bootout", target], timeout: stopTimeout))
        guard result.succeeded else { throw ServiceError.launchctl("bootout", result.combined) }
        let deadline = Date().addingTimeInterval(stopTimeout)
        repeat {
            try Task.checkCancellation()
            job = try await checkedJobStatus()
            if !job.loaded { return }
            try await Task.sleep(for: pollInterval)
        } while Date() < deadline
        throw ServiceError.io("Le service ne s'est pas arrêté dans les \(Int(stopTimeout)) s.")
    }

    func waitUntilDown() async throws {
        let deadline = Date().addingTimeInterval(stopTimeout)
        while await probeAPI(attemptClient) {
            guard Date() < deadline else { throw ServiceError.io("L'ancienne API répond encore après l'arrêt du service.") }
            try await Task.sleep(for: pollInterval)
        }
    }

    @discardableResult
    func waitUntilUp(action: String, replacingPID: Int? = nil) async -> Bool {
        let deadline = Date().addingTimeInterval(startTimeout)
        var sawRunning = false
        let started = Date()
        while Date() < deadline, !Task.isCancelled {
            let reachable = await probeAPI(attemptClient)
            job = await jobStatus()
            guard scriptURL == attemptScriptURL, clientProvider().baseURL == attemptClient?.baseURL else {
                apiReachable = false
                fail("Le script ou l'adresse du serveur a changé pendant le démarrage. Actualisez son état.")
                return false
            }
            apiReachable = reachable
            // A different server can answer at this address while our job has already exited.
            if reachable && job.running && (replacingPID == nil || (job.pid != nil && job.pid != replacingPID)) {
                status = computeStatus()
                message = "Serveur \(action) : l'API répond."
                failure = nil
                loadLog()
                startedScriptHash = attemptScriptHash
                await onServerStarted?()
                return true
            }
            sawRunning = sawRunning || job.running
            if !job.running && !job.pending && job.lastExitCode != nil && (sawRunning || Date().timeIntervalSince(started) >= min(2, startTimeout / 2)) {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        loadLog()
        job = await jobStatus()
        apiReachable = await probeAPI(attemptClient)
        status = computeStatus()
        let exit = job.lastExitCode.map { " (code de sortie \($0))" } ?? ""
        fail(apiReachable
            ? "L'API répond, mais le nouveau processus du service n'est pas prêt\(exit). Consultez le journal ci-dessous."
            : "Le service a été lancé mais l'API ne répond pas\(exit). Consultez le journal ci-dessous.")
        return false
    }

    // MARK: Fichiers

    enum ServiceError: Error, CustomStringConvertible {
        case launchctl(String, String)
        case io(String)

        var description: String {
            switch self {
            case .launchctl(let verb, let out):
                let detail = out.trimmingCharacters(in: .whitespacesAndNewlines)
                return "launchctl \(verb) a échoué" + (detail.isEmpty ? "." : " : \(detail)")
            case .io(let m): return m
            }
        }
    }

    func ensureExecutable() throws {
        let path = scriptURL.resolvingSymlinksInPath().path
        let fm = FileManager.default
        guard let perms = (try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber else {
            throw ServiceError.io("Script introuvable : \(path)")
        }
        let mode = perms.uint16Value
        if mode & 0o100 == 0 { try fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o100)], ofItemAtPath: path) }
    }

    /// Dossier 0700, journal 0600 ; au-delà de 10 Mio, l'ancien journal devient `.1`.
    func prepareLog() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.logs.path)
        let log = paths.log.path
        if let size = (try? fm.attributesOfItem(atPath: log))?[.size] as? NSNumber, size.intValue > Self.maxLogBytes {
            let old = log + ".1"
            try? fm.removeItem(atPath: old)
            try? fm.moveItem(atPath: log, toPath: old)
        }
        if !fm.fileExists(atPath: log) {
            guard fm.createFile(atPath: log, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ServiceError.io("Impossible de créer le journal \(log)")
            }
        }
    }

    /// Écriture atomique, 0644 (launchd refuse un plist modifiable par d'autres).
    func writePlist(_ spec: LaunchAgentSpec) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        let tmp = paths.launchAgents.appendingPathComponent(".\(LaunchAgentSpec.label).tmp-\(UUID().uuidString)")
        try spec.data().write(to: tmp)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tmp.path)
        if rename(tmp.path, paths.plist.path) != 0 {
            let reason = String(cString: strerror(errno))
            try? fm.removeItem(at: tmp)
            throw ServiceError.io("Écriture de \(paths.plist.path) impossible : \(reason)")
        }
    }
}
