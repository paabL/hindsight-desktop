import Foundation

/// Agent launchd qui exécute le script de lancement du serveur Hindsight dans la session de l'utilisateur.
///
/// launchd (et non l'app) est le parent du serveur : il survit à la fermeture de l'app, peut démarrer à
/// l'ouverture de session et écrit ses sorties dans un journal. Aucun shell n'est interposé : le script est
/// exécuté directement (il doit donc être exécutable et avoir un shebang).
public struct LaunchAgentSpec: Sendable, Hashable {
    public static let label = "local.hindsight.api"

    public var scriptPath: String
    public var logPath: String
    public var runAtLoad: Bool
    public var path: String
    /// File gelée : le serveur démarre sans son worker (`HINDSIGHT_API_WORKER_ENABLED=false`) ; l'API répond,
    /// les opérations restent en attente. Posé dans l'environnement du service, pas dans le script de l'utilisateur.
    public var workerPaused: Bool

    public static let workerEnabledVariable = "HINDSIGHT_API_WORKER_ENABLED"

    public init(scriptPath: String, logPath: String, runAtLoad: Bool, path: String, workerPaused: Bool = false) {
        self.scriptPath = scriptPath
        self.logPath = logPath
        self.runAtLoad = runAtLoad
        self.path = path
        self.workerPaused = workerPaused
    }

    public var plist: [String: Any] {
        var env = ["PATH": path, "HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH": "true"]
        if workerPaused { env[Self.workerEnabledVariable] = "false" }
        return [
            "Label": Self.label,
            "ProgramArguments": [scriptPath],
            "RunAtLoad": runAtLoad,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
            "EnvironmentVariables": env,
            // Laisse au serveur le temps de terminer proprement ses requêtes à l'arrêt.
            "ExitTimeOut": 30,
        ]
    }

    public func data() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Relit un plist installé (pour détecter un script ou un journal différents).
    public static func parse(_ data: Data) -> LaunchAgentSpec? {
        guard let d = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            d["Label"] as? String == label, let args = d["ProgramArguments"] as? [String], let script = args.first
        else { return nil }
        let env = d["EnvironmentVariables"] as? [String: String]
        return LaunchAgentSpec(
            scriptPath: script, logPath: d["StandardOutPath"] as? String ?? "", runAtLoad: d["RunAtLoad"] as? Bool ?? false,
            path: env?["PATH"] ?? "", workerPaused: env?[workerEnabledVariable]?.lowercased() == "false")
    }
}

/// État d'un job tel que le décrit `launchctl print gui/<uid>/<label>`.
public struct LaunchJobStatus: Sendable, Hashable {
    public var loaded: Bool
    public var running: Bool
    public var pid: Int?
    public var lastExitCode: Int?
    public var pending: Bool = false

    public static let notLoaded = LaunchJobStatus(loaded: false, running: false, pid: nil, lastExitCode: nil)

    /// Analyse la sortie (format texte non contractuel : seules quelques lignes stables sont lues).
    public static func parse(printOutput text: String) -> LaunchJobStatus {
        var s = LaunchJobStatus(loaded: true, running: false, pid: nil, lastExitCode: nil)
        var seen = Set<Substring>()
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let eq = line.range(of: " = ") else { continue }
            let key = line[..<eq.lowerBound], value = line[eq.upperBound...]
            // Seule la première occurrence compte : des sous-sections reprennent parfois les mêmes clés.
            guard seen.insert(key).inserted else { continue }
            switch key {
            case "state":
                s.running = value == "running"
                s.pending = ["spawn scheduled", "spawn requested", "waiting"].contains(String(value))
            case "pid": s.pid = Int(value)
            case "last exit code": s.lastExitCode = Int(value)
            default: break
            }
        }
        if s.pid != nil { s.running = true }
        return s
    }
}

/// Emplacements utilisés par le service (injectables pour les tests).
public struct ServicePaths: Sendable, Hashable {
    public var launchAgents: URL
    public var logs: URL

    public init(launchAgents: URL, logs: URL) {
        self.launchAgents = launchAgents
        self.logs = logs
    }

    public static var standard: ServicePaths {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return ServicePaths(
            launchAgents: home.appendingPathComponent("Library/LaunchAgents"),
            logs: home.appendingPathComponent("Library/Logs/Hindsight"))
    }

    public var plist: URL { launchAgents.appendingPathComponent(LaunchAgentSpec.label + ".plist") }
    public var log: URL { logs.appendingPathComponent("hindsight-api.log") }
}

/// Repère, dans le script de lancement, un serveur lancé en arrière-plan : launchd considère alors le job
/// terminé dès la fin du script et arrête le reste de son groupe de processus.
public enum LaunchScriptShape {
    public static func backgroundingWarning(_ text: String) -> String? {
        for raw in text.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if let hash = line.range(of: " #") { line = String(line[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
            let backgrounded = line.hasSuffix("&") && !line.hasSuffix("&&")
            if backgrounded || line.hasPrefix("nohup ") || line.contains(" nohup ") {
                return "Le script semble lancer le serveur en arrière-plan (« \(line) »). Pour le service, lancez-le au premier plan, par exemple : exec hindsight-api --port 8888"
            }
        }
        return nil
    }
}
