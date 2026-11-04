import Foundation
import Observation

/// Modèle de décision hs-decide-1-flash servi sur ce Mac, pour le fournisseur `hindsight` du serveur 1.2.0
/// (`HINDSIGHT_API_DECISION_MODEL_BASE_URL` pointé sur 127.0.0.1).
///
/// Le modèle est publié pour vLLM, qui ne tourne pas sur macOS. Le serveur `serve.py` (copie de
/// scripts/hindsight-decision-serve.py) reprend le rendu officiel du modèle et fait le calcul de vLLM avec
/// PyTorch, sur le GPU du Mac. Tout vit dans ~/.hindsight/decision : un environnement Python à part (celui
/// du serveur Hindsight n'est pas touché), le modèle à une révision figée et la clé attendue (fichier 0600).
/// launchd lance le serveur à l'ouverture de session ; il n'écoute que 127.0.0.1.
@MainActor
@Observable
public final class LocalDecisionModel {
    public struct Paths: Sendable, Hashable {
        public var root: URL
        public var launchAgents: URL
        public var logs: URL

        public init(root: URL, launchAgents: URL, logs: URL) {
            self.root = root
            self.launchAgents = launchAgents
            self.logs = logs
        }

        public static func standard(service: ServicePaths = .standard) -> Paths {
            Paths(
                root: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hindsight/decision"),
                launchAgents: service.launchAgents, logs: service.logs)
        }

        public var python: URL { root.appendingPathComponent("venv/bin/python") }
        public var hf: URL { root.appendingPathComponent("venv/bin/hf") }
        public var model: URL { root.appendingPathComponent("hs-decide-1-flash") }
        public var weights: URL { model.appendingPathComponent("model.safetensors") }
        public var script: URL { root.appendingPathComponent("serve.py") }
        public var keyFile: URL { root.appendingPathComponent("api-key") }
        public var plist: URL { launchAgents.appendingPathComponent(LocalDecisionModel.label + ".plist") }
        public var log: URL { logs.appendingPathComponent("hindsight-decision.log") }
    }

    public enum Phase: Sendable, Equatable {
        case unknown, notInstalled, installing(String), stopped, starting, running

        public var summary: String {
            switch self {
            case .unknown: return "État inconnu"
            case .notInstalled: return "Non installé"
            case .installing(let step): return step
            case .stopped: return "Installé, arrêté"
            case .starting: return "Démarrage…"
            case .running: return "En marche sur ce Mac"
            }
        }
    }

    public nonisolated static let label = "local.hindsight.decision"
    public nonisolated static let repository = "hindsight-ai/hs-decide-1-flash"
    /// Révision vérifiée (rendu et poids) ; une nouvelle révision passe par une mise à jour de l'app.
    public nonisolated static let revision = "0399aa237dc2e715ce802f6265d9084985e0ed7d"
    public nonisolated static let port = 8766
    public nonisolated static let baseURL = "http://127.0.0.1:\(port)"
    /// Au-delà, le serveur répond `max_tokens_exceeded` et Hindsight découpe la requête : l'attention d'une
    /// requête bien plus longue ne tiendrait pas dans la mémoire d'un Mac.
    public nonisolated static let maxRequestTokens = 8192
    public nonisolated static let packages = ["torch>=2.8", "transformers>=5.16.1", "pydantic>=2.12", "huggingface-hub>=1.0"]

    public private(set) var phase: Phase = .unknown
    /// Fin de la sortie de l'installation (pip, téléchargement, vérification) : aucune clé n'y paraît.
    public private(set) var log = ""
    public private(set) var problem: String?
    public private(set) var isBusy = false
    public var confirmation: ConfirmationRequest?

    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored public let paths: Paths
    @ObservationIgnored private let uid: UInt32
    @ObservationIgnored private let probe: @Sendable (URL) async -> Bool
    @ObservationIgnored private let locate: @Sendable (String) -> String?
    @ObservationIgnored private let startTimeout: TimeInterval
    @ObservationIgnored private let pollInterval: Duration

    public init(
        runner: ProcessRunning = SystemProcessRunner(), paths: Paths = .standard(), uid: UInt32 = FileSafety.currentUID,
        probe: @escaping @Sendable (URL) async -> Bool = LocalDecisionModel.healthy,
        locate: @escaping @Sendable (String) -> String? = LLMConnections.findExecutable,
        startTimeout: TimeInterval = 180, pollInterval: Duration = .seconds(1)
    ) {
        self.runner = runner
        self.paths = paths
        self.uid = uid
        self.probe = probe
        self.locate = locate
        self.startTimeout = startTimeout
        self.pollInterval = pollInterval
    }

    var domain: String { "gui/\(uid)" }
    var target: String { "\(domain)/\(Self.label)" }
    var healthURL: URL { URL(string: Self.baseURL + "/health")! }

