import Foundation
import HindsightAPI
import Observation

/// Les documents de la banque et leurs sources, réunis : compare les dossiers suivis (métadonnées `repo` et
/// `path`) et les sessions Codex / Claude Code aux documents de la banque, liste aussi les documents
/// sans source suivie ; envoie ou retire les documents après validation explicite.
/// La liste (`library`) est ce qu'affiche l'écran « Documents ».
@MainActor
@Observable
public final class FileCoverageViewModel {
    /// Contenu préparé d'un envoi : textes par `retain`, autres fichiers par `files/retain`.
    public struct Upload: Sendable {
        public let items: [(item: MemoryItem, bytes: Int)]
        public let files: [(file: UploadFile, metadata: FileRetainMetadata)]
        /// Caractères envoyés à l'extraction ; pour un PDF ou un fichier Office, estimés à un dixième de sa taille.
        public let characters: Int
        public let unreadable: [String]
        public var count: Int { items.count + files.count }
        public var approxTokens: Int { characters / 4 }
    }

    /// Coût réel d'extraction d'un fichier, d'après les traces LLM du serveur.
    public struct Cost: Sendable {
        public init(calls: Int, tokens: TokenCount, dollars: Double, unpriced: Int, documentsRead: Int) {
            self.calls = calls
            self.tokens = tokens
            self.dollars = dollars
            self.unpriced = unpriced
            self.documentsRead = documentsRead
        }

        public let calls: Int
        public let tokens: TokenCount
        public let dollars: Double
        /// Appels inclus dans un abonnement, locaux ou hors grille tarifaire (non comptés dans `dollars`).
        public let unpriced: Int
        /// Documents dont les traces ont été lues (les fichiers découpés en ont beaucoup).
        public let documentsRead: Int
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let scanner: FileCoverageScanner
    @ObservationIgnored private let clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let bankProvider: @MainActor () -> String?
    @ObservationIgnored public var estimate: (@MainActor @Sendable (String, EstimateKind) -> CostEstimate?)?
    @ObservationIgnored public var priceBook: (@MainActor () -> PriceBook)?
    /// Refus pendant une pause de la banque : ni envoi, ni synchronisation automatique.
    @ObservationIgnored public var pauseGate: PauseGate?
    /// Politique du dossier commun, relue avant préparation et avant confirmation effective.
    @ObservationIgnored public var memoryPolicyURL: (@MainActor () -> URL?)?
    /// Sessions de conversation connues d'un catalogue (lecture seule).
    @ObservationIgnored public var sessions: (@MainActor () async -> [CodexSessionSummary])?
    @ObservationIgnored public var openOperations: (@MainActor () -> Void)?
    @ObservationIgnored public var openDocument: (@MainActor (String) -> Void)?

    public private(set) var roots: [CoverageRoot] = []
    public var includeConversations = false {
        didSet { if let bank { settings.set(includeConversations ? nil : "0", forKey: "coverageConversations.\(bank)") } }
    }
    public private(set) var state: LoadState<CoverageReport> = .idle
    public private(set) var progress: String?
    public private(set) var warnings: [String] = []
    /// Banque comparée par le dernier rapport.
    public private(set) var reportBank: String?

    public var statusFilter: CoverageStatus?
    public var search = ""
    /// Éléments choisis dans la liste (sélection multiple native).
    public var selection: Set<String> = [] {
        didSet { if selection != oldValue { invalidateApproval() } }
    }
    /// Élément affiché dans le détail (sélection simple).
    public private(set) var selectedID: String?

    /// Bibliothèque : sources suivies et documents de la banque, un élément chacun.
    public private(set) var library: [LibraryItem] = []
    public var scope: LibraryScope = .all
    public var sort: DocumentLibrary.Sort = .name
    /// Tags choisis : n'afficher que les documents qui en portent au moins un.
    public var tagFilter: Set<String> = []
    /// Relecture de la banque en cours (sans écran de chargement).
    public private(set) var isRefreshing = false
    /// Documents qu'une opération du serveur va (ré)extraire, ou que l'app vient d'envoyer.
    public private(set) var queuedIDs: Set<String> = []
    /// Coût d'extraction connu de l'historique local de consommation (35 jours), pour ces documents d'une banque.
    @ObservationIgnored public var historicalCost: (@MainActor (String, [String]) -> Cost?)?

    struct HashEntry: Sendable {
        let version: [Int64]
        let hash: String
    }

    @ObservationIgnored private var scanned: (files: [ScannedFile], sessions: [CodexSessionSummary])?
    @ObservationIgnored private var hashCache: [String: HashEntry] = [:]
    /// Envois récents (identifiant de document attendu → date), « en file » jusqu'à leur extraction.
    @ObservationIgnored private var recentSends: [String: Date] = [:]
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    /// Écrans qui demandent la relecture en direct (une vue recréée peut apparaître avant que l'ancienne disparaisse).
    @ObservationIgnored private var liveViewers = 0
    /// Documents de la dernière lecture complète, et file correspondante : base des relectures partielles.
    @ObservationIgnored private var lastDocuments: [DocumentListItem]?
    @ObservationIgnored private var entriesByID: [String: CoverageEntry] = [:]
    @ObservationIgnored private var lastQueue: (ids: Set<String>, active: Bool) = ([], false)
    /// Une banque peut porter le même nom sur plusieurs serveurs. Les chemins et options font aussi
    /// partie du contexte : un ancien inventaire ne doit jamais être réutilisé après leur modification.
    private struct Context: Equatable, Sendable {
        let revision: UUID
        let bank: String
        let server: URL
        let authorization: String?
        let roots: [CoverageRoot]
        let resolvedRoots: [URL]
        let rootIdentities: [[Int64]?]
        let conversations: Bool
        let policyURL: URL?
    }

