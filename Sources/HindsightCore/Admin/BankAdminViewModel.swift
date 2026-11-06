import Foundation
import HindsightAPI
import Observation

/// Administration d'une banque (missions et disposition : voir `MemoryDesignViewModel`) : overrides de configuration,
/// directives, modèles mentaux, export / clone / import, zone dangereuse.
/// Toute écriture passe par une `ConfirmationRequest`.
@MainActor
@Observable
public final class BankAdminViewModel {
    /// Fichier produit pour l'utilisateur (archive ZIP ou modèle JSON) ; l'UI propose de l'enregistrer.
    public struct ExportedFile: Identifiable, Sendable {
        public let id = UUID()
        public let filename: String
        public let data: Data
    }

    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    /// Prévenu quand la liste des banques change (création, clone, suppression) ou que leur nombre de faits change.
    @ObservationIgnored public var onBanksChanged: (@MainActor () async -> Void)?
    /// Message qui doit survivre à cette session : après la suppression de la banque, la session est remplacée
    /// et son `actionMessage` ne serait plus jamais affiché.
    @ObservationIgnored public var onAppMessage: (@MainActor (String) -> Void)?

    public private(set) var config: LoadState<BankConfigResponse> = .idle
    public private(set) var directives: LoadState<[DirectiveResponse]> = .idle
    public private(set) var mentalModels: LoadState<[MentalModelResponse]> = .idle
    /// Modèle mental affiché, contenu compris (la liste du serveur ne transmet pas le contenu).
    public private(set) var mentalModelDetail: LoadState<MentalModelResponse> = .idle

    /// Progression d'une opération longue (export, clone, import).
    public private(set) var longTask: String?
    public var exported: ExportedFile?
    public private(set) var templateDryRun: BankTemplateImportResponse?
    @ObservationIgnored private var pendingTemplate: BankTemplateManifest?

    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    /// Refus pendant une pause de la banque (génération de modèles mentaux).
    @ObservationIgnored public var pauseGate: PauseGate?
    /// Prévenu après une modification de la configuration de la banque (le tableau de bord se recalcule).
    @ObservationIgnored public var onConfigChanged: (@MainActor () async -> Void)?
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?

    public init(client: HindsightClient, bank: String) {
        self.client = client
        self.bank = bank
    }

    public func loadIfNeeded() async {
        if config.value == nil, !config.isLoading { await reload() }
    }

    public func reload() async {
        async let c: Void = loadConfig()
        async let d: Void = loadDirectives()
        async let m: Void = loadMentalModels()
        _ = await (c, d, m)
    }

    func loadConfig() async {
        config = .loading
        do {
            let r = try await client.bankConfig(bank)
            config = .loaded(r)
        } catch is CancellationError {
        } catch {
            config = .failed(error.userMessage)
        }
    }

    func loadDirectives() async {
        directives = .loading
        do { directives = .loaded(try await client.listDirectives(bank).items) } catch is CancellationError {} catch {
            directives = .failed(error.userMessage)
        }
    }

    func loadMentalModels() async {
        mentalModels = .loading
        do { mentalModels = .loaded(try await client.listMentalModels(bank).items) } catch is CancellationError {} catch {
            mentalModels = .failed(error.userMessage)
        }
    }

    // MARK: Configuration

    /// Pose un override arbitraire ; `rawJSON` est la valeur JSON (`true`, `5`, `"texte"`…). Retourne false si invalide.
    @discardableResult
    public func requestSetOverride(key: String, rawJSON: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty, let value = Self.parseJSONValue(rawJSON) else { return false }
        confirmation = ConfirmationRequest(
            title: "Modifier « \(k) » pour cette banque ?",
            message: "Nouvelle valeur : \(value.prettyString())\nLe serveur refuse les réglages non surchargeables (ex. modèles LLM : voir « Serveur & modèles »).",
            confirmTitle: "Appliquer", severity: .normal
        ) { [weak self] in await self?.patch([k: value], success: "« \(k) » mis à jour.") }
        return true
    }

