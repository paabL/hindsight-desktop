import Foundation
import Observation

/// Connexions prises en charge par les fournisseurs Hindsight, déléguées aux clients officiels.
/// Aucun jeton n'est lu, copié dans le script ou enregistré par l'app.
public enum LLMAccount: String, CaseIterable, Identifiable, Sendable {
    case claude = "claude-code"
    case chatGPT = "openai-codex"
    /// Compte Hindsight Cloud du fournisseur `hindsight` (serveur 1.2.0) : `hindsight-admin cloud login` enregistre
    /// la clé dans ~/.hindsight/cloud/credentials.json, où le serveur la lit quand le script n'en donne pas.
    case hindsightCloud = "hindsight"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .chatGPT: return "ChatGPT / Codex"
        case .hindsightCloud: return "Hindsight Cloud"
        }
    }
    public var executable: String {
        switch self {
        case .claude: return "claude"
        case .chatGPT: return "codex"
        case .hindsightCloud: return "hindsight-admin"
        }
    }
    public var installationURL: URL {
        switch self {
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .chatGPT: return URL(string: "https://developers.openai.com/codex/cli")!
        case .hindsightCloud: return URL(string: "https://docs.hindsight.vectorize.io")!
        }
    }
    /// Se déconnecter efface la clé enregistrée sur ce Mac ; elle reste valide jusqu'à sa révocation dans le cloud.
    public var canDisconnect: Bool { self == .hindsightCloud }
}

/// Hindsight Cloud et son API d'inférence (modèles hs-decide-1-flash, hs-rerank-1, hs-embed-1).
public enum HindsightInference {
    public static let url = "https://inference.hindsight.vectorize.io"
    public static let cloudHost = "ui.hindsight.vectorize.io"
    /// Où révoquer une clé : se déconnecter sur ce Mac ne l'invalide pas.
    public static let apiKeysPage = "https://\(cloudHost)/api-keys"
}

public struct LLMConnectionContext: Sendable, Equatable {
    public var isLocalServer: Bool
    /// nil : le dossier indiqué par le script ne peut pas être résolu sans exécuter du shell.
    public var codexHome: String?
    /// `hindsight-admin` installé avec le serveur du script ; nil : à chercher dans le PATH.
    public var hindsightAdmin: String?

    public init(isLocalServer: Bool, codexHome: String?, hindsightAdmin: String? = nil) {
        self.isLocalServer = isLocalServer
        self.codexHome = codexHome
        self.hindsightAdmin = hindsightAdmin
    }

    /// `hindsight-admin` voisin du `hindsight-api` que lance le script (`exec "$ROOT/venv/bin/hindsight-api"`).
    /// Seules les affectations littérales du script (`ROOT="$HOME/.hindsight"`) sont résolues, sans shell.
    public static func hindsightAdmin(scriptLines: [String], home: String = NSHomeDirectory()) -> String? {
        var variables = ["HOME": home]
        func expand(_ raw: String) -> String? {
            var s = raw
            if s == "~" || s.hasPrefix("~/") { s = home + s.dropFirst() }
            guard let re = try? NSRegularExpression(pattern: #"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"#) else { return nil }
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let name = Range(m.range(at: 1), in: s), let value = variables[String(s[name])],
                      let whole = Range(m.range, in: s) else { return nil }
                s.replaceSubrange(whole, with: value)
            }
            return s
        }
        for raw in scriptLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if let eq = line.firstIndex(of: "="), !line.contains(" "),
               line[..<eq].range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil {
                let value = line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let v = expand(value), !v.contains("$"), !v.contains("`") { variables[String(line[..<eq])] = v }
                continue
            }
            for token in line.split(separator: " ") {
                let word = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard word.hasSuffix("/hindsight-api"), let path = expand(word), path.hasPrefix("/") else { continue }
                return String(path.dropLast("hindsight-api".count)) + "hindsight-admin"
            }
        }
        return nil
    }

    public static func credentialsDirectory(_ value: String?, home: String = NSHomeDirectory(), expandHome: Bool = true) -> String? {
        guard var path = value, !path.isEmpty else { return home + "/.codex" }
        if expandHome {
            for prefix in ["${HOME}", "$HOME", "~"] where path == prefix || path.hasPrefix(prefix + "/") {
                path = home + path.dropFirst(prefix.count)
                break
            }
        }
        guard path.hasPrefix("/"), !path.contains(where: { "$`\n\r".contains($0) }) else { return nil }
        return (path as NSString).standardizingPath
    }
}

@MainActor
@Observable
public final class LLMConnections {
    public enum Status: Sendable, Equatable {
        case unchecked
        case checking
        case connected
        /// Hindsight Cloud : organisation de la clé enregistrée.
        case signedInTo(String)
        case signedOut
        case connecting
        case unavailable(String)
        case failed(String)

        public var isConnected: Bool {
            switch self {
            case .connected, .signedInTo: return true
            default: return false
            }
        }