    private struct ReadRequest: Sendable {
        let revision: UUID
        let context: Context
        let client: HindsightClient
    }

    private struct Inventory: Sendable {
        let files: [ScannedFile]
        let sessions: [CodexSessionSummary]
    }

    private struct Comparison: Sendable {
        let report: CoverageReport
        let cache: [String: HashEntry]
    }

    @ObservationIgnored private var readRevision = UUID()
    @ObservationIgnored private var contextRevision = UUID()
    @ObservationIgnored private var detailRevision = UUID()
    @ObservationIgnored private var readContext: Context?
    @ObservationIgnored private var reportContext: Context?
    @ObservationIgnored private var scannedContext: Context?
    @ObservationIgnored private var pendingAction: UUID?
    @ObservationIgnored private var preparingAction: UUID?
    @ObservationIgnored private var writeAction: UUID?
    public private(set) var cost: LoadState<Cost> = .idle
    public private(set) var sending: (done: Int, total: Int)?
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?

    /// Synchronisation automatique : intervalle et plafond de jetons envoyés par passage.
    public var autoSyncInterval: Duration = .seconds(30 * 60)
    public var autoSyncTokenLimit: Int {
        get { bank.flatMap { settings.string(forKey: "coverageAutoSyncLimit.\($0)") }.flatMap(Int.init) ?? 200_000 }
        set { if let bank { settings.set(String(max(0, newValue)), forKey: "coverageAutoSyncLimit.\(bank)") } }
    }
    public private(set) var lastAutoSync: String?
    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?

    /// Limites d'une requête `files/retain` (réglages serveur par défaut : 10 fichiers, 100 Mo).
    public var fileBatchLimit = 10
    public var fileBatchBytes = 90_000_000

    public init(
        settings: SettingsStore, scanner: FileCoverageScanner = FileCoverageScanner(),
        client: @escaping @MainActor () -> HindsightClient, bank: @escaping @MainActor () -> String?
    ) {
        self.settings = settings
        self.scanner = scanner
        self.clientProvider = client
        self.bankProvider = bank
    }

    public var bank: String? { bankProvider() }

    // MARK: Dossiers (mémorisés par banque)

    static func rootsKey(_ bank: String) -> String { "coverageRoots.\(bank)" }

    private func storedRoots(_ bank: String) -> [CoverageRoot] {
        settings.string(forKey: Self.rootsKey(bank)).flatMap { try? JSONDecoder().decode([CoverageRoot].self, from: Data($0.utf8)) } ?? []
    }

    func loadRoots() {
        guard let bank else { return roots = [] }
        roots = storedRoots(bank)
        includeConversations = false
    }

    func saveRoots() {
        guard let bank else { return }
        let json = roots.isEmpty ? nil : (try? JSONEncoder().encode(roots)).map { String(decoding: $0, as: UTF8.self) }
        settings.set(json, forKey: Self.rootsKey(bank))
    }

    public func addRoots(_ urls: [URL]) async {
        loadRoots()
        roots += urls.map(\.path).filter { p in !roots.contains { $0.path == p } }.map { CoverageRoot(path: $0) }
        saveRoots()
        await reload()
    }

    public func removeRoot(_ root: CoverageRoot) async {
        loadRoots()
        roots.removeAll { $0.path == root.path }
        saveRoots()
        await reload()
    }

    public func setAllFiles(_ on: Bool, for root: CoverageRoot) async {
        update(root) { $0.allFiles = on }
        await reload()
    }

    /// Chaque envoi requiert désormais une liste et une validation explicite.
    public func requestAutoSync(_ on: Bool, for root: CoverageRoot) {
        if !on { update(root) { $0.autoSync = false }; return }
        actionMessage = "La synchronisation automatique est suspendue : sélectionnez les documents et validez chaque envoi."
    }

    private func update(_ root: CoverageRoot, _ change: (inout CoverageRoot) -> Void) {
        loadRoots()
        guard let i = roots.firstIndex(where: { $0.path == root.path }) else { return }
        change(&roots[i])
        saveRoots()
    }

    /// Dépôts réellement analysés (un dossier de dépôts en donne plusieurs).
    public var repositories: [URL] { FileCoverageScanner.repositories(in: roots.map(\.url)) }

    // MARK: Analyse

    private func context(client: HindsightClient) -> Context? {
        guard let bank else { return nil }
        let roots = storedRoots(bank)
        return Context(revision: contextRevision, bank: bank, server: client.baseURL, authorization: client.authorization, roots: roots,
                       resolvedRoots: roots.map { $0.url.resolvingSymlinksInPath().standardizedFileURL },
                       rootIdentities: roots.map { root in (try? FileVersion(root.url).values).map { Array($0.prefix(2)) } },
                       conversations: includeConversations, policyURL: memoryPolicyURL?()?.standardizedFileURL)
    }

    private func matches(_ expected: Context) -> Bool { context(client: clientProvider()) == expected }

    private func invalidateApproval() {
        pendingAction = nil
        confirmation = nil
    }

    private func clearReport() {
        invalidateApproval()
        detailRevision = UUID()
        cost = .idle
        state = .idle
        reportBank = nil
        reportContext = nil
        scanned = nil
        scannedContext = nil
        library = []
        selection = []
        selectedID = nil
        warnings = []
        actionMessage = nil
        lastAutoSync = nil
        queuedIDs = []
        recentSends = [:]
        hashCache = [:]
        lastDocuments = nil
        entriesByID = [:]
        lastQueue = ([], false)
    }

