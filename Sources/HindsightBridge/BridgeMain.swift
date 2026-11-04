import AppKit
import Foundation
import HindsightAPI
import HindsightCore

/// Protocole JSON Lines privé entre Tauri et le moteur Swift. Aucun serveur local ni accès HTTP arbitraire.
@main
struct BridgeMain {
    @MainActor static func main() async {
        let bridge = DesktopBridge()
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let bytes = line.data(using: .utf8), bytes.count <= 16_000_000 else { continue }
                var id: Any = NSNull()
                let reply: [String: Any]
                do {
                    guard let request = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                          let command = request["command"] as? String else { throw BridgeFailure("Requête invalide.") }
                    id = request["id"] ?? NSNull()
                    let result = try await bridge.handle(command, request["args"] as? [String: Any] ?? [:])
                    reply = ["id": id, "result": result]
                } catch {
                    reply = ["id": id, "error": SecretMasker.mask(error.localizedDescription)]
                }
                // Ordre des clés indifférent pour la coque : pas de tri sur des réponses de plusieurs mégaoctets.
                if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.fragmentsAllowed]) {
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data([10]))
                }
            }
        } catch { /* La fermeture de la coque termine le pont. */ }
    }
}

struct BridgeFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private protocol WireOptional { var wrapped: Any? { get } }
extension Optional: WireOptional { fileprivate var wrapped: Any? { map { $0 as Any } } }
private let wireDates = ISO8601DateFormatter()
private let wireEncoder = JSONEncoder()

/// Les modèles API gardent leurs CodingKeys ; les valeurs Core sont projetées en objets d'affichage.
/// Seules des valeurs explicitement choisies ci-dessous sont sérialisées, jamais un ViewModel complet.
func wire<T>(_ value: T) -> Any {
    let boxed: Any = value
    // Optionnels et types Swift simples : même résultat que l'aller-retour JSONEncoder → JSONSerialization,
    // sans l'encodeur et l'analyseur créés pour chaque champ. Les objets Foundation suivent le chemin général.
    if let optional = boxed as? WireOptional { return optional.wrapped.map { wire($0) } ?? NSNull() }
    let kind = type(of: boxed)
    if kind == String.self || kind == Bool.self || kind == Int.self { return boxed }
    if kind == Double.self, (boxed as! Double).isFinite { return boxed }
    if let date = value as? Date { return wireDates.string(from: date) }
    if let url = value as? URL { return url.path }
    if value is NSNull { return NSNull() }
    if let data = value as? Data { return data.base64EncodedString() }
    if let encodable = value as? any Encodable,
       let data = try? wireEncoder.encode(encodable),
       let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) { return result }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional { return mirror.children.first.map { wire($0.value) } ?? NSNull() }
    if mirror.displayStyle == .collection || mirror.displayStyle == .set { return mirror.children.map { wire($0.value) } }
    if mirror.displayStyle == .dictionary {
        var output: [String: Any] = [:]
        for child in mirror.children {
            let pair = Array(Mirror(reflecting: child.value).children)
            if pair.count == 2, let key = pair[0].value as? String { output[key] = wire(pair[1].value) }
        }
        return output
    }
    if mirror.displayStyle == .struct || mirror.displayStyle == .tuple {
        var output: [String: Any] = [:]
        for child in mirror.children { if let label = child.label { output[label] = wire(child.value) } }
        return output
    }
    return String(describing: value)
}

@MainActor
final class DesktopBridge {
    let app: AppModel
    var ownConfirmation: ConfirmationRequest?
    var section = "sources"
    var note: String?
    var workspace: MemoryWorkspace!
    var updater: AppUpdateViewModel!
    var updateTask: Task<Void, Never>?
    /// Installation ou démarrage du modèle de décision local : plusieurs minutes, hors du fil des commandes.
    var decisionTask: Task<Void, Never>?
    var graphMode = GraphViewModel.Mode.entities
    var graphLimit = 300
    var autoSyncConfirmation: UUID?
    var catalogCache: (stamp: [String], header: Any)?
    let testing = ProcessInfo.processInfo.environment["HINDSIGHT_DESKTOP_TEST_MODE"] == "1"

