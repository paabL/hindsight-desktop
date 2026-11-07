import Foundation
import HindsightAPI

/// One source ledger per folder/bank. Reading never collects, retains, deletes or consolidates.
@MainActor
public final class MemoryWorkspace {
    public var confirmation: ConfirmationRequest?
    public private(set) var records: [[String: Any]] = []
    public private(set) var error: String?
    public private(set) var message: String?
    private let folder: MemoryFolderViewModel
    private let client: () -> HindsightClient
    private let bank: () -> String?
    private var documents: [String: DocumentListItem] = [:]
    private var readable: Set<String> = []
    private struct SourceDigest {
        let url: URL
        let version: FileVersion
        let hash: String
        let boardID: String?
        let managedPath: String?
    }
    private var sourceDigests: [String: SourceDigest] = [:]
    private var catalogVersion: (url: URL, version: FileVersion)?
    public private(set) var catalog: [String: Any]?
    private var targets: [String: String] = [:]
    private var policy: [String: Any] = [:] { didSet { policyIndex = PolicyIndex(policy) } }
    /// Politique indexée une fois par changement : `buildRows` l'interroge pour chaque alias de chaque source.
    private var policyIndex = PolicyIndex([:])
    private var archivedGit: [String: Set<String>] = [:]
    private var preferences: [String: Bool] = [:]
    private var pending: [String: String] = [:]
    private var bindings: [String: String] = [:]
    private var operations: [String: String] = [:]
    private var failures: [String: String] = [:]
    private var comparisonAvailable = false
    private var repairOldTracking = false
    private var loadedBank: String?
    private var loadedRoot: String?
    private var loadedServer: URL?
    private var refreshID = UUID()
    private var preparationID = UUID()
    private var actionInProgress = false
    public private(set) var revision = UUID()
    public private(set) var previousRevision: UUID?
    public private(set) var changedRecords: [[String: Any]] = []
    public var pauseGate: PauseGate?
    /// Banque déclarée par `memory-policy.json` : le dossier lui appartient. Une autre banque
    /// sélectionnée peut parcourir le catalogue, jamais en envoyer, retirer ou relier les sources.
    public private(set) var boundBank: String?
    public var bankMismatch: Bool {
        guard let boundBank, let selected = bank() else { return false }
        return boundBank != selected
    }
    private var mismatchMessage: String {
        "Ce dossier est rattaché à la banque « \(boundBank ?? "") ». Sélectionnez-la pour envoyer ou retirer ses sources."
    }
    private func readBoundBank() { boundBank = Self.declaredBank(in: folder.repository) }
    /// Banque déclarée par la politique d'un dossier mémoire, sans charger le reste.
    public static func declaredBank(in repository: URL?) -> String? {
        guard let url = repository?.appendingPathComponent("memory-policy.json"), FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (value["bank_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private struct Context: Equatable {
        let bank: String?
        let root: URL?
        let collection: URL?
        let server: URL
    }
    private var context: Context {
        Context(bank: bank(), root: folder.repository, collection: folder.collection, server: client().baseURL)
    }
    private func requireContext(_ expected: Context) throws {
        guard !Task.isCancelled, context == expected else { throw failure("Le contexte a changé ; préparez un nouvel aperçu.") }
    }
    private func requireLoadedContext() throws {
        guard loadedBank == bank(), loadedRoot == folder.repository?.path, loadedServer == client().baseURL else {
            throw failure("Le contexte a changé ; actualisez les sources.")
        }
    }

    public func invalidate() {
        refreshID = UUID(); preparationID = UUID(); revision = UUID()
        previousRevision = nil; changedRecords = []
        documents = [:]; records = []; readable = []; targets = [:]
        comparisonAvailable = false; loadedBank = nil; loadedRoot = nil; loadedServer = nil
        confirmation = nil; error = nil; message = nil
    }

    public init(folder: MemoryFolderViewModel, client: @escaping () -> HindsightClient, bank: @escaping () -> String?) {
        self.folder = folder; self.client = client; self.bank = bank
    }
    /// Format sans version texte (PDF seul…) : la source n'est pas en erreur, elle n'est pas envoyable.
    static let unsupportedFormatCode = 2
    private func failure(_ text: String) -> NSError { NSError(domain: "MemoryWorkspace", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private var ledgerURL: URL? { folder.collection?.appendingPathComponent(".memory-workspace.json") }
    private var policyURL: URL? { folder.repository?.appendingPathComponent("memory-policy.json") }
    private func decode(_ url: URL) throws -> [String: Any] {
        guard let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw failure("Configuration mémoire illisible.") }
        return d
    }
    private func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func loadPolicy() throws {
        policy = [:]; archivedGit = [:]; preferences = [:]; pending = [:]; operations = [:]; failures = [:]; bindings = [:]; repairOldTracking = false
        if let url = policyURL, FileManager.default.fileExists(atPath: url.path) {
            policy = try decode(url)
            guard policy["version"] as? Int == 1, policy["excluded_document_ids"] is [String: Any], policy["deferred_document_ids"] is [String: Any] else { throw failure("Politique mémoire incompatible ; envoi suspendu.") }
        }
        boundBank = (policy["bank_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if policy["bank_id"] as? String == bank(), let root = folder.repository?.resolvingSymlinksInPath() {
            for (id, value) in policy["excluded_document_ids"] as? [String: Any] ?? [:] where id.hasPrefix("gitlog:") {
                let repo = String(id.dropFirst(7))
                archivedGit[repo] = ["*"]
                if let relative = (value as? [String: Any])?["archive"] as? String, !relative.hasPrefix("/") {
                    let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
                    if url.path.hasPrefix(root.path + "/"), let text = try? String(contentsOf: url, encoding: .utf8) {
                        let regex = try! NSRegularExpression(pattern: "(?m)^([0-9a-f]{7,40}) [0-9]{4}-")
                        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                        let prefixes = Set(matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
                        if !prefixes.isEmpty { archivedGit[repo] = prefixes }
                    }
                }
            }
        }
        if let url = ledgerURL, FileManager.default.fileExists(atPath: url.path) {
            let ledger = try decode(url)
            let value = ledger[bank() ?? ""]
            guard value == nil || value is [String: Any] else { throw failure("Sélection mémoire illisible ; envoi suspendu.") }
            let state = value as? [String: Any] ?? [:]
            for key in ["enabled", "pending", "operations", "failures", "bindings"] where state[key] != nil {
                guard state[key] is [String: Any] else { throw failure("Sélection mémoire invalide ; envoi suspendu.") }
                guard key == "enabled" ? state[key] is [String: Bool] : state[key] is [String: String] else {
                    throw failure("Suivi mémoire invalide ; envoi suspendu.")
                }
            }
            if let value = state["server_url"] {
                guard let server = value as? String else { throw failure("Suivi mémoire invalide ; envoi suspendu.") }
                guard server == client().baseURL.absoluteString else { throw failure("Cette sélection mémoire appartient à un autre serveur ; envoi suspendu.") }
            }
            preferences = state["enabled"] as? [String: Bool] ?? [:]
            pending = state["pending"] as? [String: String] ?? [:]
            operations = state["operations"] as? [String: String] ?? [:]
            failures = state["failures"] as? [String: String] ?? [:]
            bindings = state["bindings"] as? [String: String] ?? [:]
            guard Set(operations.keys).isSubset(of: Set(pending.keys)) else { throw failure("Suivi mémoire incomplet ; envoi suspendu.") }
            repairOldTracking = (state["tracking_version"] as? Int ?? 1) < 2 && !failures.isEmpty
        }
    }
    private func persist() throws {
        guard let url = ledgerURL, let bank = bank() else { throw failure("Choisissez un dossier et une banque.") }
        var ledger = FileManager.default.fileExists(atPath: url.path) ? try decode(url) : [:]
        ledger[bank] = ["tracking_version": repairOldTracking ? 1 : 2, "server_url": client().baseURL.absoluteString, "enabled": preferences, "pending": pending, "operations": operations, "failures": failures, "bindings": bindings]
        try write(ledger, to: url)
    }
    /// Reconcile old false failures from the exact saved submissions, never by resending them.
    private func recoverTracking(_ bank: String, refreshToken: UUID) async throws -> [String: OperationStatusResponse] {
        guard repairOldTracking, let root = folder.collection, let ledger = ledgerURL else { return [:] }
        let currentClient = client(), expectedRoot = loadedRoot
        let directory = root.appendingPathComponent(".memory-operations")
        let packets = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = packets.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var statuses: [String: OperationStatusResponse] = [:]
        var retryRecovery = false
        var restored = Set<String>()
        for url in sorted where url.pathExtension == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: id) != nil,
                  let data = try? Data(contentsOf: url), let packet = try? JSONDecoder().decode(RetainRequest.self, from: data), packet.operationId == id else { continue }
            let affected = packet.items.filter { item in item.documentId.map { failures[$0] != nil && operations[$0] == nil && !restored.contains($0) } ?? false }
            guard !affected.isEmpty else { continue }
            let status = try? await currentClient.operation(bank, id: id)
            guard !Task.isCancelled, refreshID == refreshToken, self.bank() == bank, expectedRoot == folder.repository?.path,
                  client().baseURL == currentClient.baseURL else { throw failure("Le contexte a changé ; actualisez la vue.") }
            guard let status else { retryRecovery = true; continue }
            let backup = root.appendingPathComponent(".memory-workspace.pre-tracking-v2.json")
            if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: ledger, to: backup) }
            statuses[id] = status
            for item in affected {
                guard let target = item.documentId, case .text(let text) = item.content else { continue }
                pending[target] = SHA256.hex(Data(text.utf8)); operations[target] = id; failures[target] = nil; restored.insert(target)
            }
        }
        repairOldTracking = retryRecovery
        return statuses
    }
    /// A queue row can retain an old task status after its operation has finished. Read the
    /// operation itself before blocking, and inspect every page before declaring the queue idle.
    private struct QueueOperation: Sendable {
        let id: String
        let status: OperationStatusResponse
    }
    private func hasActiveStatus(_ rows: [OperationResponse], checked: [String: OperationStatusResponse], retainOnly: Bool) -> Bool {
        rows.contains { row in
            guard let operation = checked[row.operationId ?? row.id] else { return false }
            let kind = operation.operationType ?? operation.taskType ?? row.operationType ?? row.taskType
            if retainOnly && !["retain", "batch_retain"].contains(kind) { return false }
            let state = OperationStatusKind(operation.status)
            return state.isActive || state == .other || operation.childOperations?.contains(where: {
                let state = OperationStatusKind($0.status)
                return state.isActive || state == .other
            }) == true
        }
    }
    private func hasActiveWork(_ bank: String, client currentClient: HindsightClient, retainOnly: Bool = false) async throws -> Bool {
        let expected = context
        guard expected.bank == bank, expected.server == currentClient.baseURL else { throw failure("Le contexte a changé ; préparez un nouvel aperçu.") }
        var checked: [String: OperationStatusResponse] = [:]
        for status in ["pending", "processing"] {
            let types: [String?] = retainOnly ? ["retain", "batch_retain"] : [nil]
            for type in types {
                var offset = 0
                var seen = Set<String>()
                while true {
                    let page = try await currentClient.listOperations(bank, status: status, type: type, limit: 100, offset: offset)
                    try requireContext(expected)
                    var requested = Set<String>()
                    var missing: [String] = []
                    for row in page.operations {
                        // Several task rows can legitimately share one parent operation.
                        guard seen.insert(row.id).inserted else { throw failure("File d’opérations incomplète ; actualisez avant tout envoi.") }
                        let id = row.operationId ?? row.id
                        if checked[id] == nil, requested.insert(id).inserted { missing.append(id) }
                    }
                    if hasActiveStatus(page.operations, checked: checked, retainOnly: retainOnly) { return true }
                    // Verify historical task rows without one network round trip per row in series.
                    // Bound concurrency and retain only status metadata, never source text.
                    for start in stride(from: 0, to: missing.count, by: 4) {
                        let ids = Array(missing[start..<min(start + 4, missing.count)])
                        let results = try await withThrowingTaskGroup(of: QueueOperation.self) { group in
                            for id in ids {
                                group.addTask { QueueOperation(id: id, status: try await currentClient.operation(bank, id: id)) }
                            }
                            var values: [QueueOperation] = []
                            for try await value in group { values.append(value) }
                            return values
                        }
                        try requireContext(expected)
                        for result in results { checked[result.id] = result.status }
                        if hasActiveStatus(page.operations, checked: checked, retainOnly: retainOnly) { return true }
                    }
                    for row in page.operations {
                        guard checked[row.operationId ?? row.id] != nil else { throw failure("File d’opérations incomplète ; actualisez avant tout envoi.") }
                    }
                    offset += page.operations.count
                    if offset >= page.total { break }
                    guard !page.operations.isEmpty else { throw failure("File d’opérations incomplète ; actualisez avant tout envoi.") }
                }
            }
        }
        return false
    }
    /// Mêmes réponses qu'un parcours de chaque entrée, groupe « en attente » d'abord, puis « retirés ».
    struct PolicyIndex {
        struct Group {
            struct Source: Hashable { let repo: String; let path: String }
            var ids: Set<String> = []
            var sources: Set<Source> = []
            var originals: Set<String> = []
            var suffixes: [String] = []

            init(_ values: [String: Any]) {
                ids = Set(values.keys)
                for value in values.values {
                    let object = value as? [String: Any] ?? [:]
                    if let original = object["original_path"] as? String { originals.insert(original) }
                    guard let source = object["source"] as? [String: String], let r = source["repo"], let p = source["path"] else { continue }
                    sources.insert(Source(repo: r.precomposedStringWithCanonicalMapping, path: p.precomposedStringWithCanonicalMapping))
                    if !r.isEmpty, !p.isEmpty { suffixes.append(("/" + r + "/" + p).precomposedStringWithCanonicalMapping) }
                }
            }

            func matches(repo: String, path: String, original: String?) -> Bool {
                if !path.isEmpty, sources.contains(Source(repo: repo.precomposedStringWithCanonicalMapping, path: path.precomposedStringWithCanonicalMapping)) { return true }
                guard let original else { return false }
                if originals.contains(original) { return true }
                let normalized = original.precomposedStringWithCanonicalMapping
                return suffixes.contains { normalized.hasSuffix($0) }
            }
        }
        let bank: String?
        let deferred: Group
        let excluded: Group
        /// Conversion d'un seul tenant, comme la lecture d'origine de `origin` : un retrait mal formé l'annule entièrement.
        let excludedEntries: [String: [String: Any]]?

        init(_ policy: [String: Any]) {
            bank = policy["bank_id"] as? String
            deferred = Group(policy["deferred_document_ids"] as? [String: Any] ?? [:])
            excluded = Group(policy["excluded_document_ids"] as? [String: Any] ?? [:])
            excludedEntries = policy["excluded_document_ids"] as? [String: [String: Any]]
        }

        func isWorkspaceExclusion(_ id: String) -> Bool { excludedEntries?[id]?["origin"] as? String == "workspace" }
    }
    private func policyReason(id: String, repo: String, path: String, original: String? = nil) -> String? {
        guard policyIndex.bank == bank() else { return nil }
        let contained = "Source contenant des documents retirés ou en attente de revue"
        if policyIndex.deferred.ids.contains(id) { return "En attente de revue" }
        if policyIndex.deferred.matches(repo: repo, path: path, original: original) { return contained }
        if policyIndex.excluded.ids.contains(id) { return "Retrait validé" }
        if policyIndex.excluded.matches(repo: repo, path: path, original: original) { return contained }
        return nil
    }
    private func sourceURL(_ record: [String: Any], root: URL?) throws -> URL {
        guard let root, let files = record["files"] as? [String: String] else { throw failure("Source locale indisponible.") }
        let chosen = files["document.md"] ?? files.keys.sorted().first(where: { ["md", "tex", "txt", "markdown"].contains(($0 as NSString).pathExtension.lowercased()) }).flatMap { files[$0] }
        guard let relative = chosen else {
            throw NSError(domain: "MemoryWorkspace", code: Self.unsupportedFormatCode, userInfo: [NSLocalizedDescriptionKey: "Une source TeX ou Markdown est requise pour ce document."])
        }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."), url.path.hasPrefix(root.path + "/"),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw failure("Source hors du dossier du catalogue.") }
        return url
    }
    private func sourceDigest(_ record: [String: Any], root: URL?) throws -> SourceDigest {
        let url = try sourceURL(record, root: root)
        let version = try FileVersion(url)
        let key = record["id"] as? String ?? url.path
        let managedPath = (record["context"] as? [String: Any])?["managed_path"] as? String
        if let cached = sourceDigests[key], cached.url == url, cached.version == version, cached.managedPath == managedPath { return cached }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard try FileVersion(url) == version else { throw failure("Source modifiée pendant sa lecture ; actualisez la vue.") }
        var boardID: String?
        if ((record["context"] as? [String: Any])?["managed_path"] as? String)?.hasPrefix("board/") == true,
           let range = text.range(of: "(?m)^id: *([^\\n]+)", options: .regularExpression) {
            boardID = String(text[range]).dropFirst(3).trimmingCharacters(in: .whitespaces)
        }
        let digest = SourceDigest(url: url, version: version, hash: SHA256.hex(Data(text.utf8)), boardID: boardID, managedPath: managedPath)
        sourceDigests[key] = digest
        return digest
    }
    private func readTexts(_ rows: [[String: Any]]) throws -> [String: String] {
        let root = folder.collection?.resolvingSymlinksInPath()
        return try Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return (id, try String(contentsOf: sourceURL(row, root: root), encoding: .utf8))
        })
    }
    private func originalKey(_ record: [String: Any], boardID: String?) -> String? {
        let context = record["context"] as? [String: Any] ?? [:]
        guard let path = context["managed_path"] as? String else { return nil }
        let repo = (record["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder.repository?.lastPathComponent ?? ""
        if path.hasPrefix("board/"), let id = boardID {
            if path.contains("/cards/") { return "card-" + id }
            if path.hasSuffix("chantier.md") { return "chantier-" + id }
        }
        if path == "board/project.md" { return "board-project" }
        return "doc:\(repo):\(path)"
    }
    /// First paint uses only the manifest. No source is actionable until comparison finishes.
    public func prime() {
        if !records.isEmpty, loadedBank == bank(), loadedRoot == folder.repository?.path,
           loadedServer == client().baseURL { return }
        invalidate()
        folder.reload()
        readBoundBank()
        let foreign = bankMismatch
        do {
            try loadCatalog()
            records = (catalog?["records"] as? [[String: Any]] ?? []).compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                var row = row
                row["memory"] = ["state": foreign ? "other_bank" : "unknown", "enabled": false, "locked": true, "stored": false,
                                 "can_remove": false, "document_id": "source:" + id, "reason": foreign ? mismatchMessage : "", "hash": ""]
                return row
            }
            revision = UUID()
            loadedBank = bank(); loadedRoot = folder.repository?.path; loadedServer = client().baseURL
        } catch {
            catalog = nil; catalogVersion = nil
            self.error = "Catalogue illisible : \(error.localizedDescription)"
        }
    }
    private func loadCatalog() throws {
        guard let url = folder.catalogURL else { catalog = nil; catalogVersion = nil; return }
        let version = try FileVersion(url)
        if catalogVersion?.url != url || catalogVersion?.version != version {
            catalog = try decode(url)
            guard catalog?["version"] as? Int == 1, catalog?["mode"] as? String == "collection_only" else {
                catalog = nil; catalogVersion = nil
                throw failure("Le format de ce catalogue n'est pas pris en charge.")
            }
            let ids = (catalog?["records"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            guard let rows = catalog?["records"] as? [[String: Any]], ids.count == rows.count,
                  ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
                catalog = nil; catalogVersion = nil
                throw failure("Identifiants du catalogue invalides ou dupliqués ; envoi suspendu.")
            }
            catalogVersion = try FileVersion(url) == version ? (url, version) : nil
        }
    }
    public func refresh() async {
        let token = UUID(); refreshID = token
        let currentClient = client(), currentBank = bank(), currentRoot = folder.repository?.path
        func isCurrent() -> Bool {
            !Task.isCancelled && refreshID == token && bank() == currentBank
                && folder.repository?.path == currentRoot && client().baseURL == currentClient.baseURL
        }
        confirmation = nil; error = nil; message = nil; folder.reload()
        if loadedBank != currentBank || loadedRoot != currentRoot || loadedServer != currentClient.baseURL { documents = [:]; records = []; readable = []; targets = [:]; comparisonAvailable = false }
        loadedBank = currentBank; loadedRoot = currentRoot; loadedServer = currentClient.baseURL
        do {
            try loadPolicy()
            var fresh: [String: DocumentListItem] = [:]
            if let bank = currentBank {
                var offset = 0
                while true {
                    // Le coût d'une page est surtout fixe côté serveur : 1 000 documents par requête au lieu de 100.
                    let page = try await currentClient.listDocuments(bank, limit: 1000, offset: offset)
                    guard isCurrent() else { return }
                    for doc in page.items { fresh[doc.id] = doc }
                    offset += page.items.count
                    if offset >= page.total { break }
                    guard !page.items.isEmpty else { throw failure("Inventaire Hindsight incomplet.") }
                }
            } else { error = "Connectez Hindsight pour comparer les versions." }
            documents = fresh; comparisonAvailable = currentBank != nil
            if let bank = currentBank {
                let wasRepairing = repairOldTracking
                let recovered = try await recoverTracking(bank, refreshToken: token)
                guard isCurrent() else { return }
                let hadTracking = !operations.isEmpty
                var checkedQueue = false
                var retainWork: Bool?
                for id in Set(operations.values) {
                    let op: OperationStatusResponse?
                    if let cached = recovered[id] { op = cached } else { op = try? await currentClient.operation(bank, id: id) }
                    guard isCurrent() else { return }
                    guard let op, ["failed", "cancelled", "completed"].contains(op.status) else { continue }
                    let childFailed = op.childOperations?.contains { ["failed", "cancelled"].contains($0.status) } == true
                    let childActive = op.childOperations?.contains { ["pending", "processing"].contains($0.status) } == true
                    let parent = op.operationType == "batch_retain" || op.resultMetadata?["is_parent"] == .bool(true)
                    for target in operations.keys.filter({ operations[$0] == id }) {
                        let matches = pending[target] != nil && fresh[target]?.contentHash == pending[target]
                        let failed = op.status != "completed" || childFailed
                        if !failed && childActive { continue }
                        if !failed && parent && !matches {
                            if !checkedQueue { retainWork = try? await hasActiveWork(bank, client: currentClient, retainOnly: true); checkedQueue = true }
                            guard isCurrent() else { return }
                            // A completed batch dispatcher is not a completed extraction. If the
                            // server cannot expose child status, wait until its retain queue drains.
                            if retainWork != false { continue }
                        }
                        if failed || !matches { failures[target] = "Le traitement précédent a échoué ou n’a pas enregistré cette version. Une nouvelle validation est nécessaire pour réessayer." }
                        else { failures[target] = nil }
                        pending[target] = nil; operations[target] = nil
                    }
                }
                if hadTracking || !recovered.isEmpty || wasRepairing { try persist() }
            }
        } catch {
            guard isCurrent() else { return }
            self.error = error.localizedDescription; documents = [:]; comparisonAvailable = false
        }
        guard isCurrent() else { return }
        buildRows()
    }
    private func buildRows() {
        let oldRevision = revision
        let previous = Dictionary(records.compactMap { row in (row["id"] as? String).map { ($0, row) } }, uniquingKeysWith: { _, last in last })
        records = []; readable = []; targets = [:]
        do {
            try loadCatalog()
        } catch { self.error = "Catalogue illisible : \(error.localizedDescription)"; catalog = nil; catalogVersion = nil }
        let raw = catalog?["records"] as? [[String: Any]] ?? []
        let ids = Set(raw.compactMap { $0["id"] as? String })
        sourceDigests = sourceDigests.filter { ids.contains($0.key) }
        var claimed = Set<String>()
        let foreign = bankMismatch
        let root = folder.collection?.resolvingSymlinksInPath()
        // Index des documents, dans l'ordre de parcours de `documents` : le premier porteur de chaque
        // `source_record_id` et le suffixe « /dépôt/chemin » de chacun, au lieu de deux parcours par source.
        var bySourceRecord: [String: String] = [:]
        var pathSuffixes: [String: [String]] = [:]
        for doc in documents.values {
            if case .string(let source)? = doc.documentMetadata?["source_record_id"], bySourceRecord[source] == nil { bySourceRecord[source] = doc.id }
            if let repo = doc.documentMetadata?["repo"]?.stringValue, let path = doc.documentMetadata?["path"]?.stringValue, !repo.isEmpty, !path.isEmpty {
                pathSuffixes[("/" + repo + "/" + path).precomposedStringWithCanonicalMapping, default: []].append(doc.id)
            }
        }
        for var record in raw {
            guard let id = record["id"] as? String else { continue }
            let context = record["context"] as? [String: Any] ?? [:]
            let path = context["managed_path"] as? String ?? ""
            let repo = (record["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder.repository?.lastPathComponent ?? ""
            var readError: String?
            let digest: SourceDigest?
            var unsupported = false
            do { digest = try sourceDigest(record, root: root) } catch {
                digest = nil; readError = error.localizedDescription
                unsupported = (error as NSError).code == Self.unsupportedFormatCode
            }
            let canonical = "source:" + id
            let aliases = [bindings[id], canonical, id, originalKey(record, boardID: digest?.boardID)].compactMap { $0 }
            let original = (context["original_path"] as? String)?.precomposedStringWithCanonicalMapping
            let byAlias = aliases.first(where: { documents[$0] != nil }) ?? bySourceRecord[id]
            var byPath: [String] = []
            if byAlias == nil, let original {
                for index in original.indices where original[index] == "/" {
                    byPath.append(contentsOf: pathSuffixes[String(original[index...])] ?? [])
                }
            }
            let matched = byAlias ?? (byPath.count == 1 ? byPath.first : nil)
            let target = matched ?? bindings[id] ?? canonical
            var policyAliases = aliases + [target]
            if record["kind"] as? String == "conversations", let source = record["source_id"] as? String,
               let range = source.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", options: .regularExpression) {
                policyAliases.append("conversation:" + source[range].lowercased())
            }
            let commit = context["commit"] as? String ?? ""
            let gitHeld = record["kind"] as? String == "github" && !commit.isEmpty && (archivedGit[repo]?.contains(where: { $0 == "*" || commit.hasPrefix($0) }) ?? false)
            let hold = policyAliases.compactMap { policyReason(id: $0, repo: repo, path: path, original: original) }.first ?? (gitHeld ? "Commit déjà classé hors mémoire" : nil)
            let aside = ["internal_review", "empty_export"].contains(context["conversation_kind"] as? String ?? "")
            let ownExclusion = policyIndex.isWorkspaceExclusion(target)
            let enabled = hold == nil && digest != nil && (preferences[id] ?? !aside)
            let hash = digest?.hash
            var state = !enabled ? "excluded" : documents[target] == nil ? "new" : documents[target]?.contentHash == hash ? "current" : "modified"
            if enabled && failures[target] != nil { state = "failed" }
            if enabled && !comparisonAvailable { state = "unknown" }
            if preferences[id] != false && readError != nil && hold == nil && !aside { state = unsupported ? "unsupported" : "error" }
            if pending[target] != nil && comparisonAvailable {
                if operations[target] == nil && documents[target]?.contentHash == pending[target] { pending[target] = nil }
                else { state = "queued" }
            }
            if let matched { claimed.insert(matched) }
            record["memory"] = ["state": state, "enabled": enabled, "document_id": target, "stored": matched != nil,
                                "can_remove": matched != nil && (hold == nil || ownExclusion), "locked": (hold != nil && !ownExclusion) || digest == nil, "reason": hold ?? readError ?? failures[target] ?? "", "hash": hash ?? "", "stored_hash": documents[target]?.contentHash ?? ""]
            if foreign {
                // Catalogue d'une autre banque : consultable, jamais envoyé ni retiré depuis celle-ci.
                record["memory"] = ["state": "other_bank", "enabled": false, "document_id": target, "stored": matched != nil,
                                    "can_remove": false, "locked": true, "reason": mismatchMessage, "hash": hash ?? "", "stored_hash": documents[target]?.contentHash ?? ""]
            }
            records.append(record); if digest != nil { readable.insert(id) }; targets[id] = target
        }
        // Sources imported by other tools stay visible; do not infer that their file disappeared.
        // Sous un catalogue d'une autre banque, les documents de celle-ci n'ont rien à y relier.
        for doc in documents.values.sorted(by: { $0.id < $1.id }) where !foreign && !claimed.contains(doc.id) {
            let id = "bank:" + doc.id
            let hold = policyReason(id: doc.id, repo: doc.documentMetadata?["repo"]?.stringValue ?? "", path: doc.documentMetadata?["path"]?.stringValue ?? "")
            records.append(["id": id, "title": doc.id, "kind": "documents", "project": "", "project_name": "En mémoire", "repository": doc.documentMetadata?["repo"]?.stringValue ?? "", "files": [:], "source_updated_at": doc.updatedAt,
                            "memory": ["state": hold == nil ? (doc.documentMetadata?["source_record_id"] == nil ? "unlinked" : "missing") : "excluded", "enabled": false, "stored": true, "can_remove": hold == nil || policyIndex.isWorkspaceExclusion(doc.id), "locked": hold != nil && !policyIndex.isWorkspaceExclusion(doc.id), "document_id": doc.id, "stored_hash": doc.contentHash ?? "", "reason": hold ?? "Source à relier au catalogue"]])
            targets[id] = doc.id
        }
        changedRecords = records.filter { row in
            guard let id = row["id"] as? String, let old = previous[id] else { return true }
            return !NSDictionary(dictionary: old).isEqual(to: row)
        }
        previousRevision = oldRevision; revision = UUID()
    }
    public func setEnabled(_ id: String, enabled: Bool) throws { try setEnabled([id], enabled: enabled) }
    public func setEnabled(_ ids: [String], enabled: Bool) throws {
        try requireLoadedContext()
        for id in ids {
            guard let row = records.first(where: { $0["id"] as? String == id }), let state = row["memory"] as? [String: Any], state["locked"] as? Bool != true, readable.contains(id) else { throw failure("Une source nécessite une revue ou une version texte.") }
        }
        confirmation = nil
        if enabled, let url = policyURL, FileManager.default.fileExists(atPath: url.path) {
            var latest = try decode(url); var entries = latest["excluded_document_ids"] as? [String: Any] ?? [:]
            for id in ids {
                if let target = targets[id], (entries[target] as? [String: Any])?["origin"] as? String == "workspace" { entries[target] = nil }
            }
            if JSONSerialization.isValidJSONObject(latest), latest["bank_id"] as? String == bank() {
                latest["excluded_document_ids"] = entries; try write(latest, to: url); policy = latest
            }
        }
        for id in ids { preferences[id] = enabled }
        try persist(); buildRows()
    }
    public func link(_ id: String, document: String) throws {
        try requireLoadedContext()
        guard readable.contains(id), let row = records.first(where: { $0["id"] as? String == id }),
              let state = row["memory"] as? [String: Any], state["locked"] as? Bool != true,
              state["stored"] as? Bool != true, documents[document] != nil,
              records.contains(where: { $0["id"] as? String == "bank:" + document && ($0["memory"] as? [String: Any])?["locked"] as? Bool != true })
        else { throw failure("Choisissez une source non liée et un document disponible.") }
        confirmation = nil; bindings[id] = document; try persist(); buildRows()
    }

    public func storedText(_ id: String) async throws -> String {
        let expected = context, currentClient = client()
        guard loadedBank == expected.bank, loadedRoot == expected.root?.path, loadedServer == expected.server else { throw failure("Actualisez les sources de cette banque.") }
        guard let bank = bank(), let target = targets[id] else { throw failure("Document inconnu.") }
        let document = try await currentClient.document(bank, id: target)
        try requireContext(expected)
        return document.originalText ?? ""
    }
    private func checkQueue(_ bank: String, client currentClient: HindsightClient) async throws {
        if try await hasActiveWork(bank, client: currentClient) { throw failure("Des opérations sont encore en cours. Consultez « Activité › Traitements » puis actualisez.") }
    }
    /// Refreshes only the local archive. It does not require or contact Hindsight.
    public func refreshSources() async {
        confirmation = nil; message = nil; error = nil
        await folder.collectSources()
        if loadedBank != bank() || loadedRoot != folder.repository?.path || loadedServer != client().baseURL {
            documents = [:]; comparisonAvailable = false
        }
        loadedBank = bank(); loadedRoot = folder.repository?.path; loadedServer = client().baseURL
        do { try loadPolicy() } catch { self.error = error.localizedDescription }
        if let collectionError = folder.error { error = collectionError }
        buildRows()
        if error == nil { message = "Sources collectées. Aucun envoi ni traitement Hindsight." }
    }

    /// Prepares the existing catalogue; collecting and sending are independent actions.
    public func prepareSend() async {
        let preparation = UUID(); preparationID = preparation
        confirmation = nil; message = nil
        guard let bank = bank(), let root = folder.repository else { error = "Choisissez une banque et ouvrez un catalogue."; return }
        if let reason = pauseGate?(bank) { error = reason; return }
        folder.reload()
        guard folder.catalogURL != nil, folder.error == nil else { error = folder.error ?? "Choisissez un catalogue existant."; return }
        let expected = context, currentClient = client()
        await refresh()
        guard preparationID == preparation, context == expected, error == nil else { return }
        guard !bankMismatch else { error = mismatchMessage; return }
        do { try await checkQueue(bank, client: currentClient) } catch {
            if preparationID == preparation, context == expected { self.error = error.localizedDescription }
            return
        }
        guard preparationID == preparation, context == expected, !Task.isCancelled else { return }
        let selected = records.filter { row in
            let s = row["memory"] as? [String: Any] ?? [:]
            return s["enabled"] as? Bool == true && ["new", "modified", "failed"].contains(s["state"] as? String ?? "")
        }
        guard !records.contains(where: { ($0["memory"] as? [String: Any])?["state"] as? String == "queued" }) else { error = "Un envoi est encore en cours. Actualisez après son traitement."; return }
        guard !selected.isEmpty else { message = "Toutes les sources activées sont à jour."; return }
        let texts: [String: String]
        do { texts = try readTexts(selected) } catch { self.error = error.localizedDescription; return }
        guard selected.allSatisfy({ row in
            guard let id = row["id"] as? String, let text = texts[id] else { return false }
            return SHA256.hex(Data(text.utf8)) == (row["memory"] as? [String: Any])?["hash"] as? String
        }) else { error = "Les sources ont changé ; préparez un nouvel aperçu."; return }
        let frozenTexts = texts, frozenTargets = targets, frozenPreferences = preferences
        let frozenPolicy = try? JSONSerialization.data(withJSONObject: policy, options: .sortedKeys)
        let frozenRows = selected.map { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        let baseline = documents.mapValues(\.contentHash)
        let items: [MemoryItem] = selected.compactMap { row in
            guard let id = row["id"] as? String, let text = texts[id], let target = targets[id] else { return nil }
            return MemoryItem(content: .text(text), timestamp: .string(row["source_updated_at"] as? String ?? ISO8601DateFormatter().string(from: Date())), context: "Source complète : " + (row["title"] as? String ?? id) + "; type : " + (row["kind"] as? String ?? "") + "; " + ((row["context"] as? [String: Any])?["claims"] as? String ?? "Contenu source, avec ses dates et limites ; les hypothèses ne sont pas des résultats validés."),
                              metadata: ["source_record_id": id, "repo": row["repository"] as? String ?? "", "project": row["project"] as? String ?? "", "kind": row["kind"] as? String ?? ""], documentId: target,
                              tags: ["source:catalog", "project:" + (row["project"] as? String ?? ""), "repo:" + (row["repository"] as? String ?? "")], observationScopes: .string("shared"), strategy: "doc")
        }
        let chars = selected.reduce(0) { $0 + (texts[$1["id"] as? String ?? ""]?.count ?? 0) }
        let binds = boundBank == nil
        var consumed = false
        confirmation = ConfirmationRequest(title: "Envoyer les sources à Hindsight ?", message: "\(items.count) sources complètes vers « \(bank) », environ \(chars / 4) jetons de texte avant extraction.\n\n" + selected.map { "• " + ($0["title"] as? String ?? "") + " — " + (targets[$0["id"] as? String ?? ""] ?? "") }.joined(separator: "\n") + "\n\nLes sources modifiées remplacent leur version mémorisée. Aucune suppression d’autres documents. La consolidation dépend des réglages de la banque." + (binds ? "\n\nCe dossier sera rattaché à « \(bank) » : ses sources ne pourront pas être envoyées à une autre banque." : ""), confirmTitle: "Envoyer") { [weak self] in
            guard let self else { return }
            guard !consumed else { return }; consumed = true
            guard self.context == expected else { self.error = "Le contexte a changé ; préparez un nouvel aperçu."; return }
            if let reason = self.pauseGate?(bank) { self.error = reason; return }
            guard !self.actionInProgress else { return }
            self.actionInProgress = true
            defer { self.actionInProgress = false }
            await self.refresh()
            guard self.context == expected, !Task.isCancelled else { return }
            let currentTexts = try? self.readTexts(selected)
            guard self.error == nil, self.preferences == frozenPreferences,
                  (try? JSONSerialization.data(withJSONObject: self.policy, options: .sortedKeys)) == frozenPolicy,
                  selected.enumerated().allSatisfy({ index, row in
                    let current = self.records.first(where: { $0["id"] as? String == row["id"] as? String })
                    return current.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) } == frozenRows[index]
                  }), self.documents.mapValues(\.contentHash) == baseline,
                  selected.allSatisfy({ row in let id = row["id"] as? String ?? ""; return currentTexts?[id] == frozenTexts[id] && self.targets[id] == frozenTargets[id] && (self.records.first(where: { $0["id"] as? String == id })?["memory"] as? [String: Any])?["enabled"] as? Bool == true }) else {
                self.error = "Les sources, la sélection ou la banque ont changé. Préparez un nouvel aperçu."; return
            }
            guard !self.bankMismatch else { self.error = self.mismatchMessage; return }
            do {
                try await self.checkQueue(bank, client: currentClient)
                try self.requireContext(expected)
                if binds { try self.bindFolder(to: bank) }
                for batch in RetainBatching.batches(items.map { ($0, (frozenTexts[$0.metadata?["source_record_id"] ?? ""]?.utf8.count ?? 0) + 2000) }, byteLimit: 8_000_000, itemLimit: 10) {
                    try self.requireContext(expected)
                    if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                    let operation = UUID().uuidString
                    for item in batch { if let id = item.documentId, let key = item.metadata?["source_record_id"], let text = frozenTexts[key] {
                        self.pending[id] = SHA256.hex(Data(text.utf8)); self.operations[id] = operation; self.failures[id] = nil
                    } }
                    let request = RetainRequest(items: batch, async: true, operationId: operation)
                    let directory = root.appendingPathComponent("collection/.memory-operations", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let packet = directory.appendingPathComponent(operation + ".json")
                    try JSONEncoder().encode(request).write(to: packet, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: packet.path)
                    try self.persist()
                    guard try await currentClient.retain(bank, request).success else { throw self.failure("Le serveur n’a pas accepté l’envoi. Vérifiez son état avant toute reprise.") }
                    try self.requireContext(expected)
                }
                self.message = "\(items.count) sources envoyées ; traitement à suivre dans cette liste."
            } catch {
                guard self.context == expected else { return }
                self.error = error.localizedDescription
            }
            self.buildRows()
        }
    }
    /// Le premier envoi rattache le dossier à sa banque, dans la politique que lisent tous les outils.
    private func bindFolder(to bank: String) throws {
        guard let url = policyURL else { throw failure("Choisissez une banque et ouvrez un catalogue.") }
        var latest: [String: Any] = FileManager.default.fileExists(atPath: url.path)
            ? try decode(url) : ["version": 1, "excluded_document_ids": [String: Any](), "deferred_document_ids": [String: Any]()]
        if let existing = (latest["bank_id"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) {
            guard existing == bank else { boundBank = existing; throw failure(mismatchMessage) }
        } else {
            latest["bank_id"] = bank
            try write(latest, to: url)
        }
        policy = latest; boundBank = bank
    }
    /// Reuses the exact request and operation UUID: a timeout must never create a second extraction.
    public func requestRetry(_ id: String) {
        confirmation = nil; error = nil; message = nil
        do { try requireLoadedContext() } catch { self.error = error.localizedDescription; return }
        guard !bankMismatch else { error = mismatchMessage; return }
        guard let bank = bank(), let root = folder.repository, let target = targets[id], let operation = operations[target], UUID(uuidString: operation) != nil else { error = "Aucun envoi à vérifier pour cette source."; return }
        let expected = context, currentClient = client()
        do {
            let path = root.appendingPathComponent("collection/.memory-operations/" + operation + ".json")
            let data = try Data(contentsOf: path)
            let request = try JSONDecoder().decode(RetainRequest.self, from: data)
            guard request.operationId == operation, request.items.allSatisfy({ item in
                guard let id = item.documentId, case .text(let text) = item.content else { return false }
                return operations[id] == operation && pending[id] == SHA256.hex(Data(text.utf8))
            }) else { throw failure("Le lot initial ne correspond plus à la file locale.") }
            let expectedPolicy = try JSONSerialization.data(withJSONObject: policy, options: .sortedKeys)
            let expectedPreferences = preferences
            var consumed = false
            confirmation = ConfirmationRequest(title: "Vérifier ou reprendre l’envoi initial ?", message: "Le même lot de \(request.items.count) sources sera présenté au serveur avec son identifiant initial. Un lot déjà accepté ne sera pas extrait deux fois. Le texte est celui de l’aperçu initial.\n\n" + request.items.compactMap(\.documentId).joined(separator: "\n"), confirmTitle: "Vérifier / reprendre", severity: .normal) { [weak self] in
                guard let self, self.context == expected, !consumed else { return }; consumed = true
                guard !self.actionInProgress else { return }
                self.actionInProgress = true
                defer { self.actionInProgress = false }
                do {
                    if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                    guard try Data(contentsOf: path) == data else { throw self.failure("Le lot a changé depuis l’aperçu.") }
                    try self.loadPolicy()
                    guard self.preferences == expectedPreferences,
                          try JSONSerialization.data(withJSONObject: self.policy, options: .sortedKeys) == expectedPolicy else {
                        throw self.failure("La sélection ou la politique a changé ; préparez un nouvel aperçu.")
                    }
                    guard request.items.allSatisfy({ item in
                        guard let target = item.documentId, case .text(let text) = item.content else { return false }
                        return self.operations[target] == operation && self.pending[target] == SHA256.hex(Data(text.utf8))
                    }) else { throw self.failure("Le lot initial ne correspond plus à la file locale.") }
                    try self.requireContext(expected)
                    guard try await currentClient.retain(bank, request).success else { throw self.failure("Le serveur n’a pas accepté l’envoi. Vérifiez son état avant toute reprise.") }
                    try self.requireContext(expected)
                    self.error = nil
                    self.message = "Envoi initial retrouvé ou repris. Actualisez pour vérifier le résultat."
                } catch { if self.context == expected { self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }

    public func requestRemove(_ id: String) {
        confirmation = nil; error = nil; message = nil
        do { try requireLoadedContext() } catch { self.error = error.localizedDescription; return }
        guard let bank = bank(), let root = folder.repository, let target = targets[id], let row = records.first(where: { $0["id"] as? String == id }), (row["memory"] as? [String: Any])?["can_remove"] as? Bool == true else { error = "Source indisponible ou en attente de revue."; return }
        if let reason = pauseGate?(bank) { error = reason; return }
        guard pending[target] == nil else { error = "Attendez la fin du traitement avant de retirer cette source."; return }
        let expected = context, currentClient = client()
        let expectedHash = documents[target]?.contentHash
        var consumed = false
        confirmation = ConfirmationRequest(title: "Retirer de la mémoire ?", message: "\(target)\n\nLe fichier local est conservé. Cette source sera exclue des prochains envois. Le document et ses faits seront retirés de Hindsight après sauvegarde locale du texte et des métadonnées.", confirmTitle: "Retirer", severity: .destructive) { [weak self] in
            guard let self, self.context == expected, !consumed else { return }; consumed = true
            guard !self.actionInProgress else { return }
            self.actionInProgress = true
            defer { self.actionInProgress = false }
            do {
                if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                try await self.checkQueue(bank, client: currentClient)
                try self.requireContext(expected)
                try self.loadPolicy(); self.buildRows()
                guard self.pending[target] == nil else { throw self.failure("Attendez la fin du traitement avant de retirer cette source.") }
                guard self.targets[id] == target, (self.records.first(where: { $0["id"] as? String == id })?["memory"] as? [String: Any])?["can_remove"] as? Bool == true else { throw self.failure("La sélection ou la politique a changé ; rechargez la vue.") }
                guard self.policyReason(id: target, repo: "", path: "") == nil || (self.policy["excluded_document_ids"] as? [String: [String: Any]])?[target]?["origin"] as? String == "workspace" else { throw self.failure("La politique a changé ; rechargez la vue.") }
                let backup = root.appendingPathComponent("archives/hindsight/retraits-app/" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if self.documents[target] != nil {
                    let doc = try await currentClient.document(bank, id: target)
                    try self.requireContext(expected)
                    try JSONEncoder().encode(doc).write(to: backup.appendingPathComponent("document.json"), options: .atomic)
                    if let expected = expectedHash, SHA256.hex(Data((doc.originalText ?? "").utf8)) != expected { throw self.failure("La version mémorisée a changé ; rechargez la vue.") }
                }
                // Persist exclusions before delete, so a failed request cannot cause a future re-send.
                if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                self.preferences[id] = false; try self.persist()
                if let url = self.policyURL, self.policy.isEmpty || self.policy["bank_id"] as? String == bank {
                    var p = self.policy.isEmpty ? ["version": 1, "bank_id": bank, "excluded_document_ids": [:], "deferred_document_ids": [:]] : try self.decode(url)
                    var excluded = p["excluded_document_ids"] as? [String: Any] ?? [:]
                    excluded[target] = ["action": "archived", "origin": "workspace", "reason": "Retrait validé dans l’app", "archive": backup.path, "original_path": (row["context"] as? [String: Any])?["original_path"] as? String ?? ""]
                    p["excluded_document_ids"] = excluded; try self.write(p, to: url)
                }
                if self.documents[target] != nil { guard try await currentClient.deleteDocument(bank, id: target).success else { throw self.failure("Le serveur n’a pas confirmé le retrait. La source reste exclue des futurs envois.") } }
                try self.requireContext(expected)
                self.pending[target] = nil; try self.persist(); await self.refresh(); self.message = "Source retirée et exclue. Fichier conservé."
            } catch {
                guard self.context == expected else { return }
                let detail = error.localizedDescription; await self.refresh()
                if self.context == expected { self.error = detail }
            }
        }
    }
}
