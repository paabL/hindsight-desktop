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
    private var texts: [String: String] = [:]
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
    public var pauseGate: PauseGate?

    public init(folder: MemoryFolderViewModel, client: @escaping () -> HindsightClient, bank: @escaping () -> String?) {
        self.folder = folder; self.client = client; self.bank = bank
    }
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
            }
            preferences = state["enabled"] as? [String: Bool] ?? [:]
            pending = state["pending"] as? [String: String] ?? [:]
            operations = state["operations"] as? [String: String] ?? [:]
            failures = state["failures"] as? [String: String] ?? [:]
            bindings = state["bindings"] as? [String: String] ?? [:]
            repairOldTracking = (state["tracking_version"] as? Int ?? 1) < 2 && !failures.isEmpty
        }
    }
    private func persist() throws {
        guard let url = ledgerURL, let bank = bank() else { throw failure("Choisissez un dossier et une banque.") }
        var ledger = FileManager.default.fileExists(atPath: url.path) ? try decode(url) : [:]
        ledger[bank] = ["tracking_version": repairOldTracking ? 1 : 2, "enabled": preferences, "pending": pending, "operations": operations, "failures": failures, "bindings": bindings]
        try write(ledger, to: url)
    }
    /// Reconcile old false failures from the exact saved submissions, never by resending them.
    private func recoverTracking(_ bank: String) async throws -> [String: OperationStatusResponse] {
        guard repairOldTracking, let root = folder.collection, let ledger = ledgerURL else { return [:] }
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
            guard let status = try? await client().operation(bank, id: id) else { retryRecovery = true; continue }
            guard self.bank() == bank, loadedRoot == folder.repository?.path else { throw failure("Le contexte a changé ; actualisez la vue.") }
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
    private func hasRetainWork(_ bank: String) async throws -> Bool {
        for status in ["pending", "processing"] {
            for type in ["retain", "batch_retain"] {
                if try await client().listOperations(bank, status: status, type: type, limit: 1).total > 0 { return true }
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
    private func sourceText(_ record: [String: Any], root: URL?) throws -> String {
        guard let root, let files = record["files"] as? [String: String] else { throw failure("Source locale indisponible.") }
        let chosen = files["document.md"] ?? files.keys.sorted().first(where: { ["md", "tex", "txt", "markdown"].contains(($0 as NSString).pathExtension.lowercased()) }).flatMap { files[$0] }
        guard let relative = chosen else { throw failure("Une source TeX ou Markdown est requise pour ce document.") }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."), url.path.hasPrefix(root.path + "/"),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw failure("Source hors du dossier commun.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    private func originalKey(_ record: [String: Any], text: String?) -> String? {
        let context = record["context"] as? [String: Any] ?? [:]
        guard let path = context["managed_path"] as? String else { return nil }
        let repo = (record["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder.repository?.lastPathComponent ?? ""
        if path.hasPrefix("board/"), let text, let range = text.range(of: "(?m)^id: *([^\\n]+)", options: .regularExpression) {
            let id = String(text[range]).dropFirst(3).trimmingCharacters(in: .whitespaces)
            if path.contains("/cards/") { return "card-" + id }
            if path.hasSuffix("chantier.md") { return "chantier-" + id }
        }
        if path == "board/project.md" { return "board-project" }
        return "doc:\(repo):\(path)"
    }
    public func refresh() async {
        confirmation = nil; error = nil; comparisonAvailable = false; folder.reload()
        if loadedBank != bank() || loadedRoot != folder.repository?.path { documents = [:]; records = []; texts = [:]; targets = [:] }
        loadedBank = bank(); loadedRoot = folder.repository?.path
        do {
            try loadPolicy()
            var fresh: [String: DocumentListItem] = [:]
            if let bank = bank() {
                var offset = 0
                while true {
                    // Le coût d'une page est surtout fixe côté serveur : 1 000 documents par requête au lieu de 100.
                    let page = try await client().listDocuments(bank, limit: 1000, offset: offset)
                    guard self.bank() == bank, loadedRoot == folder.repository?.path else { return }
                    for doc in page.items { fresh[doc.id] = doc }
                    offset += page.items.count
                    if offset >= page.total { break }
                    guard !page.items.isEmpty else { throw failure("Inventaire Hindsight incomplet.") }
                }
            } else { error = "Connectez Hindsight pour comparer les versions." }
            documents = fresh; comparisonAvailable = bank() != nil
            if let bank = bank() {
                let wasRepairing = repairOldTracking
                let recovered = try await recoverTracking(bank)
                let hadTracking = !operations.isEmpty
                var checkedQueue = false
                var retainWork: Bool?
                for id in Set(operations.values) {
                    let op: OperationStatusResponse?
                    if let cached = recovered[id] { op = cached } else { op = try? await client().operation(bank, id: id) }
                    guard self.bank() == bank, loadedRoot == folder.repository?.path else { return }
                    guard let op, ["failed", "cancelled", "completed"].contains(op.status) else { continue }
                    let childFailed = op.childOperations?.contains { ["failed", "cancelled"].contains($0.status) } == true
                    let childActive = op.childOperations?.contains { ["pending", "processing"].contains($0.status) } == true
                    let parent = op.operationType == "batch_retain" || op.resultMetadata?["is_parent"] == .bool(true)
                    for target in operations.keys.filter({ operations[$0] == id }) {
                        let matches = pending[target] != nil && fresh[target]?.contentHash == pending[target]
                        let failed = op.status != "completed" || childFailed
                        if !failed && childActive { continue }
                        if !failed && parent && !matches {
                            if !checkedQueue { retainWork = try? await hasRetainWork(bank); checkedQueue = true }
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
        } catch { self.error = error.localizedDescription; documents = [:]; comparisonAvailable = false }
        buildRows()
    }
    private func buildRows() {
        records = []; texts = [:]; targets = [:]
        let catalog = folder.catalogURL.flatMap { try? decode($0) } ?? [:]
        let raw = catalog["records"] as? [[String: Any]] ?? []
        var claimed = Set<String>()
        let root = folder.collection?.resolvingSymlinksInPath()
        // Index des documents, dans l'ordre de parcours de `documents` : le premier porteur de chaque
        // `source_record_id` et le suffixe « /dépôt/chemin » de chacun, au lieu de deux parcours par source.
        var bySourceRecord: [String: String] = [:]
        var pathSuffixes: [(id: String, suffix: String)] = []
        for doc in documents.values {
            if case .string(let source)? = doc.documentMetadata?["source_record_id"], bySourceRecord[source] == nil { bySourceRecord[source] = doc.id }
            if let repo = doc.documentMetadata?["repo"]?.stringValue, let path = doc.documentMetadata?["path"]?.stringValue, !repo.isEmpty, !path.isEmpty {
                pathSuffixes.append((doc.id, ("/" + repo + "/" + path).precomposedStringWithCanonicalMapping))
            }
        }
        for var record in raw {
            guard let id = record["id"] as? String else { continue }
            let context = record["context"] as? [String: Any] ?? [:]
            let path = context["managed_path"] as? String ?? ""
            let repo = (record["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? folder.repository?.lastPathComponent ?? ""
            var readError: String?
            let text: String?
            do { text = try sourceText(record, root: root) } catch { text = nil; readError = error.localizedDescription }
            let canonical = "source:" + id
            let aliases = [bindings[id], canonical, id, originalKey(record, text: text)].compactMap { $0 }
            let original = (context["original_path"] as? String)?.precomposedStringWithCanonicalMapping
            let byPath = original.map { original in pathSuffixes.filter { original.hasSuffix($0.suffix) } } ?? []
            let matched = aliases.first(where: { documents[$0] != nil }) ?? bySourceRecord[id] ?? (byPath.count == 1 ? byPath.first?.id : nil)
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
            let enabled = hold == nil && text != nil && (preferences[id] ?? !aside)
            let hash = text.map { SHA256.hex(Data($0.utf8)) }
            var state = !enabled ? "excluded" : documents[target] == nil ? "new" : documents[target]?.contentHash == hash ? "current" : "modified"
            if enabled && failures[target] != nil { state = "error" }
            if enabled && !comparisonAvailable { state = "unknown" }
            if preferences[id] != false && readError != nil && hold == nil && !aside { state = "error" }
            if pending[target] != nil && comparisonAvailable {
                if operations[target] == nil && documents[target]?.contentHash == pending[target] { pending[target] = nil }
                else { state = "queued" }
            }
            if let matched { claimed.insert(matched) }
            record["memory"] = ["state": state, "enabled": enabled, "document_id": target, "stored": matched != nil,
                                "can_remove": hold == nil || ownExclusion, "locked": (hold != nil && !ownExclusion) || text == nil, "reason": hold ?? readError ?? failures[target] ?? "", "hash": hash ?? ""]
            records.append(record); texts[id] = text; targets[id] = target
        }
        // Sources imported by other tools stay visible; do not infer that their file disappeared.
        for doc in documents.values.sorted(by: { $0.id < $1.id }) where !claimed.contains(doc.id) {
            let id = "bank:" + doc.id
            let hold = policyReason(id: doc.id, repo: doc.documentMetadata?["repo"]?.stringValue ?? "", path: doc.documentMetadata?["path"]?.stringValue ?? "")
            records.append(["id": id, "title": doc.id, "kind": "documents", "project": "", "project_name": "En mémoire", "repository": doc.documentMetadata?["repo"]?.stringValue ?? "", "files": [:], "source_updated_at": doc.updatedAt,
                            "memory": ["state": hold == nil ? (doc.documentMetadata?["source_record_id"] == nil ? "unlinked" : "missing") : "excluded", "enabled": false, "stored": true, "can_remove": hold == nil || policyIndex.isWorkspaceExclusion(doc.id), "locked": hold != nil && !policyIndex.isWorkspaceExclusion(doc.id), "document_id": doc.id, "reason": hold ?? "Source à relier au catalogue"]])
            targets[id] = doc.id
        }
    }
    public func setEnabled(_ id: String, enabled: Bool) throws { try setEnabled([id], enabled: enabled) }
    public func setEnabled(_ ids: [String], enabled: Bool) throws {
        for id in ids {
            guard let row = records.first(where: { $0["id"] as? String == id }), let state = row["memory"] as? [String: Any], state["locked"] as? Bool != true, texts[id] != nil else { throw failure("Une source nécessite une revue ou une version texte.") }
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
        guard texts[id] != nil, let row = records.first(where: { $0["id"] as? String == id }),
              let state = row["memory"] as? [String: Any], state["locked"] as? Bool != true,
              state["stored"] as? Bool != true, documents[document] != nil,
              records.contains(where: { $0["id"] as? String == "bank:" + document && ($0["memory"] as? [String: Any])?["locked"] as? Bool != true })
        else { throw failure("Choisissez une source non liée et un document disponible.") }
        confirmation = nil; bindings[id] = document; try persist(); buildRows()
    }

    public func storedText(_ id: String) async throws -> String {
        guard let bank = bank(), let target = targets[id] else { throw failure("Document inconnu.") }
        return try await client().document(bank, id: target).originalText ?? ""
    }
    private func checkQueue(_ bank: String) async throws {
        for status in ["pending", "processing"] {
            let queue = try await client().listOperations(bank, status: status, limit: 1)
            guard queue.operations.isEmpty else { throw failure("Des opérations sont encore en cours. Consultez Opérations puis actualisez.") }
        }
    }
    /// Refreshes only the local archive. It does not require or contact Hindsight.
    public func refreshSources() async {
        confirmation = nil; message = nil; error = nil
        await folder.collectSources()
        if loadedBank != bank() || loadedRoot != folder.repository?.path {
            documents = [:]; comparisonAvailable = false
        }
        loadedBank = bank(); loadedRoot = folder.repository?.path
        do { try loadPolicy() } catch { self.error = error.localizedDescription }
        if let collectionError = folder.error { error = collectionError }
        buildRows()
        if error == nil { message = "Dossier actualisé. Aucun envoi ni traitement Hindsight." }
    }

    /// Prepares the existing catalogue; collecting and sending are independent actions.
    public func prepareSend() async {
        confirmation = nil; message = nil
        guard let bank = bank(), let root = folder.repository else { error = "Choisissez un dossier mémoire et une banque."; return }
        if let reason = pauseGate?(bank) { error = reason; return }
        folder.reload()
        guard folder.catalogURL != nil, folder.error == nil else { error = folder.error ?? "Choisissez un catalogue existant."; return }
        await refresh()
        guard error == nil else { return }
        do { try await checkQueue(bank) } catch { self.error = error.localizedDescription; return }
        let selected = records.filter { row in
            let s = row["memory"] as? [String: Any] ?? [:]
            return s["enabled"] as? Bool == true && ["new", "modified", "error"].contains(s["state"] as? String ?? "")
        }
        guard !records.contains(where: { ($0["memory"] as? [String: Any])?["state"] as? String == "queued" }) else { error = "Un envoi est encore en cours. Actualisez après son traitement."; return }
        guard !selected.isEmpty else { message = "Toutes les sources activées sont à jour."; return }
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
        confirmation = ConfirmationRequest(title: "Envoyer les sources à Hindsight ?", message: "\(items.count) sources complètes vers « \(bank) », environ \(chars / 4) jetons de texte avant extraction.\n\n" + selected.map { "• " + ($0["title"] as? String ?? "") + " — " + (targets[$0["id"] as? String ?? ""] ?? "") }.joined(separator: "\n") + "\n\nLes sources modifiées remplacent leur version mémorisée. Aucune suppression d’autres documents. La consolidation dépend des réglages de la banque.", confirmTitle: "Envoyer") { [weak self] in
            guard let self else { return }
            guard self.bank() == bank, self.folder.repository == root else { self.error = "Le contexte a changé ; préparez un nouvel aperçu."; return }
            if let reason = self.pauseGate?(bank) { self.error = reason; return }
            await self.refresh()
            guard self.error == nil, self.preferences == frozenPreferences,
                  (try? JSONSerialization.data(withJSONObject: self.policy, options: .sortedKeys)) == frozenPolicy,
                  selected.enumerated().allSatisfy({ index, row in
                    let current = self.records.first(where: { $0["id"] as? String == row["id"] as? String })
                    return current.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) } == frozenRows[index]
                  }), self.documents.mapValues(\.contentHash) == baseline,
                  selected.allSatisfy({ row in let id = row["id"] as? String ?? ""; return self.texts[id] == frozenTexts[id] && self.targets[id] == frozenTargets[id] && (self.records.first(where: { $0["id"] as? String == id })?["memory"] as? [String: Any])?["enabled"] as? Bool == true }) else {
                self.error = "Les sources, la sélection ou la banque ont changé. Préparez un nouvel aperçu."; return
            }
            do {
                try await self.checkQueue(bank)
                for batch in CodexImportViewModel.batches(items.map { ($0, (frozenTexts[$0.metadata?["source_record_id"] ?? ""]?.utf8.count ?? 0) + 2000) }, byteLimit: 8_000_000, itemLimit: 10) {
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
                    guard try await self.client().retain(bank, request).success else { throw self.failure("Le serveur n’a pas accepté l’envoi. Vérifiez son état avant toute reprise.") }
                }
                self.message = "\(items.count) sources envoyées ; traitement à suivre dans cette liste."
            } catch { self.error = error.localizedDescription }
            self.buildRows()
        }
    }
    /// Reuses the exact request and operation UUID: a timeout must never create a second extraction.
    public func requestRetry(_ id: String) {
        confirmation = nil
        guard let bank = bank(), let root = folder.repository, let target = targets[id], let operation = operations[target], UUID(uuidString: operation) != nil else { error = "Aucun envoi à vérifier pour cette source."; return }
        do {
            let path = root.appendingPathComponent("collection/.memory-operations/" + operation + ".json")
            let data = try Data(contentsOf: path)
            let request = try JSONDecoder().decode(RetainRequest.self, from: data)
            guard request.operationId == operation, request.items.allSatisfy({ item in
                guard let id = item.documentId, case .text(let text) = item.content else { return false }
                return operations[id] == operation && pending[id] == SHA256.hex(Data(text.utf8))
            }) else { throw failure("Le lot initial ne correspond plus à la file locale.") }
            confirmation = ConfirmationRequest(title: "Vérifier ou reprendre l’envoi initial ?", message: "Le même lot de \(request.items.count) sources sera présenté au serveur avec son identifiant initial. Un lot déjà accepté ne sera pas extrait deux fois. Le texte est celui de l’aperçu initial.\n\n" + request.items.compactMap(\.documentId).joined(separator: "\n"), confirmTitle: "Vérifier / reprendre", severity: .normal) { [weak self] in
                guard let self, self.bank() == bank, self.folder.repository == root else { return }
                do {
                    if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                    guard try Data(contentsOf: path) == data else { throw self.failure("Le lot a changé depuis l’aperçu.") }
                    guard try await self.client().retain(bank, request).success else { throw self.failure("Le serveur n’a pas accepté l’envoi. Vérifiez son état avant toute reprise.") }
                    self.message = "Envoi initial retrouvé ou repris. Actualisez pour vérifier le résultat."
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    public func requestRemove(_ id: String) {
        confirmation = nil
        guard let bank = bank(), let root = folder.repository, let target = targets[id], let row = records.first(where: { $0["id"] as? String == id }), (row["memory"] as? [String: Any])?["can_remove"] as? Bool == true else { error = "Source indisponible ou en attente de revue."; return }
        if let reason = pauseGate?(bank) { error = reason; return }
        guard pending[target] == nil else { error = "Attendez la fin du traitement avant de retirer cette source."; return }
        let expectedHash = documents[target]?.contentHash
        confirmation = ConfirmationRequest(title: "Retirer de la mémoire ?", message: "\(target)\n\nLe fichier local est conservé. Cette source sera exclue des prochains envois. Le document et ses faits seront retirés de Hindsight après sauvegarde locale du texte et des métadonnées.", confirmTitle: "Retirer", severity: .destructive) { [weak self] in
            guard let self, self.bank() == bank, self.folder.repository == root else { return }
            do {
                if let reason = self.pauseGate?(bank) { throw self.failure(reason) }
                try await self.checkQueue(bank)
                try self.loadPolicy(); self.buildRows()
                guard self.targets[id] == target, (self.records.first(where: { $0["id"] as? String == id })?["memory"] as? [String: Any])?["can_remove"] as? Bool == true else { throw self.failure("La sélection ou la politique a changé ; rechargez la vue.") }
                guard self.policyReason(id: target, repo: "", path: "") == nil || (self.policy["excluded_document_ids"] as? [String: [String: Any]])?[target]?["origin"] as? String == "workspace" else { throw self.failure("La politique a changé ; rechargez la vue.") }
                let backup = root.appendingPathComponent("archives/hindsight/retraits-app/" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if self.documents[target] != nil {
                    let doc = try await self.client().document(bank, id: target)
                    try JSONEncoder().encode(doc).write(to: backup.appendingPathComponent("document.json"), options: .atomic)
                    if let expected = expectedHash, SHA256.hex(Data((doc.originalText ?? "").utf8)) != expected { throw self.failure("La version mémorisée a changé ; rechargez la vue.") }
                }
                // Persist exclusions before delete, so a failed request cannot cause a future re-send.
                self.preferences[id] = false; try self.persist()
                if let url = self.policyURL, self.policy.isEmpty || self.policy["bank_id"] as? String == bank {
                    var p = self.policy.isEmpty ? ["version": 1, "bank_id": bank, "excluded_document_ids": [:], "deferred_document_ids": [:]] : try self.decode(url)
                    var excluded = p["excluded_document_ids"] as? [String: Any] ?? [:]
                    excluded[target] = ["action": "archived", "origin": "workspace", "reason": "Retrait validé dans l’app", "archive": backup.path, "original_path": (row["context"] as? [String: Any])?["original_path"] as? String ?? ""]
                    p["excluded_document_ids"] = excluded; try self.write(p, to: url)
                }
                if self.documents[target] != nil { guard try await self.client().deleteDocument(bank, id: target).success else { throw self.failure("Le serveur n’a pas confirmé le retrait. La source reste exclue des futurs envois.") } }
                self.pending[target] = nil; try self.persist(); self.message = "Source retirée et exclue. Fichier conservé."; await self.refresh()
            } catch { let detail = error.localizedDescription; await self.refresh(); self.error = detail }
        }
    }
}