        public var summary: String {
            switch self {
            case .unchecked: return "Connexion non vérifiée"
            case .checking: return "Vérification…"
            case .connected: return "Session OAuth disponible"
            case .signedInTo(let organization): return "Connecté à \(organization)"
            case .signedOut: return "Non connecté"
            case .connecting: return "Terminez la connexion dans le navigateur…"
            case .unavailable(let message), .failed(let message): return message
            }
        }
    }

    public private(set) var statuses: [LLMAccount: Status] = [:]
    public private(set) var authorizationURL: URL?
    public private(set) var activeAccount: LLMAccount?
    public private(set) var isRefreshing = false
    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private let locate: @Sendable (String) -> String?
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var refreshingContext: LLMConnectionContext?

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locate: @escaping @Sendable (String) -> String? = LLMConnections.findExecutable
    ) {
        self.runner = runner
        self.locate = locate
    }

    public nonisolated static func findExecutable(_ name: String) -> String? {
        SystemProcessRunner.standardPath().split(separator: ":")
            .map { String($0) + "/" + name }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func status(_ account: LLMAccount) -> Status { statuses[account] ?? .unchecked }

    public func refresh(_ context: LLMConnectionContext) async {
        guard activeAccount == nil else { return }
        if isRefreshing, refreshingContext == context { return }
        let checkRevision = UUID()
        revision = checkRevision
        refreshingContext = context
        isRefreshing = true
        defer {
            if revision == checkRevision {
                isRefreshing = false
                refreshingContext = nil
            }
        }
        for account in LLMAccount.allCases {
            guard revision == checkRevision else { return }
            statuses[account] = .checking
            let result = await check(account, context: context)
            guard revision == checkRevision else { return }
            statuses[account] = result
        }
    }

    /// Appelé uniquement par le bouton « Se connecter ». Le client officiel ouvre le navigateur
    /// et conserve la session dans son propre stockage, également utilisé par Hindsight.
    public func connect(_ account: LLMAccount, context: LLMConnectionContext) {
        guard activeAccount == nil else { return }
        if let problem = problem(account, context: context) {
            statuses[account] = .unavailable(problem)
            return
        }
        guard let executable = executable(account, context: context) else {
            statuses[account] = .unavailable(Self.missingExecutable(account))
            return
        }
        let loginRevision = UUID()
        invalidateChecks()
        revision = loginRevision
        activeAccount = account
        authorizationURL = nil
        statuses[account] = .connecting
        let invocation = invocation(account, executable: executable, login: true, context: context)
        let buffer = LoginOutput()
        loginTask = Task { [weak self, runner] in
            defer {
                if let self, self.revision == loginRevision {
                    self.activeAccount = nil
                    self.authorizationURL = nil
                    self.loginTask = nil
                }
            }
            do {
                guard !Task.isCancelled, self?.revision == loginRevision else { return }
                let owner = self
                let result = try await runner.run(invocation) { chunk in
                    let output = buffer.append(chunk)
                    guard let url = Self.authorizationURL(in: output, account: account) else { return }
                    Task { @MainActor in
                        guard let owner, owner.revision == loginRevision, owner.activeAccount == account else { return }
                        owner.authorizationURL = url
                    }
                }
                guard let self, self.revision == loginRevision, !Task.isCancelled else { return }
                if result.succeeded {
                    let status = await self.check(account, context: context)
                    guard self.revision == loginRevision, !Task.isCancelled else { return }
                    self.statuses[account] = status
                } else {
                    self.statuses[account] = .failed(result.timedOut
                        ? "Connexion expirée. Réessayez."
                        : "Connexion non terminée. Réessayez ou vérifiez le client officiel.")
                }
            } catch {
                guard let self, self.revision == loginRevision, !Task.isCancelled else { return }
                self.statuses[account] = .failed("Impossible de lancer la connexion. Vérifiez le client officiel.")
            }
        }
    }

    /// Hindsight Cloud seulement : `hindsight-admin cloud logout` efface la clé enregistrée sur ce Mac.
    public func disconnect(_ account: LLMAccount, context: LLMConnectionContext) async {
        guard account.canDisconnect, activeAccount == nil, let executable = executable(account, context: context) else { return }
        invalidateChecks()
        let invocation = ProcessInvocation(executable, ["cloud", "logout"], in: NSHomeDirectory(), environment: ["HOME": NSHomeDirectory()],
                                           inheritEnvironment: false, timeout: 30)
        if let result = try? await runner.run(invocation), result.succeeded {
            statuses[account] = await check(account, context: context)
        } else {
            statuses[account] = .failed("Déconnexion impossible. Réessayez.")
        }
    }

    public func cancel() {
        invalidateChecks()
        loginTask?.cancel()
        loginTask = nil
        if let activeAccount { statuses[activeAccount] = .unchecked }
        activeAccount = nil
        authorizationURL = nil
    }

    private func invalidateChecks() {
        revision = UUID()
        isRefreshing = false
        refreshingContext = nil
        for (account, status) in statuses where status == .checking { statuses[account] = .unchecked }
    }

    private func problem(_ account: LLMAccount, context: LLMConnectionContext) -> String? {
        if !context.isLocalServer { return "Connexion à effectuer sur la machine du serveur." }
        if account == .chatGPT, context.codexHome == nil {
            return "Dossier Codex calculé par le script : précisez son chemin dans les réglages avancés."
        }
        return nil
    }

    private func invocation(_ account: LLMAccount, executable: String, login: Bool, context: LLMConnectionContext) -> ProcessInvocation {
        var environment = ["HOME": NSHomeDirectory()]
        var arguments: [String]
        switch account {
        case .claude:
            arguments = login ? ["auth", "login", "--claudeai"] : ["auth", "status", "--json"]
        case .chatGPT:
            // Le fournisseur Hindsight lit auth.json, pas le trousseau. Cette option ne change
            // pas config.toml ni le mode de stockage des autres lancements de Codex.
            environment["CODEX_HOME"] = context.codexHome
            arguments = ["-c", "cli_auth_credentials_store=\"file\"", "login"] + (login ? [] : ["status"])
        case .hindsightCloud:
            // La connexion attend jusqu'à 10 min l'approbation dans le navigateur ; Python démarre en 2 à 3 s.
            return ProcessInvocation(executable, ["cloud", login ? "login" : "status"], in: NSHomeDirectory(), environment: environment,
                                     inheritEnvironment: false, timeout: login ? 660 : 30)
        }
        return ProcessInvocation(executable, arguments, in: NSHomeDirectory(), environment: environment,
                                 inheritEnvironment: false, timeout: login ? 300 : 15)
    }

    private func executable(_ account: LLMAccount, context: LLMConnectionContext) -> String? {
        if account == .hindsightCloud, let admin = context.hindsightAdmin { return admin }
        return locate(account.executable)
    }

    nonisolated static func missingExecutable(_ account: LLMAccount) -> String {
        account == .hindsightCloud
            ? "hindsight-admin introuvable : il est installé avec le serveur Hindsight."
            : "\(account.executable) n'est pas installé sur ce Mac."
    }

    /// Sortie de `hindsight-admin cloud status` : « Organization: <nom> (<id>) » une fois connecté. La clé n'y
    /// paraît que par ses 4 derniers caractères, qui ne sont pas lus.
    nonisolated static func cloudStatus(_ result: ProcessOutput) -> Status {
        if result.timedOut { return .failed("Le client ne répond pas. Réessayez.") }
        guard result.succeeded else {
            // Un hindsight-admin 1.1.0 n'a pas de commande `cloud` (typer : « No such command 'cloud' »).
            return result.combined.contains("No such command")
                ? .unavailable("Serveur Hindsight 1.2.0 requis.") : .failed("Vérification impossible. Réessayez.")
        }
        for line in result.stdout.split(separator: "\n") where line.hasPrefix("Organization: ") {
            var organization = line.dropFirst("Organization: ".count).trimmingCharacters(in: .whitespaces)
            if let id = organization.range(of: " (", options: .backwards) { organization = String(organization[..<id.lowerBound]) }
            return .signedInTo(organization.isEmpty || organization == "(unknown)" ? "Hindsight Cloud" : organization)
        }
        return .signedOut
    }

    private func check(_ account: LLMAccount, context: LLMConnectionContext) async -> Status {
        if let problem = problem(account, context: context) { return .unavailable(problem) }
        guard let executable = executable(account, context: context) else {
            return .unavailable(Self.missingExecutable(account))
        }
        do {
            let result = try await runner.run(invocation(account, executable: executable, login: false, context: context))
            if account == .hindsightCloud { return Self.cloudStatus(result) }
            if result.timedOut { return .failed("Le client ne répond pas. Réessayez.") }
            guard result.succeeded else { return result.status == 1 ? .signedOut : .failed("Vérification impossible. Réessayez.") }
            switch account {
            case .claude:
                guard let data = result.stdout.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let loggedIn = json["loggedIn"] as? Bool,
                      let method = json["authMethod"] as? String else {
                    return .failed("Statut inconnu. Mettez à jour Claude Code.")
                }
                return loggedIn && ["claude.ai", "oauth_token"].contains(method) ? .connected : .signedOut
            case .chatGPT:
                return result.combined.lowercased().contains("logged in using chatgpt") ? .connected : .signedOut
            case .hindsightCloud:
                return Self.cloudStatus(result)
            }
        } catch {
            return .failed("Vérification impossible. Vérifiez le client officiel.")
        }
    }

    /// N'expose que les pages d'autorisation attendues, jamais les sorties brutes des clients.
    nonisolated static func authorizationURL(in output: String, account: LLMAccount) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"https://[^\s\u001B<>\"]+"#) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        for match in regex.matches(in: output, range: range) {
            guard let r = Range(match.range, in: output), let url = URL(string: String(output[r])),
                  url.scheme == "https", url.user == nil, url.password == nil else { continue }
            switch account {
            case .claude, .chatGPT:
                let host = account == .claude ? "claude.ai" : "auth.openai.com"
                if url.host == host, ["/oauth/authorize", "/authorize"].contains(url.path) { return url }
            case .hindsightCloud:
                if url.host == HindsightInference.cloudHost, url.path == "/connect/desktop" { return url }
            }
        }
        return nil
    }
}

private final class LoginOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ chunk: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        text = String((text + chunk).suffix(16_384))
        return text
    }
}