    /// À appeler dès un changement de serveur ou de banque, avant les lectures du nouveau contexte.
    /// Invalide aussi un aller-retour A → B → A pendant une requête ou une confirmation ouverte.
    public func invalidateContext() {
        contextRevision = UUID()
        readRevision = UUID()
        readContext = nil
        clearReport()
        loadRoots()
        isRefreshing = false
        progress = nil
    }

    private func beginRead() -> ReadRequest? {
        loadRoots()
        readRevision = UUID()
        let client = clientProvider()
        guard let context = context(client: client) else {
            clearReport()
            readContext = nil
            isRefreshing = false
            progress = nil
            return nil
        }
        if (reportContext ?? readContext) != context { clearReport() }
        readContext = context
        isRefreshing = true
        return ReadRequest(revision: readRevision, context: context, client: client)
    }

    private func isCurrent(_ request: ReadRequest) -> Bool {
        !Task.isCancelled && readRevision == request.revision && matches(request.context)
    }

    private func finishRead(_ request: ReadRequest) {
        guard readRevision == request.revision else { return }
        isRefreshing = false
        progress = nil
        if state.isLoading { state = .idle }
    }

    public func loadIfNeeded() async {
        let current = context(client: clientProvider())
        if (reportContext ?? readContext) != current || (state.value == nil && !state.isLoading) { await reload() }
    }

    /// Analyse les dossiers et les conversations, puis relit la banque.
    public func reload() async {
        guard let request = beginRead() else { return }
        defer { finishRead(request) }
        if state.value == nil { state = .loading }
        let roots = request.context.roots
        progress = roots.isEmpty ? nil : "Inventaire des dossiers…"
        let (files, warnings) = roots.isEmpty ? ([], []) : await scanner.scan(roots: roots)
        guard isCurrent(request) else { return }
        var sessions: [CodexSessionSummary] = []
        if request.context.conversations, let provider = self.sessions {
            progress = "Inventaire des conversations…"
            sessions = Self.sessions(await provider(), within: roots)
        }
        guard isCurrent(request) else { return }
        self.warnings = warnings
        scanned = (files, sessions)
        scannedContext = request.context
        await readMemory(request, inventory: Inventory(files: files, sessions: sessions))
    }

    /// Relit la banque (documents, file d'attente) sans réanalyser les dossiers.
    public func refreshMemory() async {
        let current = context(client: clientProvider())
        guard let scanned, scannedContext == current, reportContext == current else { return await reload() }
        guard let request = beginRead() else { return }
        defer { finishRead(request) }
        await readMemory(request, inventory: Inventory(files: scanned.files, sessions: scanned.sessions))
    }

    private func readMemory(_ request: ReadRequest, inventory: Inventory) async {
        let bank = request.context.bank, client = request.client
        do {
            if state.value == nil { progress = "Lecture des documents de « \(bank) »…" }
            let documents = try await Self.allDocuments(client: client, bank: bank)
            guard isCurrent(request) else { return }
            let queue = await Self.queuedDocuments(client: client, bank: bank)
            guard isCurrent(request) else { return }
            if state.value == nil { progress = "Comparaison…" }
            await compare(documents: documents, queue: queue, request: request, inventory: inventory)
        } catch is CancellationError {
        } catch {
            guard isCurrent(request) else { return }
            if state.value == nil { state = .failed(error.userMessage) } else { actionMessage = "Relecture impossible : \(error.userMessage)" }
        }
    }

    /// Compare sources et documents (hors du fil principal), puis reconstruit la liste.
    private func compare(documents: [DocumentListItem], queue: (ids: Set<String>, active: Bool), request: ReadRequest, inventory: Inventory) async {
        guard isCurrent(request) else { return }
        let files = inventory.files, sessions = inventory.sessions, cache = hashCache
        let result = await Task.detached(priority: .userInitiated) {
            var cache = cache
            let r = FileCoverage.report(files: files, sessions: sessions, documents: documents) { f in Self.hash(f, cache: &cache) }
            return Comparison(report: r, cache: cache)
        }.value
        guard isCurrent(request) else { return }
        hashCache = result.cache
        lastDocuments = documents
        lastQueue = queue
        state = .loaded(result.report)
        entriesByID = [:]
        for entry in result.report.entries { entriesByID[entry.id] = entry }
        reportBank = request.context.bank
        reportContext = request.context
        rebuildLibrary(queue: queue)
    }

    /// Relit seulement les documents en file quand ils sont peu nombreux (une banque peut en compter des
    /// milliers) ; sinon toute la banque.
    public func refreshQueued() async {
        let current = context(client: clientProvider())
        guard reportContext == current, scannedContext == current, let scanned,
              var documents = lastDocuments, !queuedIDs.isEmpty, queuedIDs.count <= 25 else {
            return await refreshMemory()
        }
        guard let request = beginRead() else { return }
        defer { finishRead(request) }
        let ids = queuedIDs, client = request.client, bank = request.context.bank
        let inventory = Inventory(files: scanned.files, sessions: scanned.sessions)
        do {
            for id in ids {
                let page = try await client.listDocuments(bank, q: id, limit: 20)
                guard isCurrent(request) else { return }
                if let fresh = page.items.first(where: { $0.id == id }) {
                    if let i = documents.firstIndex(where: { $0.id == id }) { documents[i] = fresh } else { documents.append(fresh) }
                }
            }
            let queue = await Self.queuedDocuments(client: client, bank: bank)
            guard isCurrent(request) else { return }
            await compare(documents: documents, queue: queue, request: request, inventory: inventory)
        } catch {
            guard isCurrent(request) else { return }
            await readMemory(request, inventory: inventory)
        }
    }

