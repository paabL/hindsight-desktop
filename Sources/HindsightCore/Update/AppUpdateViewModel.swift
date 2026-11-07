import Foundation
import Observation

public struct GitCommit: Sendable, Hashable, Identifiable {
    public var id: String { sha }
    public let sha: String
    public let author: String
    public let date: String
    public let subject: String

    public var short: String { String(sha.prefix(7)) }

    /// Lignes `%H<US>%an<US>%ad<US>%s` (séparateur 0x1F).
    static func parse(_ text: String) -> [GitCommit] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, f[0].count >= 7 else { return nil }
            return GitCommit(sha: f[0], author: f[1], date: f[2], subject: f[3])
        }
    }
}

/// Mises à jour de l'app depuis son dépôt git : récupération, liste des commits, puis — après
/// confirmation — avance rapide sur le commit exact présenté, recompilation et remplacement de l'app.
///
/// Sécurité :
/// - git est appelé sans shell, avec des arguments en tableau ; branche et dépôt distant sont validés ;
/// - seuls les transports chiffrés (https, ssh) sont acceptés ; un changement d'URL du dépôt distant
///   depuis la dernière mise à jour est signalé dans la confirmation ;
/// - l'avance rapide vise le commit affiché (`merge --ff-only <sha>`), pas « ce qu'il y a sur le serveur
///   au moment du clic » ; une copie locale modifiée ou divergente n'est jamais écrasée ;
/// - le code récupéré est compilé et exécuté : la confirmation le dit explicitement.
@MainActor
@Observable
public final class AppUpdateViewModel {
    public enum Phase: Sendable, Equatable {
        case idle
        case checking
        case upToDate
        case available
        /// La copie locale est plus récente que l'app installée (mise à jour faite à la main).
        case rebuildAvailable
        case working(String)
        /// Nouvelle version installée à la place de l'app : il reste à relancer.
        case readyToRelaunch
        /// Construite mais non installée (l'app tourne hors bundle).
        case built(String)
        case failed(String)
    }

    public nonisolated static let git = "/usr/bin/git"
    public nonisolated static let bash = "/bin/bash"

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let runner: ProcessRunning
    public let appInfo: AppInfo
    private let tauri: Bool

    public var repositoryPath: String
    public var checkAtLaunch: Bool {
        didSet { settings.set(checkAtLaunch ? nil : "false", forKey: SettingsKey.updateCheckAtLaunch) }
    }
    public private(set) var phase: Phase = .idle
    public private(set) var branch: String?
    public private(set) var remoteName: String?
    public private(set) var remoteURL: String?
    public private(set) var head: String?
    public private(set) var target: String?
    public private(set) var pending: [GitCommit] = []
    public private(set) var isDirty = false
    /// Fichiers suivis modifiés localement (sortie de `git status --porcelain`), pour le dire précisément.
    public private(set) var dirtyFiles: [String] = []
    public private(set) var canFastForward = true
    public private(set) var lastChecked: Date?
    public private(set) var log = ""
    public var confirmation: ConfirmationRequest?

    public init(settings: SettingsStore, runner: ProcessRunning = SystemProcessRunner(), appInfo: AppInfo, tauri: Bool = false) {
        self.tauri = tauri
        self.settings = settings
        self.runner = runner
        self.appInfo = appInfo
        self.repositoryPath = settings.string(forKey: SettingsKey.updateRepository) ?? appInfo.sourceRepository ?? ""
        self.checkAtLaunch = settings.string(forKey: SettingsKey.updateCheckAtLaunch) != "false"
    }

    public func selectRepository(_ path: String) {
        guard !isWorking, path != repositoryPath else { return }
        repositoryPath = path
        confirmation = nil
        head = nil
        target = nil
        pending = []
        remoteURL = nil
        remoteName = nil
        branch = nil
        isDirty = false
        dirtyFiles = []
        lastChecked = nil
        phase = .idle
    }

