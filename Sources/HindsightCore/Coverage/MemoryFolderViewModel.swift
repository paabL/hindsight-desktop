import Foundation
import Observation

/// The common folder is the source archive; loading it never contacts Hindsight.
@MainActor
@Observable
public final class MemoryFolderViewModel {
    public private(set) var folder: URL?
    public private(set) var catalogURL: URL?
    public private(set) var revision = UUID()
    public private(set) var error: String?
    public private(set) var collecting = false
    public private(set) var importing = false
    public private(set) var importSummary: String?
    public private(set) var output = ""
    public var confirmation: ConfirmationRequest?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let python: String

    public init(settings: SettingsStore, runner: ProcessRunning = SystemProcessRunner(), home: URL = URL(fileURLWithPath: NSHomeDirectory()), python: String? = nil, discoverAutomatically: Bool = true) {
        self.settings = settings
        self.runner = runner
        self.python = python ?? ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
        folder = settings.string(forKey: SettingsKey.memoryFolderPath).map { URL(fileURLWithPath: $0) }
            ?? (discoverAutomatically ? Self.discover(home: home) : nil)
        reload()
    }

    public var repository: URL? {
        guard let folder else { return nil }
        let parent = folder.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("catalog.json").path) && FileManager.default.fileExists(atPath: parent.appendingPathComponent("collect.py").path) ? parent : folder
    }

    public var collection: URL? { catalogURL?.deletingLastPathComponent() }
    public var indexURL: URL? {
        guard let url = collection?.appendingPathComponent("index.html"), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    public var canCollect: Bool {
        guard let url = repository?.appendingPathComponent("collect.py") else { return false }
        return FileManager.default.fileExists(atPath: url.path) && !collecting
    }

    public func choose(_ url: URL) {
        guard !collecting else { return }
        folder = url.standardizedFileURL
        settings.set(folder?.path, forKey: SettingsKey.memoryFolderPath)
        confirmation = nil
        output = ""
        importSummary = nil
        reload()
    }

    public func reload() {
        error = nil
        catalogURL = nil
        guard let folder else { return }
        let candidates = [folder.appendingPathComponent("catalog.json"), folder.appendingPathComponent("collection/catalog.json")]
        guard let catalog = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            error = "Ce dossier ne contient pas encore de catalogue. Choisissez le dépôt mémoire ou son dossier collection."
            revision = UUID()
            return
        }
        do {
            let data = try Data(contentsOf: catalog)
            let header = try JSONDecoder().decode(CatalogHeader.self, from: data)
            guard header.version == 1, header.mode == "collection_only" else {
                error = "Le format de ce catalogue n'est pas pris en charge."
                revision = UUID()
                return
            }
            catalogURL = catalog
        } catch { self.error = "Catalogue illisible : \(error.localizedDescription)" }
        revision = UUID()
    }

    /// The only executable here is collect.py; sync.py and Hindsight are never invoked.
    public func requestCollection() {
        guard canCollect, let root = repository else { return }
        let script = root.appendingPathComponent("collect.py")
        let issues = FileSafety.inspect(script, requireExecutable: false).filter(\.isBlocking)
        guard issues.isEmpty else { error = issues.map(\.description).joined(separator: "\n"); return }
        guard let data = try? Data(contentsOf: script) else { error = "Collecteur illisible."; return }
        let hash = SHA256.hex(data)
        confirmation = ConfirmationRequest(
            title: "Collecter les sources ?",
            message: "Le collecteur de ce dossier sera exécuté avec vos droits. Il relit les conversations, GitHub, W&B et les rapports selon la configuration du projet, puis actualise les archives locales. Aucun envoi ni traitement Hindsight.\n\nDossier : \(root.path)",
            confirmTitle: "Collecter", severity: .normal
        ) { [weak self] in await self?.collect(root: root, expectedHash: hash) }
    }

    /// Explicit file selection archives locally; it never runs the provider collectors or Hindsight.
    public func requestImport(paths: [String], project: String) {
        guard canCollect, let root = repository else { return }
        confirmation = nil
        error = nil
        guard !paths.isEmpty, project.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
            error = "Choisissez un projet et au moins un fichier."
            return
        }
        do {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard path.hasPrefix("/"), ["md", "tex", "pdf"].contains(url.pathExtension.lowercased()),
                      values.isRegularFile == true, values.isSymbolicLink != true else {
                    error = "Choisissez uniquement des fichiers .md, .tex ou .pdf ordinaires."
                    return
                }
            }
            let script = root.appendingPathComponent("collect.py")
            let issues = FileSafety.inspect(script, requireExecutable: false).filter(\.isBlocking)
            guard issues.isEmpty else { error = issues.map(\.description).joined(separator: "\n"); return }
            let hash = SHA256.hex(try Data(contentsOf: script))
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
            confirmation = ConfirmationRequest(
                title: "Ajouter \(paths.count) document(s) ?",
                message: "Projet : \(project)\nDestination : \(root.path)/documents/\(project)/\n\n\(names)\n\nLe collecteur de ce dossier copie les originaux et actualise uniquement le catalogue local. Aucun envoi ni traitement Hindsight ; les quatre collecteurs externes ne sont pas lancés.",
                confirmTitle: "Ajouter", severity: .normal
            ) { [weak self] in
                let args = ["--project", project] + paths.flatMap { ["--import-file", $0] }
                await self?.collect(root: root, expectedHash: hash, arguments: args, importing: true)
            }
        } catch { self.error = "Fichier inaccessible : \(error.localizedDescription)" }
    }

    public func collectSources() async {
        guard canCollect, let root = repository else { error = "Le dossier ne peut pas être collecté."; return }
        let script = root.appendingPathComponent("collect.py")
        let issues = FileSafety.inspect(script, requireExecutable: false).filter(\.isBlocking)
        guard issues.isEmpty else { error = issues.map(\.description).joined(separator: "\n"); return }
        guard let data = try? Data(contentsOf: script) else { error = "Collecteur illisible."; return }
        await collect(root: root, expectedHash: SHA256.hex(data))
    }

    private func collect(root: URL, expectedHash: String, arguments: [String] = [], importing isImport: Bool = false) async {
        guard !collecting else { return }
        let script = root.appendingPathComponent("collect.py")
        guard let data = try? Data(contentsOf: script), SHA256.hex(data) == expectedHash else {
            error = "Le collecteur a changé depuis la confirmation. Relancez la demande."
            return
        }
        collecting = true
        importing = isImport
        importSummary = nil
        error = nil
        output = ""
        defer { collecting = false; importing = false }
        do {
            let result = try await runner.run(ProcessInvocation(python, [script.path] + arguments, in: root.path, timeout: 7200)) { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    self.output = String((self.output + SecretMasker.mask(text)).suffix(20_000))
                }
            }
            reload()
            if !result.succeeded {
                error = result.timedOut ? "La collecte a dépassé le délai prévu. Les archives déjà enregistrées sont conservées."
                    : isImport ? "Ajout incomplet : " + (result.stderr.isEmpty ? "Consultez l’état des documents dans le catalogue." : SecretMasker.mask(String(result.stderr.suffix(1200))))
                    : "La collecte est incomplète. Consultez l'état des sources dans le catalogue."
            } else if isImport {
                let line = result.stdout.split(separator: "\n").last.map(String.init) ?? ""
                if let bytes = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    let added = json["imported"] as? Int ?? 0
                    let unchanged = json["unchanged"] as? Int ?? 0
                    importSummary = "\(added) document(s) ajouté(s) ou mis à jour, \(unchanged) déjà à jour. Aucun traitement Hindsight."
                }
            }
        } catch { self.error = "Collecte impossible : \(error.localizedDescription)" }
    }

    private struct CatalogHeader: Decodable { let version: Int; let mode: String }

    /// Reuse opted-in project locations, without a machine-specific path or a home-directory scan.
    static func discover(home: URL) -> URL? {
        let path = home.appendingPathComponent(".hindsight/coding-agent.json")
        guard let data = try? Data(contentsOf: path), let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mapping = config["mapPathToBank"] as? [String: String] else { return nil }
        var found: [String: URL] = [:]
        for path in mapping.keys {
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for folder in [root] + children where FileManager.default.fileExists(atPath: folder.appendingPathComponent("projects.toml").path) {
                let key = folder.standardizedFileURL.path.precomposedStringWithCanonicalMapping
                found[key] = folder
            }
        }
        return found.count == 1 ? found.values.first : nil
    }
}