    /// Un document vient d'être remis en extraction (retraitement) : « en file » tout de suite, puis suivi.
    public func markQueued(_ documentID: String) {
        guard let reportContext, matches(reportContext) else { return }
        recentSends[documentID] = Date()
        rebuildLibrary(queue: (lastQueue.ids, true))
    }

    /// Empreinte recalculée après remplacement ou modification, même si taille et mtime sont conservées.
    nonisolated static func hash(_ f: ScannedFile, cache: inout [String: HashEntry]) -> String? {
        guard let version = try? FileVersion(f.url).values else { return nil }
        if let c = cache[f.key], c.version == version { return c.hash }
        guard let data = try? Data(contentsOf: f.url) else { return nil }
        guard (try? FileVersion(f.url).values) == version else { return nil }
        let h = SHA256.hex(data)
        cache[f.key] = HashEntry(version: version, hash: h)
        return h
    }

    /// Documents visés par les opérations en attente ou en cours, et s'il y en a au moins une.
    nonisolated static func queuedDocuments(client: HindsightClient, bank: String) async -> (ids: Set<String>, active: Bool) {
        var ids = Set<String>()
        var active = false
        for status in ["pending", "processing"] {
            var offset = 0
            // Jusqu'à 1 000 opérations par statut : de quoi suivre un gros import.
            while offset < 1_000 {
                guard let page = try? await client.listOperations(bank, status: status, limit: 100, offset: offset, excludeParents: true) else { break }
                if page.total > 0 { active = true }
                for op in page.operations { if let d = op.documentId { ids.insert(d) } }
                offset += page.operations.count
                if page.operations.isEmpty || offset >= page.total { break }
            }
        }
        return (ids, active)
    }

    /// Reconstruit la liste ; un envoi récent reste « en file » tant que son document n'a pas été réécrit
    /// depuis, que le serveur a encore du travail (ou dans la minute qui suit l'envoi).
    private func rebuildLibrary(queue: (ids: Set<String>, active: Bool)) {
        guard let report = state.value else {
            library = []
            return
        }
        let now = Date()
        var byID: [String: DocumentListItem] = [:]
        for d in report.entries.flatMap(\.documents) + report.orphans + report.others { byID[d.id] = d }
        var queued = queue.ids
        for (id, sent) in recentSends {
            let rewritten = byID[id].flatMap { HSDate.parse($0.updatedAt) }.map { $0 >= sent } ?? false
            if rewritten || now.timeIntervalSince(sent) > 86_400 || (!queue.active && now.timeIntervalSince(sent) > 60) {
                recentSends[id] = nil
            } else {
                queued.insert(id)
            }
        }
        queuedIDs = queued
        library = DocumentLibrary.build(report: report, queued: queued)
        let ids = Set(library.map(\.id))
        selection = selection.filter { ids.contains($0) }
        if let id = selectedID, !ids.contains(id) { selectedID = nil }
    }

