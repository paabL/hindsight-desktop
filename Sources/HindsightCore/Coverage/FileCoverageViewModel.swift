import Foundation
import HindsightAPI
import Observation

/// Les documents de la banque et leurs sources, réunis : compare les dossiers suivis (métadonnées `repo` et
/// `path`) et les sessions Codex / Claude Code / Hermes aux documents de la banque, liste aussi les documents
/// sans source suivie ; envoie ce qui manque ou a changé, retire ce qui n'a plus de source, et peut
/// synchroniser seul. La liste (`library`) est ce qu'affiche l'écran « Documents ».
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
    /// Sessions de conversation connues de l'import (lecture seule).
    @ObservationIgnored public var sessions: (@MainActor () async -> [CodexSessionSummary])?
    @ObservationIgnored public var openOperations: (@MainActor () -> Void)?
    @ObservationIgnored public var openDocument: (@MainActor (String) -> Void)?
    /// Ouvre « Importer » avec ces sessions cochées et la banque pour cible.
    @ObservationIgnored public var openImport: (@MainActor ([String], String) -> Void)?

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
    public var selection: Set<String> = []
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
        let size: Int
        let modified: Date
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
    @ObservationIgnored private var lastQueue: (ids: Set<String>, active: Bool) = ([], false)
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

    func loadRoots() {
        guard let bank else { return roots = [] }
        roots = settings.string(forKey: Self.rootsKey(bank)).flatMap { try? JSONDecoder().decode([CoverageRoot].self, from: Data($0.utf8)) } ?? []
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
        guard let i = roots.firstIndex(where: { $0.path == root.path }) else { return }
        change(&roots[i])
        saveRoots()
    }

    /// Dépôts réellement analysés (un dossier de dépôts en donne plusieurs).
    public var repositories: [URL] { FileCoverageScanner.repositories(in: roots.map(\.url)) }

    // MARK: Analyse

    public func loadIfNeeded() async {
        if reportBank != bank || state.value == nil, !state.isLoading { await reload() }
    }

    /// Analyse les dossiers et les conversations, puis relit la banque.
    public func reload() async {
        loadRoots()
        guard let bank else {
            state = .idle
            reportBank = nil
            library = []
            return
        }
        if reportBank != bank {
            // Autre banque : rien de l'ancienne ne doit rester affiché pendant la lecture.
            library = []
            selection = []
            selectedID = nil
            queuedIDs = []
            recentSends = [:]
            lastDocuments = nil
            lastQueue = ([], false)
        }
        if state.value == nil || reportBank != bank { state = .loading }
        isRefreshing = true
        defer {
            isRefreshing = false
            progress = nil
        }
        progress = roots.isEmpty ? nil : "Inventaire des dossiers…"
        let (files, warnings) = roots.isEmpty ? ([], []) : await scanner.scan(roots: roots)
        var sessions: [CodexSessionSummary] = []
        if includeConversations, let provider = self.sessions {
            progress = "Inventaire des conversations…"
            sessions = Self.sessions(await provider(), within: roots)
        }
        guard self.bank == bank else { return }
        self.warnings = warnings
        scanned = (files, sessions)
        await readMemory(bank: bank)
    }

    /// Relit la banque (documents, file d'attente) sans réanalyser les dossiers.
    public func refreshMemory() async {
        guard let bank, scanned != nil, reportBank == bank else { return await reload() }
        isRefreshing = true
        defer { isRefreshing = false }
        await readMemory(bank: bank)
    }

    private func readMemory(bank: String) async {
        guard let scanned else { return }
        let client = clientProvider()
        do {
            if state.value == nil { progress = "Lecture des documents de « \(bank) »…" }
            let documents = try await Self.allDocuments(client: client, bank: bank)
            let queue = await Self.queuedDocuments(client: client, bank: bank)
            if state.value == nil { progress = "Comparaison…" }
            await compare(documents: documents, queue: queue, bank: bank)
        } catch is CancellationError {
        } catch {
            if state.value == nil || reportBank != bank { state = .failed(error.userMessage) } else { actionMessage = "Relecture impossible : \(error.userMessage)" }
        }
    }

    /// Compare sources et documents (hors du fil principal), puis reconstruit la liste.
    private func compare(documents: [DocumentListItem], queue: (ids: Set<String>, active: Bool), bank: String) async {
        guard let scanned else { return }
        let files = scanned.files, sessions = scanned.sessions, cache = hashCache
        let (report, newCache) = await Task.detached(priority: .userInitiated) { () -> (CoverageReport, [String: HashEntry]) in
            var cache = cache
            let r = FileCoverage.report(files: files, sessions: sessions, documents: documents) { f in Self.hash(f, cache: &cache) }
            return (r, cache)
        }.value
        // La banque a pu changer pendant la lecture.
        guard self.bank == bank else { return }
        hashCache = newCache
        lastDocuments = documents
        lastQueue = queue
        state = .loaded(report)
        reportBank = bank
        rebuildLibrary(queue: queue)
    }

    /// Relit seulement les documents en file quand ils sont peu nombreux (une banque peut en compter des
    /// milliers) ; sinon toute la banque.
    public func refreshQueued() async {
        guard let bank, reportBank == bank, var documents = lastDocuments, !queuedIDs.isEmpty, queuedIDs.count <= 25 else {
            return await refreshMemory()
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let client = clientProvider()
        for id in queuedIDs {
            guard let page = try? await client.listDocuments(bank, q: id, limit: 20), self.bank == bank else { continue }
            if let fresh = page.items.first(where: { $0.id == id }) {
                if let i = documents.firstIndex(where: { $0.id == id }) { documents[i] = fresh } else { documents.append(fresh) }
            }
        }
        let queue = await Self.queuedDocuments(client: client, bank: bank)
        guard self.bank == bank else { return }
        await compare(documents: documents, queue: queue, bank: bank)
    }

    /// Un document vient d'être remis en extraction (retraitement) : « en file » tout de suite, puis suivi.
    public func markQueued(_ documentID: String) {
        recentSends[documentID] = Date()
        rebuildLibrary(queue: (lastQueue.ids, true))
    }

    /// Empreinte d'un fichier texte, recalculée seulement s'il a changé (taille ou date).
    nonisolated static func hash(_ f: ScannedFile, cache: inout [String: HashEntry]) -> String? {
        if let c = cache[f.key], c.size == f.size, c.modified == f.modified { return c.hash }
        guard let data = try? Data(contentsOf: f.url) else { return nil }
        let h = SHA256.hex(data)
        cache[f.key] = HashEntry(size: f.size, modified: f.modified, hash: h)
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

    public var selectedEntry: CoverageEntry? { state.value?.entries.first { $0.id == selectedID } }

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
        e.canSend || !e.documents.isEmpty || (e.session != nil && e.status != .current)
    }

    public func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Choisit ce qui est visible et à envoyer (fichiers ou conversations).
    public func selectVisible() {
        for i in visibleItems where i.canSend || i.canImport { selection.insert(i.id) }
    }

    public func clearSelection() { selection = [] }

    public var selectedEntries: [CoverageEntry] { selectedItems.compactMap(\.entry) }

    // MARK: Détail et coût réel

    /// Sélection depuis la liste : le détail suit tout de suite, le coût arrive ensuite.
    public func choose(_ id: String?) {
        guard id != selectedID else { return }
        selectedID = id
        cost = .idle
        Task { await select(id) }
    }

    public func select(_ id: String?) async {
        selectedID = id
        cost = .idle
        guard let bank, let item = focusedItem, !item.documents.isEmpty else { return }
        cost = .loading
        let docs = Array(item.documents.prefix(20)), client = clientProvider(), book = priceBook?() ?? .defaults
        var calls = 0, tokens = TokenCount(), dollars = 0.0, unpriced = 0
        do {
            for d in docs {
                let page = try await client.llmRequests(bank, callType: ModelCallKind.generativeFilter, documentID: d.id, limit: 500)
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
            if selectedID == id { cost = .loaded(result) }
        } catch {
            if selectedID == id { cost = .failed(error.userMessage) }
        }
    }

    // MARK: Envoi (confirmé)

    /// Lit les fichiers choisis (hors du fil principal) et prépare les requêtes.
    nonisolated static func prepare(_ files: [ScannedFile]) -> Upload {
        var items: [(MemoryItem, Int)] = []
        var uploads: [(UploadFile, FileRetainMetadata)] = []
        var characters = 0
        var unreadable: [String] = []
        for f in files {
            if f.url.pathExtension.lowercased() == "pdf" {
                unreadable.append(f.key + " (PDF : fournir la source TeX ou Markdown)")
                continue
            }
            guard let data = try? Data(contentsOf: f.url) else {
                unreadable.append(f.key)
                continue
            }
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
        }
        return Upload(items: items, files: uploads, characters: characters, unreadable: unreadable)
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
        guard let bank else { return }
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        let selected = selectedEntries
        let conversations = selected.filter { $0.session != nil && $0.status != .current }.compactMap(\.session).map(\.id)
        let entries = selected.filter(\.canSend)
        if let reason = selectionPolicyError(entries, bank: bank) {
            confirmation = nil
            actionMessage = reason
            return
        }
        guard !entries.isEmpty else {
            if !conversations.isEmpty { openImport?(conversations, bank) }
            return
        }
        let upload = await Task.detached(priority: .userInitiated) { Self.prepare(entries.map(\.file)) }.value
        guard upload.count > 0 else {
            actionMessage = "Aucun fichier lisible parmi la sélection : " + upload.unreadable.joined(separator: ", ")
            return
        }
        let replaced = entries.filter { !$0.documents.isEmpty }.count
        var lines = [
            "\(upload.count) fichier(s) → banque « \(bank) » : \(upload.items.count) en texte, \(upload.files.count) converti(s) par le serveur (HTML, Office).",
            "≈ \(Format.number(upload.approxTokens)) jetons envoyés au LLM d'extraction (estimation grossière pour les fichiers convertis).",
        ]
        lines.append("Documents sélectionnés :\n" + entries.filter { entry in !upload.unreadable.contains { $0.hasPrefix(entry.file.key + " (") } }.map { "• " + $0.file.key }.joined(separator: "\n"))
        if replaced > 0 { lines.append("\(replaced) document(s) existant(s) seront REMPLACÉS : leurs faits sont supprimés puis réextraits.") }
        if !upload.unreadable.isEmpty { lines.append("Ignoré(s) : " + upload.unreadable.joined(separator: ", ")) }
        if let e = estimate?(bank, .retain(characters: upload.characters, images: 0, consolidation: true)) { lines.append(e.summary) }
        if !conversations.isEmpty { lines.append("Les \(conversations.count) conversation(s) cochée(s) s'ouvriront ensuite dans « Importer ».") }
        lines.append("Les images intégrées aux HTML sont retirées. L'extraction se fait en tâche de fond ; suivez-la dans « Opérations ».")
        confirmation = ConfirmationRequest(
            title: "Envoyer à « \(bank) » ?", message: lines.joined(separator: "\n"), confirmTitle: "Envoyer",
            severity: replaced > 0 ? .destructive : .normal
        ) { [weak self] in
            guard let self else { return }
            // Une pause a pu être décidée pendant que la confirmation était ouverte.
            if let reason = self.pauseGate?(bank) {
                self.actionMessage = reason
                return
            }
            if let reason = self.selectionPolicyError(entries, bank: bank) {
                self.actionMessage = reason
                return
            }
            await self.perform(upload, bank: bank)
            if !conversations.isEmpty { self.openImport?(conversations, bank) }
        }
    }

    @discardableResult
    func perform(_ upload: Upload, bank: String) async -> Int {
        let client = clientProvider()
        var operations = 0, sent = 0, errors: [String] = []
        sending = (0, upload.count)
        let start = Date()
        for batch in CodexImportViewModel.batches(upload.items, byteLimit: 8_000_000, itemLimit: 10) {
            do {
                let r = try await client.retain(bank, RetainRequest(items: batch, async: true))
                operations += r.operationIds?.count ?? (r.operationId == nil ? 0 : 1)
                sent += batch.count
                for item in batch { if let id = item.documentId { recentSends[id] = start } }
            } catch {
                errors.append("\(batch.first?.documentId ?? "?")… : \(error.userMessage)")
            }
            sending = (sent, upload.count)
        }
        for batch in Self.fileBatches(upload.files, limit: fileBatchLimit, bytes: fileBatchBytes) {
            do {
                let r = try await client.retainFiles(bank, files: batch.map(\.file), metadata: batch.map(\.metadata))
                operations += r.operationIds.count
                sent += batch.count
                for f in batch { if let id = f.metadata.documentId { recentSends[id] = start } }
            } catch {
                errors.append("\(batch.first?.metadata.documentId ?? "?")… : \(error.userMessage)")
            }
            sending = (sent, upload.count)
        }
        sending = nil
        selection = []
        actionMessage =
            "\(sent)/\(upload.count) fichier(s) mis en file d'extraction dans « \(bank) » (\(operations) opération(s))."
            + (errors.isEmpty ? "" : " Refusés : " + errors.joined(separator: " ; "))
        if sent > 0, reportBank == bank { await refreshMemory() }
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
        guard let bank, !docs.isEmpty else { return }
        let facts = docs.reduce(0) { $0 + $1.memoryUnitCount }
        confirmation = ConfirmationRequest(
            title: "Retirer \(docs.count) document(s) de « \(bank) » ?",
            message: "\(what) : \(Format.count(docs.count, "document")) et \(Format.count(facts, "fait")) supprimés définitivement de la banque. Les fichiers ne sont pas touchés ; les renvoyer coûtera une nouvelle extraction.",
            confirmTitle: "Retirer", severity: .destructive, requiredText: docs.count > 10 ? bank : nil
        ) { [weak self] in
            await self?.remove(docs, bank: bank)
        }
    }

    func remove(_ docs: [DocumentListItem], bank: String) async {
        let client = clientProvider()
        var removed = 0, errors: [String] = []
        for d in docs {
            do {
                _ = try await client.deleteDocument(bank, id: d.id)
                removed += 1
            } catch {
                errors.append("\(d.id) : \(error.userMessage)")
            }
        }
        selection = []
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

    /// Un passage : analyse, puis envoi si le volume tient sous le plafond.
    public func autoSyncOnce() async {
        loadRoots()
        if roots.contains(where: \.autoSync) {
            lastAutoSync = "Synchronisation automatique suspendue : sélectionnez et validez chaque envoi."
            return
        }
        guard let bank, roots.contains(where: \.autoSync), sending == nil, confirmation == nil else { return }
        if pauseGate?(bank) != nil {
            lastAutoSync = "Synchronisation automatique suspendue : la banque est en pause (\(Format.dateTime(Date())))."
            return
        }
        await reload()
        // L'analyse est longue : la banque affichée ou la pause ont pu changer entre-temps.
        guard self.bank == bank, reportBank == bank else { return }
        if pauseGate?(bank) != nil {
            lastAutoSync = "Synchronisation automatique suspendue : la banque est en pause (\(Format.dateTime(Date())))."
            return
        }
        let entries = autoSyncEntries
        guard !entries.isEmpty else {
            lastAutoSync = "Synchronisation automatique : rien à envoyer (\(Format.dateTime(Date())))."
            return
        }
        let upload = await Task.detached(priority: .utility) { Self.prepare(entries.map(\.file)) }.value
        guard self.bank == bank, pauseGate?(bank) == nil else { return }
        guard upload.approxTokens <= autoSyncTokenLimit else {
            lastAutoSync = "Synchronisation automatique suspendue : \(entries.count) fichier(s), ≈ \(Format.number(upload.approxTokens)) jetons, au-delà du plafond de \(Format.number(autoSyncTokenLimit)). Envoyez-les à la main ou relevez le plafond."
            return
        }
        let sent = await perform(upload, bank: bank)
        lastAutoSync = "Synchronisation automatique : \(sent) fichier(s) envoyé(s) (\(Format.dateTime(Date())))."
        await reload()
    }

    /// Boucle de fond, tant que l'app est ouverte.
    public func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.autoSyncInterval else { return }
                try? await Task.sleep(for: interval)
                await self?.autoSyncOnce()
            }
        }
    }
}
