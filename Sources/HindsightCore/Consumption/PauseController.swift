import Foundation
import HindsightAPI
import Observation

/// Refus d'un envoi pendant une pause : message à afficher, ou nil si l'envoi est permis.
public typealias PauseGate = @MainActor (String) -> String?

/// Mettre en pause ce qui consomme du LLM, à trois niveaux, pour toutes les banques ou une seule.
///
/// L'API Hindsight n'a pas de pause : chaque niveau s'appuie sur ce qui existe.
/// 1. **Pause** (banque ou toutes) : l'app n'envoie plus rien (fichiers, imports, relances, consolidations
///    manuelles) et coupe la consolidation automatique de la banque (`enable_auto_consolidation`). Le réglage
///    d'avant est mémorisé, par serveur et par banque, et rétabli à la reprise : valeur explicite, ou retour
///    à la valeur héritée (`null`). Ce qui n'a pas pu être fait (serveur injoignable, banques pas encore
///    chargées) est rattrapé à la reconnexion (`reconcile`). Les rafraîchissements de modèles mentaux
///    en attente ou en cours sont annulés, puis ceux qui arrivent pendant la pause (`sweepRefreshes`) : ce sont
///    eux qui consomment le plus (Sonnet, outils), et le modèle mental garde son contenu. Le reste de la file continue.
/// 2. **Geler la file** (serveur) : le service relance le serveur sans worker ; l'API et les lectures
///    restent disponibles, les opérations attendent. Seulement pour un serveur lancé par l'app.
/// 3. **Vider la file** : annule les opérations en attente (définitif : il faudra renvoyer leur contenu).
/// Au-delà, « Arrêter le serveur » coupe tout.
@MainActor
@Observable
public final class PauseController {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let banksProvider: @MainActor () -> [String]
    @ObservationIgnored private let serviceProvider: @MainActor () -> HindsightServiceViewModel?
    @ObservationIgnored private let serverProvider: @MainActor () -> String
    /// Worker actif d'après `/version` (nil : inconnu, serveur injoignable).
    @ObservationIgnored public var workerEnabled: (@MainActor () -> Bool?)?
    /// Relit `/version` après un redémarrage du serveur (l'app reste « connectée » pendant un gel).
    @ObservationIgnored public var refreshServerInfo: (@MainActor () async -> Void)?

    /// Pause de toutes les banques.
    public private(set) var globalPause: Bool
    /// Banques en pause individuellement.
    public private(set) var pausedBanks: Set<String>
    /// Pourquoi la pause a été déclenchée automatiquement (plafond), et quand.
    public private(set) var autoReason: String?
    public private(set) var since: Date?
    /// Gel, dégel, vidage en cours (une seule de ces actions à la fois).
    public private(set) var working = false
    /// Mise en accord de la configuration des banques en cours.
    public private(set) var reconciling = false
    @ObservationIgnored private var reconcileAgain = false
    /// Pendant une pause, annulation régulière des rafraîchissements qui arrivent (relances, autres clients).
    @ObservationIgnored public var refreshSweepInterval: Duration = .seconds(60)
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var sweeping = false
    @ObservationIgnored private let automaticSweeping: Bool
    public var isBusy: Bool { working || reconciling }
    public private(set) var progress: String?
    public var confirmation: ConfirmationRequest?
    public var message: String?

    public init(
        settings: SettingsStore, client: @escaping @MainActor () -> HindsightClient, banks: @escaping @MainActor () -> [String],
        service: @escaping @MainActor () -> HindsightServiceViewModel?, server: @escaping @MainActor () -> String = { "" },
        automaticSweeping: Bool = true
    ) {
        self.automaticSweeping = automaticSweeping
        self.settings = settings
        self.clientProvider = client
        self.banksProvider = banks
        self.serviceProvider = service
        self.serverProvider = server
        self.globalPause = settings.string(forKey: Keys.global) == "1"
        self.pausedBanks = Set(Self.decode(settings.string(forKey: Keys.banks)))
        self.autoReason = settings.string(forKey: Keys.reason)
        self.since = settings.string(forKey: Keys.since).flatMap(HSDate.parse)
        if anyPause { startSweeping() }
    }