    init() {
        let defaults = UserDefaults(suiteName: "local.hindsight.desktop")!
        // Préférences indépendantes : le premier lancement n'altère pas celles de SwiftUI.
        let settings: SettingsStore = testing ? InMemorySettingsStore() : UserDefaultsSettingsStore(defaults: defaults)
        let ledgerURL = UsageLedger.defaultURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("HindsightDesktop/usage-ledger.json")
        let env = ProcessInfo.processInfo.environment
        let identity = AppInfo(version: env["HINDSIGHT_DESKTOP_VERSION"] ?? "dev", build: "Tauri", commit: env["HINDSIGHT_DESKTOP_COMMIT"], sourceRepository: env["HINDSIGHT_DESKTOP_SOURCE"], bundlePath: env["HINDSIGHT_DESKTOP_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 })
        app = AppModel(settings: settings, appInfo: identity, ledger: testing ? nil : UsageLedger(url: ledgerURL), automaticActions: false)
        updater = AppUpdateViewModel(settings: settings, appInfo: identity, tauri: true)
        workspace = MemoryWorkspace(folder: app.memoryFolder, client: { [unowned self] in self.app.client }, bank: { [unowned self] in self.app.selectedBankID })
        workspace.pauseGate = app.pause.gate
        // Les sessions OAuth ne sont lues que sur demande explicite, après confirmation.
    }

    func session() throws -> BankSession {
        guard let session = app.session else { throw BridgeFailure("Connectez le serveur et choisissez une banque.") }
        return session
    }

    func handle(_ command: String, _ p: [String: Any]) async throws -> Any {
        func str(_ key: String, _ fallback: String = "") -> String { p[key] as? String ?? fallback }
        func strings(_ key: String) -> [String] { p[key] as? [String] ?? [] }
        switch command {
        case "bootstrap", "snapshot": break
        case "connect":
            await app.connect()
            await connected()
        case "server.url":
            clearConfirmations()
            guard await app.applyServerURL(str("url")) else { throw BridgeFailure(app.serverURLNotice ?? "Adresse invalide.") }
            await connected()
        case "updates.check":
            if updater.isWorking || updateTask != nil { break }
            if let path = p["path"] as? String { updater.selectRepository(path) }
            updateTask = Task { @MainActor in await self.updater.check(); self.updateTask = nil }
        case "updates.releaseReady":
            let ready = !updater.isWorking && updateTask == nil
                && !app.memoryFolder.collecting && !app.memoryFolder.importing
                && !app.localDecision.isBusy && decisionTask == nil
                && app.coverage.sending == nil && app.projectSync.running == nil
            return ["releaseUpdateReady": ready]
        case "updates.install":
            guard updateTask == nil, !updater.isWorking else { throw BridgeFailure("Une mise à jour est en cours.") }; updater.requestUpdate()
        case "updates.rebuild":
            guard updateTask == nil, !updater.isWorking else { throw BridgeFailure("Une mise à jour est en cours.") }
            if let path = p["path"] as? String { updater.selectRepository(path) }
            updater.requestRebuild()
        case "updates.relaunch":
            guard updater.phase == .readyToRelaunch else { throw BridgeFailure("Aucune mise à jour installée à relancer.") }
            return ["relaunch": true]
        case "bank.select":
            guard app.banks.contains(where: { $0.bankId == str("id") }) else { throw BridgeFailure("Banque inconnue.") }
            clearConfirmations()
            app.selectBank(str("id"))
            if !testing { await app.services.estimator.refreshProfile(bank: str("id")) }
        case "bank.create": app.requestCreateBank(id: str("id"), name: str("name"), mission: str("mission"))
        case "bank.rename": app.bankManagement.requestRename(try session().bank, name: str("name"))
        case "bank.merge": app.bankManagement.requestMerge(source: str("source"), into: str("target"))
        case "section":
            section = str("section", "sources")
            try await load(section, p)
        case "folder.choose":
            let path = str("path")
            guard path.hasPrefix("/") else { throw BridgeFailure("Choisissez un dossier absolu.") }
            app.memoryFolder.choose(URL(fileURLWithPath: path))
            await workspace.refresh()
        case "folder.refresh": await workspace.refreshSources()
        case "folder.prepare": await workspace.prepareSend()
        case "folder.enabled":
            if let ids = p["ids"] as? [String] { try workspace.setEnabled(ids, enabled: p["enabled"] as? Bool ?? false) }
            else { try workspace.setEnabled(str("id"), enabled: p["enabled"] as? Bool ?? false) }
        case "folder.retry": workspace.requestRetry(str("id"))
        case "folder.remove": workspace.requestRemove(str("id"))
        case "folder.link": try workspace.link(str("id"), document: str("document"))
        case "folder.stored": return ["text": try await workspace.storedText(str("id"))]
        case "folder.collect": app.memoryFolder.requestCollection()
        case "folder.import": app.memoryFolder.requestImport(paths: strings("paths"), project: str("project"))
        case "folder.open":
            let url = try sourceURL(str("path"))
            guard ["pdf", "tex", "md"].contains(url.pathExtension.lowercased()) else { throw BridgeFailure("Format de document non autorisé.") }
            if !testing { NSWorkspace.shared.open(url) }
        case "folder.reveal":
            if let url = app.memoryFolder.repository { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path) }
        case "folder.read": return try readSource(str("path"))
        case "external.open":
            guard let url = URL(string: str("url")), ["https", "codex", "claude"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { throw BridgeFailure("Lien non autorisé.") }
            NSWorkspace.shared.open(url)
        case "search":
            let s = try session()
            let search = s.search
            search.query = str("query")
            search.mode = SearchViewModel.Mode(rawValue: str("mode", "recall")) ?? .recall
            search.budget = str("budget", "mid")
            search.prune = p["prune"] as? Bool
            search.dedup = p["dedup"] as? Bool
            search.filter = FactFilter()
            search.filter.tags = strings("tags")
            search.filter.types = Set(strings("types")).intersection(FactFilter.allTypes)
            search.filter.task = str("task").isEmpty ? nil : str("task")
            search.filter.start = HSDate.parse(p["start"] as? String)
            search.filter.end = HSDate.parse(p["end"] as? String)
            if !str("entity").isEmpty {
                guard let entity = s.catalog.entities.first(where: { $0.id == str("entity") }) else { throw BridgeFailure("Entité inconnue ; rechargez les filtres.") }
                search.filter.entity = EntityRef(id: entity.id, name: entity.canonicalName)
            }
            if search.mode == .reflect {
                let query = search.query, budget = search.budget, filter = search.filter
                ownConfirmation = ConfirmationRequest(title: "Interroger la mémoire ?", message: "Le modèle rédigera une réponse à partir des faits de cette banque.\n\n" + (search.reflectEstimate?.summary ?? "Cette action consomme des jetons ; estimation indisponible.") + "\n\n" + query, confirmTitle: "Générer la réponse", severity: .normal) {
                    search.query = query; search.budget = budget; search.filter = filter; search.mode = .reflect
                    await search.run()
                }
            } else { await search.run() }
        case "search.more": await (try session()).search.loadMore()
        case "fact.open": return wire(try await app.client.memory(try session().bank, id: str("id")))
        case "document.open":
            let s = try session()
            let reader = s.documents.open(documentID: str("id"))
            await reader.load(); await reader.loadFacts()
            return readerSnapshot(reader)
        case "document.close": (try session()).documents.closeReader()
        case "attachment.load":
            let s = try session()
            guard let attachment = s.documents.reader?.attachments.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Pièce jointe inconnue.") }
            let asset = try await s.attachmentLoader.load(attachment)
            guard asset.data.count <= 12_000_000 else { throw BridgeFailure("Cette pièce jointe dépasse 12 Mo.") }
            return ["base64": asset.data.base64EncodedString(), "mediaType": attachment.mediaType, "id": attachment.id]
        case "document.delete": (try session()).documents.reader?.requestDelete()
        case "document.reprocess": (try session()).documents.reader?.requestReprocess()
        case "document.tags": (try session()).documents.reader?.requestUpdateTags(strings("tags"))
        case "document.scope": (try session()).documents.reader?.requestUpdateScope(str("scope"))
        case "documents.more": await (try session()).documents.loadMore()
        case "model.open":
            let admin = try session().admin
            await admin.loadMentalModel(str("id"))
            return ["model": wire(admin.mentalModelDetail.value), "error": wire(admin.mentalModelDetail.errorMessage)]
        case "model.create": (try session()).admin.requestCreateMentalModel(name: str("name"), sourceQuery: str("query"), tags: strings("tags"))
        case "model.refresh", "model.delete":
            let admin = try session().admin
            guard let model = admin.mentalModels.value?.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Synthèse inconnue.") }
            if command == "model.refresh" { admin.requestRefreshMentalModel(model) } else { admin.requestDeleteMentalModel(model) }
        case "operations.more": await (try session()).operations.loadMore()
        case "operation.open":
            let operations = try session().operations
            await operations.select(str("id"))
            return wire(operations.selectedDetail.value)
        case "operation.retry", "operation.cancel", "operation.delete", "operation.now":
            let operations = try session().operations
            guard let row = operations.rows.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Opération inconnue.") }
            switch command {
            case "operation.retry": operations.requestRetry(row)
            case "operation.cancel": operations.requestCancel(row)
            case "operation.now": operations.requestRunNow(row)
            default: operations.requestDelete(row)
            }
        case "operations.retryFailed": await (try session()).operations.requestRetryAllFailed()
        case "operations.consolidate": (try session()).operations.requestConsolidation()
        case "operations.recover": (try session()).operations.requestRecoverConsolidation()
        case "pause.pause", "pause.resume":
            let bank = p["all"] as? Bool == true ? nil : try session().bank
            ownConfirmation = ConfirmationRequest(title: command == "pause.pause" ? "Mettre les traitements en pause ?" : "Reprendre les traitements ?", message: bank.map { "Banque : \($0)." } ?? "Toutes les banques sont concernées.", confirmTitle: command == "pause.pause" ? "Mettre en pause" : "Reprendre", severity: .normal) { [app] in
                if command == "pause.pause" { await app.pause.pause(bank: bank, reason: "Pause manuelle depuis Hindsight Desktop") }
                else { await app.pause.resume(bank: bank) }
            }
        case "pause.freeze": app.pause.requestFreeze()
        case "pause.unfreeze": app.pause.requestUnfreeze()
        case "pause.drain": await app.pause.requestDrain(bank: p["all"] as? Bool == true ? nil : try session().bank)
        case "subscription.refresh":
            ownConfirmation = ConfirmationRequest(
                title: "Vérifier les quotas d'abonnement ?",
                message: "Ce relevé ponctuel lit la session Codex dans ~/.codex/auth.json et, si vous l'autorisez, la session Claude Code dans le Trousseau. Les jetons servent uniquement à interroger chatgpt.com et api.anthropic.com ; ils ne sont ni enregistrés par l'app, ni envoyés au serveur Hindsight. Aucun appel à un modèle. Aucun relevé automatique n'est activé.",
                confirmTitle: "Vérifier les quotas"
            ) { [weak self] in
                guard let self, !self.testing else { return }
                let reading = await SubscriptionUsage.fetch()
                self.app.consumption.apply(reading, claudeCache: SubscriptionUsage.claudeCache())
            }
        case "budget.save":
            let budget = try decode(ConsumptionBudgets.self, p["budget"] ?? [:])
            let amounts = [budget.dailyDollars, budget.codexQuotaPercent].compactMap { $0 }
            guard amounts.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= ConsumptionBudgets.maxAmount }),
                  (budget.codexQuotaPercent ?? 0) <= 100, budget.warnAt > 0, budget.warnAt <= 1,
                  budget.subscriptions.values.allSatisfy({ [$0.tokens5h, $0.tokensWeek].compactMap { $0 }.allSatisfy { $0 > 0 && Double($0) <= ConsumptionBudgets.maxAmount } }) else { throw BridgeFailure("Les plafonds doivent être des montants positifs valides.") }
            let description = "Budget quotidien : \(budget.dailyDollars.map { ConsumptionBudgets.amountText($0) + " USD" } ?? "sans plafond")\nQuota Codex : \(budget.codexQuotaPercent.map { ConsumptionBudgets.amountText($0) + " % consommés" } ?? "sans plafond")\n" + budget.subscriptions.sorted(by: { $0.key < $1.key }).map { "\($0.key) : \($0.value.tokens5h.map(String.init) ?? "—") jetons sur 5 h ; \($0.value.tokensWeek.map(String.init) ?? "—") sur 7 jours" }.joined(separator: "\n") + "\nAu dépassement : \(budget.effectiveAction.title)."
            ownConfirmation = ConfirmationRequest(title: "Enregistrer les plafonds ?", message: description, confirmTitle: "Enregistrer", severity: .normal) { [app] in app.consumption.budgets = budget }
        case "prices.save":
            let book = try decode(PriceBook.self, p["prices"] ?? [:])
            ownConfirmation = ConfirmationRequest(title: "Modifier la grille tarifaire ?", message: "Les estimations de coût utiliseront cette grille dans Hindsight Desktop.", confirmTitle: "Enregistrer", severity: .normal) { [app] in app.services.estimator.priceBook = book }
        case "memory.save", "memory.trial":
            let memory = try session().memoryDesign
            // La projection inverse passe par les clés de configuration officielles.
            let updates = try decode([String: JSONValue].self, p["config"] ?? [:])
            let config = try await app.client.bankConfig(try session().bank)
            memory.draft = MemoryDesign(config: config.config.merging(updates) { _, new in new })
            if command == "memory.trial" { memory.sampleText = str("sample"); memory.requestTrial() }
            else { memory.requestSave() }
        case "memory.reset": (try session()).memoryDesign.requestResetAll()
        case "admin.override":
            guard (try session()).admin.requestSetOverride(key: str("key"), rawJSON: str("value")) else { throw BridgeFailure("Valeur invalide.") }
        case "admin.reset": (try session()).admin.requestResetConfig()
        case "directive.create": (try session()).admin.requestCreateDirective(name: str("name"), content: str("content"))
        case "directive.delete", "directive.update":
            let admin = try session().admin
            guard let d = admin.directives.value?.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Directive inconnue.") }
            if command == "directive.delete" { admin.requestDeleteDirective(d) }
            else { admin.requestUpdateDirective(d, name: p["name"] as? String, content: p["content"] as? String, isActive: p["active"] as? Bool) }
        case "admin.clone": (try session()).admin.requestClone(targetBankID: str("target"))
        case "admin.export", "admin.template":
            let admin = try session().admin
            if command == "admin.export" { await admin.exportArchive() } else { await admin.exportTemplate() }
            guard let file = admin.exported else { throw BridgeFailure(admin.actionMessage ?? "Export impossible.") }
            return ["filename": file.filename, "base64": file.data.base64EncodedString()]
        case "admin.import":
            guard let data = Data(base64Encoded: str("base64")) else { throw BridgeFailure("Archive invalide.") }
            (try session()).admin.requestImportArchive(data: data, filename: str("filename"), merge: true, target: try session().bank)
        case "admin.template.validate":
            guard let data = Data(base64Encoded: str("base64")) else { throw BridgeFailure("Modèle invalide.") }
            await (try session()).admin.validateTemplate(data)
        case "admin.template.apply": (try session()).admin.requestApplyTemplate()
        case "admin.clearObservations": (try session()).admin.requestClearObservations()
        case "admin.deleteMemories": (try session()).admin.requestDeleteMemories(type: p["type"] as? String)
        case "admin.deleteBank": (try session()).admin.requestDeleteBank()
        case "audit.enable": (try session()).audit.requestEnableAudit()
        case "audit.disable": (try session()).audit.requestDisableAudit()
        case "graph.select":
            let graph = (try session()).graph
            guard graph.index(of: str("id")) != nil else { throw BridgeFailure("Ce nœud ne fait pas partie du graphe chargé.") }
            await graph.select(str("id"))
        case "server.script": app.serverSettings.scriptPath = str("path"); await app.serverSettings.load()
        case "server.field":
            guard str("name").range(of: "^HINDSIGHT_API_[A-Z0-9_]+$", options: .regularExpression) != nil else { throw BridgeFailure("Nom de réglage Hindsight invalide.") }
            app.serverSettings.setValue(str("name"), p["value"] as? String)
        case "server.variable":
            guard app.serverSettings.addVariable(str("name"), str("value")) else { throw BridgeFailure("Nom de variable invalide.") }
        case "server.provider": app.serverSettings.selectProvider(str("provider"), forRole: str("role"))
        case "server.decision", "server.reranker":
            let settings = app.serverSettings!, source = str("source")
            // Un serveur 1.1.0 refuserait de démarrer avec un fournisseur `hindsight`.
            if source != "off", !(command == "server.reranker" && source == "local"),
               !ServerCapabilities.is120(app.connection.version?.apiVersion) {
                throw BridgeFailure("Serveur Hindsight 1.2.0 requis pour les modèles Hindsight.")
            }
            switch (command, source) {
            case ("server.decision", "cloud"): settings.useCloudDecisionModel()
            case ("server.decision", "local"):
                guard app.localDecision.phase == .running else { throw BridgeFailure("Installez et démarrez d'abord le modèle de décision sur ce Mac.") }
                settings.useLocalDecisionModel(apiKey: try app.localDecision.apiKey())
            case ("server.decision", "off"): settings.disableDecisionModel()
            case ("server.reranker", "cloud"): settings.useCloudReranker()
            case ("server.reranker", "local"): settings.useLocalHindsightReranker()
            default: throw BridgeFailure("Choix inconnu.")
            }
        case "decision.install": app.localDecision.requestInstall()
        case "decision.start":
            if decisionTask == nil { decisionTask = Task { @MainActor in await self.app.localDecision.start(); self.decisionTask = nil } }
        case "decision.stop": app.localDecision.requestStop()
        case "decision.uninstall": app.localDecision.requestUninstall()
        case "server.revert": app.serverSettings.revertAll()
        case "server.save": app.serverSettings.requestSave()
        case "server.restore":
            guard let backup = app.serverSettings.backups.first(where: { $0.url.path == str("path") }) else { throw BridgeFailure("Sauvegarde inconnue.") }
            app.serverSettings.requestRestore(backup)
        case "account.connect":
            guard let account = LLMAccount(rawValue: str("account")) else { throw BridgeFailure("Compte inconnu.") }
            let context = app.serverSettings.connectionContext
            let message = account == .hindsightCloud
                ? "hindsight-admin ouvrira Hindsight Cloud dans le navigateur : connectez-vous (ou créez un compte), choisissez une organisation et approuvez. La clé créée est enregistrée dans ~/.hindsight/cloud/credentials.json, lisible par vous seul, et ses appels sont facturés sur les crédits de l'organisation."
                : "Le client officiel ouvrira une connexion à votre compte. La session reste dans le stockage de ce client sur ce Mac."
            ownConfirmation = ConfirmationRequest(title: "Connecter \(account.title) ?", message: message, confirmTitle: "Se connecter", severity: .normal) { [app] in app.serverSettings.connections.connect(account, context: context) }
        case "account.disconnect":
            guard let account = LLMAccount(rawValue: str("account")), account.canDisconnect else { throw BridgeFailure("Compte inconnu.") }
            let context = app.serverSettings.connectionContext
            ownConfirmation = ConfirmationRequest(title: "Se déconnecter de \(account.title) ?", message: "La clé enregistrée sur ce Mac (~/.hindsight/cloud/credentials.json) sera effacée : les modèles Hindsight Cloud du serveur n'auront plus de clé. Elle reste valide jusqu'à sa révocation sur \(HindsightInference.apiKeysPage).", confirmTitle: "Se déconnecter") { [app] in await app.serverSettings.connections.disconnect(account, context: context) }
        case "service.start": app.service.requestStart()
        case "service.stop": app.service.requestStop()
        case "service.restart": app.service.requestRestart()
        case "service.install": app.service.requestInstall(startAtLogin: p["atLogin"] as? Bool ?? false)
        case "service.uninstall": app.service.requestUninstall()
        case "service.atLogin": app.service.setStartAtLogin(p["enabled"] as? Bool ?? false)
        case "coverage.add": await app.coverage.addRoots(strings("paths").map { URL(fileURLWithPath: $0) })
        case "coverage.removeRoot", "coverage.auto", "coverage.allFiles":
            guard let root = app.coverage.roots.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Dossier inconnu.") }
            if command == "coverage.removeRoot" { await app.coverage.removeRoot(root) }
            else if command == "coverage.auto" {
                app.coverage.requestAutoSync(p["enabled"] as? Bool ?? false, for: root)
                autoSyncConfirmation = app.coverage.confirmation?.id
            }
            else { await app.coverage.setAllFiles(p["enabled"] as? Bool ?? false, for: root) }
        case "coverage.send": app.coverage.selection = Set(strings("ids")); await app.coverage.requestSend()
        case "coverage.remove": app.coverage.selection = Set(strings("ids")); app.coverage.requestRemoveSelection()
        case "sync.script": app.projectSync.setScript(str("path"))
        case "sync.run": await app.projectSync.requestSync(ids: strings("ids"))
        case "hermes.preview": await app.codexImport.showPreview(str("id"))
        case "hermes.plan":
            app.codexImport.selection = Set(strings("ids"))
            app.codexImport.targetBankID = try session().bank
            await app.codexImport.preparePlan()
        case "hermes.import": app.codexImport.requestImport()
        case "diagnostic.llm":
            let dashboard = try session().dashboard
            await dashboard.loadIfNeeded()
            ownConfirmation = ConfirmationRequest(title: "Tester les modèles du serveur ?", message: "Un court appel sera effectué pour chaque rôle LLM configuré. Cette vérification consomme des jetons.", confirmTitle: "Tester les modèles", severity: .normal) { [weak self] in
                await dashboard.testLLM()
                self?.note = dashboard.llmTestMessage ?? "Test des modèles terminé. Consultez le résultat dans Serveur & modèles."
            }
        case "confirm":
            guard let request = pending().first(where: { $0.id.uuidString == str("id") }), request.isSatisfied(by: str("typed")) else {
                throw BridgeFailure("Cette confirmation a expiré ou le texte saisi ne correspond pas.")
            }
            let workspaceAction = workspace.confirmation?.id == request.id
            let backgroundUpdate = updater.confirmation?.id == request.id
            let backgroundDecision = app.localDecision.confirmation?.id == request.id
            let activateSync = autoSyncConfirmation == request.id
            clearConfirmations()
            if backgroundUpdate { updateTask = Task { @MainActor in await request.perform(); self.updateTask = nil } }
            else if backgroundDecision { decisionTask = Task { @MainActor in await request.perform(); self.decisionTask = nil } }
            else { await request.perform(); if section == "sources" && !workspaceAction { await workspace.refresh() } }
            if activateSync { app.coverage.startAutoSync() }
        case "cancel": clearConfirmations()
        default: throw BridgeFailure("Action inconnue : \(command)")
        }
        return snapshot()
    }

