import Foundation
import HindsightAPI
import Observation

/// Structure de la mémoire d'une banque : ce qui est retenu (mission et mode d'extraction, consignes,
/// vocabulaire d'entités), ce qui est consolidé (observations), comment la banque cherche et raisonne.
/// Brouillon local, diff, essai à blanc d'extraction avec les réglages NON enregistrés, puis
/// enregistrement confirmé (`PATCH …/config`).
@MainActor
@Observable
public final class MemoryDesignViewModel {
    public let bank: String
    @ObservationIgnored private let client: HindsightClient
    @ObservationIgnored private let estimator: CostEstimator?

    public private(set) var state: LoadState<Void> = .idle
    public var draft = MemoryDesign()
    public private(set) var loaded = MemoryDesign()
    /// Clés surchargées pour cette banque (les autres viennent du serveur).
    public private(set) var overriddenKeys: Set<String> = []
    /// La pause en cours a coupé la consolidation automatique de cette banque (voir `PauseController`).
    @ObservationIgnored public var pauseCutAutoConsolidation: @MainActor () -> Bool = { false }
    /// Prévenu après un retour aux réglages du serveur (la pause recoupe ce qu'elle avait coupé).
    @ObservationIgnored public var onConfigReset: (@MainActor (String) async -> Void)?
    /// Prévenu après une modification de la configuration de la banque (le tableau de bord se recalcule).
    @ObservationIgnored public var onConfigChanged: (@MainActor () async -> Void)?
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?

    // Essai à blanc
    public var sampleText = ""
    public private(set) var trial: LoadState<DryRunExtractionResult> = .idle
    public private(set) var trialEstimate: CostEstimate?

    /// Serveur 1.1.0 : portée par défaut de la banque (réglé par `BankSession`).
    public var serverIs110 = false
    /// Serveur 1.2.0 : défauts prune/dedup de recall (réglé par `BankSession`).
    public var serverIs120 = false
    /// Faux quand le serveur refuse les réglages par banque (`bank_config_api`) : rien n'est proposé à l'écriture.
    public var configWritable = true

    public init(client: HindsightClient, bank: String, estimator: CostEstimator?) {
        self.client = client
        self.bank = bank
        self.estimator = estimator
    }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    public func reload() async {
        state = .loading
        do {
            let r = try await client.bankConfig(bank)
            loaded = MemoryDesign(config: r.config)
            draft = loaded
            overriddenKeys = Set(r.overrides.keys)
            state = .loaded(())
        } catch is CancellationError {
        } catch {
            state = .failed(error.userMessage)
        }
    }

    public var changes: [String: JSONValue] { draft.updates(from: loaded) ?? [:] }
    public var hasChanges: Bool { !changes.isEmpty }
    public var problems: [String] { draft.problems }

    public func isOverridden(_ key: String) -> Bool { overriddenKeys.contains(key) }

    public func apply(_ preset: MemoryDesignPreset) {
        preset.apply(&draft)
    }

    public func revert() { draft = loaded }

    /// Résumé lisible des changements, avec les noms de la page (textes longs abrégés). Une clé que la page
    /// ne nomme pas (réglages avancés en JSON) garde son nom de serveur.
    public var changeSummary: [String] {
        changes.map { key, value in (MemoryDesign.labels[key] ?? key, value) }.sorted { $0.0 < $1.0 }.map { label, value in
            let shown: String
            switch value {
            case .null: shown = "(valeur du serveur)"
            case .bool(let on): shown = on ? "activé" : "désactivé"
            case .int(let n): shown = Format.number(n)
            case .string(let s): shown = "« \(s.count > 90 ? String(s.prefix(90)) + "…" : s) »"
            default:
                let p = value.prettyString().replacingOccurrences(of: "\n", with: " ")
                shown = p.count > 90 ? String(p.prefix(90)) + "…" : p
            }
            return "\(label) → \(shown)"
        }
    }

