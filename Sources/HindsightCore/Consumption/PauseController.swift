import Foundation
import HindsightAPI
import Observation

/// Refus d'un envoi pendant une pause : message à afficher, ou nil si l'envoi est permis.
public typealias PauseGate = @MainActor (String) -> String?

/// Mettre en pause ce qui consomme du LLM, pour toutes les banques ou une seule, sans jamais redémarrer le serveur.
///
/// L'API Hindsight n'a pas de pause : elle s'appuie sur ce qui existe.
/// - **Pause** (banque ou toutes) : l'app n'envoie plus rien (fichiers, imports, relances, consolidations
///   manuelles) et coupe la consolidation automatique de la banque (`enable_auto_consolidation`). Le réglage
///   d'avant est mémorisé, par serveur et par banque, et rétabli à la reprise : valeur explicite, ou retour
///   à la valeur héritée (`null`). Ce qui n'a pas pu être fait (serveur injoignable, banques pas encore
///   chargées) est rattrapé à la reconnexion (`reconcile`).
/// - Les **consolidations** et les **rafraîchissements de modèles mentaux** en attente ou en cours sont annulés,
///   puis ceux qui arrivent pendant la pause (`sweepPausedWork`). L'annulation du serveur est coopérative : une
///   opération en cours finit le lot qu'elle traite, puis s'arrête. Rien n'est perdu : les faits pas encore
///   consolidés le seront plus tard, et le modèle mental garde son contenu. Sans cela, une consolidation lancée
///   à la main se relance tranche après tranche jusqu'à vider tout l'arriéré, pause ou pas.
/// - **Reprise** : la consolidation que la pause a arrêtée est relancée ; elle reprend sur les faits restants.
/// - Les extractions déjà en file continuent : les annuler ferait perdre leur contenu.
/// **Vider la file** annule les opérations en attente (définitif : il faudra renvoyer leur contenu).
/// Au-delà, « Arrêter le serveur » coupe tout.
@MainActor
@Observable
public final class PauseController {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let banksProvider: @MainActor () -> [String]
    @ObservationIgnored private let serverProvider: @MainActor () -> String
    /// Worker actif d'après `/version` (nil : inconnu, serveur injoignable).
    @ObservationIgnored public var workerEnabled: (@MainActor () -> Bool?)?

