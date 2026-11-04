import Foundation

/// Inventaire des documents d'un ou plusieurs dépôts, en lecture seule.
public struct FileCoverageScanner: Sendable {
    let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// Un dossier choisi est un dépôt s'il contient `.git` ; sinon chacun de ses sous-dossiers qui en
    /// contient un ; sinon le dossier lui-même, comme simple dossier.
    public static func repositories(in roots: [URL]) -> [URL] {
        let fm = FileManager.default
        func isRepo(_ url: URL) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(".git").path) }
        return roots.flatMap { root -> [URL] in
            if isRepo(root) { return [root] }
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let repos = children.filter(isRepo).sorted { $0.lastPathComponent < $1.lastPathComponent }
            return repos.isEmpty ? [root] : repos
        }
    }

    /// Fichiers des dépôts : suivis par git (ce que `.gitignore` exclut n'en fait pas partie), ou tous les
    /// fichiers non cachés d'un simple dossier ; documents seulement sauf option « tous les fichiers ».
    public func scan(roots: [CoverageRoot]) async -> (files: [ScannedFile], warnings: [String]) {
        var files: [ScannedFile] = []
        var warnings: [String] = []
        for root in roots {
            for repo in Self.repositories(in: [root.url]) {
                do {
                    files += try await self.files(in: repo, allFiles: root.allFiles)
                } catch {
                    warnings.append("\(repo.lastPathComponent) : \(error.userMessage)")
                }
            }
        }
        // Un dépôt atteint par deux dossiers choisis n'est compté qu'une fois.
        var seen = Set<String>()
        return (files.filter { seen.insert($0.key).inserted }.sorted { $0.key < $1.key }, warnings)
    }

    struct GitError: LocalizedError {
        let message: String
        var errorDescription: String? { "git ls-files a échoué : \(message)" }
    }

    func files(in repo: URL, allFiles: Bool) async throws -> [ScannedFile] {
        let paths: [String]
        if FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path) {
            let out = try await runner.run(ProcessInvocation("/usr/bin/git", ["-C", repo.path, "ls-files", "-z"]))
            guard out.succeeded else { throw GitError(message: String(out.combined.prefix(200))) }
            paths = out.stdout.split(separator: "\0").map(String.init)
        } else {
            paths = Self.plainFiles(in: repo)
        }
        return paths.filter { FileCoverage.includes($0, allFiles: allFiles) }.compactMap { path in
            let url = repo.appendingPathComponent(path)
            guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return ScannedFile(repo: repo.lastPathComponent, path: path, url: url, size: v.fileSize ?? 0, modified: v.contentModificationDate ?? .distantPast)
        }
    }

    static func plainFiles(in root: URL) -> [String] {
        let base = root.standardizedFileURL.path + "/"
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var out: [String] = []
        while let url = e?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                out.append(String(url.standardizedFileURL.path.dropFirst(base.count)))
            }
        }
        return out
    }
}