    public nonisolated static func healthy(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Environnement, modèle, script et service présents (une installation interrompue se reprend).
    public var isInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: paths.python.path) && fm.fileExists(atPath: paths.weights.path)
            && fm.fileExists(atPath: paths.script.path) && fm.fileExists(atPath: paths.keyFile.path)
            && fm.fileExists(atPath: paths.plist.path)
    }

    public func refresh() async {
        guard !isBusy else { return }
        guard isInstalled else {
            phase = .notInstalled
            return
        }
        if await probe(healthURL) {
            phase = .running
            return
        }
        phase = await jobStatus().running ? .starting : .stopped
    }

    func jobStatus() async -> LaunchJobStatus {
        guard let r = try? await runner.run(ProcessInvocation(HindsightServiceViewModel.launchctl, ["print", target], timeout: 10)),
              r.succeeded else { return .notLoaded }
        return LaunchJobStatus.parse(printOutput: r.stdout)
    }

    // MARK: Clé

    /// Clé attendue par le serveur local, créée au premier appel (32 octets aléatoires, fichier 0600).
    public func apiKey() throws -> String {
        let fm = FileManager.default
        if let existing = try? String(contentsOf: paths.keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 32 { return existing }
        try fm.createDirectory(at: paths.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var generator = SystemRandomNumberGenerator()
        let key = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
        guard fm.createFile(atPath: paths.keyFile.path, contents: Data((key + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw ServiceError("Écriture de \(paths.keyFile.path) impossible.")
        }
        return key
    }

    // MARK: Installation

    struct Step {
        let title: String
        let invocation: ProcessInvocation
        /// Étape déjà faite (l'environnement existe) ; les autres sont rejouées, sans effet si elles sont à jour.
        let done: () -> Bool
    }

    func steps(uv: String) -> [Step] {
        let p = paths
        let env = ["HOME": NSHomeDirectory(), "HF_HUB_DISABLE_TELEMETRY": "1"]
        func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> ProcessInvocation {
            ProcessInvocation(executable, arguments, in: p.root.path, environment: env, inheritEnvironment: false, timeout: timeout)
        }
        return [
            Step(title: "Création de l'environnement Python…",
                 invocation: run(uv, ["venv", "--allow-existing", "--python", "3.13", p.root.appendingPathComponent("venv").path], timeout: 600),
                 done: { FileManager.default.isExecutableFile(atPath: p.python.path) }),
            Step(title: "Installation de PyTorch et de ses dépendances (environ 700 Mo)…",
                 invocation: run(uv, ["pip", "install", "--python", p.python.path] + Self.packages, timeout: 3600),
                 done: { false }),
            Step(title: "Téléchargement du modèle hs-decide-1-flash (1,5 Go)…",
                 invocation: run(p.hf.path, ["download", Self.repository, "--revision", Self.revision, "--local-dir", p.model.path,
                                             "--exclude", "assets/*"], timeout: 7200),
                 done: { false }),
            Step(title: "Installation du rendu officiel du modèle…",
                 invocation: run(uv, ["pip", "install", "--python", p.python.path, "--no-deps",
                                      p.model.appendingPathComponent("serving").path], timeout: 600),
                 done: { false }),
        ]
    }

    var serveArguments: [String] {
        [paths.python.path, "-I", paths.script.path, "--model", paths.model.path]
    }

    var serviceEnvironment: [String: String] {
        ["PATH": SystemProcessRunner.standardPath(), "HF_HUB_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false",
         "PYTORCH_ENABLE_MPS_FALLBACK": "1", "PYTHONUNBUFFERED": "1"]
    }

    var plist: [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": serveArguments + ["--port", String(Self.port), "--key-file", paths.keyFile.path,
                                                  "--max-tokens", String(Self.maxRequestTokens)],
            "RunAtLoad": true,
            "StandardOutPath": paths.log.path,
            "StandardErrorPath": paths.log.path,
            "EnvironmentVariables": serviceEnvironment,
            "ExitTimeOut": 15,
        ]
    }

    public func requestInstall() {
        confirmation = ConfirmationRequest(
            title: "Installer le modèle de décision sur ce Mac ?",
            message: """
                Dans \(paths.root.path) :
                • un environnement Python 3.13 à part (uv), avec PyTorch, transformers et pydantic depuis PyPI (environ 700 Mo) ;
                • le modèle \(Self.repository) depuis Hugging Face, à la révision \(Self.revision.prefix(12)) (1,5 Go) ;
                • son rendu officiel (dossier serving/ du modèle) et un serveur local, vérifié sur l'exemple du modèle.

                Le service démarre à l'ouverture de session et n'écoute que 127.0.0.1:\(Self.port). Il occupe environ 2 Go de mémoire.
                """,
            confirmTitle: "Installer", severity: .normal
        ) { [weak self] in await self?.install() }
    }

    func install() async {
        guard !isBusy else { return }
        isBusy = true
        problem = nil
        log = ""
        defer { isBusy = false }
        guard let uv = locate("uv") else {
            problem = "uv est requis pour créer l'environnement Python : https://docs.astral.sh/uv/"
            phase = isInstalled ? .stopped : .notInstalled
            return
        }
        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for step in steps(uv: uv) where !step.done() {
                phase = .installing(step.title)
                try await runLogged(step.invocation, title: step.title)
            }
            try writeScript()
            _ = try apiKey()
            phase = .installing("Vérification sur l'exemple du modèle…")
            try await runLogged(
                ProcessInvocation(paths.python.path, Array(serveArguments.dropFirst()) + ["--check"], in: paths.root.path,
                                  environment: serviceEnvironment.merging(["HOME": NSHomeDirectory()]) { $1 }, inheritEnvironment: false,
                                  timeout: 900),
                title: "Vérification")
            try writePlist()
            try await load()
        } catch {
            problem = error.userMessage
        }
        phase = await waitUntilHealthy(fallback: isInstalled ? .stopped : .notInstalled)
    }

    private func runLogged(_ invocation: ProcessInvocation, title: String) async throws {
        let result = try await runner.run(invocation) { [weak self] chunk in
            Task { @MainActor in self?.appendLog(chunk) }
        }
        guard result.succeeded else {
            appendLog(result.stderr.isEmpty ? result.stdout : result.stderr)
            throw ServiceError(result.timedOut ? "\(title) : délai dépassé." : "\(title) : échec (code \(result.status)). Voir le journal.")
        }
    }

    func appendLog(_ chunk: String) {
        log = String((log + SecretMasker.mask(chunk)).suffix(8_000))
    }

    func writeScript() throws {
        try Data((DecisionServerScript.source + "\n").utf8).write(to: paths.script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.script.path)
    }

    func writePlist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: paths.plist, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.plist.path)
    }

    /// Charge le service (s'il ne l'est pas) et le lance.
    private func load() async throws {
        if await !jobStatus().loaded {
            let r = try await runner.run(ProcessInvocation(HindsightServiceViewModel.launchctl, ["bootstrap", domain, paths.plist.path], timeout: 20))
            guard r.succeeded else { throw ServiceError("launchctl bootstrap a échoué : \(r.combined.prefix(300))") }
        }
        let k = try await runner.run(ProcessInvocation(HindsightServiceViewModel.launchctl, ["kickstart", target], timeout: 20))
        guard k.succeeded else { throw ServiceError("launchctl kickstart a échoué : \(k.combined.prefix(300))") }
        phase = .starting
    }

    private func waitUntilHealthy(fallback: Phase) async -> Phase {
        guard problem == nil, isInstalled else { return fallback }
        let deadline = Date().addingTimeInterval(startTimeout)
        while Date() < deadline {
            if await probe(healthURL) { return .running }
            try? await Task.sleep(for: pollInterval)
        }
        problem = "Le serveur local ne répond pas : voir \(paths.log.path)."
        return await jobStatus().running ? .starting : .stopped
    }

    // MARK: Démarrer, arrêter, désinstaller

    public func start() async {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            try writePlist()
            try await load()
        } catch {
            problem = error.userMessage
        }
        phase = await waitUntilHealthy(fallback: .stopped)
    }

    public func requestStop() {
        confirmation = ConfirmationRequest(
            title: "Arrêter le modèle de décision local ?",
            message: "Hindsight repassera par ses appels LLM tant que le modèle est arrêté. Le service redémarrera à la prochaine ouverture de session.",
            confirmTitle: "Arrêter", severity: .normal
        ) { [weak self] in await self?.stop() }
    }

    func stop() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        _ = try? await runner.run(ProcessInvocation(HindsightServiceViewModel.launchctl, ["bootout", target], timeout: 30))
        phase = isInstalled ? .stopped : .notInstalled
    }

    public func requestUninstall() {
        confirmation = ConfirmationRequest(
            title: "Désinstaller le modèle de décision local ?",
            message: "Supprime le service et \(paths.root.path) (environnement Python, modèle et clé, environ 2 Go). Choisissez d'abord un autre modèle de décision dans le script du serveur.",
            confirmTitle: "Désinstaller"
        ) { [weak self] in await self?.uninstall() }
    }

    func uninstall() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        _ = try? await runner.run(ProcessInvocation(HindsightServiceViewModel.launchctl, ["bootout", target], timeout: 30))
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: paths.plist.path) { try fm.removeItem(at: paths.plist) }
            if fm.fileExists(atPath: paths.root.path) { try fm.removeItem(at: paths.root) }
            problem = nil
        } catch {
            problem = error.userMessage
        }
        log = ""
        phase = .notInstalled
    }

    struct ServiceError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
