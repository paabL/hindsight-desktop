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

    /// Résumé lisible des changements (textes longs abrégés).
    public var changeSummary: [String] {
        changes.sorted { $0.key < $1.key }.map { key, value in
            let shown: String
            switch value {
            case .null: shown = "(valeur du serveur)"
            case .string(let s): shown = "« \(s.count > 90 ? String(s.prefix(90)) + "…" : s) »"
            default:
                let p = value.prettyString().replacingOccurrences(of: "\n", with: " ")
                shown = p.count > 90 ? String(p.prefix(90)) + "…" : p
            }
            return "\(key) → \(shown)"
        }
    }

    public func requestSave() {
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
            notes.append("Sans observations, plus de consolidation : recall et reflect ne s'appuient plus que sur les faits bruts.")
        }
        if u["store_document_text"] == .bool(false) {
            notes.append("Sans texte des documents, le lecteur ne pourra plus afficher les nouveaux documents, et le retraitement sera impossible pour eux.")
        }
        confirmation = ConfirmationRequest(
            title: "Enregistrer la structure de la mémoire ?",
            message: changeSummary.joined(separator: "\n") + "\n\n" + notes.joined(separator: "\n"),
            confirmTitle: "Enregistrer", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateBankConfig(self.bank, updates: u)
                self.actionMessage = "Structure enregistrée (\(u.count) réglage(s))."
                await self.reload()
                await self.onConfigChanged?()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Remet tous les réglages de la banque aux valeurs du serveur (supprime TOUTES ses surcharges).
    public func requestResetAll() {
        confirmation = ConfirmationRequest(
            title: "Revenir à la configuration du serveur ?",
            message: "Les \(overriddenKeys.count) réglage(s) propres à « \(bank) » sont supprimés, y compris ceux de l'administration (journal d'audit, etc.). Les faits existants ne changent pas.",
            confirmTitle: "Réinitialiser"
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.resetBankConfig(self.bank)
                self.actionMessage = "Configuration réinitialisée."
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