    enum Keys {
        static let global = "pause.global"
        static let banks = "pause.banks"
        static let reason = "pause.reason"
        static let since = "pause.since"
        /// Banques dont l'app a coupé la consolidation automatique, « serveur|banque ».
        static let held = "pause.held"
        /// Réglage d'avant la pause : "1" (activée par la banque), "inherit" (activée par défaut du serveur) ou
        /// "untouched" (déjà coupée : l'app n'y a pas touché et n'aura rien à rétablir).
        static func previous(_ entry: String) -> String { "pause.autoConsolidation.\(entry)" }
    }

    static func decode(_ raw: String?) -> [String] {
        raw.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
    }

    // MARK: État

    public func isPaused(_ bank: String) -> Bool { globalPause || pausedBanks.contains(bank) }
    public var anyPause: Bool { globalPause || !pausedBanks.isEmpty }

    /// File gelée par l'app (service sans worker).
    public var queueFrozen: Bool { serviceProvider()?.isWorkerPaused ?? false }
    /// Le serveur annonce un worker arrêté (gelé par l'app ou par sa configuration).
    public var serverWorkerOff: Bool { workerEnabled?() == false }
    /// Le gel est possible : serveur lancé par le service de l'app.
    public var canFreeze: Bool { serviceProvider()?.isInstalled ?? false }

    /// Refus d'un envoi depuis l'app pendant une pause.
    public func blockReason(_ bank: String) -> String? {
        if globalPause { return "Pause en cours sur toutes les banques : rien n'est envoyé. Reprenez depuis « Consommation »." }
        if pausedBanks.contains(bank) { return "La banque « \(bank) » est en pause : rien n'y est envoyé. Reprenez-la pour continuer." }
        return nil
    }

    public var gate: PauseGate { { [weak self] bank in self?.blockReason(bank) } }

    // MARK: Banques retenues (consolidation coupée par l'app)

    private var server: String { serverProvider() }
    private func entry(_ bank: String) -> String { "\(server)|\(bank)" }

    private var held: [String] {
        get { Self.decode(settings.string(forKey: Keys.held)) }
        set {
            let list = Array(Set(newValue)).sorted()
            settings.set(list.isEmpty ? nil : (try? JSONEncoder().encode(list)).map { String(decoding: $0, as: UTF8.self) }, forKey: Keys.held)
        }
    }

