import Foundation
import HindsightAPI
import Observation

/// Lecteur d'un document source : texte (transcription) avec ses pièces jointes en place, repérage d'un
/// chunk/fait, recherche dans le texte et liste des faits extraits du document.
@MainActor
@Observable
public final class DocumentReaderViewModel: Identifiable {
    public nonisolated let documentID: String
    public let bank: String
    public let attachmentLoader: AttachmentLoader
    @ObservationIgnored private let client: HindsightClient

    public private(set) var state: LoadState<Void> = .idle
    /// Estimation de coût d'une action (fournie par la session ; absente dans certains tests).
    @ObservationIgnored public var estimate: (@MainActor (EstimateKind) -> CostEstimate?)?
    /// Refus pendant une pause de la banque.
    @ObservationIgnored public var pauseGate: PauseGate?
    public private(set) var document: DocumentResponse?
    /// « Créer des observations » pour cette banque, lu à l'ouverture (nil si le serveur ne le dit pas).
    public private(set) var createsObservations: Bool?
    /// Serveur 1.1.0 : historique du document et portée modifiable (réglé à la création).
    public var serverIs110 = false
    /// Ce qui a changé le document et ses faits, du plus récent au plus ancien (nil : non chargé ou serveur 1.0.0).
    public private(set) var history: [DocumentEvent]?
    public private(set) var chunks: [ChunkResponse] = []
    public private(set) var blocks: [ReaderBlock] = []
    public private(set) var attachments: [ChunkAttachment] = []
    /// Texte affiché (original_text, ou chunks recollés si le serveur ne stocke pas le texte).
    public private(set) var sourceText: String = ""
    /// Note affichée au-dessus du texte quand la source n'est pas le texte original.
    public private(set) var sourceNote: String?

    // Repérage
    public private(set) var focusedChunkID: String?
    public private(set) var focusedBlockIDs: Set<Int> = []
    /// Bloc vers lequel la vue doit défiler ; la vue l'efface via `consumeScrollTarget()`.
    public private(set) var scrollTarget: Int?
    @ObservationIgnored private var chunkRanges: [String: Range<Int>] = [:]

    // Recherche dans le document
    public var findQuery: String = "" {
        didSet { if oldValue != findQuery { recomputeMatches() } }
    }
    public private(set) var matchBlockIDs: [Int] = []
    public private(set) var currentMatch: Int?

    // Administration (toujours confirmée)
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?
    /// Appelé après suppression du document (pour fermer le lecteur et rafraîchir la liste).
    @ObservationIgnored public var onDeleted: (@MainActor () -> Void)?
    @ObservationIgnored public var onChanged: (@MainActor () -> Void)?
    /// Le propriétaire attend la relecture avant que la confirmation ne rende son snapshot à l'UI.
    /// Les notifications publiques restent synchrones et indépendantes d'un écran de suivi.
    @ObservationIgnored var refreshListAfterChange: (@MainActor () async -> Void)?
    /// Appelé quand le retraitement est lancé : le document repart en extraction.
    @ObservationIgnored public var onReprocessed: (@MainActor () -> Void)?

    // Faits extraits de ce document
    public private(set) var facts: LoadState<[MemoryUnitListItem]> = .idle
    public private(set) var factsTotal: Int = 0
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var factsLoadID = UUID()
    @ObservationIgnored private var factsLimit = 200

    public nonisolated var id: String { documentID }

    public init(client: HindsightClient, bank: String, documentID: String, attachmentLoader: AttachmentLoader) {
        self.client = client
        self.bank = bank
        self.documentID = documentID
        self.attachmentLoader = attachmentLoader
    }

    // MARK: Chargement

