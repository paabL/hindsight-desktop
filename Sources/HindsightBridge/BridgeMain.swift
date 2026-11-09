import AppKit
import Foundation
import HindsightAPI
import HindsightCore

/// Protocole JSON Lines privé entre Tauri et le moteur Swift. Aucun serveur local ni accès HTTP arbitraire.
@main
struct BridgeMain {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty, ProcessInfo.processInfo.environment["HINDSIGHT_DESKTOP_TEST_MODE"] == "1" { exit(64) }
        if arguments.count == 4, arguments[0] == "--relaunch-after", let pid = Int32(arguments[1]), arguments[2] == "--bundle" {
            do { try await ApplicationRelaunch.relaunch(app: URL(fileURLWithPath: arguments[3]), after: pid) }
            catch { exit(1) }
            return
        }
        if arguments.count == 2, arguments[0] == "--repair-dock" {
            do {
                let result = try DockShortcutRepair.repair(app: URL(fileURLWithPath: arguments[1]))
                print("repaired=\(result.repaired) refreshed=\(result.refreshed)")
            } catch { exit(1) }
            return
        }
        guard arguments.isEmpty else { exit(64) }
        let bridge = DesktopBridge()
        do {
            // Découpe sur « \n » seulement : U+2028/U+2029/U+0085 d'un texte collé restent dans leur requête.
            var reader = BridgeLineReader()
            for try await byte in FileHandle.standardInput.bytes {
                guard case .request(let bytes)? = reader.consume(byte) else { continue }
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
                    FileHandle.standardOutput.write(BridgeLineReader.lineSafe(data))
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
    let settings: SettingsStore
    var ownConfirmation: ConfirmationRequest?
    /// Vrai après une action confirmée : la prochaine lecture de Recherche relance sa recherche affichée.
    var searchStale = false
    var section = "sources"
    var note: String?
    var workspace: MemoryWorkspace!
    var updater: AppUpdateViewModel!
    var updateTask: Task<Void, Never>?
    /// Installation ou démarrage du modèle de décision local : plusieurs minutes, hors du fil des commandes.
    var decisionTask: Task<Void, Never>?
    var sourcesTask: Task<Void, Never>?
    var sourcesGeneration = UUID()
    var collectionTask: Task<Void, Never>?
    var serviceTask: Task<Void, Never>?
    var autoSyncConfirmation: UUID?
    var graphMode = GraphViewModel.Mode.entities
    var graphLimit = 300
    var catalogCache: (stamp: [String], header: Any)?
    /// Dossier ouvert dans Sources (catalogue ou dossier ordinaire) ; nil : la liste des dossiers de la banque.
    var openFolder: (path: String, catalog: Bool)?
    /// Résumé de chaque catalogue pour la liste des dossiers, relu quand son fichier change.
    var catalogSummaries: [String: (stamp: [String], summary: [String: Any])] = [:]
    /// Clé d'occurrence de chaque message émis (voir `forgetEmittedMessages`), préfixée par cette exécution du
    /// moteur pour qu'un moteur relancé ne réutilise pas les clés déjà vues par la coque.
    var messageKeys: [String: String] = [:]
    var messageSerial = 0
    let messageSession = String(UUID().uuidString.prefix(8))
    var banksRefreshedAt = Date.distantPast
    let testing = ProcessInfo.processInfo.environment["HINDSIGHT_DESKTOP_TEST_MODE"] == "1"

    init() {
        let defaults = UserDefaults(suiteName: "local.hindsight.desktop")!
        // Préférences indépendantes : le premier lancement n'altère pas celles de SwiftUI.
        let settings: SettingsStore = testing ? InMemorySettingsStore() : UserDefaultsSettingsStore(defaults: defaults)
        self.settings = settings
        let ledgerURL = UsageLedger.defaultURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("HindsightDesktop/usage-ledger.json")
        let env = ProcessInfo.processInfo.environment
        let identity = AppInfo(version: env["HINDSIGHT_DESKTOP_VERSION"] ?? "dev", build: "Tauri", commit: env["HINDSIGHT_DESKTOP_COMMIT"], sourceRepository: env["HINDSIGHT_DESKTOP_SOURCE"], bundlePath: env["HINDSIGHT_DESKTOP_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 })
        app = AppModel(settings: settings, appInfo: identity, ledger: testing ? nil : UsageLedger(url: ledgerURL), automaticActions: false)
        updater = AppUpdateViewModel(settings: settings, appInfo: identity, tauri: true)
        workspace = MemoryWorkspace(folder: app.memoryFolder, client: { [unowned self] in self.app.client }, bank: { [unowned self] in self.app.selectedBankID })
        workspace.pauseGate = app.pause.gate
        // Les sessions OAuth ne sont lues que sur demande explicite, après confirmation.
        if !testing, let path = env["HINDSIGHT_DESKTOP_BUNDLE"], !path.isEmpty {
            _ = try? DockShortcutRepair.repair(app: URL(fileURLWithPath: path))
        }
    }

    func session() throws -> BankSession {
        guard let session = app.session else { throw BridgeFailure("Connectez le serveur et choisissez une banque.") }
        return session
    }

    func handle(_ command: String, _ p: [String: Any]) async throws -> Any {
        func str(_ key: String, _ fallback: String = "") -> String { p[key] as? String ?? fallback }
        func strings(_ key: String) -> [String] { p[key] as? [String] ?? [] }
        // Lectures et sondages ne touchent pas aux messages ; toute autre commande repart de résultats neufs.
        if !["bootstrap", "snapshot", "section", "updates.releaseReady", "document.status"].contains(command) { forgetEmittedMessages() }
        switch command {
        case "bootstrap", "snapshot": break
        case "connect":
            await app.connect()
            await connected()
        case "server.url":
            guard serviceTask == nil, !app.service.isBusy else { throw BridgeFailure("Le service est déjà en cours de modification.") }
            closeFolder()
            clearConfirmations()
            guard await app.applyServerURL(str("url")) else { throw BridgeFailure(app.serverURLNotice ?? "Adresse invalide.") }
            await connected()
        case "updates.check":
            if updater.isWorking || updateTask != nil { break }
            if let path = p["path"] as? String { updater.selectRepository(path) }
            updateTask = Task { @MainActor in await self.updater.check(); self.updateTask = nil }
        case "updates.releaseReady":
            let ready = !updater.isWorking && updateTask == nil
                && !app.memoryFolder.collecting && !app.memoryFolder.importing && collectionTask == nil
                && !app.localDecision.isBusy && decisionTask == nil
                && !app.service.isBusy && serviceTask == nil
                && app.coverage.sending == nil
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
            closeFolder()
            app.selectBank(str("id"))
            if !testing { await app.services.estimator.refreshProfile(bank: str("id")) }
        case "bank.create": app.requestCreateBank(id: str("id"), name: str("name"), mission: str("mission"))
        case "bank.rename": app.bankManagement.requestRename(try session().bank, name: str("name"))
        case "bank.merge": await app.bankManagement.requestMerge(source: str("source"), into: str("target"))
        case "section":
            section = str("section", "sources")
            try await load(section, p)
        case "folder.choose":
            // Ouvre un dossier de Sources : son catalogue s'il passe par lui dans cette banque, sinon ses fichiers.
            let path = str("path")
            guard path.hasPrefix("/") else { throw BridgeFailure("Choisissez un dossier absolu.") }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw BridgeFailure("Ce dossier est introuvable.")
            }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let catalog = SourceFolders.isCatalog(url, for: listBank)
            if catalog, collectionTask != nil || app.memoryFolder.collecting { throw BridgeFailure("Une collecte est en cours dans ce dossier.") }
            cancelSourcesRefresh()
            openFolder = (url.path, catalog)
            if catalog {
                app.memoryFolder.choose(url)
                if p["background"] as? Bool == true { startSourcesRefresh() } else { await workspace.refresh() }
            } else {
                releaseClosedCatalog()
                if app.selectedBankID != nil { await app.coverage.loadIfNeeded() }
            }
        case "folder.close": closeFolder()
        case "folder.refresh":
            if p["background"] as? Bool == true {
                guard collectionTask == nil else { break }
                cancelSourcesRefresh(invalidate: false)
                collectionTask = Task { @MainActor in
                    await self.workspace.refreshSources()
                    self.collectionTask = nil
                    self.releaseClosedCatalog()
                }
            } else { await workspace.refreshSources() }
        case "folder.prepare":
            guard collectionTask == nil else { throw BridgeFailure("Une collecte est en cours dans ce dossier.") }
            cancelSourcesRefresh(invalidate: false)
            await workspace.prepareSend()
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
            // Un dossier de la banque ou le dossier ouvert ; sans chemin, le catalogue ouvert.
            let requested = str("path")
            if requested.isEmpty {
                if let url = app.memoryFolder.repository, !testing { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path) }
            } else {
                let known = listBank.map { FileCoverageViewModel.storedRoots(settings: settings, bank: $0) }?.contains { $0.path == requested } == true
                guard known || openFolder?.path == requested else { throw BridgeFailure("Dossier inconnu.") }
                if !testing { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: requested) }
            }
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
                ownConfirmation = ConfirmationRequest(title: "Obtenir une réponse ?", message: "Le modèle rédigera une réponse à partir des faits de cette banque.\n\n" + (search.reflectEstimate?.summary ?? "Cette action consomme des jetons ; estimation indisponible.") + "\n\n" + query, confirmTitle: "Obtenir la réponse", severity: .normal) {
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
        case "document.status":
            // Le lecteur se ferme côté moteur après une suppression réussie : la fenêtre suit cet état.
            let reader = app.session?.documents.reader
            return ["open": reader != nil && (str("id").isEmpty || reader?.documentID == str("id")),
                    "confirming": reader?.confirmation != nil]
        case "document.delete", "document.reprocess", "document.tags", "document.scope":
            // Après une suppression, le lecteur n'existe plus : refuser au lieu d'ignorer l'action.
            guard let reader = try session().documents.reader, str("id").isEmpty || reader.documentID == str("id") else {
                throw BridgeFailure("Ce document n’est plus ouvert.")
            }
            switch command {
            case "document.delete": reader.requestDelete()
            case "document.reprocess": await reader.requestReprocess()
            case "document.tags": reader.requestUpdateTags(strings("tags"))
            default: reader.requestUpdateScope(str("scope"))
            }
        case "documents.more": await (try session()).documents.loadMore()
        // Trier par nom ou par nombre de faits porte sur toute la banque : on charge d'abord toutes les pages.
        case "documents.all": await (try session()).documents.loadAll()
        case "model.open":
            let admin = try session().admin
            await admin.loadMentalModel(str("id"))
            return ["model": wire(admin.mentalModelDetail.value), "error": wire(admin.mentalModelDetail.errorMessage)]
        case "model.create": (try session()).admin.requestCreateMentalModel(name: str("name"), sourceQuery: str("query"), tags: strings("tags"))
        case "model.refresh", "model.delete":
            let admin = try session().admin
            guard let model = admin.mentalModels.value?.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Connaissance inconnue.") }
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
        case "consolidation.consolidate": (try session()).consolidation.requestConsolidation()
        case "consolidation.recover": (try session()).consolidation.requestRecoverConsolidation()
        case "consolidation.more": await (try session()).consolidation.loadMore()
        case "consolidation.sources": return ["sources": wire(try await (try session()).consolidation.sources(of: str("id")))]
        case "pause.pause", "pause.resume":
            let bank = p["all"] as? Bool == true ? nil : try session().bank
            let pausing = command == "pause.pause"
            let scope = bank.map { "« \($0) »" } ?? "Toutes les banques"
            ownConfirmation = ConfirmationRequest(
                title: pausing ? (bank.map { "Mettre « \($0) » en pause ?" } ?? "Mettre toutes les banques en pause ?")
                    : (bank.map { "Reprendre « \($0) » ?" } ?? "Reprendre toutes les banques ?"),
                message: pausing
                    ? "\(scope) : plus aucun envoi depuis cette app, consolidation automatique coupée, régénérations de connaissances annulées. Les opérations déjà en file continuent ; pour les arrêter aussi, gelez la file."
                    : "\(scope) : les envois reprennent et la consolidation automatique retrouve son réglage d'avant la pause.",
                confirmTitle: pausing ? "Mettre en pause" : "Reprendre", severity: .normal) { [app] in
                if command == "pause.pause" { await app.pause.pause(bank: bank, reason: "Pause manuelle depuis Hindsight Desktop") }
                else { await app.pause.resume(bank: bank) }
            }
        case "pause.reconcile": await app.pause.retryReconcile()
        case "pause.freeze": app.pause.requestFreeze()
        case "pause.unfreeze": app.pause.requestUnfreeze()
        case "pause.drain": await app.pause.requestDrain(bank: p["all"] as? Bool == true ? nil : try session().bank)
        case "budget.save":
            let budget = try decode(ConsumptionBudgets.self, p["budget"] ?? [:])
            let amounts = [budget.dailyDollars].compactMap { $0 }
            guard amounts.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= ConsumptionBudgets.maxAmount }),
                  budget.warnAt > 0, budget.warnAt <= 1 else { throw BridgeFailure("Les plafonds doivent être des montants positifs valides.") }
            let description = "Budget quotidien : \(budget.dailyDollars.map { ConsumptionBudgets.amountText($0) + " USD" } ?? "sans plafond")\nAu dépassement : \(budget.effectiveAction.title)."
            ownConfirmation = ConfirmationRequest(title: "Enregistrer les plafonds ?", message: description, confirmTitle: "Enregistrer", severity: .normal) { [app] in app.consumption.budgets = budget }
        case "prices.save":
            let book = try decode(PriceBook.self, p["prices"] ?? [:])
            ownConfirmation = ConfirmationRequest(title: "Modifier la grille tarifaire ?", message: "Les estimations de coût utiliseront cette grille dans Hindsight Desktop.", confirmTitle: "Enregistrer", severity: .normal) { [app] in app.services.estimator.priceBook = book }
        case "memory.save", "memory.trial":
            let memory = try session().memoryDesign
            // La projection inverse passe par les clés de configuration officielles.
            let updates = try decode([String: JSONValue].self, p["config"] ?? [:])
            // Une clé que cet écran ne relit pas serait ignorée sans le dire : la refuser.
            let unsupported = updates.keys.filter { !MemoryDesign.editableKeys.contains($0) }.sorted()
            guard unsupported.isEmpty else {
                throw BridgeFailure("Clés non prises en charge ici : \(unsupported.joined(separator: ", ")). Modifiez-les dans Réglages › Banque › Configuration avancée de la banque.")
            }
            let config = try await app.client.bankConfig(try session().bank)
            memory.draft = MemoryDesign(config: config.config.merging(updates) { _, new in new })
            if command == "memory.trial" { memory.sampleText = str("sample"); memory.requestTrial() }
            else { memory.requestSave() }
        case "memory.reset": (try session()).memoryDesign.requestResetAll()
        case "admin.override":
            guard (try session()).admin.requestSetOverride(key: str("key"), rawJSON: str("value")) else { throw BridgeFailure("Valeur invalide.") }
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
            // Un seul retour : l'enregistrement du fichier le confirme, un échec revient comme erreur de la commande.
            let outcome = admin.actionMessage
            admin.actionMessage = nil
            guard let file = admin.exported else { throw BridgeFailure(outcome ?? "Export impossible.") }
            admin.exported = nil
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
        case "server.models.prepare":
            guard let changes = p["changes"] as? [String: String] else { throw BridgeFailure("Réglages des modèles invalides.") }
            let settings = app.serverSettings!
            if !ServerCapabilities.is120(app.connection.version?.apiVersion), changes.keys.contains(where: { $0.contains("DECISION_MODEL") }) {
                throw BridgeFailure("Serveur Hindsight 1.2.0 requis pour ces réglages de décision.")
            }
            try settings.prepareModelWorkflow(changes, revision: str("revision"))
        case "server.decision", "server.reranker":
            let settings = app.serverSettings!, source = str("source")
            // Un serveur 1.1.0 refuserait de démarrer avec un fournisseur `hindsight`.
            if source != "off", !(command == "server.reranker" && source == "local"),
               let version = app.connection.version?.apiVersion, !ServerCapabilities.is120(version) {
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
        case "service.restart":
            guard serviceTask == nil, !app.service.isBusy else { throw BridgeFailure("Le service est déjà en cours de modification.") }
            app.service.requestRestart()
        case "service.install": app.service.requestInstall(startAtLogin: p["atLogin"] as? Bool ?? false)
        case "service.uninstall": app.service.requestUninstall()
        case "service.atLogin": app.service.setStartAtLogin(p["enabled"] as? Bool ?? false)
        case "coverage.add":
            guard app.selectedBankID != nil else { throw BridgeFailure("Choisissez une banque avant d'ajouter un dossier.") }
            await app.coverage.addRoots(strings("paths").map { URL(fileURLWithPath: $0) })
        case "coverage.removeRoot", "coverage.auto", "coverage.allFiles":
            guard let root = app.coverage.roots.first(where: { $0.id == str("id") }) else { throw BridgeFailure("Dossier inconnu.") }
            if command == "coverage.removeRoot" {
                if openFolder?.path == root.url.standardizedFileURL.path { closeFolder() }
                await app.coverage.removeRoot(root)
            }
            else if command == "coverage.auto" {
                app.coverage.requestAutoSync(p["enabled"] as? Bool ?? false, for: root)
                autoSyncConfirmation = app.coverage.confirmation?.id
            }
            else { await app.coverage.setAllFiles(p["enabled"] as? Bool ?? false, for: root) }
        case "coverage.send": app.coverage.selection = Set(strings("ids")); await app.coverage.requestSend()
        case "coverage.remove": app.coverage.selection = Set(strings("ids")); app.coverage.requestRemoveSelection()
        case "diagnostic.llm":
            // Le serveur teste les modèles au nom d'une banque (`POST …/banks/{id}/health/llm`).
            guard app.session != nil else { throw BridgeFailure("Choisissez une banque : le test des modèles passe par une banque du serveur.") }
            let dashboard = try session().dashboard
            await dashboard.loadIfNeeded()
            // Pas de confirmation (ni de jetons promis) pour un test qui ne peut pas partir.
            if let refusal = dashboard.llmTestRefusal { throw BridgeFailure(refusal) }
            ownConfirmation = ConfirmationRequest(title: "Tester les modèles du serveur ?", message: "Un court appel sera effectué pour chaque rôle LLM configuré. Cette vérification consomme des jetons.", confirmTitle: "Tester les modèles", severity: .normal) { [weak self] in
                await dashboard.testLLM()
                self?.note = dashboard.llmTestMessage
                    ?? dashboard.llmHealth.map(LLMHealthSummary.sentence) ?? "Le test des modèles n'a pas abouti."
            }
        case "confirm":
            guard let request = pending().first(where: { $0.id.uuidString == str("id") }), request.isSatisfied(by: str("typed")) else {
                throw BridgeFailure("Cette confirmation a expiré ou le texte saisi ne correspond pas.")
            }
            let workspaceAction = workspace.confirmation?.id == request.id
            let backgroundUpdate = updater.confirmation?.id == request.id
            let backgroundDecision = app.localDecision.confirmation?.id == request.id
            let backgroundService = p["background"] as? Bool == true &&
                (app.service.confirmation?.id == request.id ||
                 (app.serverSettings.confirmation?.id == request.id && request.title == "Redémarrer le serveur Hindsight ?"))
            if backgroundService, serviceTask != nil || app.service.isBusy { throw BridgeFailure("Le service est déjà en cours de modification.") }
            let backgroundCollection = app.memoryFolder.confirmation?.id == request.id && p["background"] as? Bool == true
            let activateSync = autoSyncConfirmation == request.id
            clearConfirmations()
            if backgroundUpdate { updateTask = Task { @MainActor in await request.perform(); self.updateTask = nil } }
            else if backgroundDecision { decisionTask = Task { @MainActor in await request.perform(); self.decisionTask = nil } }
            else if backgroundService {
                serviceTask = Task { @MainActor in
                    await request.perform()
                    self.serviceTask = nil
                }
            }
            else if backgroundCollection {
                guard collectionTask == nil else { throw BridgeFailure("Une collecte est en cours dans ce dossier.") }
                cancelSourcesRefresh(invalidate: false)
                collectionTask = Task { @MainActor in
                    await request.perform()
                    if self.openFolder?.catalog == true { await self.workspace.refresh() }
                    self.collectionTask = nil
                    self.releaseClosedCatalog()
                }
            }
            else {
                await request.perform()
                // Une action confirmée a pu supprimer ou modifier des faits : Recherche relira ses résultats.
                searchStale = true
                if section == "sources" && !workspaceAction && openFolder?.catalog == true { await workspace.refresh() }
            }
            if activateSync { app.coverage.startAutoSync() }
        case "cancel": clearConfirmations()
        default: throw BridgeFailure("Action inconnue : \(command)")
        }
        return snapshot(sourceRevision: p["sourceRevision"] as? String)
    }
    /// Banque dont Sources montre les dossiers : la banque choisie, ou hors connexion la dernière choisie.
    var listBank: String? {
        if let bank = app.selectedBankID { return bank }
        return app.connection.isConnected ? nil : settings.string(forKey: SettingsKey.lastBank)
    }

    /// Retour à la liste des dossiers. Une collecte en cours garde son dossier jusqu'à sa fin.
    func closeFolder() {
        openFolder = nil
        cancelSourcesRefresh()
        releaseClosedCatalog()
    }

    /// Referme le catalogue que Sources n'affiche plus, dès qu'aucune collecte ne l'occupe.
    func releaseClosedCatalog() {
        guard openFolder?.catalog != true, app.memoryFolder.folder != nil, collectionTask == nil, !app.memoryFolder.collecting else { return }
        app.memoryFolder.choose(nil)
        workspace.invalidate()
    }

    func cancelSourcesRefresh(invalidate: Bool = true) {
        sourcesGeneration = UUID(); sourcesTask?.cancel(); sourcesTask = nil
        if invalidate { workspace.invalidate() }
    }
    func startSourcesRefresh() {
        guard sourcesTask == nil, collectionTask == nil else { return }
        workspace.prime()
        let generation = UUID(); sourcesGeneration = generation
        sourcesTask = Task { @MainActor in
            await self.workspace.refresh()
            if self.sourcesGeneration == generation { self.sourcesTask = nil }
        }
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
        // Nombre de faits de la barre latérale : la liste des banques (une requête légère) est relue à
        // l'ouverture d'une section, au plus toutes les 5 s et jamais pendant les sondages.
        if app.connection.isConnected, !testing, p["polling"] as? Bool != true, Date().timeIntervalSince(banksRefreshedAt) > 5 {
            banksRefreshedAt = Date()
            await app.refreshBanks()
        }
        if name == "sources" {
            if openFolder?.catalog == true {
                if p["background"] as? Bool == true { startSourcesRefresh() } else { await workspace.refresh() }
            } else if let bank = app.selectedBankID,
                      FileCoverageViewModel.storedRoots(settings: settings, bank: bank).contains(where: { !SourceFolders.isCatalog($0.url, for: bank) }) {
                // Liste et dossier ordinaire : comparaison des fichiers avec la banque (les catalogues ont la leur).
                await app.coverage.reload()
            }
            return
        }
        if name == "consumption" {
            await app.consumption.poll()
            await app.consumption.loadServices(serverIs120: ServerCapabilities.is120(app.connection.version?.apiVersion))
            return
        }
        if name == "server" {
            await app.serverSettings.loadIfNeeded(); await app.service.refresh()
            app.serverSettings.reconcilePendingRestart()
            return
        }
        if name == "model-settings" {
            await app.serverSettings.loadIfNeeded()
            await app.service.refresh()
            app.serverSettings.reconcilePendingRestart()
            await app.localDecision.refresh()
            await app.serverSettings.connections.refresh(app.serverSettings.connectionContext)
            return
        }
        if name == "settings" { return }
        // Réglages › Banque sans banque : la page ne propose que la création, rien à charger.
        if name == "admin", app.session == nil { return }
        let s = try session()
        switch name {
        // « Actualiser la vue » demande au serveur de recalculer ses statistiques (liens, répartition).
        case "dashboard": await s.dashboard.reload(refreshStats: p["explicit"] as? Bool == true)
        case "models": await s.admin.reload()
        case "admin": await s.admin.reload(withTotals: true)
        case "documents":
            s.documents.query = p["query"] as? String ?? ""
            s.documents.selectedTags = p["tags"] as? [String] ?? []
            await s.documents.reload()
        case "operations":
            if let status = p["status"] as? String {
                guard let filter = OperationsViewModel.StatusFilter(rawValue: status) else { throw BridgeFailure("Filtre d'opérations inconnu.") }
                s.operations.statusFilter = filter
            }
            await s.operations.reload(silently: p["polling"] as? Bool == true)
        case "facts", "timeline":
            s.timeline.text = p["query"] as? String ?? ""
            let type = p["type"] as? String ?? ""
            s.timeline.filter.types = name == "facts" && ["world", "experience", "observation"].contains(type) ? Set([type]) : []
            s.timeline.maxFacts = section == "facts" ? 1_000 : 20_000
            await s.timeline.reload()
        case "graph":
            graphMode = GraphViewModel.Mode(rawValue: p["mode"] as? String ?? graphMode.rawValue) ?? .entities
            graphLimit = min(max(p["limit"] as? Int ?? graphLimit, 50), 2000)
            s.graph.mode = graphMode
            s.graph.maxNodes = graphLimit
            s.graph.minCount = 1
            await s.graph.reload(layout: false)
        case "audit": await s.audit.reload(); await s.reads.reload()
        case "consolidation":
            if let raw = p["period"] as? String {
                guard let period = ConsolidationViewModel.Period(rawValue: raw) else { throw BridgeFailure("Période inconnue.") }
                if period != s.consolidation.period { await s.consolidation.setPeriod(period); break }
            }
            await s.consolidation.reload(silently: p["polling"] as? Bool == true)
        case "memory": await s.memoryDesign.reload()
        case "search":
            await s.catalog.loadIfNeeded()
            if searchStale, p["polling"] as? Bool != true {
                searchStale = false
                await s.search.rerunAfterChange()
            }
        default: throw BridgeFailure("Section inconnue.")
        }
    }

    func pending() -> [ConfirmationRequest] {
        let s = app.session
        return [workspace.confirmation, updater.confirmation, ownConfirmation, app.confirmation, app.memoryFolder.confirmation, app.service.confirmation,
                app.pause.confirmation, app.coverage.confirmation,
                app.serverSettings.confirmation, app.localDecision.confirmation, app.bankManagement.confirmation,
                s?.operations.confirmation, s?.consolidation.confirmation, s?.admin.confirmation, s?.memoryDesign.confirmation,
                s?.documents.reader?.confirmation, s?.audit.confirmation].compactMap { $0 }
    }

    func clearConfirmations() {
        workspace.confirmation = nil
        updater.confirmation = nil
        ownConfirmation = nil; app.confirmation = nil; app.memoryFolder.confirmation = nil
        autoSyncConfirmation = nil
        app.service.confirmation = nil; app.pause.confirmation = nil; app.coverage.confirmation = nil
        app.serverSettings.confirmation = nil; app.localDecision.confirmation = nil
        app.bankManagement.confirmation = nil
        app.session?.operations.confirmation = nil; app.session?.consolidation.confirmation = nil; app.session?.admin.confirmation = nil
        app.session?.memoryDesign.confirmation = nil; app.session?.documents.reader?.confirmation = nil
        app.session?.audit.confirmation = nil
    }

    func snapshot(sourceRevision: String? = nil) -> [String: Any] {
        var connected = false, error: String?
        if case .connected = app.connection { connected = true }
        if case .failed(let text) = app.connection { error = text }
        let messages = currentMessages()
        // Une clé par occurrence : un message encore affiché garde la sienne, un message réapparu en reçoit une neuve.
        var keys: [String: String] = [:]
        for message in messages where keys[message] == nil {
            if let key = messageKeys[message] { keys[message] = key }
            else { messageSerial += 1; keys[message] = "\(messageSession)-\(messageSerial)" }
        }
        messageKeys = keys
        return [
            "app": ["connected": connected, "connectionError": wire(error), "serverURLNotice": wire(app.serverURLNotice), "serverURL": app.serverURL.absoluteString,
                    "version": wire(app.connection.version), "banks": wire(app.banks), "bank": wire(app.selectedBankID),
                    "folder": wire(openFolder?.catalog == true ? app.memoryFolder.repository?.path : nil), "pause": pauseSnapshot(),
                    // Mode consultation (en-tête `X-Hindsight-Mode`) : lu avec la Vue d'ensemble ou Traitements, dit partout.
                    "consultationOnly": app.session.map { $0.operations.consultationOnly || $0.consolidation.consultationOnly || $0.dashboard.snapshot?.consultationOnly == true } ?? false],
            "serviceBusy": serviceTask != nil || app.service.isBusy,
            "updates": updateSnapshot(),
            "section": section, "data": sectionData(sourceRevision: sourceRevision), "messages": messages.map { SecretMasker.mask($0) },
            "messageKeys": messages.map { keys[$0] ?? "" },
            "confirmations": pending().map { ["id": $0.id.uuidString, "title": $0.title, "message": SecretMasker.mask($0.message),
                                               "confirmTitle": $0.confirmTitle, "destructive": $0.severity == .destructive,
                                               "requiredText": wire($0.requiredText)] }
        ]
    }

    /// État réel de la pause (ce que le garde-fou applique), pas seulement où la consolidation a été coupée.
    func pauseSnapshot() -> [String: Any] {
        let pause: PauseController = app.pause
        return ["all": pause.globalPause, "banks": pause.pausedBanks.sorted(), "uncut": pause.uncutBanks, "unreleased": pause.unreleasedBanks,
                "frozen": pause.queueFrozen, "workerOff": pause.serverWorkerOff, "canFreeze": pause.canFreeze]
    }

    /// Résultats d'action et alertes affichés en bandeau par la coque.
    func currentMessages() -> [String] {
        [note, app.bannerError, app.pause.message, app.bankManagement.message,
         app.service.message, app.serverSettings.actionMessage, app.coverage.actionMessage,
         app.session?.admin.actionMessage, app.session?.operations.actionMessage, app.session?.consolidation.actionMessage,
         app.session?.memoryDesign.actionMessage, app.session?.documents.reader?.actionMessage,
         app.session?.audit.actionMessage, app.memoryFolder.importSummary].compactMap { $0 }
    }

    /// Avant une nouvelle action, efface les résultats d'action déjà émis : si l'action produit la même phrase,
    /// elle reçoit une nouvelle clé et la coque l'affiche de nouveau au lieu de la prendre pour l'ancienne.
    /// L'état du service et le résumé d'import, affichés aussi hors bandeau, ne sont pas effacés.
    func forgetEmittedMessages() {
        func emitted(_ text: String?) -> Bool { text.map { messageKeys[$0] != nil } ?? false }
        if emitted(note) { note = nil }
        if emitted(app.bannerError) { app.bannerError = nil }
        if emitted(app.pause.message) { app.pause.message = nil }
        if emitted(app.bankManagement.message) { app.bankManagement.message = nil }
        if emitted(app.serverSettings.actionMessage) { app.serverSettings.actionMessage = nil }
        if emitted(app.coverage.actionMessage) { app.coverage.actionMessage = nil }
        if let s = app.session {
            if emitted(s.admin.actionMessage) { s.admin.actionMessage = nil }
            if emitted(s.operations.actionMessage) { s.operations.actionMessage = nil }
            if emitted(s.consolidation.actionMessage) { s.consolidation.actionMessage = nil }
            if emitted(s.memoryDesign.actionMessage) { s.memoryDesign.actionMessage = nil }
            if emitted(s.audit.actionMessage) { s.audit.actionMessage = nil }
            if let reader = s.documents.reader, emitted(reader.actionMessage) { reader.actionMessage = nil }
        }
        let remaining = Set(currentMessages())
        messageKeys = messageKeys.filter { remaining.contains($0.key) }
    }

    func updateSnapshot() -> [String: Any] {
        let state: String, message: String
        switch updater.phase {
        case .idle: state = "idle"; message = "Recherchez les mises à jour ou reconstruisez cette copie."
        case .checking: state = "checking"; message = "Recherche des mises à jour…"
        // Bloc « Construire depuis les sources » : l'état décrit le dépôt local, pas les versions publiées.
        case .upToDate: state = "current"; message = "Aucun nouveau commit : cette copie du code source est à jour."
        case .available: state = "available"; message = "De nouveaux commits sont disponibles dans le dépôt source."
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

    func sectionData(sourceRevision: String? = nil) -> [String: Any] {
        let s = app.session
        switch section {
        case "sources":
            var data = foldersData()
            guard openFolder?.catalog == true else { return data }
            let folder = app.memoryFolder!
            let revision = workspace.revision.uuidString
            data.merge(["folder": wire(folder.repository?.path), "error": wire(workspace.error ?? folder.error), "memoryMessage": wire(workspace.message),
                "canCollect": folder.canCollect, "collecting": folder.collecting || collectionTask != nil, "importing": folder.importing,
                "refreshing": sourcesTask != nil, "catalogRevision": revision, "output": folder.output,
                "boundBank": wire(workspace.boundBank), "bankMismatch": workspace.bankMismatch,
                "catalogMissing": workspace.catalog == nil]) { $1 }
            if sourceRevision == revision { data["catalogUnchanged"] = true; return data }
            if let sourceRevision, sourceRevision == workspace.previousRevision?.uuidString,
               workspace.changedRecords.count < max(1, workspace.records.count / 2), var header = workspace.catalog {
                header["records"] = nil
                data["catalog"] = header
                data["catalogDelta"] = ["baseRevision": sourceRevision, "records": workspace.changedRecords,
                                        "ids": workspace.records.compactMap { $0["id"] as? String }]
                return data
            }
            var catalog: Any = NSNull()
            if let value = workspace.catalog { catalog = value }
            if var merged = catalog as? [String: Any] { merged["records"] = workspace.records; catalog = merged }
            else if !workspace.records.isEmpty { catalog = ["records": workspace.records, "sources": [], "projects": []] }
            data["catalog"] = catalog
            return data
        case "dashboard":
            return ["snapshot": wire(s?.dashboard.snapshot), "insights": wire(s?.dashboard.insights ?? []), "error": wire(s?.dashboard.state.errorMessage), "partialErrors": wire(s?.dashboard.partialErrors ?? [])]
        case "models", "admin":
            return ["models": wire(s?.admin.mentalModels.value ?? []), "directives": wire(s?.admin.directives.value ?? []),
                    "refreshing": (s?.admin.refreshingIDs).map { Array($0).sorted() } ?? [],
                    "config": wire(s?.admin.config.value), "error": wire(s?.admin.config.errorMessage),
                    "modelError": wire(s?.admin.mentalModels.errorMessage), "templateDryRun": wire(s?.admin.templateDryRun),
                    "configWritable": s?.admin.configWritable ?? true,
                    "factTotal": wire(s?.admin.factTotal), "observationTotal": wire(s?.admin.observationTotal)]
        case "search":
            return ["hits": wire(s?.search.hits ?? []), "answer": wire(s?.search.answer), "total": s?.search.total ?? 0,
                    "canLoadMore": s?.search.canLoadMore ?? false, "error": wire(s?.search.state.errorMessage),
                    "entities": wire(s?.catalog.entities ?? []), "tags": wire(s?.catalog.plainTags ?? []), "tasks": wire(s?.catalog.tasks ?? []),
                    "serverIs120": s?.search.serverIs120 ?? false]
        case "documents":
            return ["items": wire(s?.documents.sortedItems ?? []), "total": s?.documents.total ?? 0,
                    "totalIsEstimate": s?.documents.totalIsEstimate ?? false,
                    "canLoadMore": s?.documents.canLoadMore ?? false, "error": wire(s?.documents.state.errorMessage),
                    "query": s?.documents.query ?? ""]
        case "operations":
            return ["items": wire(s?.operations.rows.map(\.raw) ?? []), "total": s?.operations.total ?? 0,
                    "statusFilter": s?.operations.statusFilter.rawValue ?? "all", "refreshing": s?.operations.isRefreshing ?? false,
                    "counts": wire(s?.operations.operationCounts), "loadingMore": s?.operations.isLoadingMore ?? false,
                    "canLoadMore": s?.operations.canLoadMore ?? false, "error": wire(s?.operations.state.errorMessage),
                    "consultationOnly": s?.operations.consultationOnly ?? false,
                    // « Exécuter maintenant » n'est proposé que là où le moteur l'accepte (serveur 1.1, prochaine tentative à venir).
                    // La consolidation (état, lancement, changements) a sa vue : Mémoire › Consolidation.
                    "runNowIDs": s.map { s in s.operations.rows.filter { s.operations.canRunNow($0) }.map(\.id) } ?? []]
        case "consolidation":
            let c = s?.consolidation
            return ["status": wire(c?.status), "rawFacts": wire(c?.rawFacts), "consolidatedFacts": wire(c?.consolidatedFacts),
                    "lastConsolidatedAt": wire(c?.stats?.lastConsolidatedAt), "pace": wire(c?.pace), "scopes": wire(c?.scopes),
                    "observationTotal": wire(c?.stats.map { $0.nodesByFactType["observation"] ?? $0.totalObservations }),
                    "period": c?.period.rawValue ?? "day", "counts": wire(c?.counts), "changes": wire(c?.changes ?? []),
                    "canLoadMore": c?.canLoadMore ?? false, "loadingMore": c?.isLoadingMore ?? false,
                    "consultationOnly": c?.consultationOnly ?? false, "busy": c?.isBusy ?? false,
                    "loaded": c?.state.value != nil, "error": wire(c?.state.errorMessage), "partialErrors": wire(c?.partialErrors ?? [])]
        case "consumption":
            let m = app.consumption!
            // Totaux, histogramme et répartition calculés par le moteur sur tout l'historique suivi : la page ne
            // recompte plus une liste tronquée (les 5 000 derniers appels) sous des totaux qui, eux, sont complets.
            func period(_ p: ConsumptionMonitor.Period) -> [String: Any] {
                let tokens = { (t: TokenCount) in t.input + t.output }
                return ["calls": m.totals(p).calls,
                        "buckets": m.buckets(p).filter { $0.calls > 0 }.map { ["start": HSDate.format($0.start), "tokens": $0.tokens, "calls": $0.calls] },
                        "operations": m.breakdown(p, by: .operation, limit: 12).map { ["id": $0.id, "tokens": tokens($0.totals.tokens)] }
                            .sorted { ($0["tokens"] as? Int ?? 0) > ($1["tokens"] as? Int ?? 0) }]
            }
            return ["summary": wire(m.summary), "gauges": wire(m.gauges), "periods": ["day": period(.day), "week": period(.week)],
                    // Traces LLM coupées sur le serveur : rien n'est mesuré, les montants et les plafonds n'ont pas de sens.
                    "tracesOff": app.connection.version?.features.llmTrace == false,
                    // Le gel automatique ne vaut que pour un serveur lancé par cette app ; sinon la pause le remplace.
                    "canFreeze": app.pause.canFreeze,
                    "events": wire(Array(m.events.suffix(5000))), "queues": wire(m.queues), "budgets": wire(m.budgets),
                    "prices": wire(app.services.estimator.priceBook), "lastPoll": wire(m.lastPoll), "error": wire(m.pollError),
                    "services": wire(m.services), "servicesError": wire(m.servicesError)]
        case "facts", "timeline":
            // Liste limitée à 1 000 faits, chronologie à 20 000 : projeter seulement les champs affichés,
            // sans transmettre le fait complet (contexte, entités, étiquettes…).
            let facts = (s?.timeline.facts ?? []).map { fact -> [String: Any] in
                var item: [String: Any] = ["id": fact.id, "text": fact.text, "type": wire(fact.type), "occurredStart": wire(fact.occurredStart),
                                          "mentionedAt": wire(fact.mentionedAt), "documentID": wire(fact.documentID)]
                if section == "facts" { item["state"] = wire(fact.state); item["sourceFactIDs"] = fact.sourceFactIDs }
                return item
            }
            return ["facts": facts, "periods": wire(s?.timeline.bars ?? []), "total": s?.timeline.totalAvailable ?? 0, "truncated": s?.timeline.isTruncated ?? false, "error": wire(s?.timeline.state.errorMessage), "query": s?.timeline.text ?? "", "type": s?.timeline.filter.types.first ?? "all"]
        case "graph":
            let graph = s?.graph
            let facts = graph?.mode == .facts ? graph?.selectedFact.map { [$0.hit] } ?? [] : graph?.nodeFacts.value ?? []
            return ["mode": graphMode.rawValue, "limit": graphLimit, "nodes": wire(graph?.nodes ?? []), "edges": wire(graph?.edges ?? []),
                    "totalNodes": graph?.serverNodeTotal ?? 0, "totalEdges": graph?.serverEdgeTotal ?? 0,
                    "selectedNodeID": wire(graph?.selectedNodeID), "nodeFacts": wire(facts), "entity": wire(graph?.entityDetail.value),
                    "detailError": wire(graph?.nodeFacts.errorMessage ?? graph?.selectedFact?.detail.errorMessage), "error": wire(graph?.state.errorMessage)]
        case "audit":
            // État du journal d'audit de la banque : le bouton propose l'action inverse de l'état réel.
            let auditStatus: String
            switch s?.audit.auditStatus {
            case .enabled?: auditStatus = "enabled"
            case .disabled?: auditStatus = "disabled"
            default: auditStatus = "unknown"
            }
            return ["audit": wire(s?.audit.audit.value ?? []), "traces": wire(s?.audit.llm.value ?? []), "reads": wire(s?.reads.events ?? []), "error": wire(s?.audit.audit.errorMessage), "traceError": wire(s?.audit.llm.errorMessage),
                    "auditStatus": auditStatus, "canToggleAudit": s?.audit.canToggleAudit ?? false,
                    "auditTotal": s?.audit.auditTotal ?? 0, "traceTotal": s?.audit.llmTotal ?? 0]
        case "memory": return ["draft": wire(s?.memoryDesign.draft), "configWritable": s?.memoryDesign.configWritable ?? true, "config": wire(s?.admin.config.value), "error": wire(s?.memoryDesign.state.errorMessage), "trial": wire(s?.memoryDesign.trial.value), "trialError": wire(s?.memoryDesign.trial.errorMessage), "problems": s?.memoryDesign.problems ?? [], "serverIs120": s?.memoryDesign.serverIs120 ?? false,
                           // Clés propres à la banque : la page les signale, « Revenir aux réglages du serveur » les supprime toutes.
                           "overridden": (s?.memoryDesign.overriddenKeys).map { Array($0).sorted() } ?? [],
                           "pauseCutAutoConsolidation": s.map { app.pause.cutAutoConsolidation($0.bank) } ?? false]
        case "server", "model-settings": return serverSnapshot()
        default: return [:]
        }
    }

    /// Sources : les dossiers de la banque et, pour un dossier ordinaire ouvert, ses fichiers comparés à la banque.
    func foldersData() -> [String: Any] {
        let bank = listBank
        let roots = bank.map { FileCoverageViewModel.storedRoots(settings: settings, bank: $0) } ?? []
        let compared = bank != nil && app.coverage.reportBank == bank
        let tracked = compared ? app.coverage.library.filter { $0.group.kind == .folder } : []
        var rows: [[String: Any]] = []
        var openItems: [[String: Any]] = []
        var claimed = Set<String>()
        for root in roots {
            let catalog = SourceFolders.isCatalog(root.url, for: bank)
            var row: [String: Any] = ["path": root.path, "name": root.url.lastPathComponent, "kind": catalog ? "catalog" : "folder",
                                      "allFiles": root.allFiles, "autoSync": root.autoSync,
                                      "exists": FileManager.default.fileExists(atPath: root.path)]
            if catalog {
                row.merge(catalogSummary(root.url)) { $1 }
            } else if compared {
                // Un dépôt atteint par deux dossiers suivis n'est compté qu'une fois, dans le premier.
                let repoURLs = Dictionary(
                    FileCoverageScanner.repositories(in: [root.url]).map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
                let repos = Set(repoURLs.keys).subtracting(claimed)
                claimed.formUnion(repos)
                let items = tracked.filter { repos.contains($0.group.title) }
                // « Fichier disparu » seulement s'il n'est plus sur le disque ; sinon il est exclu du suivi
                // (fichiers ignorés, « Inclure tous les fichiers texte » décoché).
                func excluded(_ item: HindsightCore.LibraryItem) -> Bool {
                    guard item.state == .fileMissing, let d = item.documents.first, let (repo, path) = FileCoverage.repoAndPath(d),
                          let base = repoURLs[repo] else { return false }
                    return FileManager.default.fileExists(atPath: base.appendingPathComponent(path).path)
                }
                let excludedIDs = Set(items.filter(excluded).map(\.id))
                row["files"] = items.filter { $0.entry != nil }.count
                row["missing"] = items.filter { $0.state == .fileMissing && !excludedIDs.contains($0.id) }.count
                row["excluded"] = excludedIDs.count
                row["toSend"] = items.filter(\.canSend).count
                row["modified"] = items.filter { $0.state == .modified }.count
                row["queued"] = items.filter { $0.state == .queued }.count
                if openFolder?.catalog == false, openFolder?.path == root.url.standardizedFileURL.path {
                    openItems = items.map { item in
                        var row = (wire(item) as? [String: Any]) ?? [:]
                        let pdfToSend = item.state == .notSent && item.entry.map { FileCoverage.needsTextSource($0.file.path) } == true
                        row["state"] = excludedIDs.contains(item.id) ? "excluded" : pdfToSend ? "needsSource" : item.state.rawValue
                        row["canSend"] = item.canSend
                        return row
                    }
                }
            }
            rows.append(row)
        }
        var data: [String: Any] = ["folders": rows, "bank": wire(app.selectedBankID), "listBank": wire(bank),
                                   "open": wire(openFolder?.path), "openKind": wire(openFolder.map { $0.catalog ? "catalog" : "folder" }),
                                   "foldersLoading": app.coverage.state.isLoading || app.coverage.isRefreshing,
                                   "foldersError": wire(app.coverage.state.errorMessage), "warnings": app.coverage.warnings]
        if openFolder?.catalog == false { data["items"] = openItems; data["compared"] = compared }
        return data
    }

    /// Nombre de sources et date de collecte d'un catalogue, sans ses archives à part (comme la page du catalogue).
    func catalogSummary(_ folder: URL) -> [String: Any] {
        let summary: [String: Any] = ["catalogBank": wire(SourceFolders.declaredBank(of: folder))]
        guard let url = SourceFolders.catalogURL(in: folder),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue else { return summary }
        let stamp = [url.path, String(size), String(describing: attributes[.modificationDate]), String(describing: attributes[.systemFileNumber])]
        if let cached = catalogSummaries[folder.path], cached.stamp == stamp { return summary.merging(cached.summary) { $1 } }
        var values: [String: Any] = ["unreadable": true]
        if size < 60_000_000, let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let records = json["records"] as? [[String: Any]] {
            let aside: Set<String> = ["internal_review", "empty_export"]
            values = ["sources": records.filter { !aside.contains(($0["context"] as? [String: Any])?["conversation_kind"] as? String ?? "") }.count,
                      "collectedAt": json["generated_at"] ?? NSNull()]
        }
        catalogSummaries[folder.path] = (stamp, values)
        return summary.merging(values) { $1 }
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
                "modelWorkflow": wire(settings.modelWorkflow),
                "configurationProblems": settings.configurationProblems,
                "providerChoices": settings.providerChoices.map { ["id": $0.id, "title": $0.title] },
                "modelsByProvider": wire(settings.modelsByProvider),
                "hindsightModels": hindsightModelsSnapshot(),
                "roles": settings.roles.map { ["id": $0.role.id, "title": $0.role.title, "effective": $0.effective, "isModelRole": $0.role.isModelRole, "fallback": wire($0.role.fallback), "fields": fields($0.fields), "models": wire(settings.modelChoices(forRole: $0.role.id))] },
                "otherVariables": fields(settings.otherVariables), "warnings": settings.actionableWarnings,
                "accounts": LLMAccount.allCases.map { account -> [String: Any] in
                    let status = settings.connections.status(account)
                    let state: String
                    switch status {
                    case .unchecked: state = "unknown"
                    case .checking, .connecting: state = "pending"
                    case .connected, .signedInTo: state = "connected"
                    case .signedOut, .unavailable, .failed: state = "disconnected"
                    }
                    return ["id": account.rawValue, "title": account.title, "status": status.summary, "state": state,
                            "connected": status.isConnected, "canDisconnect": account.canDisconnect]
                },
                // Lien de secours si le client n'a pas pu ouvrir le navigateur ; il ne contient aucune clé.
                "connectingAccount": wire(settings.connections.activeAccount?.rawValue),
                "authorizationURL": wire(settings.connections.authorizationURL?.absoluteString),
                "diff": wire(settings.compactDiff), "backups": wire(settings.backups), "error": wire(settings.state.errorMessage),
                "diagnostic": wire(app.session?.dashboard.llmHealth?.operations.map { row in
                    ["role": row.operation, "title": LLMHealthSummary.roleTitle(row.operation), "ok": row.ok,
                     "status": LLMHealthSummary.statusLabel(row.status), "latencyMs": wire(row.latencyMs)] as [String: Any]
                }),
                "diagnosticAt": wire(app.session?.dashboard.llmTestedAt),
                "diagnosticError": wire(app.session?.dashboard.llmTestMessage),
                "canTestModels": app.session != nil && app.session?.dashboard.llmTestRefusal == nil,
                "testModelsBlocked": wire(app.session == nil
                    ? "Choisissez une banque pour tester les modèles : le test passe par une banque du serveur."
                    : app.session?.dashboard.llmTestRefusal),
                "service": ["installed": service.isInstalled, "running": service.job.running, "reachable": service.apiReachable,
                            "busy": service.isBusy || serviceTask != nil, "phase": serviceTask != nil && !service.isBusy ? "starting" : service.phase,
                            "error": wire(service.failure), "message": wire(service.message), "lastExitCode": wire(service.job.lastExitCode),
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
         "canReprocess": reader.canReprocess, "observations": wire(reader.createsObservations),
         "scopeEditable": reader.serverIs110, "scope": wire(reader.currentScope),
         "scopeMode": wire(reader.currentScopeMode),
         "facts": wire(reader.facts.value ?? []), "factsTotal": reader.factsTotal, "factsError": wire(reader.facts.errorMessage),
         "history": wire(reader.history), "error": wire(reader.state.errorMessage),
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