    /// Banques de ce serveur dont l'app a coupé la consolidation et qui attendent d'être rétablies.
    public var heldBanks: [String] {
        let prefix = server + "|"
        return held.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    // MARK: Pause et reprise (immédiates, réversibles)

    /// Met en pause une banque, ou toutes (`bank` nil). `reason` : déclenchement automatique (plafond).
    public func pause(bank: String?, reason: String?) async {
        if let bank { pausedBanks.insert(bank) } else { globalPause = true }
        if since == nil { since = Date() }
        if let reason { autoReason = reason }
        save()
        startSweeping()
        let failures = await reconcile()
        let cancelled = await sweepRefreshes()
        let scope = bank.map { "« \($0) » est en pause." } ?? "Toutes les banques sont en pause."
        if bank == nil, banksProvider().isEmpty {
            message = scope + " Rien n'est envoyé ; la consolidation automatique et les régénérations de connaissances seront coupées dès que le serveur répondra."
        } else {
            message = scope + (cancelled > 0 ? " \(Format.count(cancelled, "régénération de connaissance annulée", "régénérations de connaissances annulées"))." : "")
                + (failures.isEmpty ? "" : " Consolidation automatique pas encore coupée pour " + failures.joined(separator: " ; ") + " (nouvel essai à la reconnexion).")
        }
    }

    // MARK: Rafraîchissements de modèles mentaux

    static let refreshType = "refresh_mental_model"

    private func startSweeping() {
        guard automaticSweeping, sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.refreshSweepInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, self.anyPause else { return }
                await self.sweepRefreshes()
            }
        }
    }

    private func stopSweepingIfIdle() {
        guard !anyPause else { return }
        sweepTask?.cancel()
        sweepTask = nil
    }

    /// Annule les rafraîchissements de modèles mentaux en attente ou en cours des banques en pause : la pause les arrête
    /// vraiment, y compris ceux relancés par le serveur ou envoyés par un autre client. Le modèle mental garde
    /// son contenu ; il sera rafraîchi à la prochaine consolidation après la reprise. Retourne le nombre annulé.
    @discardableResult
    public func sweepRefreshes() async -> Int {
        guard anyPause, !sweeping else { return 0 }
        sweeping = true
        defer { sweeping = false }
        var cancelled = 0
        for bank in banksProvider() where isPaused(bank) {
            guard let ops = try? await refreshOperations(bank) else { continue }
            for op in ops {
                if (try? await clientProvider().cancelOperation(bank, id: op.id))?.success == true { cancelled += 1 }
            }
        }
        return cancelled
    }

    /// Opérations d'une banque, en suivant la pagination de l'API.
    func listOperations(_ bank: String, status: String, type: String? = nil) async throws -> [OperationResponse] {
        var all: [OperationResponse] = []
        var offset = 0
        while true {
            let page = try await clientProvider().listOperations(bank, status: status, type: type, limit: 100, offset: offset, excludeParents: true)
            all += page.operations.filter { $0.status == status && (type == nil || $0.taskType == type) }
            offset += page.operations.count
            if page.operations.isEmpty || offset >= page.total { break }
        }
        return all
    }

    /// Rafraîchissements de modèles mentaux en cours puis en attente.
    func refreshOperations(_ bank: String) async throws -> [OperationResponse] {
        try await listOperations(bank, status: "processing", type: Self.refreshType)
            + listOperations(bank, status: "pending", type: Self.refreshType)
    }

    /// Recense les rafraîchissements en double (même modèle mental, plusieurs fois dans la file) et demande confirmation
    /// avant de les annuler. Pour chaque modèle mental, on garde celui en cours, sinon le plus récent en attente.
    public func requestCancelDuplicateRefreshes(bank: String?) async {
        guard !working else { return }
        working = true
        progress = "Recherche des régénérations en double…"
        var duplicates: [(bank: String, id: String)] = []
        var pages = 0
        do {
            for b in bank.map({ [$0] }) ?? banksProvider() {
                let ops = try await refreshOperations(b)
                let found = Self.duplicateRefreshes(ops)
                duplicates += found.cancel.map { (b, $0) }
                pages += found.pages
            }
        } catch {
            working = false
            progress = nil
            message = "Impossible de lister la file : \(error.userMessage)"
            return
        }
        working = false
        progress = nil
        guard !duplicates.isEmpty else {
            message = "Aucune régénération de connaissance en double" + (bank.map { " dans « \($0) »." } ?? ".")
            return
        }
        let ops = duplicates
        let one = ops.count == 1
        confirmation = ConfirmationRequest(
            title: "Annuler \(Format.count(ops.count, "régénération", "régénérations")) en double ?",
            message: [
                "\(Format.count(pages, "connaissance est", "connaissances sont")) dans la file plusieurs fois : \(Format.count(ops.count, "régénération")) en trop \(one ? "sera annulée" : "seront annulées").",
                "Chaque connaissance garde une seule régénération (celle en cours, sinon la plus récente) : son contenu final est le même, sans payer plusieurs fois.",
            ].joined(separator: "\n"),
            confirmTitle: "Annuler les doublons", severity: .normal
        ) { [weak self] in
            await self?.cancel(ops)
        }
    }

    /// Doublons d'une liste de rafraîchissements : identifiants à annuler et nombre de modèles mentaux concernés.
    static func duplicateRefreshes(_ ops: [OperationResponse]) -> (cancel: [String], pages: Int) {
        var cancel: [String] = []
        var pages = 0
        let byPage = Dictionary(grouping: ops.filter { $0.mentalModelId != nil }, by: { $0.mentalModelId! })
        for (_, group) in byPage where group.count > 1 {
            pages += 1
            let keep =
                group.first { $0.status == "processing" }
                ?? group.max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            cancel += group.filter { $0.id != keep?.id }.map(\.id)
        }
        return (cancel.sorted(), pages)
    }

    /// Lève la pause d'une banque, ou la pause de toutes les banques (`bank` nil) ; les banques mises en
    /// pause une à une le restent.
    public func resume(bank: String?) async {
        if let bank { pausedBanks.remove(bank) } else { globalPause = false }
        clearIfIdle()
        stopSweepingIfIdle()
        save()
        let failures = await reconcile()
        var text: String
        if let bank {
            text = globalPause
                ? "« \(bank) » n'est plus en pause à part, mais la pause de toutes les banques s'applique encore."
                : "« \(bank) » reprend : sa consolidation automatique retrouve son réglage d'avant la pause."
        } else {
            text = "Toutes les banques reprennent : la consolidation automatique retrouve son réglage d'avant la pause."
            if !pausedBanks.isEmpty { text += " Restent en pause : " + pausedBanks.sorted().joined(separator: ", ") + "." }
        }
        message = text + (failures.isEmpty ? "" : " À rétablir dès que possible : " + failures.joined(separator: " ; ") + ".")
    }

    /// Lève toutes les pauses, globale et par banque.
    public func resumeAll() async {
        pausedBanks = []
        globalPause = false
        clearIfIdle()
        stopSweepingIfIdle()
        save()
        let failures = await reconcile()
        message = "Toutes les banques reprennent." + (failures.isEmpty ? "" : " À rétablir dès que possible : " + failures.joined(separator: " ; ") + ".")
    }

    private func clearIfIdle() {
        if !anyPause, !queueFrozen {
            since = nil
            autoReason = nil
        }
    }

    /// Met la configuration des banques en accord avec la pause : coupe la consolidation des banques en pause
    /// qui ne le sont pas encore, rétablit celle des banques qui ne le sont plus. À appeler aussi quand les
    /// banques se chargent (reconnexion) : ce qui avait échoué y est rattrapé. Retourne les échecs.
    /// Si une mise en accord tourne déjà, elle repasse une fois finie (l'état a pu changer entre-temps).
    @discardableResult
    public func reconcile() async -> [String] {
        guard !reconciling else {
            reconcileAgain = true
            return []
        }
        reconciling = true
        defer {
            reconciling = false
            progress = nil
        }
        var failures: [String] = []
        repeat {
            reconcileAgain = false
            failures = []
            let banks = banksProvider()
            let toHold = banks.filter { isPaused($0) && !heldBanks.contains($0) }
            let toRelease = heldBanks.filter { !isPaused($0) }
            for (i, b) in toHold.enumerated() {
                progress = "Pause : \(i + 1) sur \(toHold.count)…"
                if let problem = await holdConsolidation(b) { failures.append("\(b) (\(problem))") }
            }
            for (i, b) in toRelease.enumerated() {
                progress = "Reprise : \(i + 1) sur \(toRelease.count)…"
                if let problem = await releaseConsolidation(b) { failures.append("\(b) (\(problem))") }
            }
        } while reconcileAgain
        return failures
    }

    /// Coupe la consolidation automatique en mémorisant le réglage d'avant (une seule fois par pause).
    func holdConsolidation(_ bank: String) async -> String? {
        let key = Keys.previous(entry(bank))
        do {
            let config = try await clientProvider().bankConfig(bank)
            var enabled = true
            if case .bool(let b)? = config.config["enable_auto_consolidation"] { enabled = b }
            if settings.string(forKey: key) == nil {
                let explicit: Bool
                if case .bool? = config.overrides["enable_auto_consolidation"] { explicit = true } else { explicit = false }
                settings.set(!enabled ? "untouched" : (explicit ? "1" : "inherit"), forKey: key)
            }
            held = held + [entry(bank)]
            if enabled { _ = try await clientProvider().updateBankConfig(bank, updates: ["enable_auto_consolidation": .bool(false)]) }
            return nil
        } catch {
            return error.userMessage
        }
    }

    /// Rétablit le réglage d'avant la pause : valeur explicite, ou valeur héritée du serveur (`null`).
    func releaseConsolidation(_ bank: String) async -> String? {
        let key = Keys.previous(entry(bank))
        do {
            switch settings.string(forKey: key) {
            case "1": _ = try await clientProvider().updateBankConfig(bank, updates: ["enable_auto_consolidation": .bool(true)])
            case "inherit": _ = try await clientProvider().updateBankConfig(bank, updates: ["enable_auto_consolidation": .null])
            default: break  // Déjà coupée avant la pause : l'app n'y a pas touché.
            }
            settings.set(nil, forKey: key)
            held = held.filter { $0 != entry(bank) }
            return nil
        } catch {
            return error.userMessage
        }
    }

    private func save() {
        settings.set(globalPause ? "1" : nil, forKey: Keys.global)
        let banks = pausedBanks.sorted()
        settings.set(banks.isEmpty ? nil : (try? JSONEncoder().encode(banks)).map { String(decoding: $0, as: UTF8.self) }, forKey: Keys.banks)
        settings.set(autoReason, forKey: Keys.reason)
        settings.set(since.map(HSDate.format), forKey: Keys.since)
    }

    // MARK: Geler la file (confirmé)

    public func requestFreeze() {
        guard let service = serviceProvider(), service.isInstalled else {
            message = "Le serveur n'est pas lancé par le service de l'app : ajoutez HINDSIGHT_API_WORKER_ENABLED=false à son environnement et redémarrez-le, ou mettez les banques en pause."
            return
        }
        var lines = [
            service.job.running
                ? "Le serveur va redémarrer (quelques secondes) sans traiter sa file : HINDSIGHT_API_WORKER_ENABLED=false est ajouté à l'environnement du service, pas à votre script."
                : "Le serveur est arrêté : il ne traitera pas sa file à son prochain démarrage (HINDSIGHT_API_WORKER_ENABLED=false dans l'environnement du service, pas dans votre script). Il n'est pas démarré pour autant.",
            "L'API, la recherche et les lectures restent disponibles ; les opérations attendent. Celles en cours sont interrompues et reprendront au dégel.",
        ]
        if service.scriptOverridesWorker {
            lines.append("Attention : votre script fixe lui-même HINDSIGHT_API_WORKER_ENABLED ; sa valeur l'emportera.")
        }
        confirmation = ConfirmationRequest(
            title: "Geler la file du serveur ?", message: lines.joined(separator: "\n"), confirmTitle: "Geler la file", severity: .normal
        ) { [weak self] in
            await self?.setFrozen(true)
        }
    }

    public func requestUnfreeze() {
        let running = serviceProvider()?.job.running ?? false
        confirmation = ConfirmationRequest(
            title: "Reprendre la file du serveur ?",
            message: running
                ? "Le serveur va redémarrer avec son worker : les opérations en attente seront traitées (consommation LLM)."
                : "Le serveur est arrêté : il traitera sa file à son prochain démarrage. Il n'est pas démarré pour autant.",
            confirmTitle: "Reprendre la file", severity: .normal
        ) { [weak self] in
            await self?.setFrozen(false)
        }
    }

    @discardableResult
    public func setFrozen(_ frozen: Bool) async -> Bool {
        guard let service = serviceProvider() else { return false }
        guard !working else {
            message = "Une autre action est en cours (gel, vidage) : réessayez dans un instant."
            return false
        }
        working = true
        progress = frozen ? "Gel de la file…" : "Reprise de la file…"
        defer {
            working = false
            progress = nil
        }
        let ok = await service.setWorkerPaused(frozen)
        guard ok else {
            message = service.message
            return false
        }
        if !service.job.running {
            message = frozen ? "File gelée au prochain démarrage du serveur." : "File reprise au prochain démarrage du serveur."
            clearIfIdle()
            save()
            return true
        }
        // Le serveur a redémarré : relire ce qu'il annonce avant de juger du résultat.
        await refreshServerInfo?()
        if frozen, workerEnabled?() == true {
            message = "Le serveur a redémarré mais son worker tourne toujours : votre script fixe probablement HINDSIGHT_API_WORKER_ENABLED."
        } else {
            message = frozen ? "File gelée : le serveur répond mais ne traite plus d'opérations." : "File reprise : le serveur traite à nouveau ses opérations."
        }
        if !frozen { clearIfIdle() }
        save()
        return true
    }

    // MARK: Vider la file (confirmé, définitif)

    /// Recense les opérations en attente puis demande confirmation avant de les annuler.
    public func requestDrain(bank: String?) async {
        guard !working else { return }
        working = true
        progress = "Recherche des opérations en attente…"
        var pending: [(bank: String, id: String)] = []
        do {
            for b in bank.map({ [$0] }) ?? banksProvider() {
                pending += try await listOperations(b, status: "pending").map { (b, $0.id) }
            }
        } catch {
            working = false
            progress = nil
            message = "Impossible de lister la file : \(error.userMessage)"
            return
        }
        working = false
        progress = nil
        guard !pending.isEmpty else {
            message = bank.map { "Aucune opération en attente dans « \($0) »." } ?? "Aucune opération en attente."
            return
        }
        let banks = Set(pending.map(\.bank))
        let ops = pending
        let one = ops.count == 1
        confirmation = ConfirmationRequest(
            title: "Annuler \(Format.count(ops.count, "opération")) en attente ?",
            message: [
                "\(Format.count(ops.count, "opération")) en attente dans \(Format.count(banks.count, "banque")) \(one ? "sera annulée" : "seront annulées") : \(one ? "son" : "leur") contenu ne sera pas extrait.",
                "C'est définitif : pour l'ajouter plus tard, il faudra le renvoyer (depuis Documents ou Importer).",
                "Une opération déjà commencée quand vous confirmez est interrompue à sa prochaine étape ; les faits déjà extraits ne sont pas touchés.",
            ].joined(separator: "\n"),
            confirmTitle: "Vider la file", severity: .destructive, requiredText: ops.count > 10 ? "vider" : nil
        ) { [weak self] in
            await self?.cancel(ops)
        }
    }

    func cancel(_ ops: [(bank: String, id: String)]) async {
        guard !working else { return }
        working = true
        defer {
            working = false
            progress = nil
        }
        var done = 0
        var failures: [String] = []
        for (i, op) in ops.enumerated() {
            progress = "Annulation : \(i + 1) sur \(ops.count)…"
            do {
                let r = try await clientProvider().cancelOperation(op.bank, id: op.id)
                if r.success { done += 1 } else { failures.append(r.message) }
            } catch {
                // Terminée entre-temps : plus rien à annuler.
                failures.append(error.userMessage)
            }
        }
        message = "\(Format.count(done, "opération annulée", "opérations annulées"))" + (failures.isEmpty ? "." : ", \(failures.count) non annulée(s) : \(failures[0])")
    }

    // MARK: Automatique

    /// Plafond dépassé : applique l'action confirmée par l'utilisateur (sans nouvelle confirmation). Une action
    /// en cours (vidage, gel…) est d'abord attendue : l'action automatique ne doit pas se perdre.
    public func apply(_ action: ConsumptionBudgets.Action, reason: String) async {
        guard action != .alert else { return }
        let deadline = Date().addingTimeInterval(120)
        while working, Date() < deadline { try? await Task.sleep(for: .milliseconds(250)) }
        switch action {
        case .alert:
            return
        case .softPause:
            guard !globalPause else { return }
            await pause(bank: nil, reason: reason)
        case .freezeQueue:
            if queueFrozen { return }
            if canFreeze {
                autoReason = reason
                if since == nil { since = Date() }
                save()
                if await setFrozen(true) { return }
            }
            // Gel impossible (serveur externe, échec) : la pause reste le meilleur recours.
            if !globalPause { await pause(bank: nil, reason: reason) }
        }
    }
}
