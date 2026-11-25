import Foundation
import Observation

/// Modèles locaux du serveur Hindsight de ce Mac, choisis rôle par rôle (reranker, embeddings, décision).
///
/// Le travail est fait par ~/.hindsight/models/hindsight-models.py (copie de scripts/hindsight-models.py) :
/// catalogue, fichier de sélection unique (selection.json) lu au lancement par l'API, le serveur MPS
/// compatible TEI et le serveur de décision, puis, pour un changement : télécharger, tester, attendre la fin
/// des opérations, activer, redémarrer, vérifier sur une vraie recherche et revenir seul en arrière en cas
/// d'échec. Le changement tourne détaché (il survit à la fermeture de l'app) ; l'app suit son job.json.
@MainActor
@Observable
public final class LocalModelManager {
    public struct Paths: Sendable, Hashable {
        public var root: URL
        public init(root: URL) { self.root = root }

        public static var standard: Paths {
            Paths(root: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hindsight"))
        }

        public var models: URL { root.appendingPathComponent("models") }
        public var manager: URL { models.appendingPathComponent("hindsight-models.py") }
        public var server: URL { models.appendingPathComponent("model-server.py") }
        public var python: URL { root.appendingPathComponent("venv/bin/python") }
        /// Script du serveur de décision : remis à jour s'il existe (moteur MLX), jamais créé ici.
        public var decisionScript: URL { root.appendingPathComponent("decision/serve.py") }
    }

    /// Dernier état rendu par `hindsight-models.py status` (catalogue, sélection, serveurs, travail, historique).
    public private(set) var status: [String: Any]?
    public private(set) var problem: String?
    public var confirmation: ConfirmationRequest?

    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored public let paths: Paths

    public init(runner: ProcessRunning = SystemProcessRunner(), paths: Paths = .standard) {
        self.runner = runner
        self.paths = paths
    }

    /// Le gestionnaire ne sert qu'un serveur Hindsight installé sur ce Mac (son environnement Python).
    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: paths.python.path) }

    public var jobRunning: Bool { (status?["job"] as? [String: Any])?["status"] as? String == "running" }

    /// Écrit les scripts de l'app quand ils diffèrent (mise à jour de l'app), sans toucher au reste.
    func installScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.models, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        func write(_ text: String, to url: URL) throws {
            let data = Data((text + "\n").utf8)
            if (try? Data(contentsOf: url)) == data { return }
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try write(ModelManagerScripts.manager, to: paths.manager)
        try write(ModelManagerScripts.server, to: paths.server)
        if fm.fileExists(atPath: paths.decisionScript.path) {
            try write(DecisionServerScript.source, to: paths.decisionScript)
        }
    }

    private func manager(_ arguments: [String], timeout: TimeInterval = 30) async throws -> ProcessOutput {
        try await runner.run(ProcessInvocation(paths.python.path, ["-I", paths.manager.path] + arguments,
                                               in: paths.models.path, timeout: timeout))
    }

    public func refresh() async {
        guard isAvailable else {
            status = nil
            return
        }
        do {
            try installScripts()
            let out = try await manager(["status"])
            guard out.succeeded, let object = try JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any] else {
                throw LocalDecisionModel.ServiceError("État des modèles locaux illisible : \(SecretMasker.mask(out.combined).prefix(300))")
            }
            status = object
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func label(_ role: String, _ option: String) -> String {
        let catalog = (status?["catalog"] as? [String: Any])?[role] as? [[String: Any]]
        return catalog?.first { $0["id"] as? String == option }?["label"] as? String ?? option
    }

    private func start(_ arguments: [String]) async {
        do {
            let out = try await manager(arguments, timeout: 60)
            guard out.succeeded else {
                let message = (try? JSONSerialization.jsonObject(with: Data(out.stderr.utf8)) as? [String: Any])?["error"] as? String
                throw LocalDecisionModel.ServiceError(message ?? "Échec du lancement : \(SecretMasker.mask(out.combined).prefix(300))")
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        await refresh()
    }

    public func requestApply(role: String, option: String) {
        let name = label(role, option)
        confirmation = ConfirmationRequest(
            title: "Activer \(name) ?",
            message: "Le modèle est téléchargé si besoin, testé sur une vraie recherche, puis activé une fois les opérations en cours terminées. Ce qui en dépend redémarre (serveur Hindsight ou serveur du modèle) et la recherche est vérifiée ; en cas d'échec, le choix actuel revient tout seul.",
            confirmTitle: "Installer et activer", severity: .normal
        ) { [weak self] in await self?.start(["start", role, option]) }
    }

    public func requestRollback(role: String) {
        guard let previous = (status?["previous"] as? [String: Any])?[role] as? String else { return }
        let name = label(role, previous)
        confirmation = ConfirmationRequest(
            title: "Revenir à \(name) ?",
            message: "Le choix précédent est réactivé de la même façon : test, activation, redémarrage et vérification.",
            confirmTitle: "Revenir en arrière", severity: .normal
        ) { [weak self] in await self?.start(["start-rollback", role]) }
    }
}