    public var hasUpdate: Bool { phase == .available || phase == .rebuildAvailable }
    public var isWorking: Bool {
        if case .working = phase { return true }
        return phase == .checking
    }
    /// Le dépôt distant diffère de celui approuvé lors de la dernière mise à jour.
    public var remoteChangedSinceApproval: Bool {
        guard let remoteURL, let approved = settings.string(forKey: SettingsKey.updateApprovedRemote) else { return false }
        return approved != remoteURL
    }

    var repoURL: URL { LaunchScriptStore.expand(repositoryPath.trimmingCharacters(in: .whitespaces)) }

    // MARK: Validation

    /// Nom de branche ou de dépôt distant sans ambiguïté (pas d'option déguisée, pas de caractère exotique).
    static func isSafeRefName(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix("-") && !s.contains("..") && s.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil
    }

    /// Transports acceptés : https://, ssh://, et la forme courte `utilisateur@hôte:chemin`.
    static func remoteProblem(_ url: String) -> String? {
        let u = url.trimmingCharacters(in: .whitespaces)
        if u.hasPrefix("https://"), let parsed = URL(string: u), parsed.user != nil || parsed.password != nil { return "L’URL du dépôt ne doit pas contenir d’identifiants." }
        if u.hasPrefix("https://") || u.hasPrefix("ssh://") { return nil }
        if u.range(of: #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^/][^\s]*$"#, options: .regularExpression) != nil { return nil }
        if u.hasPrefix("http://") || u.hasPrefix("git://") { return "Le dépôt distant (\(u)) utilise un transport non chiffré : passez en https:// ou ssh." }
        return "Transport du dépôt distant non pris en charge pour les mises à jour : \(u)"
    }

    func validateRepository() -> String? {
        let fm = FileManager.default
        let root = repoURL
        guard !repositoryPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Indiquez le dossier du dépôt hindsight-mac (le clone git d'où l'app a été construite)."
        }
        guard fm.fileExists(atPath: root.appendingPathComponent(".git").path) else { return "\(root.path) n'est pas un dépôt git." }
        if tauri {
            guard fm.fileExists(atPath: root.appendingPathComponent("desktop/src-tauri/tauri.conf.json").path),
                  fm.fileExists(atPath: root.appendingPathComponent("desktop/scripts/update-build.mjs").path) else { return "Ce dossier ne contient pas Hindsight Desktop Tauri." }
            return nil
        }
        guard let pkg = try? String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8), pkg.contains("HindsightMac"),
            fm.fileExists(atPath: root.appendingPathComponent("scripts/make-app.sh").path)
        else { return "\(root.path) ne contient pas le projet hindsight-mac." }
        return nil
    }

    func git(_ args: [String], timeout: TimeInterval = 30) async throws -> ProcessOutput {
        try await runner.run(
            ProcessInvocation(
                Self.git, ["-C", repoURL.path] + args,
                environment: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C", "GIT_OPTIONAL_LOCKS": "0"], timeout: timeout))
    }

    func gitValue(_ args: [String]) async throws -> String {
        let r = try await git(args)
        guard r.succeeded else { throw UpdateError.git(args.first ?? "git", r.combined) }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum UpdateError: Error, CustomStringConvertible {
        case git(String, String)
        case message(String)

        var description: String {
            switch self {
            case .git(let verb, let out):
                let d = SecretMasker.mask(out.trimmingCharacters(in: .whitespacesAndNewlines))
                return "git \(verb) a échoué" + (d.isEmpty ? "." : " : \(d)")
            case .message(let m): return m
            }
        }
    }

    // MARK: Vérification

    public func check() async {
        settings.set(repositoryPath.isEmpty ? nil : repositoryPath, forKey: SettingsKey.updateRepository)
        confirmation = nil
        phase = .checking
        pending = []
        do {
            if let problem = validateRepository() { throw UpdateError.message(problem) }
            let b = try await gitValue(["rev-parse", "--abbrev-ref", "HEAD"])
            guard b != "HEAD" else { throw UpdateError.message("Le dépôt n'est sur aucune branche (HEAD détachée).") }
            guard Self.isSafeRefName(b) else { throw UpdateError.message("Nom de branche inattendu : \(b)") }
            branch = b
            let remote = (try? await gitValue(["config", "--get", "branch.\(b).remote"])).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
            guard Self.isSafeRefName(remote) else { throw UpdateError.message("Nom de dépôt distant inattendu : \(remote)") }
            remoteName = remote
            let url = try await gitValue(["remote", "get-url", remote])
            if let problem = Self.remoteProblem(url) { throw UpdateError.message(problem) }
            remoteURL = url

            let fetch = try await git(["fetch", "--no-tags", "--quiet", remote, b], timeout: 120)
            guard fetch.succeeded else { throw UpdateError.git("fetch", fetch.combined) }
            let t = try await gitValue(["rev-parse", "--verify", "FETCH_HEAD^{commit}"])
            let h = try await gitValue(["rev-parse", "--verify", "HEAD^{commit}"])
            target = t
            head = h
            let logOut = try await gitValue(["log", "--format=%H%x1f%an%x1f%ad%x1f%s", "--date=short", "--max-count=200", "\(h)..\(t)"])
            pending = GitCommit.parse(logOut)
            canFastForward = (try await git(["merge-base", "--is-ancestor", h, t])).status == 0
            // Format « XY chemin » ; `gitValue` ayant retiré les espaces de tête, on coupe après l'état.
            dirtyFiles = (try await gitValue(["status", "--porcelain", tauri ? "--untracked-files=all" : "--untracked-files=no"]))
                .split(separator: "\n").map { $0.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            isDirty = !dirtyFiles.isEmpty
            lastChecked = Date()
            if !pending.isEmpty {
                phase = .available
            } else if appInfo.isBundled, let built = appInfo.commit, built != h {
                phase = .rebuildAvailable
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed("\(error)")
        }
    }

    /// Vérification discrète au lancement (si activée et si l'app connaît son dépôt).
    public func checkAtLaunchIfEnabled() async {
        guard checkAtLaunch, appInfo.isBundled, validateRepository() == nil else { return }
        await check()
        if case .failed = phase { phase = .idle }  // pas d'alerte au démarrage pour un réseau absent
    }

    // MARK: Mise à jour (confirmée)

    public func requestUpdate() {
        guard let target, let branch, let remoteURL, !pending.isEmpty else { return }
        if !canFastForward {
            phase = .failed("L'historique local a divergé de \(remoteName ?? "origin")/\(branch) : mettez à jour à la main.")
            return
        }
        if tauri && isDirty {
            phase = .failed("La copie locale contient des modifications. Enregistrez-les dans Git avant d’appliquer les commits distants, ou utilisez Recompiler cette copie.")
            return
        }
        var lines: [String] = []
        if isDirty {
            // Des modifications locales : elles sont mises de côté (git stash), jamais perdues.
            lines.append("Modifications locales mises de côté avant la mise à jour (git stash ; « git stash pop » pour les reprendre) :")
            lines += dirtyFiles.prefix(10).map { "  \($0)" }
            if dirtyFiles.count > 10 { lines.append("  … et \(Format.count(dirtyFiles.count - 10, "autre"))") }
            lines.append("")
        }
        if remoteChangedSinceApproval {
            lines.append("⚠︎ Le dépôt distant a changé depuis la dernière mise à jour (avant : \(settings.string(forKey: SettingsKey.updateApprovedRemote) ?? "?")).")
        }
        lines.append("Dépôt : \(remoteURL)")
        lines.append("Branche : \(branch) → \(String(target.prefix(12)))")
        lines.append("\(Format.count(pending.count, "commit")) :")
        lines += pending.prefix(15).map { "  \($0.short)  \($0.subject) — \($0.author), \($0.date)" }
        if pending.count > 15 { lines.append("  … et \(Format.count(pending.count - 15, "autre"))") }
        lines.append("\nCe code sera compilé puis exécuté sur ce Mac, avec vos droits. N'acceptez que des commits d'une source de confiance.")
        lines.append("L'app sera remplacée ; il suffira ensuite de la relancer.")
        let checkedHead = head, checkedRepository = repoURL.path
        let stash = isDirty
        confirmation = ConfirmationRequest(
            title: "Installer la mise à jour ?", message: lines.joined(separator: "\n"),
            confirmTitle: stash ? "Mettre de côté et mettre à jour" : "Mettre à jour", severity: .normal
        ) { [weak self] in
            await self?.update(to: target, remote: remoteURL, stashingLocalChanges: stash, checkedHead: checkedHead, checkedRepository: checkedRepository)
        }
    }

    func update(to sha: String, remote: String, stashingLocalChanges: Bool = false, checkedHead: String? = nil, checkedRepository: String? = nil) async {
        if tauri {
            do {
                guard repoURL.path == checkedRepository,
                      try await gitValue(["rev-parse", "HEAD"]) == checkedHead,
                      try await gitValue(["remote", "get-url", remoteName ?? "origin"]) == remote,
                      try await gitValue(["status", "--porcelain", "--untracked-files=all"]).isEmpty else {
                    throw UpdateError.message("Le dépôt a changé depuis la vérification. Recherchez les mises à jour à nouveau.")
                }
            } catch { phase = .failed("\(error)"); return }
        }
        phase = .working("Application des commits…")
        log = ""
        do {
            if stashingLocalChanges {
                let s = try await git(["stash", "push", "--quiet", "--message", "Hindsight : avant mise à jour \(String(sha.prefix(7)))"], timeout: 60)
                appendLog(s.combined)
                guard s.succeeded else { throw UpdateError.git("stash push", s.combined) }
                isDirty = false
                dirtyFiles = []
            }
            let r = try await git(["merge", "--ff-only", "--quiet", sha], timeout: 60)
            appendLog(r.combined)
            guard r.succeeded else { throw UpdateError.git("merge --ff-only", r.combined) }
            settings.set(remote, forKey: SettingsKey.updateApprovedRemote)
        } catch {
            phase = .failed("\(error)")
            return
        }
        await rebuild()
    }

    public func requestRebuild() {
        if let problem = validateRepository() {
            phase = .failed(problem)
            return
        }
        confirmation = ConfirmationRequest(
            title: "Recompiler l'app ?",
            message: "Compilation de \(repoURL.path) (quelques minutes ; la copie locale sera compilée avec vos droits), puis remplacement de l'app\(appInfo.bundlePath.map { " \($0)" } ?? "").",
            confirmTitle: "Recompiler", severity: .normal
        ) { [weak self] in
            await self?.rebuild()
        }
    }

    func rebuild() async {
        phase = .working("Compilation (quelques minutes)…")
        do {
            let invocation: ProcessInvocation
            if tauri {
                guard let node = ["/opt/homebrew/bin/node", "/opt/homebrew/opt/node@24/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    throw UpdateError.message("Node.js est nécessaire pour reconstruire cette app depuis ses sources.")
                }
                invocation = ProcessInvocation(node, [repoURL.appendingPathComponent("desktop/scripts/update-build.mjs").path], in: repoURL.path, timeout: 3600)
            } else {
                invocation = ProcessInvocation(Self.bash, [repoURL.appendingPathComponent("scripts/make-app.sh").path], in: repoURL.path, timeout: 3600)
            }
            let r = try await runner.run(invocation) { [weak self] chunk in
                Task { @MainActor in self?.appendLog(chunk) }
            }
            guard r.succeeded else {
                throw UpdateError.message(r.timedOut ? "La compilation a dépassé le délai." : "La compilation a échoué (code \(r.status)) : voir le journal.")
            }
            let built = repoURL.appendingPathComponent(tauri ? "desktop/.update-target/release/bundle/macos/Hindsight Desktop.app" : "build/Hindsight.app")
            let identifier = tauri ? "local.hindsight.desktop.tauri" : AppInfo.bundleIdentifier
            guard let current = appInfo.bundlePath else {
                try BundleInstaller.validate(built, identifier: identifier)
                phase = .built(built.path)
                return
            }
            phase = .working("Installation…")
            try BundleInstaller.replace(URL(fileURLWithPath: current), with: built, identifier: identifier)
            phase = .readyToRelaunch
        } catch {
            phase = .failed("\(error)")
        }
    }

    func appendLog(_ s: String) {
        log += SecretMasker.mask(s)
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }
}