    public func load(focusChunk: String? = nil) async {
        let id = UUID()
        loadID = id
        state = .loading
        do {
            try Task.checkCancellation()
            async let doc = client.document(bank, id: documentID)
            async let chunkList = Self.loadAllChunks(client: client, bank: bank, documentID: documentID)
            async let config = try? client.bankConfig(bank)
            let (d, cs) = try await (doc, chunkList)
            let bankConfig = await config
            try Task.checkCancellation()
            guard loadID == id else { return }
            document = d
            createsObservations = bankConfig.map { ConsolidationStatus.createsObservations($0, serverObservations: nil) }
            chunks = cs.sorted { $0.chunkIndex < $1.chunkIndex }
            attachments = DocumentTextParser.merge([d.attachments] + chunks.map { $0.attachments })
            buildSource()
            state = .loaded(())
            if let focusChunk { focus(chunkID: focusChunk) }
            recomputeMatches()
            // L'historique est un complément : son absence n'empêche pas de lire le document.
            if serverIs110 {
                let events = try? await client.documentHistory(bank, id: documentID, limit: 50).items
                guard loadID == id, !Task.isCancelled else { return }
                history = events
            }
        } catch {
            guard loadID == id else { return }
            state = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
        }
    }

    static func loadAllChunks(client: HindsightClient, bank: String, documentID: String) async throws -> [ChunkResponse] {
        var all: [ChunkResponse] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await client.documentChunks(bank, id: documentID, limit: 1000, offset: offset)
            try Task.checkCancellation()
            all += page.items
            offset += page.items.count
            if page.items.isEmpty || offset >= page.total { break }
        }
        return all
    }

    private func buildSource() {
        let ordered = chunks
        if let text = document?.originalText, !text.isEmpty {
            sourceText = text
            sourceNote = nil
            chunkRanges = Self.locate(chunks: ordered, in: text)
        } else {
            // Le serveur peut ne pas stocker le texte original : on recolle les chunks, dont les bornes sont exactes.
            var text = ""
            var ranges: [String: Range<Int>] = [:]
            var offset = 0
            for (i, c) in ordered.enumerated() {
                if i > 0 {
                    text += "\n\n"
                    offset += 2
                }
                let len = c.chunkText.utf16.count
                ranges[c.chunkId] = offset..<(offset + len)
                text += c.chunkText
                offset += len
            }
            sourceText = text
            sourceNote =
                ordered.isEmpty
                ? "Aucun texte disponible pour ce document."
                : "Texte reconstitué à partir des segments : le texte original n'est pas stocké sur le serveur, ce document ne peut donc pas être retraité."
            chunkRanges = ranges
        }
        blocks = DocumentTextParser.parse(text: sourceText, attachments: attachments)
        blocks += DocumentTextParser.unreferencedBlocks(attachments: attachments, after: blocks, textLength: sourceText.utf16.count)
    }

    /// Localise chaque chunk dans le texte original, en avançant séquentiellement (les chunks se suivent).
    static func locate(chunks: [ChunkResponse], in text: String) -> [String: Range<Int>] {
        let ns = NSString(string: text)
        var out: [String: Range<Int>] = [:]
        var from = 0
        for c in chunks {
            let needle = c.chunkText
            guard !needle.isEmpty else { continue }
            var r = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound {
                r = ns.range(of: needle)  // repli : recherche depuis le début
            }
            if r.location == NSNotFound {
                // Repli : les 120 premiers caractères suffisent à repérer l'endroit.
                let head = String(needle.prefix(120))
                r = ns.range(of: head, options: [], range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { r = ns.range(of: head) }
                if r.location != NSNotFound {
                    r.length = min(needle.utf16.count, ns.length - r.location)
                }
            }
            if r.location != NSNotFound {
                out[c.chunkId] = r.location..<(r.location + r.length)
                // Les chunks peuvent se chevaucher : le suivant commence après le début de celui-ci.
                from = min(r.location + 1, ns.length)
            }
        }
        return out
    }

    // MARK: Repérage

    public func focus(chunkID: String?) {
        focusedChunkID = chunkID
        guard let chunkID, let range = chunkRanges[chunkID] else {
            focusedBlockIDs = []
            return
        }
        let ids = blocks.filter { $0.range.overlaps(range) }.map(\.id)
        focusedBlockIDs = Set(ids)
        scrollTarget = ids.first
    }

    public func focus(fact: MemoryUnitListItem) {
        focus(chunkID: fact.chunkId)
    }

    public func consumeScrollTarget() { scrollTarget = nil }

    // MARK: Recherche

    private func recomputeMatches() {
        let q = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            matchBlockIDs = []
            currentMatch = nil
            return
        }
        matchBlockIDs = blocks.filter { $0.text?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.map(\.id)
        currentMatch = matchBlockIDs.isEmpty ? nil : 0
        if let first = matchBlockIDs.first { scrollTarget = first }
    }

    public func nextMatch() { stepMatch(+1) }
    public func previousMatch() { stepMatch(-1) }

    private func stepMatch(_ delta: Int) {
        guard !matchBlockIDs.isEmpty else { return }
        let n = matchBlockIDs.count
        let next = ((currentMatch ?? -1) + delta + n) % n
        currentMatch = next
        scrollTarget = matchBlockIDs[next]
    }

    // MARK: Faits du document

    public func loadFacts(limit: Int = 200) async {
        let id = UUID()
        factsLoadID = id
        factsLimit = max(1, limit)
        facts = .loading
        do {
            try Task.checkCancellation()
            let page = try await client.listMemories(bank, MemoryListQuery(documentID: documentID, limit: factsLimit))
            try Task.checkCancellation()
            guard factsLoadID == id else { return }
            factsTotal = page.total
            facts = .loaded(page.items)
        } catch {
            guard factsLoadID == id else { return }
            facts = Task.isCancelled || error is CancellationError ? .idle : .failed(error.userMessage)
        }
    }

    private func refreshAfterChange() async {
        await load(focusChunk: focusedChunkID)
        await loadFacts(limit: factsLimit)
        onChanged?()
        await refreshListAfterChange?()
    }

    // MARK: Administration du document

    /// Les tags envoyés REMPLACENT ceux du document (contrat de l'API).
    public func requestUpdateTags(_ tags: [String]) {
        let clean = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        let current = (document?.tags ?? []).sorted()
        guard clean != current else { return }
        let removed = current.filter { !clean.contains($0) }, added = clean.filter { !current.contains($0) }
        confirmation = ConfirmationRequest(
            title: "Enregistrer les étiquettes du document ?",
            message: "Ajoutées : \(added.isEmpty ? "—" : added.joined(separator: ", "))\nRetirées : \(removed.isEmpty ? "—" : removed.joined(separator: ", "))\n\n"
                + (createsObservations == false
                    ? "Les étiquettes sont propagées à tous ses faits. Cette banque ne crée pas d'observations : rien n'est reconsolidé."
                    : "Les étiquettes sont propagées à tous ses faits ; les observations concernées sont invalidées et reconsolidées sous les nouvelles étiquettes (appel LLM)."),
            confirmTitle: "Enregistrer les étiquettes", severity: removed.isEmpty ? .normal : .destructive
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateDocumentTags(self.bank, id: self.documentID, tags: clean)
                self.actionMessage = "Étiquettes mises à jour."
                await self.refreshAfterChange()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Portée actuelle du document, en clair (nil si le serveur n'en dit rien).
    public var currentScope: String? {
        ObservationScope.label(document?.observationScopes, retainParams: document?.retainParams)
    }

    /// Portée actuelle quand c'est un mode nommé (« shared »…) ; nil pour une liste d'étiquettes ou si inconnue.
    public var currentScopeMode: String? {
        if case .string(let s)? = document?.observationScopes ?? document?.retainParams?["observation_scopes"] { return s }
        return nil
    }

    /// Portées proposées dans le lecteur (les listes explicites d'étiquettes restent possibles par l'API).
    public static let scopeModes = ["shared", "combined", "per_tag", "all_combinations"]

    /// Serveur 1.1.0 : change la portée des observations du document sans réextraire ses faits.
    public func requestUpdateScope(_ mode: String) {
        guard serverIs110 else {
            actionMessage = "Changer la portée d'un document demande un serveur Hindsight 1.1.0 ou plus récent."
            return
        }
        guard createsObservations != false else {
            actionMessage = "Cette banque ne crée pas d'observations : changer la portée n'aurait aucun effet."
            return
        }
        let current = currentScope
        guard current != ObservationScope.label(.string(mode)) else {
            actionMessage = "Ce document a déjà cette portée."
            return
        }
        let target = ObservationScope.label(.string(mode)) ?? mode
        confirmation = ConfirmationRequest(
            title: "Passer la portée en « \(target) » ?",
            message: "Actuelle : \(current ?? "inconnue"). Les faits ne sont pas réextraits. Ceux dont les observations changent de portée les perdent et repartent en consolidation (appel LLM), avec les faits d'autres documents qui les partageaient. Un changement qui laisse chaque fait dans les mêmes observations ne relance rien.",
            confirmTitle: "Changer la portée", severity: .destructive
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.client.updateDocumentScopes(self.bank, id: self.documentID, scopes: .string(mode))
                self.actionMessage = "Portée mise à jour."
                await self.refreshAfterChange()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    /// Le serveur réextrait le texte original stocké : sans lui, rien à retraiter.
    public var canReprocess: Bool { !(document?.originalText ?? "").isEmpty }

    public func requestReprocess() async {
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        guard canReprocess else {
            actionMessage = "Ce document ne peut pas être retraité : son texte original n'est pas stocké sur le serveur."
            return
        }
        // La consolidation n'entre dans l'estimation que si la banque consolide après l'extraction.
        let consolidates = ConsolidationStatus.consolidatesAfterExtraction(try? await client.bankConfig(bank), serverObservations: nil)
        let facts = document?.memoryUnitCount ?? 0
        confirmation = ConfirmationRequest(
            title: "Retraiter ce document ?",
            message: "\(facts == 1 ? "Son fait sera supprimé puis ré-extrait" : "Ses \(Format.number(facts)) faits seront supprimés puis ré-extraits") avec la configuration actuelle du serveur (appels LLM et VLM). Les corrections manuelles faites sur ces faits seront perdues."
                + (document.flatMap { d in
                    estimate?(.retain(characters: d.originalText?.count ?? 0, images: d.attachments?.count ?? 0, consolidation: consolidates))
                }.map { "\n\n" + $0.summary } ?? ""),
            confirmTitle: "Retraiter"
        ) { [weak self] in
            guard let self else { return }
            // Une pause a pu être décidée pendant que la confirmation était ouverte.
            if let reason = self.pauseGate?(self.bank) {
                self.actionMessage = reason
                return
            }
            do {
                let r = try await self.client.reprocessDocument(self.bank, id: self.documentID)
                _ = r
                self.actionMessage = "Retraitement en file : suivez-le dans « Activité › Traitements »."
                self.onReprocessed?()
                // La soumission est asynchrone : relire l'état actuel ne prétend pas que l'opération
                // est terminée, mais évite de conserver indéfiniment les faits de l'ancien snapshot.
                await self.refreshAfterChange()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }

    public func requestDelete() {
        confirmation = ConfirmationRequest(
            title: "Supprimer définitivement ce document ?",
            message: {
                let n = document?.memoryUnitCount ?? 0
                let what = n == 0 ? "Le document et ses segments sont supprimés"
                    : n == 1 ? "Le document, ses segments et son fait sont supprimés"
                    : "Le document, ses segments et ses \(Format.number(n)) faits sont supprimés"
                return what + ". Irréversible : exportez d'abord si besoin."
            }(),
            confirmTitle: "Supprimer", requiredText: documentID
        ) { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.client.deleteDocument(self.bank, id: self.documentID)
                self.actionMessage = "Document supprimé (\(Format.count(r.memoryUnitsDeleted, "fait")))."
                self.onDeleted?()
                await self.refreshListAfterChange?()
            } catch {
                self.actionMessage = "Échec : \(error.userMessage)"
            }
        }
    }
}