    public func requestSave() {
        guard configWritable else {
            actionMessage = ServerCapabilities.bankConfigDisabledMessage
            return
        }
        if let p = problems.first {
            actionMessage = p
            return
        }
        let u = changes
        guard !u.isEmpty else {
            actionMessage = "Aucun changement à enregistrer."
            return
        }
        var notes = [
            "Ces réglages deviennent propres à la banque « \(bank) ».",
            "Ils s'appliquent aux PROCHAINES extractions, consolidations et réponses : les faits déjà extraits ne changent pas (retraitez un document pour lui appliquer la nouvelle extraction).",
        ]
        if u["entity_labels"] != nil || u["retain_extraction_mode"] != nil || u["retain_mission"] != nil {
            notes.append("Conseil : testez d'abord l'extraction avec l'essai à blanc.")
        }
        if u["enable_observations"] == .bool(false) {
            notes.append("Sans observations, plus de consolidation : la recherche et les réponses ne s'appuient plus que sur les faits.")
        }
        if u["store_document_text"] == .bool(false) {
            notes.append("Sans texte des documents, le lecteur ne pourra plus afficher les nouveaux documents, et le retraitement sera impossible pour eux.")
        }
        confirmation = ConfirmationRequest(
            title: "Enregistrer le comportement de la mémoire ?",
            message: changeSummary.joined(separator: "\n") + "\n\n" + notes.joined(separator: "\n"),
            confirmTitle: "Enregistrer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateBankConfig(self.bank, updates: u)
                self.actionMessage = "Comportement enregistré (\(Format.count(u.count, "réglage")))."
                await self.reload()
                await self.onConfigChanged?()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Remet tous les réglages de la banque aux valeurs du serveur (supprime TOUTES ses surcharges).
    public func requestResetAll() {
        guard configWritable else {
            actionMessage = ServerCapabilities.bankConfigDisabledMessage
            return
        }
        // La coupure posée par la pause n'est pas un réglage de la banque : ni comptée, ni levée par ce retour.
        let paused = pauseCutAutoConsolidation()
        let keys = overriddenKeys.subtracting(paused ? ["enable_auto_consolidation"] : [])
        guard !keys.isEmpty else {
            actionMessage = "Cette banque n'a aucun réglage propre : elle suit déjà le serveur."
            return
        }
        confirmation = ConfirmationRequest(
            title: "Revenir aux réglages du serveur ?",
            message: (keys.count > 1
                ? "Les \(Format.number(keys.count)) réglages propres à « \(bank) » sont supprimés"
                : "Le réglage propre à « \(bank) » est supprimé")
                + ", y compris ceux de l'administration (journal d'accès, etc.). Les faits existants ne changent pas."
                + (paused ? " La consolidation automatique reste coupée jusqu'à la fin de la pause." : ""),
            confirmTitle: "Revenir aux réglages du serveur"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.resetBankConfig(self.bank)
                await self.onConfigReset?(self.bank)
                self.actionMessage = "Réglages du serveur rétablis."
                await self.reload()
                await self.onConfigChanged?()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    // MARK: Essai à blanc

    /// Extraction d'essai sur `sampleText` avec les réglages du BROUILLON (rien n'est enregistré).
    /// Appelle le LLM : confirmation avec estimation.
    public func requestTrial() {
        let text = sampleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let e = estimator?.estimate(.retain(characters: text.count, images: 0, consolidation: false), bank: bank)
        confirmation = ConfirmationRequest(
            title: "Essai à blanc de l'extraction ?",
            message: "Le LLM d'extraction lit \(Format.number(text.count)) caractères avec les réglages du brouillon. Rien n'est enregistré dans la banque.\n\n\(e?.summary ?? "")",
            confirmTitle: "Lancer l'essai", severity: .normal
        ) { [weak self] in
            await self?.runTrial(text)
        }
    }

    func runTrial(_ text: String) async {
        trial = .loading
        trialEstimate = nil
        let d = draft
        let req = DryRunExtractRequest(
            content: .text(text),
            retainMission: d.retainMission.isEmpty ? nil : d.retainMission,
            retainExtractionMode: d.extractionMode,
            retainCustomInstructions: d.extractionMode == "custom" ? d.customInstructions : nil,
            retainChunkSize: d.chunkSize,
            entityLabels: d.entityLabels.isEmpty ? nil : d.entityLabels.compactMap(\.labelGroupInput),
            entitiesAllowFreeForm: d.entitiesAllowFreeForm)
        do {
            let r = try await client.dryRunExtract(bank, req)
            trial = .loaded(r)
            if let u = r.usage, let estimator {
                // Projection : ce que coûterait un document de 100 000 caractères avec ces réglages.
                trialEstimate = estimator.extrapolate(
                    measured: TokenCount(input: u.inputTokens, output: u.outputTokens, cached: u.cachedTokens, thoughts: u.thoughtsTokens),
                    sampleCharacters: text.count, totalCharacters: 100_000, bank: bank)
            }
        } catch {
            trial = .failed(error.userMessage)
        }
    }
}
