import Foundation
import HindsightAPI
import Observation

/// Ce que le script de synchronisation du projet enverrait, lu dans la sortie de `--dry-run`.
/// Format attendu (sync.py de nomad-memory) :
///     NOMAD-RL           doc        20 documents,    7 à envoyer (209 k caractères)
///     source disparue : doc:NOMAD-RL:docs/companion.md
///     Total : 39 documents, 348 k caractères, environ 87 k jetons à extraire ; 2 orphelins, gardés sans --prune.
public struct ProjectSyncPreview: Sendable, Hashable {
    public struct Group: Sendable, Hashable {
        public var repo: String
        public var kind: String
        public var documents: Int
        public var toSend: Int
        public var kiloCharacters: Int
    }

    public var groups: [Group] = []
    public var orphans: [String] = []
    public var documents: [String] = []
    public var approval: String?
    public var toSend = 0
    public var kiloCharacters = 0

    /// nil si la ligne « Total » manque : la sortie n'est pas celle attendue, on n'envoie rien.
    public static func parse(_ output: String) -> ProjectSyncPreview? {
        var p = ProjectSyncPreview()
        var total = false
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.wholeMatch(of: #/(\S+)\s+(\S+)\s+(\d+) documents,\s+(\d+) à envoyer \((\d+) k caractères\)/#) {
                p.groups.append(Group(repo: String(m.1), kind: String(m.2), documents: Int(m.3)!, toSend: Int(m.4)!, kiloCharacters: Int(m.5)!))
            } else if line.hasPrefix("À envoyer : ") {
                let payload = String(line.dropFirst("À envoyer : ".count))
                if let range = payload.range(of: " | sha256="),
                   payload[range.upperBound...].wholeMatch(of: #/[0-9a-f]{64}/#) != nil {
                    p.documents.append(String(payload[..<range.lowerBound]))
                }
            } else if let m = line.wholeMatch(of: #/Plan : ([0-9a-f]{64})/#) {
                p.approval = String(m.1)
            } else if let m = line.wholeMatch(of: #/source disparue : (.+)/#) {
                p.orphans.append(String(m.1))
            } else if let m = line.prefixMatch(of: #/Total : (\d+) documents, (\d+) k caractères/#) {
                p.toSend = Int(m.1)!
                p.kiloCharacters = Int(m.2)!
                total = true
            }
        }
        guard total else { return nil }
        if p.toSend > 0 && (p.approval == nil || p.documents.count != p.toSend) { return nil }
        return p
    }
}

/// Lance le script de synchronisation du projet (sync.py) depuis l'app : aperçu `--dry-run` et coût
/// d'abord, puis l'envoi seulement après confirmation. Refusé pendant une pause de la banque, et tant
/// que la banque traite encore un envoi précédent (le relancer renverrait et ferait payer deux fois).
@MainActor
@Observable
public final class ProjectSyncViewModel {
    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?
    /// Étape en cours (« Aperçu… », « Envoi… »), nil au repos.
    public private(set) var running: String?

    @ObservationIgnored public var pauseGate: PauseGate?
    @ObservationIgnored public var estimate: (@MainActor (String, EstimateKind) -> CostEstimate?)?
    /// Envois (rétentions) encore en attente ou en cours dans la banque ; nil si la file est illisible.
    @ObservationIgnored public var pendingRetains: (@MainActor (String) async -> Int?)?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let bankProvider: @MainActor () -> String?
    /// Change à chaque choix de script, pour que la vue relise `scriptPath`.
    private var scriptVersion = 0

    public init(settings: SettingsStore, runner: ProcessRunning, bank: @escaping @MainActor () -> String?) {
        self.settings = settings
        self.runner = runner
        self.bankProvider = bank
    }

    public var bank: String? { bankProvider() }

    static func scriptKey(_ bank: String) -> String { "projectSyncScript.\(bank)" }

    /// Script choisi pour la banque affichée.
    public var scriptPath: String? {
        _ = scriptVersion
        return bank.flatMap { settings.string(forKey: Self.scriptKey($0)) }
    }

    public func setScript(_ path: String?) {
        guard let bank else { return }
        settings.set(path, forKey: Self.scriptKey(bank))
        scriptVersion += 1
    }

