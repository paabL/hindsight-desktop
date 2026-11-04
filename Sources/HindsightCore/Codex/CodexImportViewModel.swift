import Foundation
import HindsightAPI
import Observation

/// Construction de banques à partir de conversations Codex entières (exigence 8 de docs/context.md).
///
/// Lecture seule des fichiers de session ; rien n'est envoyé au serveur avant une confirmation qui
/// annonce le volume et le coût (extraction LLM).
@MainActor
@Observable
public final class CodexImportViewModel {
    /// Que faire des documents déjà présents dans la banque cible ?
    public enum ConflictPolicy: String, CaseIterable, Sendable, Identifiable {
        /// Ne renvoyer que les tâches absentes.
        case skip
        /// Ne renvoyer que les absentes + les tâches qui ont grandi depuis l'import (conversation continuée).
        case complete
        /// Tout renvoyer ; les documents existants sont remplacés (faits supprimés puis réextraits).
        case replace

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .skip: return "Ignorer les documents déjà importés"
            case .complete: return "Compléter (ajouter les nouvelles tâches, remplacer celles qui ont continué)"
            case .replace: return "Tout remplacer"
            }
        }
    }

    public struct PlannedSession: Identifiable, Sendable {
        public var id: String { summary.id }
        public let summary: CodexSessionSummary
        public let meta: CodexSessionMeta
        public let tasks: [CodexTask]
        /// Tâches à envoyer et leur mode (`replace` = remplace un document existant).
        public let toSend: [(task: CodexTask, replaces: Bool)]
        public let alreadyImported: Int
        /// Tâches déjà importées dont le contenu a grandi (conversation continuée).
        public let grown: [String]
        public let warnings: [String]
    }

    public struct ImportPlan: Sendable {
        public let sessions: [PlannedSession]
        public var documents: Int { sessions.reduce(0) { $0 + $1.toSend.count } }
        public var replacements: Int { sessions.reduce(0) { $0 + $1.toSend.filter(\.replaces).count } }
        public var characters: Int { sessions.reduce(0) { $0 + $1.toSend.reduce(0) { $0 + $1.task.textLength } } }
        public var images: Int { sessions.reduce(0) { $0 + $1.toSend.reduce(0) { $0 + $1.task.imageCount } } }
        public var approxTokens: Int { characters / 4 }
        public var skipped: Int { sessions.reduce(0) { $0 + $1.alreadyImported } - replacements }
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let index: CodexIndex
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let banksProvider: @MainActor () -> [String]
    @ObservationIgnored private let createBank: @MainActor (String, String, String) async -> Bool
    /// Ouvre la section Opérations de la banque cible après l'envoi.
    @ObservationIgnored public var openOperations: (@MainActor (String) -> Void)?
    /// Estimation de coût (banque cible, puis action).
    @ObservationIgnored public var estimate: (@MainActor @Sendable (String, EstimateKind) -> CostEstimate?)?
    /// Refus pendant une pause (banque cible en pause).
    @ObservationIgnored public var pauseGate: PauseGate?

    /// Coût estimé de l'import préparé (extraction, vision et consolidation automatique).
    public var planEstimate: CostEstimate? {
        guard let p = plan.value, p.documents > 0 else { return nil }
        return estimate?(effectiveTarget, .retain(characters: p.characters, images: p.images, consolidation: true))
    }

    // Sources
    public var roots: [URL]
    public var zstd: URL? { nil }

    public private(set) var scanState: LoadState<Void> = .idle
    public private(set) var scanProgress: (done: Int, total: Int)?
    public private(set) var sessions: [CodexSessionSummary] = []

    // Filtres et sélection
    public var search = ""
    /// Afficher aussi les revues automatiques et les sous-agents (masqués par défaut).
    public var showAutomated = false
    /// Filtre par outil d'origine (`nil` = toutes les sources).
    public var sourceFilter: ConversationSource?
    public var selection: Set<String> = []

    // Aperçu
    public private(set) var previewID: String?
    public private(set) var preview: LoadState<CodexConversation> = .idle
    public var options = CodexImportOptions() {
        didSet { if oldValue != options { rebuildPreviewTasks() } }
    }
    /// Découpage de la session en aperçu (recalculé au chargement ou au changement d'options, pas à chaque rendu).
    public private(set) var previewTasks: [CodexTask] = []

    // Cible
    public var targetBankID = ""
    public var createNewBank = false
    public var newBankName = ""
    public var newBankMission = "Mémoire de mes conversations avec mes agents de code : décisions, problèmes rencontrés, solutions, préférences."
    public var conflictPolicy: ConflictPolicy = .skip

    // Plan et envoi
    public private(set) var plan: LoadState<ImportPlan> = .idle
    public private(set) var planProgress: String?
    public private(set) var sending: (done: Int, total: Int)?
    public private(set) var operationIDs: [String] = []
    public private(set) var sendErrors: [String] = []
    public private(set) var dryRun: LoadState<DryRunExtractionResult> = .idle
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?

    /// Taille maximale d'une requête de rétention (octets estimés) et nombre d'items par requête.
    public var batchByteLimit = 8_000_000
    public var batchItemLimit = 10

    public init(
        settings: SettingsStore, index: CodexIndex = CodexIndex(), roots: [URL] = CodexIndex.defaultRoots,
        client: @escaping @MainActor () -> HindsightClient, banks: @escaping @MainActor () -> [String],
        createBank: @escaping @MainActor (String, String, String) async -> Bool
    ) {
        self.settings = settings
        self.index = index
        self.roots = roots
        self.clientProvider = client
        self.banksProvider = banks
        self.createBank = createBank
    }

    // MARK: Inventaire

    public func scanIfNeeded() async {
        if sessions.isEmpty, !scanState.isLoading { await scan() }
    }

    public func scan() async {
        scanState = .loading
        scanProgress = nil
        let roots = self.roots, zstd = self.zstd, index = self.index
        let result = await index.scan(roots: roots, zstd: zstd) { [weak self] done, total in
            await MainActor.run { self?.scanProgress = (done, total) }
        }
        sessions = result
        scanProgress = nil
        selection = selection.filter { id in result.contains { $0.id == id } }
        scanState = .loaded(())
        if result.isEmpty {
            actionMessage = "Aucune session trouvée dans : " + roots.map(\.path).joined(separator: ", ")
        }
    }

    public var filteredSessions: [CodexSessionSummary] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return sessions.filter { s in
            if !showAutomated, let m = s.meta, !m.isUserConversation { return false }
            if let f = sourceFilter, s.source != f { return false }
            guard !q.isEmpty else { return true }
            let hay = [s.firstUserText, s.meta?.cwd, s.meta?.id, s.meta?.originator, s.file.path].compactMap { $0 }.joined(separator: " ")
            return hay.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Nombre de sessions par outil (pour le filtre).
    public func count(_ source: ConversationSource) -> Int { sessions.filter { $0.source == source }.count }

    public var hiddenAutomatedCount: Int {
        sessions.filter { s in s.meta.map { !$0.isUserConversation } ?? false }.count
    }

    public var compressedWithoutZstd: Int {
        zstd == nil ? sessions.filter { $0.file.isCompressed }.count : 0
    }

    public func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        plan = .idle
    }

    public func selectAllVisible() {
        for s in filteredSessions where s.error == nil && !s.isLegacyFlat { selection.insert(s.id) }
        plan = .idle
    }

    public func clearSelection() {
        selection = []
        plan = .idle
    }

    /// Un changement d'option ou de cible rend le plan obsolète.
    public func invalidatePlan() async {
        if case .loaded = plan { plan = .idle }
    }

    // MARK: Aperçu d'une session

    public func showPreview(_ id: String?) async {
        previewID = id
        dryRun = .idle
        guard let id, let s = sessions.first(where: { $0.id == id }) else {
            preview = .idle
            previewTasks = []
            return
        }
        preview = .loading
        previewTasks = []
        let file = s.file, zstd = self.zstd
        do {
            let conv = try await Task.detached(priority: .userInitiated) { try ConversationReader.parse(file, zstd: zstd) }.value
            if previewID == id {
                preview = .loaded(conv)
                rebuildPreviewTasks()
            }
        } catch {
            if previewID == id { preview = .failed("\(error)") }
        }
    }

    private func rebuildPreviewTasks() {
        previewTasks = preview.value.map { CodexTranscript.tasks($0, options: options) } ?? []
    }

    /// Texte lisible d'une tâche (blocs texte concaténés, images signalées).
    public static func plainText(_ t: CodexTask) -> String {
        switch t.content {
        case .text(let s): return s
        case .blocks(let bs):
            return bs.map { b -> String in
                switch b {
                case .text(let tb): return tb.text
                case .image: return "🖼"
                case .file(let f): return "[fichier \(f.filename ?? "")]"
                }
            }.joined()
        }
    }

    // MARK: Plan d'import

    public var canPlan: Bool {
        !selection.isEmpty && !effectiveTarget.isEmpty && (createNewBank ? newBankProblem == nil : true)
    }

    public var effectiveTarget: String { targetBankID.trimmingCharacters(in: .whitespaces) }

    public var newBankProblem: String? {
        guard createNewBank else { return nil }
        let id = effectiveTarget
        if id.isEmpty || id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) == nil {
            return "Identifiant de banque invalide."
        }
        if banksProvider().contains(id) { return "La banque « \(id) » existe déjà : décochez « nouvelle banque »." }
        return nil
    }

    /// Lit les sessions choisies, découpe en tâches et compare avec la banque cible.
    public func preparePlan() async {
        guard canPlan else { return }
        plan = .loading
        let chosen = sessions.filter { selection.contains($0.id) }.sorted { $0.sortDate < $1.sortDate }
        let client = clientProvider(), bank = effectiveTarget, zstd = self.zstd, options = self.options
        let policy = conflictPolicy, isNew = createNewBank
        var planned: [PlannedSession] = []
        for (i, s) in chosen.enumerated() {
            planProgress = "Lecture \(i + 1)/\(chosen.count) : \(s.meta?.projectName ?? s.file.url.lastPathComponent)…"
            do {
                let file = s.file
                let conv = try await Task.detached(priority: .userInitiated) { try ConversationReader.parse(file, zstd: zstd) }.value
                let tasks = CodexTranscript.tasks(conv, options: options)
                let existing =
                    isNew ? [:] : try await Self.existingDocuments(client: client, bank: bank, prefix: CodexTranscript.documentID(sessionID: conv.meta.id, task: nil, source: conv.meta.source))
                planned.append(Self.plan(summary: s, conv: conv, tasks: tasks, existing: existing, policy: policy))
            } catch is CancellationError {
                plan = .idle
                planProgress = nil
                return
            } catch {
                planned.append(
                    PlannedSession(
                        summary: s, meta: s.meta ?? CodexSessionMeta(id: "?"), tasks: [], toSend: [], alreadyImported: 0, grown: [],
                        warnings: ["Lecture impossible : \(error.userMessage)"]))
            }
        }
        planProgress = nil
        plan = .loaded(ImportPlan(sessions: planned))
    }

    /// Documents `<source>-<session>…` déjà présents : identifiant → longueur du texte.
    static func existingDocuments(client: HindsightClient, bank: String, prefix: String) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        var offset = 0
        while true {
            let page = try await client.listDocuments(bank, q: prefix, limit: 100, offset: offset)
            for d in page.items where d.id.hasPrefix(prefix) { out[d.id] = d.textLength }
            offset += page.items.count
            if page.items.isEmpty || offset >= page.total { break }
        }
        return out
    }

    /// Décide quoi envoyer pour une session. Une tâche « a grandi » si son texte dépasse nettement celui
    /// du document importé (la conversation a continué dans cette tâche).
    static func plan(
        summary: CodexSessionSummary, conv: CodexConversation, tasks: [CodexTask], existing: [String: Int], policy: ConflictPolicy
    ) -> PlannedSession {
        var toSend: [(CodexTask, Bool)] = []
        var grown: [String] = []
        var already = 0
        for t in tasks {
            guard let len = existing[t.documentID] else {
                toSend.append((t, false))
                continue
            }
            already += 1
            let hasGrown = t.textLength > len + max(200, len / 10)
            if hasGrown { grown.append(t.documentID) }
            switch policy {
            case .skip: break
            case .complete: if hasGrown { toSend.append((t, true)) }
            case .replace: toSend.append((t, true))
            }
        }
        var warnings = conv.warnings
        if tasks.isEmpty { warnings.append("Aucun échange utilisateur/Codex à importer dans cette session.") }
        if let m = summary.meta, m.forkedFromID != nil {
            warnings.append("Session copiée d'une autre (forked_from_id) : son début peut répéter la session d'origine.")
        }
        if conv.imageCount > 0, !tasks.contains(where: { $0.imageCount > 0 }) {
            warnings.append("Images présentes mais non importées (option désactivée).")
        }
        return PlannedSession(
            summary: summary, meta: conv.meta, tasks: tasks, toSend: toSend, alreadyImported: already, grown: grown, warnings: warnings)
    }

    // MARK: Aperçu d'extraction (facultatif, appelle le LLM)

    public func requestDryRun(_ task: CodexTask) {
        guard !createNewBank, !effectiveTarget.isEmpty, let conv = preview.value else {
            actionMessage = "L'aperçu d'extraction utilise la configuration d'une banque existante : choisissez-en une."
            return
        }
        let bank = effectiveTarget
        let item = CodexTranscript.memoryItem(task, meta: conv.meta, options: options)
        confirmation = ConfirmationRequest(
            title: "Aperçu des faits extraits ?",
            message: "La tâche \(CodexTranscript.taskNumber(task.number)) (≈ \(Format.number(task.approxTokens)) jetons) est envoyée au LLM d'extraction de « \(bank) » pour voir les faits produits. Rien n'est enregistré.",
            confirmTitle: "Lancer l'aperçu", severity: .normal
        ) { [weak self] in
            guard let self else { return }
            self.dryRun = .loading
            do {
                let r = try await self.clientProvider().dryRunExtract(
                    bank, DryRunExtractRequest(content: item.content, context: item.context ?? "", timestamp: task.date.map(HSDate.format)))
                self.dryRun = .loaded(r)
            } catch {
                self.dryRun = .failed(error.userMessage)
            }
        }
    }

    // MARK: Envoi (confirmé)

    public func requestImport() {
        guard let p = plan.value, p.documents > 0 else { return }
        let bank = effectiveTarget
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        var lines = [
            "\(p.documents) document(s) issus de \(p.sessions.count) session(s) → banque « \(bank) »\(createNewBank ? " (nouvelle)" : "").",
            "≈ \(Format.number(p.approxTokens)) jetons de texte et \(p.images) image(s) envoyés au LLM d'extraction (et au VLM pour les images).",
        ]
        lines.append("Documents sélectionnés :")
        lines.append(contentsOf: p.sessions.flatMap { session in
            session.toSend.map { "• " + $0.task.documentID + " — " + $0.task.title }
        })
        if p.replacements > 0 {
            lines.append("\(p.replacements) document(s) existant(s) seront REMPLACÉS : leurs faits actuels sont supprimés puis réextraits.")
        }
        if p.skipped > 0 { lines.append("\(p.skipped) document(s) déjà présent(s) ignoré(s).") }
        if let e = planEstimate { lines.append(e.summary) }
        lines.append("L'extraction se fait en tâche de fond ; suivez-la dans « Opérations ».")
        confirmation = ConfirmationRequest(
            title: "Importer dans « \(bank) » ?", message: lines.joined(separator: "\n"), confirmTitle: "Importer",
            severity: p.replacements > 0 ? .destructive : .normal
        ) { [weak self] in
            guard let self else { return }
            // Une pause a pu être décidée pendant que la confirmation était ouverte.
            if let reason = self.pauseGate?(bank) {
                self.actionMessage = reason
                return
            }
            await self.performImport(p, bank: bank)
        }
    }

    func performImport(_ p: ImportPlan, bank: String) async {
        operationIDs = []
        sendErrors = []
        if createNewBank {
            let ok = await createBank(bank, newBankName, newBankMission)
            guard ok else {
                actionMessage = "La banque « \(bank) » n'a pas pu être créée : import annulé."
                return
            }
            createNewBank = false
            targetBankID = bank
        }
        let client = clientProvider()
        var items: [(item: MemoryItem, bytes: Int)] = []
        for s in p.sessions {
            for (t, _) in s.toSend {
                // `replace` (défaut serveur) : sans effet pour un nouveau document, remplace un existant.
                let item = CodexTranscript.memoryItem(t, meta: s.meta, options: options, updateMode: "replace")
                items.append((item, t.textLength + t.imageBytes * 4 / 3 + 2000))
            }
        }
        let batches = Self.batches(items, byteLimit: batchByteLimit, itemLimit: batchItemLimit)
        sending = (0, items.count)
        var sent = 0
        for batch in batches {
            do {
                let r = try await client.retain(bank, RetainRequest(items: batch, async: true))
                operationIDs += r.operationIds ?? r.operationId.map { [$0] } ?? []
                sent += batch.count
            } catch is CancellationError {
                break
            } catch {
                sendErrors.append("Lot de \(batch.count) document(s) (\(batch.first?.documentId ?? "?")…) : \(error.userMessage)")
            }
            sending = (sent, items.count)
        }
        sending = nil
        actionMessage =
            "\(sent)/\(items.count) document(s) mis en file d'extraction dans « \(bank) » (\(operationIDs.count) opération(s))."
            + (sendErrors.isEmpty ? "" : " \(sendErrors.count) lot(s) refusé(s).")
        plan = .idle
    }

    /// Lots respectant un nombre d'items et une taille estimée maximum (un item trop gros part seul).
    static func batches(_ items: [(item: MemoryItem, bytes: Int)], byteLimit: Int, itemLimit: Int) -> [[MemoryItem]] {
        var out: [[MemoryItem]] = []
        var cur: [MemoryItem] = []
        var size = 0
        for (item, bytes) in items {
            if !cur.isEmpty, cur.count >= itemLimit || size + bytes > byteLimit {
                out.append(cur)
                cur = []
                size = 0
            }
            cur.append(item)
            size += bytes
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