    public func requestResetConfig() {
        let n = config.value?.overrides.count ?? 0
        confirmation = ConfirmationRequest(
            title: "Supprimer les \(n) override(s) de la banque ?",
            message: "La banque revient aux valeurs globales du serveur (missions, disposition, réglages de rétention/recall…).",
            confirmTitle: "Réinitialiser"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.resetBankConfig(self.bank)
                self.actionMessage = "Configuration réinitialisée."
                await self.loadConfig()
                await self.onConfigChanged?()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    static func parseJSONValue(_ raw: String) -> JSONValue? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let v = try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8)) { return v }
        return .string(t)  // texte nu accepté comme chaîne
    }

    private func patch(_ u: [String: JSONValue], success: String) async {
        do {
            _ = try await client.updateBankConfig(bank, updates: u)
            actionMessage = success
            await loadConfig()
            await onConfigChanged?()
        } catch {
            actionMessage = "Refusé par le serveur : \(error.userMessage)"
        }
    }

    // MARK: Directives

    /// `onCreated` : appelé après création réussie (l'interface vide alors son formulaire, pas avant).
    public func requestCreateDirective(name: String, content: String, priority: Int = 0, onCreated: @escaping @MainActor @Sendable () -> Void = {}) {
        let n = name.trimmingCharacters(in: .whitespaces), c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !c.isEmpty else { return }
        confirmation = ConfirmationRequest(
            title: "Créer la directive « \(n) » ?", message: c, confirmTitle: "Créer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.createDirective(self.bank, CreateDirectiveRequest(name: n, content: c, priority: priority))
                self.actionMessage = "Directive créée."
                onCreated()
                await self.loadDirectives()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    public func requestUpdateDirective(
        _ d: DirectiveResponse, name: String? = nil, content: String? = nil, priority: Int? = nil, isActive: Bool? = nil
    ) {
        let newName = name?.trimmingCharacters(in: .whitespaces), newContent = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        var changes: [String] = []
        if let newName, newName != d.name { changes.append("Nom : \(newName)") }
        if let newContent, newContent != d.content { changes.append("Contenu : \(newContent)") }
        if let priority, priority != d.priority { changes.append("Priorité : \(priority)") }
        if let isActive { changes.append(isActive ? "Elle sera réactivée." : "Elle sera désactivée (conservée).") }
        guard !changes.isEmpty else { return }
        confirmation = ConfirmationRequest(
            title: "Modifier la directive « \(d.name) » ?", message: changes.joined(separator: "\n"), confirmTitle: "Appliquer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateDirective(
                    self.bank, id: d.id,
                    UpdateDirectiveRequest(
                        name: newName == d.name ? nil : newName, content: newContent == d.content ? nil : newContent,
                        priority: priority == d.priority ? nil : priority, isActive: isActive))
                self.actionMessage = "Directive mise à jour."
                await self.loadDirectives()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    public func requestDeleteDirective(_ d: DirectiveResponse) {
        confirmation = ConfirmationRequest(
            title: "Supprimer la directive « \(d.name) » ?", message: d.content, confirmTitle: "Supprimer"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.deleteDirective(self.bank, id: d.id)
                self.actionMessage = "Directive supprimée."
                await self.loadDirectives()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    // MARK: Modèles mentaux

    /// Crée un modèle mental : une synthèse épinglée, régénérée par le LLM à partir de `sourceQuery`.
    public func requestCreateMentalModel(name: String, sourceQuery: String, tags: [String] = [], onCreated: @escaping @MainActor @Sendable () -> Void = {}) {
        let n = name.trimmingCharacters(in: .whitespaces), q = sourceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !q.isEmpty else { return }
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        confirmation = ConfirmationRequest(
            title: "Créer le modèle mental « \(n) » ?",
            message: "Question source : \(q)\n\nSon contenu est généré par le LLM (opération asynchrone)."
                + (estimate?(.mentalModelRefresh).map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Créer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            if let reason = self.pauseGate?(self.bank) {
                self.actionMessage = reason
                return
            }
            do {
                let r = try await self.client.createMentalModel(self.bank, CreateMentalModelRequest(name: n, sourceQuery: q, tags: tags))
                self.actionMessage = "Modèle mental créé ; génération lancée (\(r.operationId))."
                onCreated()
                await self.loadMentalModels()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    public func requestRefreshMentalModel(_ m: MentalModelResponse) {
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        confirmation = ConfirmationRequest(
            title: "Rafraîchir « \(m.name) » ?",
            message: (m.isKnowledgePage == true
                ? "La page de connaissance est régénérée par le LLM (opération asynchrone)."
                : "Le modèle mental est régénéré par le LLM (opération asynchrone).")
                + (estimate?(.mentalModelRefresh).map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Rafraîchir", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            if let reason = self.pauseGate?(self.bank) {
                self.actionMessage = reason
                return
            }
            do {
                let r = try await self.client.refreshMentalModel(self.bank, id: m.id)
                self.actionMessage = "Rafraîchissement lancé (\(r.operationId))."
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    /// Charge un modèle mental complet (contenu, question source, déclenchement). Lecture seule, sans appel LLM.
    public func loadMentalModel(_ id: String) async {
        if mentalModelDetail.value?.id != id { mentalModelDetail = .loading }
        do { mentalModelDetail = .loaded(try await client.mentalModel(bank, id: id)) } catch is CancellationError {} catch {
            mentalModelDetail = .failed(error.userMessage)
        }
    }

    /// Quand le modèle mental se rafraîchit tout seul, en clair.
    public static func refreshPolicy(_ t: MentalModelTriggerOutput?) -> String {
        guard let t else { return "À la main seulement" }
        var parts: [String] = []
        if t.refreshAfterConsolidation { parts.append("après chaque consolidation") }
        if let cron = t.refreshCron, !cron.isEmpty { parts.append("selon l'horaire « \(cron) »") }
        guard !parts.isEmpty else { return "À la main seulement" }
        return "Automatique : " + parts.joined(separator: " et ")
    }

    public func requestDeleteMentalModel(_ m: MentalModelResponse) {
        // Le serveur distingue les pages de connaissance des modèles mentaux autonomes : chacun garde son nom.
        let page = m.isKnowledgePage == true
        confirmation = ConfirmationRequest(
            title: page ? "Supprimer la page de connaissance « \(m.name) » ?" : "Supprimer le modèle mental « \(m.name) » ?",
            message: "Son contenu et son historique sont supprimés.",
            confirmTitle: "Supprimer"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.deleteMentalModel(self.bank, id: m.id)
                self.actionMessage = page ? "Page de connaissance supprimée." : "Modèle mental supprimé."
                if self.mentalModelDetail.value?.id == m.id { self.mentalModelDetail = .idle }
                await self.loadMentalModels()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    // MARK: Export / clone / import

    /// Export complet (archive ZIP asynchrone) : attend l'opération puis télécharge l'archive.
    /// Intervalle de sondage des opérations (raccourci dans les tests).
    @ObservationIgnored var pollInterval: Duration = .seconds(2)

    func exportArchiveForTests() async {
        pollInterval = .milliseconds(10)
        await exportArchive()
    }

    public func exportArchive(includeData: Bool = true, includeConfig: Bool = true, includeHistory: Bool = false) async {
        longTask = "Export en cours…"
        defer { longTask = nil }
        do {
            let sub = try await client.exportBank(
                bank, includeData: includeData, includeBankConfig: includeConfig, includeHistory: includeHistory)
            let done = try await OperationWaiter.wait(client: client, bank: bank, operationID: sub.operationId, interval: pollInterval) { [weak self] s in
                self?.longTask = "Export : \(s.progress?.stage ?? s.status)…"
            }
            let target = OperationWaiter.downloadTarget(done)
            longTask = "Téléchargement de l'archive…"
            let data: Data
            if let url = target.url { data = try await client.downloadFile(url: url) } else if let key = target.key {
                data = try await client.downloadFile(key: key)
            } else {
                throw HindsightError.refused("L'export est terminé mais le serveur n'indique pas où télécharger l'archive.")
            }
            exported = ExportedFile(filename: target.filename ?? "\(bank)-export.zip", data: data)
            actionMessage = "Archive prête (\(Format.bytes(data.count)))."
        } catch {
            actionMessage = "Échec de l'export : \(error.userMessage)"
        }
    }

    /// Modèle de banque (configuration, modèles mentaux, directives) en JSON.
    public func exportTemplate() async {
        do {
            let m = try await client.exportTemplate(bank)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            exported = ExportedFile(filename: "\(bank)-template.json", data: try enc.encode(m))
        } catch {
            actionMessage = "Échec : \(error.userMessage)"
        }
    }

    public func requestClone(targetBankID: String, includeData: Bool = true, includeConfig: Bool = true, includeHistory: Bool = false) {
        let target = targetBankID.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        guard target != bank else {
            actionMessage = "Le clone doit porter un nouvel identifiant."
            return
        }
        confirmation = ConfirmationRequest(
            title: "Cloner « \(bank) » vers « \(target) » ?",
            message: "Une nouvelle banque est créée (elle ne doit pas exister). Sans appel LLM : faits ré-indexés, entités résolues à nouveau."
                + (includeConfig ? " Attention : la configuration copiée inclut les webhooks de la banque source." : ""),
            confirmTitle: "Cloner", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            self.longTask = "Clonage…"
            defer { self.longTask = nil }
            do {
                let sub = try await self.client.cloneBank(
                    self.bank, targetBankID: target, includeData: includeData, includeBankConfig: includeConfig,
                    includeHistory: includeHistory)
                _ = try await OperationWaiter.wait(client: self.client, bank: self.bank, operationID: sub.operationId, interval: pollInterval) { [weak self] s in
                    self?.longTask = "Clonage : \(s.progress?.stage ?? s.status)…"
                }
                self.actionMessage = "Banque « \(target) » créée."
                await self.onBanksChanged?()
            } catch { self.actionMessage = "Échec du clonage : \(error.userMessage)" }
        }
    }

    /// Import d'une archive ZIP. `restore` crée `target` (qui ne doit pas exister) ; `merge` ajoute à cette banque.
    public func requestImportArchive(data: Data, filename: String, merge: Bool, target: String?, conflict: String = "skip") {
        let t = target?.trimmingCharacters(in: .whitespaces)
        confirmation = ConfirmationRequest(
            title: merge ? "Fusionner l'archive dans « \(bank) » ?" : "Restaurer l'archive dans une nouvelle banque ?",
            message: merge
                ? "Les documents de l'archive sont ajoutés. Documents déjà présents : \(conflict == "replace" ? "REMPLACÉS" : conflict == "new-id" ? "importés sous un nouvel identifiant" : "ignorés")."
                : "La banque « \(t?.isEmpty == false ? t! : "(id de l'archive)") » sera créée ; elle ne doit pas exister.",
            confirmTitle: merge ? "Fusionner" : "Restaurer", severity: merge && conflict == "replace" ? .destructive : .normal
        ) { [weak self] in
            guard let self else { return }
            self.longTask = "Import…"
            defer { self.longTask = nil }
            do {
                let sub = try await self.client.importBankArchive(
                    self.bank, archive: data, filename: filename, mode: merge ? "merge" : "restore",
                    targetBankID: merge ? nil : (t?.isEmpty == false ? t : nil), documentConflict: conflict)
                _ = try await OperationWaiter.wait(client: self.client, bank: self.bank, operationID: sub.operationId, interval: pollInterval) { [weak self] s in
                    self?.longTask = "Import : \(s.progress?.stage ?? s.status)…"
                }
                self.actionMessage = "Import terminé."
                await self.onBanksChanged?()
            } catch { self.actionMessage = "Échec de l'import : \(error.userMessage)" }
        }
    }

    /// Valide un modèle JSON (dry run) ; l'application demande ensuite une confirmation.
    public func validateTemplate(_ data: Data) async {
        templateDryRun = nil
        pendingTemplate = nil
        do {
            let m = try JSONDecoder().decode(BankTemplateManifest.self, from: data)
            templateDryRun = try await client.importTemplate(bank, manifest: m, dryRun: true)
            pendingTemplate = m
        } catch let e as DecodingError {
            actionMessage = "Fichier de modèle invalide : \(HindsightClient.describe(e))"
        } catch {
            actionMessage = "Échec de la validation : \(error.userMessage)"
        }
    }

    public func requestApplyTemplate() {
        guard let m = pendingTemplate, let dry = templateDryRun else { return }
        let parts = [
            dry.configApplied ? "configuration" : nil,
            dry.mentalModelsCreated.isEmpty ? nil : "\(dry.mentalModelsCreated.count) modèle(s) mental(aux) créés",
            dry.mentalModelsUpdated.isEmpty ? nil : "\(dry.mentalModelsUpdated.count) mis à jour",
            dry.directivesCreated.isEmpty ? nil : "\(dry.directivesCreated.count) directive(s) créée(s)",
            dry.directivesUpdated.isEmpty ? nil : "\(dry.directivesUpdated.count) mise(s) à jour",
        ].compactMap { $0 }
        confirmation = ConfirmationRequest(
            title: "Appliquer le modèle à « \(bank) » ?", message: "Effet prévu : " + (parts.isEmpty ? "aucun changement" : parts.joined(separator: ", ")) + ".",
            confirmTitle: "Appliquer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.importTemplate(self.bank, manifest: m, dryRun: false)
                self.actionMessage = "Modèle appliqué."
                self.templateDryRun = nil
                self.pendingTemplate = nil
                await self.reload()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    // MARK: Zone dangereuse (identifiant de banque à retaper)

    public func requestClearObservations() {
        confirmation = ConfirmationRequest(
            title: "Effacer toutes les observations de « \(bank) » ?",
            message: "Les faits sont conservés ; les observations seront recréées par une nouvelle consolidation (appels LLM).",
            confirmTitle: "Effacer les observations", requiredText: bank
        ) { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.client.clearObservations(self.bank)
                self.actionMessage = "\(r.deletedCount ?? 0) observation(s) effacée(s)."
                // Le nombre de faits affiché pour la banque inclut les observations.
                await self.onBanksChanged?()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    /// `type` : world, experience, observation, ou nil pour tous les faits.
    public func requestDeleteMemories(type: String?) {
        confirmation = ConfirmationRequest(
            title: type.map { "Supprimer tous les faits « \($0) » de « \(bank) » ?" } ?? "Supprimer TOUS les faits de « \(bank) » ?",
            message: "Irréversible. Les documents restent, mais leurs faits disparaissent. Exportez la banque d'abord.",
            confirmTitle: "Supprimer", requiredText: bank
        ) { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.client.deleteAllMemories(self.bank, type: type)
                self.actionMessage = "\(r.deletedCount ?? 0) fait(s) supprimé(s)."
                await self.onBanksChanged?()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }

    public func requestDeleteBank() {
        confirmation = ConfirmationRequest(
            title: "Supprimer définitivement la banque « \(bank) » ?",
            message: "Faits, documents, entités, observations, configuration : tout est supprimé, sans retour possible. Exportez-la d'abord.",
            confirmTitle: "Supprimer la banque", requiredText: bank
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.deleteBank(self.bank)
                if let onAppMessage = self.onAppMessage { onAppMessage("Banque supprimée.") } else { self.actionMessage = "Banque supprimée." }
                await self.onBanksChanged?()
            } catch { self.actionMessage = "Échec : \(error.userMessage)" }
        }
    }
}