    /// Aperçu puis demande de confirmation. Rien n'est envoyé ici.
    public func requestSync(ids: [String] = []) async {
        guard let bank, running == nil else { return }
        guard let script = scriptPath else {
            actionMessage = "Choisissez d'abord le script de synchronisation du projet."
            return
        }
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        // Le script vise une banque écrite en dur : refuser s'il n'écrit pas dans celle qui est affichée.
        guard let source = try? String(contentsOfFile: script, encoding: .utf8) else {
            actionMessage = "Script illisible : \(script)"
            return
        }
        guard source.contains("/banks/\(bank)\"") || source.contains("/banks/\(bank)/") else {
            actionMessage = "Ce script n'écrit pas dans la banque « \(bank) » : rien n'est lancé."
            return
        }
        let scriptHash = SHA256.hex(Data(source.utf8))
        guard let pendingRetains, let pending = await pendingRetains(bank) else {
            actionMessage = "File d’envoi illisible : réessayez avant de préparer la synchronisation."
            return
        }
        if pending > 0 {
            actionMessage = "La banque traite encore \(Format.count(pending, "envoi")) : attendez la fin, sinon les mêmes documents seraient renvoyés et payés deux fois."
            return
        }
        let filters = ids.flatMap { ["--select", $0] }
        running = "Aperçu…"
        defer { running = nil }
        let output: ProcessOutput
        do {
            output = try await runner.run(invocation(script, ["--dry-run"] + filters, timeout: 180))
        } catch {
            actionMessage = "Aperçu impossible : \(error.localizedDescription)"
            return
        }
        guard output.succeeded, let preview = ProjectSyncPreview.parse(output.stdout) else {
            actionMessage = "Aperçu impossible" + (output.timedOut ? " (délai dépassé)" : "") + " :\n" + Self.tail(output.combined)
            return
        }
        guard preview.toSend > 0 else {
            actionMessage = "Rien à envoyer : la banque est à jour" + (preview.orphans.isEmpty ? "." : " ; \(Format.count(preview.orphans.count, "document sans source", "documents sans source")) en mémoire, rien n'est supprimé.")
            return
        }
        confirmation = ConfirmationRequest(
            title: "Envoyer \(Format.count(preview.toSend, "document")) du projet ?",
            message: message(preview, bank: bank, script: script),
            confirmTitle: "Envoyer", severity: .normal
        ) { [weak self] in await self?.send(script: script, bank: bank, approval: preview.approval!, scriptHash: scriptHash, filters: filters) }
    }

    func message(_ p: ProjectSyncPreview, bank: String, script: String) -> String {
        var lines = p.groups.filter { $0.toSend > 0 }.map { g in
            "• \(g.repo) · \(g.kind) : \(Format.count(g.toSend, "document")) (\(g.kiloCharacters) k caractères)"
        }
        lines.append("")
        lines.append("Documents à envoyer :")
        lines.append(contentsOf: p.documents.map { "• " + $0 })
        if !p.orphans.isEmpty {
            lines.append("")
            lines.append("\(Format.count(p.orphans.count, "document dont la source a disparu", "documents dont la source a disparu")) : rien n'est supprimé.")
        }
        lines.append("")
        if let e = estimate?(bank, .retain(characters: p.kiloCharacters * 1000, images: 0, consolidation: false)) {
            lines.append(e.summary.replacingOccurrences(of: "Estimation :", with: "Estimation (extraction des faits) :"))
        }
        lines.append("Le script s'arrête après l'envoi ; ne le relancez pas avant que la banque ait fini de traiter ces documents.")
        lines.append("Script : \(script)")
        return lines.joined(separator: "\n")
    }

    func send(script: String, bank: String, approval: String, scriptHash: String, filters: [String]) async {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: script)), SHA256.hex(data) == scriptHash else {
            actionMessage = "Le script a changé depuis l’aperçu. Relancez la vérification ; rien n’a été envoyé."
            return
        }
        if let reason = pauseGate?(bank) {
            actionMessage = reason
            return
        }
        guard let pendingRetains, let pending = await pendingRetains(bank), pending == 0 else {
            actionMessage = "La file d’envoi est occupée ou illisible : rien n’a été envoyé."
            return
        }
        running = "Envoi…"
        defer { running = nil }
        do {
            let output = try await runner.run(invocation(script, filters + ["--approve", approval], timeout: 600))
            if output.succeeded {
                let sent = output.stdout.components(separatedBy: .newlines).last { $0.hasPrefix("Envoyé") }
                actionMessage = (sent ?? "Envoi terminé.") + " La banque les traite maintenant (voir Opérations)."
            } else {
                actionMessage = "Échec de l'envoi" + (output.timedOut ? " (délai dépassé)" : "") + " :\n" + Self.tail(output.combined)
            }
        } catch {
            actionMessage = "Échec de l'envoi : \(error.localizedDescription)"
        }
    }

    private func invocation(_ script: String, _ args: [String], timeout: TimeInterval) -> ProcessInvocation {
        ProcessInvocation(script, args, in: (script as NSString).deletingLastPathComponent, timeout: timeout)
    }

    static func tail(_ text: String, lines: Int = 8) -> String {
        text.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(lines).joined(separator: "\n")
    }
}