    /// Pause de toutes les banques.
    public private(set) var globalPause: Bool
    /// Banques en pause individuellement.
    public private(set) var pausedBanks: Set<String>
    /// Pourquoi la pause a été déclenchée automatiquement (plafond), et quand.
    public private(set) var autoReason: String?
    public private(set) var since: Date?
    /// Vidage ou annulation en cours (une seule de ces actions à la fois).
    public private(set) var working = false
    /// Mise en accord de la configuration des banques en cours.
    public private(set) var reconciling = false
    @ObservationIgnored private var reconcileAgain = false
    /// Pendant une pause, annulation régulière des consolidations et rafraîchissements qui arrivent (relances, autres clients).
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
        server: @escaping @MainActor () -> String = { "" },
        automaticSweeping: Bool = true
    ) {
        self.automaticSweeping = automaticSweeping
        self.settings = settings
        self.clientProvider = client
        self.banksProvider = banks
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
        /// Banques dont la pause a arrêté une consolidation, « serveur|banque » : la reprise la relance.
        static let stopped = "pause.stoppedConsolidations"
    }

    static func decode(_ raw: String?) -> [String] {
        raw.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
    }

    // MARK: État

    public func isPaused(_ bank: String) -> Bool { globalPause || pausedBanks.contains(bank) }
    public var anyPause: Bool { globalPause || !pausedBanks.isEmpty }

    /// Le serveur annonce un worker arrêté (par sa propre configuration) : rien de la file n'avance.
    public var serverWorkerOff: Bool { workerEnabled?() == false }

    /// Refus d'un envoi depuis l'app pendant une pause.
    public func blockReason(_ bank: String) -> String? {
        if globalPause { return "Pause en cours sur toutes les banques : rien n'est envoyé. Reprenez depuis « Activité › Traitements »." }
        if pausedBanks.contains(bank) { return "La banque « \(bank) » est en pause : rien n'y est envoyé. Reprenez-la pour continuer." }
        return nil
    }

    public var gate: PauseGate { { [weak self] bank in self?.blockReason(bank) } }

    // MARK: Banques retenues (consolidation coupée par l'app)

    private var server: String { serverProvider() }
    private func entry(_ bank: String) -> String { "\(server)|\(bank)" }

    private var held: [String] {
        get { Self.decode(settings.string(forKey: Keys.held)) }
        set { storeList(newValue, forKey: Keys.held) }
    }

    /// Consolidations arrêtées par la pause, à relancer à la reprise (« serveur|banque »).
    private var stopped: [String] {
        get { Self.decode(settings.string(forKey: Keys.stopped)) }
        set { storeList(newValue, forKey: Keys.stopped) }
    }

    private func storeList(_ values: [String], forKey key: String) {
        let list = Array(Set(values)).sorted()
        settings.set(list.isEmpty ? nil : (try? JSONEncoder().encode(list)).map { String(decoding: $0, as: UTF8.self) }, forKey: key)
    }

    /// Banques de ce serveur dont la pause a arrêté la consolidation.
    public var stoppedConsolidations: [String] {
        let prefix = server + "|"
        return stopped.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// Banques de ce serveur dont l'app a coupé la consolidation et qui attendent d'être rétablies.
    public var heldBanks: [String] {
        let prefix = server + "|"
        return held.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// La pause a elle-même coupé la consolidation automatique de cette banque (elle était activée avant) :
    /// le réglage affiché n'est pas celui de la banque, et la reprise le rétablira.
    public func cutAutoConsolidation(_ bank: String) -> Bool {
        heldBanks.contains(bank) && ["1", "inherit"].contains(settings.string(forKey: Keys.previous(entry(bank))) ?? "")
    }

    /// Les réglages propres à la banque viennent d'être supprimés (retour aux valeurs du serveur) : la coupure de
    /// la pause est partie avec eux. Après la reprise, la banque héritera du serveur ; pendant la pause, on recoupe.
    public func bankConfigWasReset(_ bank: String) async {
        guard cutAutoConsolidation(bank) else { return }
        settings.set("inherit", forKey: Keys.previous(entry(bank)))
        do {
            _ = try await clientProvider().updateBankConfig(bank, updates: ["enable_auto_consolidation": .bool(false)])
        } catch {
            // Plus coupée : la banque redevient « à couper », signalée et rattrapée au prochain chargement.
            held = held.filter { $0 != entry(bank) }
            message = "Consolidation automatique pas encore coupée pour \(bank) (\(error.userMessage))."
        }
    }

    /// Banques en pause dont la consolidation automatique n'a pas encore pu être coupée (serveur injoignable,
    /// écriture refusée) : la pause bloque les envois, mais le serveur peut encore consolider.
    public var uncutBanks: [String] {
        let held = Set(heldBanks)
        return banksProvider().filter { isPaused($0) && !held.contains($0) }
    }

    /// Banques reprises dont la consolidation automatique n'a pas encore pu être rétablie.
    public var unreleasedBanks: [String] { heldBanks.filter { !isPaused($0) } }

    /// « Réessayer » du bandeau : coupe ou rétablit ce qui n'a pas pu l'être, sur demande.
    public func retryReconcile() async {
        let failures = await reconcile()
        message = failures.isEmpty
            ? "Consolidation automatique mise en accord avec la pause."
            : "Toujours en échec : " + failures.joined(separator: " ; ") + "."
    }

    // MARK: Pause et reprise (immédiates, réversibles)

    /// Met en pause une banque, ou toutes (`bank` nil). `reason` : déclenchement automatique (plafond).
    public func pause(bank: String?, reason: String?) async {
        if let bank, pausedBanks.contains(bank) {
            message = "« \(bank) » est déjà en pause."
            return
        }
        if bank == nil, globalPause {
            message = "Toutes les banques sont déjà en pause."
            return
        }
        if let bank { pausedBanks.insert(bank) } else { globalPause = true }
        if since == nil { since = Date() }
        if let reason { autoReason = reason }
        save()
        startSweeping()
        let failures = await reconcile()
        let swept = await sweepPausedWork()
        let scope = bank.map { "« \($0) » est en pause." } ?? "Toutes les banques sont en pause."
        if bank == nil, banksProvider().isEmpty {
            message = scope + " Rien n'est envoyé. Serveur injoignable : la consolidation automatique n'est pas encore coupée (le bandeau propose de réessayer)."
        } else {
            var stoppedText: [String] = []
            if swept.consolidations > 0 {
                stoppedText.append(swept.consolidations == 1
                    ? "La consolidation s'arrête après le lot en cours ; elle reprendra à la reprise."
                    : "\(swept.consolidations) consolidations s'arrêtent après leur lot en cours ; elles reprendront à la reprise.")
            }
            if swept.refreshes > 0 {
                stoppedText.append(Format.count(swept.refreshes, "régénération de connaissance annulée", "régénérations de connaissances annulées") + ".")
            }
            message = ([scope] + stoppedText).joined(separator: " ")
                + (failures.isEmpty ? "" : " Consolidation automatique pas encore coupée pour " + failures.joined(separator: " ; ") + " (le bandeau propose de réessayer).")
        }
    }

    // MARK: Consolidations et rafraîchissements arrêtés pendant la pause

    static let refreshType = "refresh_mental_model"
    static let consolidationType = "consolidation"

    private func startSweeping() {
        guard automaticSweeping, sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.refreshSweepInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, self.anyPause else { return }
                await self.sweepPausedWork()
            }
        }
    }

    private func stopSweepingIfIdle() {
        guard !anyPause else { return }
        sweepTask?.cancel()
        sweepTask = nil
    }

    /// Annule les consolidations et les rafraîchissements de modèles mentaux en attente ou en cours des banques en
    /// pause : la pause les arrête vraiment, y compris la tranche suivante qu'une consolidation se redonne, ceux
    /// relancés par le serveur ou envoyés par un autre client. L'annulation est coopérative (fin du lot en cours) ;
    /// les faits non consolidés restent à consolider, le modèle mental garde son contenu. Une banque dont une
    /// consolidation est annulée est notée : la reprise la relance. Retourne le nombre annulé de chaque sorte.
    @discardableResult
    public func sweepPausedWork() async -> (consolidations: Int, refreshes: Int) {
        guard anyPause, !sweeping else { return (0, 0) }
        sweeping = true
        defer { sweeping = false }
        var consolidations = 0, refreshes = 0
        for bank in banksProvider() where isPaused(bank) {
            if let ops = try? await activeOperations(bank, type: Self.consolidationType) {
                var any = false
                for op in ops where (try? await clientProvider().cancelOperation(bank, id: op.id))?.success == true {
                    consolidations += 1
                    any = true
                }
                if any { stopped = stopped + [entry(bank)] }
            }
            if let ops = try? await refreshOperations(bank) {
                for op in ops where (try? await clientProvider().cancelOperation(bank, id: op.id))?.success == true { refreshes += 1 }
            }
        }
        return (consolidations, refreshes)
    }

    /// Relance la consolidation des banques reprises que la pause avait arrêtée. Retourne les échecs.
    private func restartStoppedConsolidations() async -> (restarted: [String], failures: [String]) {
        var restarted: [String] = [], failures: [String] = []
        for bank in stoppedConsolidations where !isPaused(bank) {
            do {
                _ = try await clientProvider().triggerConsolidation(bank)
                restarted.append(bank)
            } catch {
                failures.append("\(bank) (\(error.userMessage))")
            }
            // Relancée ou non, on n'y revient pas : un échec se signale, la consolidation se relance à la main.
            stopped = stopped.filter { $0 != entry(bank) }
        }
        return (restarted, failures)
    }

    private func restartText(_ r: (restarted: [String], failures: [String])) -> String {
        var parts: [String] = []
        if !r.restarted.isEmpty {
            parts.append(r.restarted.count == 1
                ? "La consolidation de « \(r.restarted[0]) » reprend là où la pause l'avait arrêtée."
                : "Les consolidations reprennent là où la pause les avait arrêtées : " + r.restarted.joined(separator: ", ") + ".")
        }
        if !r.failures.isEmpty {
            parts.append("Consolidation à relancer depuis Mémoire › Consolidation : " + r.failures.joined(separator: " ; ") + ".")
        }
        return parts.map { " " + $0 }.joined()
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

    /// Opérations d'un type en cours puis en attente.
    func activeOperations(_ bank: String, type: String) async throws -> [OperationResponse] {
        try await listOperations(bank, status: "processing", type: type)
            + listOperations(bank, status: "pending", type: type)
    }

    /// Rafraîchissements de modèles mentaux en cours puis en attente.
    func refreshOperations(_ bank: String) async throws -> [OperationResponse] {
        try await activeOperations(bank, type: Self.refreshType)
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
        if let bank, !pausedBanks.contains(bank) {
            message = globalPause
                ? "« \(bank) » n'est en pause qu'avec toutes les banques : reprenez toutes les banques."
                : "« \(bank) » n'est pas en pause."
            return
        }
        if bank == nil, !globalPause {
            message = pausedBanks.isEmpty
                ? "Aucune banque n'est en pause."
                : "Aucune pause sur toutes les banques. En pause une à une : " + pausedBanks.sorted().joined(separator: ", ") + "."
            return
        }
        if let bank { pausedBanks.remove(bank) } else { globalPause = false }
        clearIfIdle()
        stopSweepingIfIdle()
        save()
        let failures = await reconcile()
        let restart = await restartStoppedConsolidations()
        var text: String
        if let bank {
            text = "« \(bank) » reprend : sa consolidation automatique retrouve son réglage d'avant la pause."
        } else {
            text = "Toutes les banques reprennent : la consolidation automatique retrouve son réglage d'avant la pause."
            if !pausedBanks.isEmpty { text += " Restent en pause : " + pausedBanks.sorted().joined(separator: ", ") + "." }
        }
        message = text + restartText(restart)
            + (failures.isEmpty ? "" : " À rétablir dès que possible : " + failures.joined(separator: " ; ") + ".")
    }

    /// Lève toutes les pauses, globale et par banque.
    public func resumeAll() async {
        pausedBanks = []
        globalPause = false
        clearIfIdle()
        stopSweepingIfIdle()
        save()
        let failures = await reconcile()
        let restart = await restartStoppedConsolidations()
        message = "Toutes les banques reprennent." + restartText(restart)
            + (failures.isEmpty ? "" : " À rétablir dès que possible : " + failures.joined(separator: " ; ") + ".")
    }

    private func clearIfIdle() {
        if !anyPause {
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
            if enabled { _ = try await clientProvider().updateBankConfig(bank, updates: ["enable_auto_consolidation": .bool(false)]) }
            held = held + [entry(bank)]
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
                "\(Format.count(ops.count, "opération")) en attente dans \(Format.count(banks.count, "banque")) \(one ? "sera annulée" : "seront annulées") : extractions, consolidations, régénérations.",
                "C'est définitif : un document dont l'extraction est annulée devra être renvoyé depuis « Documents ».",
                "Une opération déjà commencée quand vous confirmez est interrompue à sa prochaine étape ; les faits déjà extraits ne sont pas touchés.",
            ].joined(separator: "\n"),
            // Au-delà de dix, on fait retaper la banque (ou le nombre d'opérations pour toutes) : rien de propre à une langue.
            confirmTitle: "Vider la file", severity: .destructive, requiredText: ops.count > 10 ? (bank ?? String(ops.count)) : nil
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
        message = "\(Format.count(done, "opération annulée", "opérations annulées"))" + (failures.isEmpty ? "." : ", \(Format.count(failures.count, "non annulée", "non annulées")) : \(failures[0])")
    }

    // MARK: Automatique

    /// Plafond dépassé : applique l'action confirmée par l'utilisateur (sans nouvelle confirmation). Une action
    /// en cours (vidage…) est d'abord attendue : l'action automatique ne doit pas se perdre.
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
        }
    }
}