    func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed))
    }

    func connected() async {
        guard app.connection.isConnected, !testing else { return }
        await app.serverSettings.loadIfNeeded()
        if let bank = app.selectedBankID { await app.services.estimator.refreshProfile(bank: bank) }
        app.consumption.start()
    }

    func load(_ name: String, _ p: [String: Any]) async throws {
        if name == "sources" { await workspace.refresh(); return }
        if name == "consumption" {
            await app.consumption.poll()
            await app.consumption.loadServices(serverIs120: ServerCapabilities.is120(app.connection.version?.apiVersion))
            return
        }
        if name == "server" {
            await app.serverSettings.loadIfNeeded(); await app.service.refresh(); await app.localDecision.refresh()
            await app.serverSettings.connections.refresh(app.serverSettings.connectionContext)
            return
        }
        if name == "settings" { return }
        if name == "hermes" { await app.codexImport.scan(); return }
        let s = try session()
        switch name {
        case "dashboard": await s.dashboard.reload()
        case "models", "admin": await s.admin.reload()
        case "documents":
            s.documents.query = p["query"] as? String ?? ""
            s.documents.selectedTags = p["tags"] as? [String] ?? []
            await s.documents.reload()
        case "coverage": await app.coverage.reload()
        case "operations":
            s.operations.statusFilter = OperationsViewModel.StatusFilter(rawValue: p["status"] as? String ?? "all") ?? .all
            await s.operations.reload()
        case "timeline":
            s.timeline.text = p["query"] as? String ?? ""
            s.timeline.maxFacts = 20_000
            await s.timeline.reload()
        case "graph":
            graphMode = GraphViewModel.Mode(rawValue: p["mode"] as? String ?? graphMode.rawValue) ?? .entities
            graphLimit = min(max(p["limit"] as? Int ?? graphLimit, 50), 2000)
            s.graph.mode = graphMode
            s.graph.maxNodes = graphLimit
            s.graph.minCount = 1
            await s.graph.reload(layout: false)
        case "audit": await s.audit.reload(); await s.reads.reload()
        case "memory": await s.memoryDesign.reload()
        case "search": await s.catalog.loadIfNeeded()
        default: throw BridgeFailure("Section inconnue.")
        }
    }

    func pending() -> [ConfirmationRequest] {
        let s = app.session
        return [workspace.confirmation, updater.confirmation, ownConfirmation, app.confirmation, app.memoryFolder.confirmation, app.service.confirmation,
                app.pause.confirmation, app.coverage.confirmation, app.projectSync.confirmation,
                app.serverSettings.confirmation, app.localDecision.confirmation, app.codexImport.confirmation, app.bankManagement.confirmation,
                s?.operations.confirmation, s?.admin.confirmation, s?.memoryDesign.confirmation,
                s?.documents.reader?.confirmation, s?.audit.confirmation].compactMap { $0 }
    }

    func clearConfirmations() {
        workspace.confirmation = nil
        updater.confirmation = nil
        autoSyncConfirmation = nil
        ownConfirmation = nil; app.confirmation = nil; app.memoryFolder.confirmation = nil
        app.service.confirmation = nil; app.pause.confirmation = nil; app.coverage.confirmation = nil
        app.projectSync.confirmation = nil; app.serverSettings.confirmation = nil; app.localDecision.confirmation = nil
        app.codexImport.confirmation = nil; app.bankManagement.confirmation = nil
        app.session?.operations.confirmation = nil; app.session?.admin.confirmation = nil
        app.session?.memoryDesign.confirmation = nil; app.session?.documents.reader?.confirmation = nil
        app.session?.audit.confirmation = nil
    }

    func snapshot() -> [String: Any] {
        var connected = false, error: String?
        if case .connected = app.connection { connected = true }
        if case .failed(let text) = app.connection { error = text }
        let messages = [note, app.bannerError, app.pause.message, app.bankManagement.message,
                        app.service.message, app.serverSettings.actionMessage, app.coverage.actionMessage,
                        app.session?.admin.actionMessage, app.session?.operations.actionMessage,
                        app.session?.memoryDesign.actionMessage, app.session?.documents.reader?.actionMessage,
                        app.codexImport.actionMessage, app.projectSync.actionMessage, app.memoryFolder.importSummary].compactMap { $0 }
        return [
            "app": ["connected": connected, "connectionError": wire(error), "serverURLNotice": wire(app.serverURLNotice), "serverURL": app.serverURL.absoluteString,
                    "version": wire(app.connection.version), "banks": wire(app.banks), "bank": wire(app.selectedBankID),
                    "folder": wire(app.memoryFolder.repository?.path), "paused": wire(app.pause.heldBanks)],
            "updates": updateSnapshot(),
            "section": section, "data": sectionData(), "messages": messages.map { SecretMasker.mask($0) },
            "confirmations": pending().map { ["id": $0.id.uuidString, "title": $0.title, "message": SecretMasker.mask($0.message),
                                               "confirmTitle": $0.confirmTitle, "destructive": $0.severity == .destructive,
                                               "requiredText": wire($0.requiredText)] }
        ]
    }

    func updateSnapshot() -> [String: Any] {
        let state: String, message: String
        switch updater.phase {
        case .idle: state = "idle"; message = "Recherchez les mises à jour ou reconstruisez cette copie."
        case .checking: state = "checking"; message = "Recherche des mises à jour…"
        case .upToDate: state = "current"; message = "Vous utilisez la version à jour."
        case .available: state = "available"; message = "Une mise à jour est disponible."
        case .rebuildAvailable: state = "rebuild"; message = "La copie locale est plus récente que l’app."
        case .working(let text): state = "working"; message = text
        case .readyToRelaunch: state = "ready"; message = "Mise à jour installée. Relancez l’application."
        case .built(let path): state = "built"; message = "Application construite : " + path
        case .failed(let text): state = "failed"; message = text
        }
        return ["state": state, "message": SecretMasker.mask(message), "working": updater.isWorking || updateTask != nil,
                "repository": updater.repositoryPath, "version": updater.appInfo.displayVersion,
                "commits": wire(updater.pending), "dirty": updater.isDirty, "log": updater.log,
                "checkedAt": wire(updater.lastChecked), "remote": wire(updater.remoteURL)]
    }

    func sectionData() -> [String: Any] {
        let s = app.session
        switch section {
        case "sources":
            let folder = app.memoryFolder!
            var catalog: Any = NSNull()
            if let url = folder.catalogURL, let header = catalogHeader(url) { catalog = header }
            if var merged = catalog as? [String: Any] { merged["records"] = workspace.records; catalog = merged }
            else if !workspace.records.isEmpty { catalog = ["records": workspace.records, "sources": [], "projects": []] }
            return ["catalog": catalog, "folder": wire(folder.repository?.path), "error": wire(workspace.error ?? folder.error), "memoryMessage": wire(workspace.message),
                    "canCollect": folder.canCollect, "collecting": folder.collecting, "importing": folder.importing, "output": folder.output]
        case "dashboard":
            return ["snapshot": wire(s?.dashboard.snapshot), "insights": wire(s?.dashboard.insights ?? []), "error": wire(s?.dashboard.state.errorMessage), "partialErrors": wire(s?.dashboard.partialErrors ?? [])]
        case "models", "admin":
            return ["models": wire(s?.admin.mentalModels.value ?? []), "directives": wire(s?.admin.directives.value ?? []),
                    "config": wire(s?.admin.config.value), "error": wire(s?.admin.config.errorMessage), "syncScript": wire(app.projectSync.scriptPath),
                    "modelError": wire(s?.admin.mentalModels.errorMessage), "templateDryRun": wire(s?.admin.templateDryRun)]
        case "search":
            return ["hits": wire(s?.search.hits ?? []), "answer": wire(s?.search.answer), "total": s?.search.total ?? 0,
                    "canLoadMore": s?.search.canLoadMore ?? false, "error": wire(s?.search.state.errorMessage),
                    "entities": wire(s?.catalog.entities ?? []), "tags": wire(s?.catalog.plainTags ?? []), "tasks": wire(s?.catalog.tasks ?? []),
                    "serverIs120": s?.search.serverIs120 ?? false]
        case "documents":
            return ["items": wire(s?.documents.sortedItems ?? []), "total": s?.documents.total ?? 0,
                    "canLoadMore": s?.documents.canLoadMore ?? false, "error": wire(s?.documents.state.errorMessage)]
        case "coverage":
            return ["items": wire(app.coverage.visibleItems), "roots": wire(app.coverage.roots), "error": wire(app.coverage.state.errorMessage), "warnings": app.coverage.warnings]
        case "operations":
            return ["items": wire(s?.operations.rows.map(\.raw) ?? []), "total": s?.operations.total ?? 0,
                    "canLoadMore": s?.operations.canLoadMore ?? false, "error": wire(s?.operations.state.errorMessage),
                    "consultationOnly": s?.operations.consultationOnly ?? false]
        case "consumption":
            let m = app.consumption!
            return ["summary": wire(m.summary), "gauges": wire(m.gauges), "codexQuota": wire(m.codexQuota), "claudeQuota": wire(m.claudeQuota),
                    "events": wire(Array(m.events.suffix(5000))), "queues": wire(m.queues), "budgets": wire(m.budgets),
                    "prices": wire(app.services.estimator.priceBook), "lastPoll": wire(m.lastPoll), "error": wire(m.pollError), "quotaProblems": m.quotaProblems,
                    "services": wire(m.services), "servicesError": wire(m.servicesError)]
        case "timeline":
            // Jusqu'à 20 000 faits : seulement les champs que la chronologie affiche ou filtre, soit 2,5 fois moins
            // de données à sérialiser, transmettre et analyser que le fait complet (contexte, entités, étiquettes…).
            let facts = (s?.timeline.facts ?? []).map { fact -> [String: Any] in
                ["id": fact.id, "text": fact.text, "type": wire(fact.type), "occurredStart": wire(fact.occurredStart),
                 "mentionedAt": wire(fact.mentionedAt), "documentID": wire(fact.documentID)]
            }
            return ["facts": facts, "periods": wire(s?.timeline.bars ?? []), "total": s?.timeline.totalAvailable ?? 0, "truncated": s?.timeline.isTruncated ?? false, "error": wire(s?.timeline.state.errorMessage)]
        case "graph":
            let graph = s?.graph
            let facts = graph?.mode == .facts ? graph?.selectedFact.map { [$0.hit] } ?? [] : graph?.nodeFacts.value ?? []
            return ["mode": graphMode.rawValue, "limit": graphLimit, "nodes": wire(graph?.nodes ?? []), "edges": wire(graph?.edges ?? []),
                    "totalNodes": graph?.serverNodeTotal ?? 0, "totalEdges": graph?.serverEdgeTotal ?? 0,
                    "selectedNodeID": wire(graph?.selectedNodeID), "nodeFacts": wire(facts), "entity": wire(graph?.entityDetail.value),
                    "detailError": wire(graph?.nodeFacts.errorMessage ?? graph?.selectedFact?.detail.errorMessage), "error": wire(graph?.state.errorMessage)]
        case "audit": return ["audit": wire(s?.audit.audit.value ?? []), "traces": wire(s?.audit.llm.value ?? []), "reads": wire(s?.reads.events ?? []), "error": wire(s?.audit.audit.errorMessage), "traceError": wire(s?.audit.llm.errorMessage)]
        case "memory": return ["draft": wire(s?.memoryDesign.draft), "config": wire(s?.admin.config.value), "error": wire(s?.memoryDesign.state.errorMessage), "trial": wire(s?.memoryDesign.trial.value), "trialError": wire(s?.memoryDesign.trial.errorMessage), "problems": s?.memoryDesign.problems ?? [], "serverIs120": s?.memoryDesign.serverIs120 ?? false]
        case "server": return serverSnapshot()
        case "hermes": return ["items": wire(app.codexImport.filteredSessions), "preview": wire(app.codexImport.preview.value), "plan": wire(app.codexImport.plan.value), "error": wire(app.codexImport.scanState.errorMessage), "sendErrors": app.codexImport.sendErrors]
        default: return [:]
        }
    }

    /// Catalogue lu sans ses enregistrements (remplacés par ceux de l'espace mémoire), relu seulement quand
    /// le fichier change de taille, de date de modification ou d'inode, au lieu de 3 Mo analysés à chaque réponse.
    func catalogHeader(_ url: URL) -> Any? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size < 30_000_000 else { return nil }
        let stamp = [url.path, String(size), String(describing: attributes[.modificationDate]), String(describing: attributes[.systemFileNumber])]
        if let cached = catalogCache, cached.stamp == stamp { return cached.header }
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var header: Any = json
        if var object = json as? [String: Any] { object["records"] = nil; header = object }
        catalogCache = (stamp, header)
        return header
    }

    func serverSnapshot() -> [String: Any] {
        let settings = app.serverSettings!, service = app.service!
        func fields(_ values: [ServerSettingsViewModel.FieldState]) -> [[String: Any]] {
            values.map { ["name": $0.name, "label": $0.label, "help": $0.help, "secret": $0.isSecret,
                          "value": wire($0.isSecret ? nil : $0.value), "configured": $0.value != nil, "changed": $0.isChanged, "dynamic": $0.isDynamic] }
        }
        return ["scriptPath": settings.scriptPath, "hasChanges": settings.hasChanges, "needsRestart": settings.needsRestart,
                "hindsightModels": hindsightModelsSnapshot(),
                "roles": settings.roles.map { ["id": $0.role.id, "title": $0.role.title, "effective": $0.effective, "fields": fields($0.fields), "models": wire(settings.modelChoices(forRole: $0.role.id))] },
                "otherVariables": fields(settings.otherVariables), "warnings": settings.actionableWarnings,
                "accounts": LLMAccount.allCases.map { ["id": $0.rawValue, "title": $0.title, "status": settings.connections.status($0).summary,
                                                       "connected": settings.connections.status($0).isConnected, "canDisconnect": $0.canDisconnect] },
                // Lien de secours si le client n'a pas pu ouvrir le navigateur ; il ne contient aucune clé.
                "connectingAccount": wire(settings.connections.activeAccount?.rawValue),
                "authorizationURL": wire(settings.connections.authorizationURL?.absoluteString),
                "diff": wire(settings.compactDiff), "backups": wire(settings.backups), "error": wire(settings.state.errorMessage),
                "diagnostic": wire(app.session?.dashboard.snapshot?.llmHealth), "diagnosticError": wire(app.session?.dashboard.llmTestMessage),
                "service": ["installed": service.isInstalled, "running": service.job.running, "reachable": service.apiReachable,
                            "canStart": service.canStart, "canStop": service.canStop, "atLogin": service.installed?.runAtLoad ?? false,
                            "log": service.logTail, "scriptWarning": wire(service.scriptWarning), "frozen": service.isWorkerPaused]]
    }

    func hindsightModelsSnapshot() -> [String: Any] {
        let settings = app.serverSettings!, local = app.localDecision!
        let phase: String
        switch local.phase {
        case .unknown: phase = "unknown"
        case .notInstalled: phase = "notInstalled"
        case .installing: phase = "installing"
        case .stopped: phase = "stopped"
        case .starting: phase = "starting"
        case .running: phase = "running"
        }
        let cloud = settings.connections.status(.hindsightCloud)
        return ["serverIs120": ServerCapabilities.is120(app.connection.version?.apiVersion),
                "decision": settings.decisionModelSource.rawValue, "reranker": settings.rerankerSource.rawValue,
                "cloudConnected": cloud.isConnected,
                // Seulement une fois le compte vérifié : pas d'alerte pendant la vérification.
                "needsCloudAccount": settings.cloudModelsUseAccountKey && !cloud.isConnected
                    && ![.unchecked, .checking, .connecting].contains(cloud),
                "local": ["phase": phase, "summary": local.phase.summary, "busy": local.isBusy || decisionTask != nil,
                          "installed": local.isInstalled, "problem": wire(local.problem), "log": local.log,
                          "root": local.paths.root.path, "logPath": local.paths.log.path]]
    }

    func readerSnapshot(_ reader: DocumentReaderViewModel) -> [String: Any] {
        ["document": wire(reader.document), "text": reader.sourceText, "note": wire(reader.sourceNote),
         "facts": wire(reader.facts.value ?? []), "history": wire(reader.history), "error": wire(reader.state.errorMessage),
         "blocks": reader.blocks.map { block -> [String: Any] in
             if let text = block.text { return ["id": block.id, "type": "text", "text": text] }
             if let ref = block.attachmentRef { return ["id": block.id, "type": "attachment", "attachmentID": ref.attachment?.id ?? ref.id, "image": ref.isImage, "attachment": wire(ref.attachment)] }
             return ["id": block.id, "type": "text", "text": ""]
         }]
    }

    func sourceURL(_ path: String) throws -> URL {
        guard let root = app.memoryFolder.collection?.resolvingSymlinksInPath() else { throw BridgeFailure("Aucun catalogue sélectionné.") }
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), url.path.hasPrefix(root.path + "/"),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw BridgeFailure("Ce fichier est hors du dossier collection ou n’est pas un fichier ordinaire.")
        }
        return url
    }

    func readSource(_ path: String) throws -> [String: Any] {
        let url = try sourceURL(path)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else {
            throw BridgeFailure("Ce fichier dépasse 2 Mo. Ouvrez l’original pour le consulter.")
        }
        return ["text": try String(contentsOf: url, encoding: .utf8), "path": path]
    }
}