    /// Relit la banque toutes les 20 s tant que l'écran est visible et que des extractions sont en cours.
    public func startLiveRefresh(every interval: Duration = .seconds(20)) {
        liveViewers += 1
        guard liveTask == nil else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                if !self.queuedIDs.isEmpty, !self.isRefreshing, self.sending == nil { await self.refreshQueued() }
            }
        }
    }

    public func stopLiveRefresh() {
        liveViewers = max(0, liveViewers - 1)
        guard liveViewers == 0 else { return }
        liveTask?.cancel()
        liveTask = nil
    }

    /// Conversations ouvertes dans un dossier analysé (toutes si aucun dossier n'est choisi). Les chemins sont
    /// comparés en forme Unicode composée : « é » peut être stocké en un ou deux caractères.
    static func sessions(_ all: [CodexSessionSummary], within roots: [CoverageRoot]) -> [CodexSessionSummary] {
        guard !roots.isEmpty else { return all }
        let prefixes = roots.map { ($0.url.standardizedFileURL.path + "/").precomposedStringWithCanonicalMapping }
        return all.filter { s in
            guard let cwd = s.meta?.cwd else { return false }
            let c = (URL(fileURLWithPath: cwd).standardizedFileURL.path + "/").precomposedStringWithCanonicalMapping
            return prefixes.contains { c.hasPrefix($0) }
        }
    }

    static func allDocuments(client: HindsightClient, bank: String) async throws -> [DocumentListItem] {
        var out: [DocumentListItem] = []
        while true {
            let page = try await client.listDocuments(bank, limit: 500, offset: out.count)
            out += page.items
            if page.items.isEmpty || out.count >= page.total { return out }
        }
    }

    public var filteredEntries: [CoverageEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return (state.value?.entries ?? []).filter { e in
            if let s = statusFilter, e.status != s { return false }
            return q.isEmpty || e.file.key.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    public var selectedEntry: CoverageEntry? { selectedID.flatMap { entriesByID[$0] } }

    // MARK: Bibliothèque : filtres

    /// Éléments affichés : périmètre, tags, recherche (nom, emplacement, identifiant de document).
    public var visibleItems: [LibraryItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return library.filter { i in
            guard scope.includes(i) else { return false }
            if !tagFilter.isEmpty, tagFilter.isDisjoint(with: i.tags) { return false }
            guard !q.isEmpty else { return true }
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            return i.title.range(of: q, options: opts) != nil || i.location.range(of: q, options: opts) != nil
                || i.documents.contains { $0.id.range(of: q, options: opts) != nil }
        }
    }

    public var sections: [(group: LibraryGroup, items: [LibraryItem])] { DocumentLibrary.sections(visibleItems, sort: sort) }

    public func count(_ scope: LibraryScope) -> Int { library.filter(scope.includes).count }

    /// Tags des documents, du plus fréquent au moins fréquent.
    public var availableTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for i in library { for t in i.tags { counts[t, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { ($1.count, $0.tag) < ($0.count, $1.tag) }
    }

    public var focusedItem: LibraryItem? { library.first { $0.id == selectedID } }
    public var selectedItems: [LibraryItem] { library.filter { selection.contains($0.id) } }

    /// Élément qui contient ce document (pour suivre un document ouvert depuis un autre écran).
    public func item(containing documentID: String) -> LibraryItem? {
        library.first { i in i.documents.contains { $0.id == documentID } }
    }

    // MARK: Sélection

    /// Cochable : à envoyer (absent, modifié, sans fait) ou à retirer (présent en mémoire).
    public static func isSelectable(_ e: CoverageEntry) -> Bool {
        e.canSend || !e.documents.isEmpty
    }

    public func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Choisit les fichiers visibles et envoyables.
    public func selectVisible() {
        for i in visibleItems where i.canSend { selection.insert(i.id) }
    }

    public func clearSelection() { selection = [] }

    public var selectedEntries: [CoverageEntry] { selectedItems.compactMap(\.entry) }

    // MARK: Détail et coût réel

    /// Sélection depuis la liste : le détail suit tout de suite, le coût arrive ensuite.
    public func choose(_ id: String?) {
        guard id != selectedID else { return }
        selectedID = id
        cost = .idle
        detailRevision = UUID()
        let revision = detailRevision
        Task { await readCost(id, revision: revision) }
    }

    public func select(_ id: String?) async {
        selectedID = id
        cost = .idle
        detailRevision = UUID()
        await readCost(id, revision: detailRevision)
    }

    private func readCost(_ id: String?, revision: UUID) async {
        let client = clientProvider()
        guard revision == detailRevision, selectedID == id, let context = context(client: client), reportContext == context,
              let item = focusedItem, !item.documents.isEmpty else { return }
        let bank = context.bank
        cost = .loading
        let docs = Array(item.documents.prefix(20)), book = priceBook?() ?? .defaults
        var calls = 0, tokens = TokenCount(), dollars = 0.0, unpriced = 0
        do {
            for d in docs {
                let page = try await client.llmRequests(bank, callType: ModelCallKind.generativeFilter, documentID: d.id, limit: 500)
                guard revision == detailRevision, selectedID == id, matches(context), focusedItem?.documents == item.documents, !Task.isCancelled else { return }
                for r in page.items where r.isGenerative {
                    let t = TokenCount(input: r.inputTokens ?? 0, output: r.outputTokens ?? 0, cached: r.cachedTokens ?? 0, thoughts: r.thoughtsTokens ?? 0)
                    calls += 1
                    tokens = tokens + t
                    if let d = book.billing(provider: r.provider, model: r.model, tokens: t).dollars { dollars += d } else { unpriced += 1 }
                }
            }
            var result = Cost(calls: calls, tokens: tokens, dollars: dollars, unpriced: unpriced, documentsRead: docs.count)
            // Le serveur ne garde ses traces qu'un temps : l'historique local de l'app peut en savoir plus.
            if let h = historicalCost?(bank, item.documents.map(\.id)), h.calls > calls { result = h }
            if revision == detailRevision, selectedID == id, matches(context), focusedItem?.documents == item.documents, !Task.isCancelled { cost = .loaded(result) }
        } catch {
            if revision == detailRevision, selectedID == id, matches(context), focusedItem?.documents == item.documents, !Task.isCancelled { cost = .failed(error.userMessage) }
        }
    }

    // MARK: Envoi (confirmé)

    private struct SourceStamp: Sendable, Equatable {
        let file: ScannedFile
        let version: [Int64]
        let resolvedURL: URL
        let hash: String
    }

    private struct PreparedUpload: Sendable {
        let upload: Upload
        let sources: [SourceStamp]
    }

    /// Refuse les liens ajoutés sous un dossier choisi. Les octets lus et leur identité restent figés
    /// jusqu'à la validation ; l'envoi ne relit jamais un autre fichier à la place de celui approuvé.
    nonisolated private static func readSource(_ file: ScannedFile, roots: [CoverageRoot]?) throws -> (data: Data, stamp: SourceStamp) {
        let url = file.url.standardizedFileURL, fm = FileManager.default
        guard (try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular else {
            throw HindsightError.refused("Source remplacée ou non ordinaire : \(file.key)")
        }
        if let roots {
            guard let root = roots.first(where: {
                url.path.hasPrefix($0.url.standardizedFileURL.path + "/") && FileCoverage.includes(file.path, allFiles: $0.allFiles)
            }) else { throw HindsightError.refused("Source hors des dossiers suivis : \(file.key)") }
            let rootURL = root.url.standardizedFileURL
            var parent = url.deletingLastPathComponent()
            while parent != rootURL {
                guard (try fm.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType) == .typeDirectory else {
                    throw HindsightError.refused("Le chemin de la source a changé : \(file.key)")
                }
                let next = parent.deletingLastPathComponent()
                guard next != parent else { throw HindsightError.refused("Source hors du dossier suivi.") }
                parent = next
            }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
                throw HindsightError.refused("Source hors du dossier suivi : \(file.key)")
            }
        }
        let before = try FileVersion(url).values
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let data = try Data(contentsOf: url)
        guard try FileVersion(url).values == before,
              (try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular,
              url.resolvingSymlinksInPath().standardizedFileURL == resolved else {
            throw HindsightError.refused("Le fichier a changé pendant la lecture : \(file.key)")
        }
        return (data, SourceStamp(file: file, version: before, resolvedURL: resolved, hash: SHA256.hex(data)))
    }

    /// Lit les fichiers choisis (hors du fil principal) et prépare les requêtes.
    nonisolated static func prepare(_ files: [ScannedFile]) -> Upload { prepareFiles(files, roots: nil).upload }

    nonisolated private static func prepareFiles(_ files: [ScannedFile], roots: [CoverageRoot]?) -> PreparedUpload {
        var items: [(MemoryItem, Int)] = []
        var uploads: [(UploadFile, FileRetainMetadata)] = []
        var sources: [SourceStamp] = []
        var characters = 0
        var unreadable: [String] = []
        for f in files {
            if f.url.pathExtension.lowercased() == "pdf" {
                unreadable.append(f.key + " (PDF : fournir la source TeX ou Markdown)")
                continue
            }
            guard let source = try? readSource(f, roots: roots) else {
                unreadable.append(f.key)
                continue
            }
            let data = source.data
            if FileCoverage.isText(f.path) {
                guard let text = String(data: data, encoding: .utf8) else {
                    unreadable.append(f.key + " (pas du texte UTF-8)")
                    continue
                }
                items.append((FileCoverage.memoryItem(f, text: text), data.count + 2000))
                characters += text.count
            } else {
                let u = FileCoverage.upload(f, data: data)
                uploads.append(u)
                characters += u.file.mimeType == "text/html" ? u.file.data.count / 3 : u.file.data.count / 10
            }
            sources.append(source.stamp)
        }
        return PreparedUpload(upload: Upload(items: items, files: uploads, characters: characters, unreadable: unreadable), sources: sources)
    }

    nonisolated private static func sourcesUnchanged(_ sources: [SourceStamp], roots: [CoverageRoot]) -> Bool {
        sources.allSatisfy { source in
            guard let current = try? readSource(source.file, roots: roots) else { return false }
            return current.stamp == source
        }
    }

    private func selectionPolicyError(_ entries: [CoverageEntry], bank: String) -> String? {
        guard let provider = memoryPolicyURL else { return nil }
        guard let url = provider() else { return "Choisissez le dossier mémoire commun avant de préparer un envoi." }
        do {
            guard let policy = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                policy["version"] as? Int == 1, let target = policy["bank_id"] as? String,
                let excluded = policy["excluded_document_ids"] as? [String: Any],
                let deferred = policy["deferred_document_ids"] as? [String: Any]
            else { return "La politique du dossier mémoire est invalide ; aucun envoi autorisé." }
            guard target == bank else { return nil }
            let blocked = Set(excluded.keys).union(deferred.keys)
            let sources = (Array(excluded.values) + Array(deferred.values)).compactMap { ($0 as? [String: Any])?["source"] as? [String: String] }
            let denied = entries.filter { entry in
                blocked.contains(FileCoverage.documentID(repo: entry.file.repo, path: entry.file.path))
                    || entry.documents.contains { blocked.contains($0.id) }
                    || sources.contains { source in
                        source["repo"]?.precomposedStringWithCanonicalMapping == entry.file.repo.precomposedStringWithCanonicalMapping
                            && source["path"]?.precomposedStringWithCanonicalMapping == entry.file.path.precomposedStringWithCanonicalMapping
                    }
            }
            return denied.isEmpty ? nil : "Sélection refusée : source archivée ou en attente de revue.\n" + denied.map { $0.file.key }.joined(separator: "\n")
        } catch {
            return "La politique du dossier mémoire est inaccessible ; aucun envoi autorisé."
        }
    }

    public func requestSend() async {
        guard writeAction == nil, preparingAction == nil else { return }
        invalidateApproval()
        let client = clientProvider()
        guard let context = context(client: client) else { return }
        let bank = context.bank, approvedSelection = selection, token = UUID()
        let selected = selectedEntries
        let entries = selected.filter(\.canSend)
        if let reason = pauseGate?(bank) ?? selectionPolicyError(entries, bank: bank) {
            actionMessage = reason
            return
        }
        guard context == reportContext else {
            actionMessage = "Le contexte a changé. Actualisez les dossiers avant de préparer l’envoi."
            return
        }
        pendingAction = token
        guard !entries.isEmpty else { invalidateApproval(); return }
        preparingAction = token
        defer { if preparingAction == token { preparingAction = nil } }
        let prepared = await Task.detached(priority: .userInitiated) { Self.prepareFiles(entries.map(\.file), roots: context.roots) }.value
        guard pendingAction == token, matches(context), selection == approvedSelection, !Task.isCancelled else {
            if pendingAction == token { invalidateApproval() }
            return
        }
        let upload = prepared.upload
        guard upload.count > 0 else {
            invalidateApproval()
            actionMessage = "Aucun fichier lisible parmi la sélection : " + upload.unreadable.joined(separator: ", ")
            return
        }
        let replaced = entries.filter { !$0.documents.isEmpty }.count
        var lines = [
            "\(upload.count) fichier(s) → banque « \(bank) » : \(upload.items.count) en texte, \(upload.files.count) converti(s) par le serveur (HTML, Office).",
            "≈ \(Format.number(upload.approxTokens)) jetons envoyés au LLM d'extraction (estimation grossière pour les fichiers convertis).",
        ]
        lines.append("Documents sélectionnés :\n" + prepared.sources.map { "• " + $0.file.key }.joined(separator: "\n"))
        if replaced > 0 { lines.append("\(replaced) document(s) existant(s) seront REMPLACÉS : leurs faits sont supprimés puis réextraits.") }
        if !upload.unreadable.isEmpty { lines.append("Ignoré(s) : " + upload.unreadable.joined(separator: ", ")) }
        if let e = estimate?(bank, .retain(characters: upload.characters, images: 0, consolidation: true)) { lines.append(e.summary) }
        lines.append("Les images intégrées aux HTML sont retirées. L'extraction se fait en tâche de fond ; suivez-la dans « Opérations ».")
        confirmation = ConfirmationRequest(
            title: "Envoyer à « \(bank) » ?", message: lines.joined(separator: "\n"), confirmTitle: "Envoyer",
            severity: replaced > 0 ? .destructive : .normal
        ) { [weak self] in
            guard let self, self.consume(token) else { return }
            defer { self.finishWrite(token) }
            guard self.validateSend(context: context, selection: approvedSelection, entries: entries) else { return }
            let unchanged = await Task.detached(priority: .userInitiated) {
                Self.sourcesUnchanged(prepared.sources, roots: context.roots)
            }.value
            guard self.validateSend(context: context, selection: approvedSelection, entries: entries) else { return }
            guard unchanged else {
                self.actionMessage = "Un fichier a été modifié ou remplacé. Préparez à nouveau l’envoi."
                return
            }
            await self.perform(upload, client: client, context: context, selection: approvedSelection, entries: entries)
        }
    }

    /// Le pont retire sa confirmation avant d'appeler `perform` ; le jeton privé reste consommable une
    /// seule fois, indépendamment de cette propriété d'affichage.
    private func consume(_ token: UUID) -> Bool {
        guard pendingAction == token, preparingAction == nil, writeAction == nil else { return false }
        pendingAction = nil
        confirmation = nil
        writeAction = token
        readRevision = UUID()
        detailRevision = UUID()
        isRefreshing = false
        progress = nil
        return true
    }

    private func finishWrite(_ token: UUID) {
        guard writeAction == token else { return }
        writeAction = nil
        sending = nil
    }

    private func validateSend(context: Context, selection approvedSelection: Set<String>, entries: [CoverageEntry]) -> Bool {
        guard !Task.isCancelled, matches(context), selection == approvedSelection else {
            actionMessage = "Le serveur, les dossiers ou la sélection ont changé. Préparez à nouveau l’envoi."
            return false
        }
        if let reason = pauseGate?(context.bank) ?? selectionPolicyError(entries, bank: context.bank) {
            actionMessage = reason
            return false
        }
        guard reportContext == context, entries.allSatisfy({ approved in
            guard let current = entriesByID[approved.id] else { return false }
            return current.file.url == approved.file.url && current.documents == approved.documents && current.canSend
        }) else {
            actionMessage = "Les documents ont changé. Actualisez la liste avant de préparer l’envoi."
            return false
        }
        return true
    }

    @discardableResult
    private func perform(_ upload: Upload, client: HindsightClient, context: Context, selection approvedSelection: Set<String>, entries: [CoverageEntry]) async -> Int {
        let bank = context.bank
        var operations = 0, sent = 0, errors: [String] = []
        sending = (0, upload.count)
        let start = Date()
        for batch in RetainBatching.batches(upload.items, byteLimit: 8_000_000, itemLimit: 10) {
            guard validateSend(context: context, selection: approvedSelection, entries: entries) else { return sent }
            do {
                let r = try await client.retain(bank, RetainRequest(items: batch, async: true))
                guard r.success else { throw HindsightError.refused("L’envoi a été refusé par le serveur.") }
                operations += r.operationIds?.count ?? (r.operationId == nil ? 0 : 1)
                sent += batch.count
                if matches(context) { for item in batch { if let id = item.documentId { recentSends[id] = start } } }
            } catch {
                errors.append("\(batch.first?.documentId ?? "?")… : \(error.userMessage)")
            }
            if matches(context) { sending = (sent, upload.count) }
        }
        for batch in Self.fileBatches(upload.files, limit: fileBatchLimit, bytes: fileBatchBytes) {
            guard validateSend(context: context, selection: approvedSelection, entries: entries) else { return sent }
            do {
                let r = try await client.retainFiles(bank, files: batch.map(\.file), metadata: batch.map(\.metadata))
                operations += r.operationIds.count
                sent += batch.count
                if matches(context) { for f in batch { if let id = f.metadata.documentId { recentSends[id] = start } } }
            } catch {
                errors.append("\(batch.first?.metadata.documentId ?? "?")… : \(error.userMessage)")
            }
            if matches(context) { sending = (sent, upload.count) }
        }
        guard matches(context), !Task.isCancelled else { return sent }
        sending = nil
        if selection == approvedSelection { selection = [] }
        actionMessage =
            "\(sent)/\(upload.count) fichier(s) mis en file d'extraction dans « \(bank) » (\(operations) opération(s))."
            + (errors.isEmpty ? "" : " Refusés : " + errors.joined(separator: " ; "))
        if sent > 0, reportContext == context { await refreshMemory() }
        return sent
    }

    /// Lots de fichiers sous les limites du serveur (un fichier trop gros part seul).
    nonisolated static func fileBatches(_ files: [(file: UploadFile, metadata: FileRetainMetadata)], limit: Int, bytes: Int)
        -> [[(file: UploadFile, metadata: FileRetainMetadata)]]
    {
        var out: [[(file: UploadFile, metadata: FileRetainMetadata)]] = []
        var cur: [(file: UploadFile, metadata: FileRetainMetadata)] = []
        var size = 0
        for f in files {
            if !cur.isEmpty, cur.count >= limit || size + f.file.data.count > bytes {
                out.append(cur)
                cur = []
                size = 0
            }
            cur.append(f)
            size += f.file.data.count
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // MARK: Retrait (confirmé)

    /// Supprime de la banque les documents de la sélection.
    public func requestRemoveSelection() {
        let items = selectedItems.filter { !$0.documents.isEmpty }
        requestRemove(items.flatMap(\.documents), what: Format.count(items.count, "élément choisi", "éléments choisis"))
    }

    /// Supprime les documents dont le fichier n'a pas été trouvé.
    public func requestRemoveOrphans() {
        requestRemove(state.value?.orphans ?? [], what: "documents sans fichier")
    }

    public func requestRemove(_ docs: [DocumentListItem], what: String) {
        guard writeAction == nil, preparingAction == nil else { return }
        invalidateApproval()
        let client = clientProvider()
        guard let context = context(client: client), reportContext == context, !docs.isEmpty else { return }
        var seen = Set<String>()
        let docs = docs.filter { seen.insert($0.id).inserted }
        let knownDocuments = Set(lastDocuments ?? [])
        guard docs.allSatisfy({ knownDocuments.contains($0) }) else {
            actionMessage = "Les documents ont changé. Actualisez la liste avant de préparer le retrait."
            return
        }
        let bank = context.bank, approvedSelection = selection, token = UUID()
        let orphanIDs = Set(state.value?.orphans.map(\.id) ?? []).intersection(docs.map(\.id))
        pendingAction = token
        let facts = docs.reduce(0) { $0 + $1.memoryUnitCount }
        confirmation = ConfirmationRequest(
            title: "Retirer \(docs.count) document(s) de « \(bank) » ?",
            message: "\(what) : \(Format.count(docs.count, "document")) et \(Format.count(facts, "fait")) supprimés définitivement de la banque. Les fichiers ne sont pas touchés ; les renvoyer coûtera une nouvelle extraction.",
            confirmTitle: "Retirer", severity: .destructive, requiredText: docs.count > 10 ? bank : nil
        ) { [weak self] in
            guard let self, self.consume(token) else { return }
            defer { self.finishWrite(token) }
            guard self.validateRemoval(context: context, selection: approvedSelection) else { return }
            do {
                let current = try await Self.allDocuments(client: client, bank: bank)
                guard self.validateRemoval(context: context, selection: approvedSelection) else { return }
                let byID = Dictionary(grouping: current, by: \.id)
                guard docs.allSatisfy({ byID[$0.id] == [$0] }) else {
                    self.actionMessage = "Les documents ont changé depuis la confirmation. Préparez à nouveau le retrait."
                    return
                }
                // Un fichier « sans source » a pu être restauré depuis l'inventaire.
                let repositories = FileCoverageScanner.repositories(in: context.roots.map(\.url))
                let restored = docs.contains { doc in
                    guard orphanIDs.contains(doc.id), let source = FileCoverage.repoAndPath(doc) else { return false }
                    return repositories.contains { repo in
                        repo.lastPathComponent == source.repo && FileManager.default.fileExists(atPath: repo.appendingPathComponent(source.path).path)
                    }
                }
                guard !restored else {
                    self.actionMessage = "Un fichier source a été retrouvé. Actualisez les dossiers avant de préparer le retrait."
                    return
                }
                await self.remove(docs, client: client, context: context, selection: approvedSelection)
            } catch {
                if self.matches(context) { self.actionMessage = "Vérification impossible : \(error.userMessage)" }
            }
        }
    }

    private func validateRemoval(context: Context, selection approvedSelection: Set<String>) -> Bool {
        guard !Task.isCancelled, matches(context), selection == approvedSelection else {
            actionMessage = "Le serveur, les dossiers ou la sélection ont changé. Préparez à nouveau le retrait."
            return false
        }
        return true
    }

    private func remove(_ docs: [DocumentListItem], client: HindsightClient, context: Context, selection approvedSelection: Set<String>) async {
        let bank = context.bank
        var removed = 0, errors: [String] = []
        for d in docs {
            guard validateRemoval(context: context, selection: approvedSelection) else { return }
            do {
                let result = try await client.deleteDocument(bank, id: d.id)
                guard result.success else { throw HindsightError.refused(result.message) }
                removed += 1
            } catch {
                errors.append("\(d.id) : \(error.userMessage)")
            }
        }
        guard matches(context), !Task.isCancelled else { return }
        if selection == approvedSelection { selection = [] }
        actionMessage = "\(removed)/\(docs.count) document(s) retiré(s) de « \(bank) »." + (errors.isEmpty ? "" : " Échecs : " + errors.joined(separator: " ; "))
        await refreshMemory()
    }

    // MARK: Synchronisation automatique

    /// Fichiers des dossiers en synchronisation automatique qui manquent ou ont changé.
    public var autoSyncEntries: [CoverageEntry] {
        let auto = roots.filter(\.autoSync).map { $0.url.standardizedFileURL.path + "/" }
        guard !auto.isEmpty else { return [] }
        return (state.value?.entries ?? []).filter { e in
            e.canSend && e.status != .noFacts && auto.contains { e.file.url.standardizedFileURL.path.hasPrefix($0) }
        }
    }

    /// Les anciens réglages restent lisibles ; aucun envoi automatique n'est exécuté.
    public func autoSyncOnce() async {
        loadRoots()
        if roots.contains(where: \.autoSync) {
            lastAutoSync = "Synchronisation automatique suspendue : sélectionnez et validez chaque envoi."
        }
    }

    /// Boucle de fond, tant que l'app est ouverte.
    public func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.autoSyncInterval else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.autoSyncOnce()
            }
        }
    }
}
