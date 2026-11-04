import Foundation
import HindsightAPI
import Observation

/// Renommer et fusionner des banques.
///
/// Hindsight n'a pas d'opération « renommer » ni « fusionner » : l'app les compose à partir de l'API.
/// - **Nom affiché** : `PATCH /banks/{id}` (champ `name`), sans effet sur les données.
/// - **Alias affiché** : un second identifiant qui mène à la même banque, montré à la place de l'id
///   (`POST …/aliases`). Rien n'est copié : c'est la façon « sans interruption » de renommer.
/// - **Changer l'identifiant** : clone vers le nouvel id (sans LLM), suppression de l'ancien, puis
///   l'ancien id devient un alias du nouveau pour que les clients existants continuent de fonctionner.
/// - **Fusion** : export de la banque source (archive de transfert), puis import en mode `merge` dans la
///   cible. Sans appel LLM : faits ré-indexés, entités résolues à nouveau dans la cible.
@MainActor
@Observable
public final class BankManagementViewModel {
    public enum AfterMerge: String, CaseIterable, Identifiable, Sendable {
        case keepSource, deleteSource, deleteAndAlias
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .keepSource: return "Garder la banque source"
            case .deleteSource: return "Supprimer la banque source"
            case .deleteAndAlias: return "Supprimer la source et garder son identifiant comme alias"
            }
        }
    }

    public enum Conflict: String, CaseIterable, Identifiable, Sendable {
        case skip, newID = "new-id", replace
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .skip: return "Ignorer les documents déjà présents"
            case .newID: return "Les importer sous un nouvel identifiant"
            case .replace: return "Remplacer ceux de la cible"
            }
        }
    }

    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let banksProvider: @MainActor () -> [BankListItem]
    @ObservationIgnored private let refreshBanks: @MainActor () async -> Void
    @ObservationIgnored private let selectBank: @MainActor (String) -> Void
    @ObservationIgnored var pollInterval: Duration = .seconds(2)

    public var confirmation: ConfirmationRequest?
    public var message: String?
    public private(set) var progress: String?
    public private(set) var aliases: [String: [BankAliasEntry]] = [:]

    public init(
        client: @escaping @MainActor () -> HindsightClient, banks: @escaping @MainActor () -> [BankListItem],
        refreshBanks: @escaping @MainActor () async -> Void, selectBank: @escaping @MainActor (String) -> Void
    ) {
        self.clientProvider = client
        self.banksProvider = banks
        self.refreshBanks = refreshBanks
        self.selectBank = selectBank
    }

    var client: HindsightClient { clientProvider() }

    public func item(_ id: String) -> BankListItem? { banksProvider().first { $0.bankId == id } }

    static func validID(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    public func loadAliases(_ bank: String) async {
        if let r = try? await client.bankAliases(bank) { aliases[bank] = r.aliases }
    }

    // MARK: Renommer

    public func requestRename(_ bank: String, name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != item(bank)?.name else { return }
        confirmation = ConfirmationRequest(
            title: "Renommer « \(bank) » en « \(n) » ?",
            message: "Seul le nom affiché change : l'identifiant, les données et les clients (MCP, scripts) ne sont pas touchés.",
            confirmTitle: "Renommer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateBank(bank, request: CreateBankRequest(name: n))
                self.message = "Banque renommée « \(n) »."
                await self.refreshBanks()
            } catch {
                self.message = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Affiche la banque sous `alias` (créé s'il n'existe pas). Les deux identifiants mènent à la même banque.
    public func requestShowAlias(_ bank: String, alias raw: String) {
        let alias = raw.trimmingCharacters(in: .whitespaces)
        guard Self.validID(alias), alias != bank else {
            message = "Alias invalide (lettres, chiffres, « - », « _ », « . »)."
            return
        }
        if banksProvider().contains(where: { $0.bankId == alias }) {
            message = "« \(alias) » est déjà l'identifiant d'une autre banque."
            return
        }
        confirmation = ConfirmationRequest(
            title: "Afficher « \(bank) » sous le nom « \(alias) » ?",
            message: "« \(alias) » devient un second identifiant de la même banque, affiché à sa place. Rien n'est copié ; « \(bank) » continue de fonctionner partout. Les journaux et exports gardent l'identifiant d'origine.",
            confirmTitle: "Appliquer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                let existing = try await self.client.bankAliases(bank).aliases.map(\.alias)
                if existing.contains(alias) {
                    _ = try await self.client.setBankAliasPrimary(bank, alias: alias, primary: true)
                } else {
                    _ = try await self.client.createBankAlias(bank, alias: alias, primary: true)
                }
                self.message = "« \(bank) » s'affiche désormais comme « \(alias) »."
                await self.loadAliases(bank)
                await self.refreshBanks()
            } catch {
                self.message = "Échec : \(error.userMessage)"
            }
        }
    }

    public func requestRemoveAlias(_ bank: String, alias: String) {
        confirmation = ConfirmationRequest(
            title: "Retirer l'alias « \(alias) » ?",
            message: "Les clients qui utilisent encore « \(alias) » n'atteindront plus cette banque (et risquent d'en créer une vide). Les données ne bougent pas.",
            confirmTitle: "Retirer"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.deleteBankAlias(bank, alias: alias)
                self.message = "Alias retiré."
                await self.loadAliases(bank)
                await self.refreshBanks()
            } catch {
                self.message = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Change l'identifiant : clone (données, réglages, historique) → suppression de l'ancien → alias.
    public func requestChangeID(_ bank: String, to raw: String, keepOldAsAlias: Bool = true) {
        let target = raw.trimmingCharacters(in: .whitespaces)
        guard Self.validID(target), target != bank else {
            message = "Identifiant invalide."
            return
        }
        if banksProvider().contains(where: { $0.bankId == target }) {
            message = "La banque « \(target) » existe déjà."
            return
        }
        let facts = item(bank)?.factCount ?? 0
        confirmation = ConfirmationRequest(
            title: "Changer l'identifiant « \(bank) » en « \(target) » ?",
            message: """
                1. La banque est copiée vers « \(target) » (\(Format.number(facts)) faits, réglages, directives, webhooks, journaux) — sans appel LLM.
                2. « \(bank) » est supprimée.
                \(keepOldAsAlias ? "3. « \(bank) » devient un alias de « \(target) » : les clients existants continuent de fonctionner." : "3. Les clients qui utilisent « \(bank) » devront être mis à jour.")

                Pendant l'opération, une écriture envoyée à « \(bank) » peut être perdue : arrêtez les agents qui l'utilisent.
                Pour seulement changer ce qui est affiché, préférez « Nom affiché » ou « Alias affiché ».
                """,
            confirmTitle: "Changer l'identifiant", requiredText: bank
        ) { [weak self] in
            await self?.changeID(bank, to: target, keepOldAsAlias: keepOldAsAlias)
        }
    }

    func changeID(_ bank: String, to target: String, keepOldAsAlias: Bool) async {
        guard progress == nil else {
            message = "Une opération sur les banques est déjà en cours."
            return
        }
        do {
            progress = "Copie vers « \(target) »…"
            let sub = try await client.cloneBank(bank, targetBankID: target, includeData: true, includeBankConfig: true, includeHistory: true)
            _ = try await OperationWaiter.wait(client: client, bank: bank, operationID: sub.operationId, interval: pollInterval) { [weak self] s in
                self?.progress = "Copie : \(s.progress?.stage ?? s.status)…"
            }
            progress = "Suppression de « \(bank) »…"
            _ = try await client.deleteBank(bank)
            if keepOldAsAlias {
                progress = "Alias « \(bank) » → « \(target) »…"
                _ = try await client.createBankAlias(target, alias: bank, primary: false)
            }
            progress = nil
            message = "Identifiant changé : « \(target) »" + (keepOldAsAlias ? " (« \(bank) » y mène encore)." : ".")
            await refreshBanks()
            selectBank(target)
        } catch {
            progress = nil
            message = "Échec : \(error.userMessage). Vérifiez l'état des deux banques avant de recommencer."
            await refreshBanks()
        }
    }

    // MARK: Fusionner

    public func requestMerge(source: String, into target: String, conflict: Conflict = .skip, after: AfterMerge = .keepSource) {
        guard source != target, item(source) != nil, item(target) != nil else {
            message = "Choisissez deux banques différentes."
            return
        }
        let s = item(source)!, t = item(target)!
        var lines = [
            "Les documents de « \(source) » (\(Format.number(s.factCount)) faits) sont ajoutés à « \(target) » (\(Format.number(t.factCount)) faits).",
            "Sans appel LLM : les faits sont ré-indexés avec le modèle d'embeddings de la cible et leurs entités fusionnées avec celles de la cible.",
            "Documents dont l'identifiant existe déjà dans la cible : \(conflict.label.lowercased()).",
            "Les réglages, directives et modèles mentaux de la source ne sont PAS copiés. Les observations de la cible seront mises à jour par sa prochaine consolidation (appels LLM).",
        ]
        switch after {
        case .keepSource: lines.append("« \(source) » est conservée.")
        case .deleteSource: lines.append("« \(source) » sera ensuite SUPPRIMÉE.")
        case .deleteAndAlias: lines.append("« \(source) » sera ensuite SUPPRIMÉE, et son identifiant mènera à « \(target) ».")
        }
        let destructive = after != .keepSource || conflict == .replace
        confirmation = ConfirmationRequest(
            title: "Fusionner « \(source) » dans « \(target) » ?", message: lines.joined(separator: "\n"),
            confirmTitle: "Fusionner", severity: destructive ? .destructive : .normal,
            requiredText: after == .keepSource ? nil : source
        ) { [weak self] in
            await self?.merge(source: source, into: target, conflict: conflict, after: after)
        }
    }

    func merge(source: String, into target: String, conflict: Conflict, after: AfterMerge) async {
        guard progress == nil else {
            message = "Une opération sur les banques est déjà en cours."
            return
        }
        var sourceDeleted = false
        do {
            progress = "Export de « \(source) »…"
            let sub = try await client.exportBank(source, includeData: true, includeBankConfig: false, includeHistory: false)
            let done = try await OperationWaiter.wait(client: client, bank: source, operationID: sub.operationId, interval: pollInterval) { [weak self] s in
                self?.progress = "Export : \(s.progress?.stage ?? s.status)…"
            }
            let where_ = OperationWaiter.downloadTarget(done)
            progress = "Téléchargement de l'archive…"
            let data: Data
            if let url = where_.url {
                data = try await client.downloadFile(url: url)
            } else if let key = where_.key {
                data = try await client.downloadFile(key: key)
            } else {
                throw HindsightError.refused("L'export est terminé mais le serveur n'indique pas où télécharger l'archive.")
            }
            progress = "Import dans « \(target) »…"
            let imp = try await client.importBankArchive(
                target, archive: data, filename: where_.filename ?? "\(source).zip", mode: "merge", documentConflict: conflict.rawValue)
            let result = try await OperationWaiter.wait(client: client, bank: target, operationID: imp.operationId, interval: pollInterval) { [weak self] s in
                self?.progress = "Import : \(s.progress?.stage ?? s.status)…"
            }
            var summary = "Fusion terminée"
            let metadata = result.resultMetadata ?? [:]
            let counts = metadata.compactMap { k, v -> String? in v.intValue.map { "\(k) \($0)" } }.sorted()
            if !counts.isEmpty { summary += " (" + counts.joined(separator: ", ") + ")" }
            // Des documents ignorés (déjà présents dans la cible) n'existent plus que dans la source :
            // on ne la supprime pas sans que l'utilisateur l'ait vu.
            let skipped = metadata.filter { $0.key.contains("skipped") }.compactMap { $0.value.intValue }.reduce(0, +)
            if after != .keepSource, conflict == .skip, skipped > 0 {
                progress = nil
                message = summary + ". « \(source) » est CONSERVÉE : \(skipped) document(s) ignoré(s) n'existent que dans la source. Vérifiez, puis supprimez-la depuis Administration."
                await refreshBanks()
                selectBank(target)
                return
            }
            if after != .keepSource {
                progress = "Suppression de « \(source) »…"
                _ = try await client.deleteBank(source)
                sourceDeleted = true
                if after == .deleteAndAlias {
                    _ = try await client.createBankAlias(target, alias: source, primary: false)
                    summary += " ; « \(source) » mène désormais à « \(target) »"
                } else {
                    summary += " ; « \(source) » supprimée"
                }
            }
            progress = nil
            message = summary + ". Lancez la consolidation de « \(target) » pour intégrer les nouveaux faits aux observations."
            await refreshBanks()
            selectBank(target)
        } catch {
            progress = nil
            message =
                sourceDeleted
                ? "Fusion faite et « \(source) » supprimée, mais l'alias n'a pas pu être créé : \(error.userMessage). Recréez-le depuis « Renommer… »."
                : "Échec de la fusion : \(error.userMessage). La banque source n'a pas été supprimée."
            await refreshBanks()
        }
    }
}
