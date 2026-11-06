import Foundation
import HindsightAPI

/// Données brutes du tableau de bord à un instant donné.
public struct DashboardSnapshot: Sendable {
    public var stats: BankStatsResponse
    public var version: VersionResponse?
    public var entityTotal: Int?
    public var timeseries: MemoriesTimeseriesResponse?
    public var recentDocuments: [DocumentListItem] = []
    public var topTags: [TagItem] = []
    public var recentFailures: [OperationResponse] = []
    /// Consolidations en cours ou en file : on ne propose pas d'en lancer une autre.
    public var activeConsolidations = 0
    public var config: BankConfigResponse?
    public var llmHealth: BankLlmHealthResponse?
    public var consultationOnly = false
    public var fetchedAt: Date

    public init(stats: BankStatsResponse, fetchedAt: Date = Date()) {
        self.stats = stats
        self.fetchedAt = fetchedAt
    }

    // MARK: Chiffres clés dérivés

    public var worldFacts: Int { stats.nodesByFactType["world"] ?? 0 }
    public var experienceFacts: Int { stats.nodesByFactType["experience"] ?? 0 }
    public var observationFacts: Int { stats.nodesByFactType["observation"] ?? stats.totalObservations }
    /// Faits « bruts » (world + experience), hors observations dérivées.
    public var rawFacts: Int { worldFacts + experienceFacts }

    public var lastWrite: Date? { HSDate.parse(stats.lastMemoryWriteAt) }
    public var lastConsolidation: Date? { HSDate.parse(stats.lastConsolidatedAt) }

    /// Part des faits bruts déjà consolidés (0…1), si calculable.
    public var consolidationCoverage: Double? {
        let raw = rawFacts
        guard raw > 0 else { return nil }
        let notDone = stats.pendingConsolidation + stats.failedConsolidation
        return min(1, max(0, Double(raw - notDone) / Double(raw)))
    }
}

public enum InsightSeverity: Int, Sendable, Comparable {
    case critical = 0, warning, info, ok
    public static func < (a: InsightSeverity, b: InsightSeverity) -> Bool { a.rawValue < b.rawValue }
}

/// Action proposée avec une alerte ; l'interface la traduit en navigation ou en demande de confirmation.
public enum InsightAction: Sendable, Hashable {
    case openOperations(status: String?)
    case recoverConsolidation
    case runConsolidation
    case openAudit
    case testLLM
    case openDocuments
}

public struct Insight: Identifiable, Sendable, Hashable {
    public let id: String
    public let severity: InsightSeverity
    public let title: String
    public let detail: String
    public let action: InsightAction?
    public let actionTitle: String?
}

/// Règles qui décident ce qui mérite l'attention. Fonction pure : testée sans réseau.
public enum DashboardInsights {
    public static func compute(_ s: DashboardSnapshot, now: Date = Date()) -> [Insight] {
        var out: [Insight] = []
        let st = s.stats

        if st.failedOperations > 0 {
            out.append(
                Insight(
                    id: "failed-operations", severity: .critical,
                    title: "\(st.failedOperations) opération(s) en échec",
                    detail: s.recentFailures.first?.errorMessage.map { "Dernière erreur : \(String($0.prefix(200)))" }
                        ?? "Ouvrez le suivi pour lire les messages d'erreur et relancer.",
                    action: .openOperations(status: "failed"), actionTitle: "Voir les échecs"))
        }
        if st.failedConsolidation > 0 {
            out.append(
                Insight(
                    id: "failed-consolidation", severity: .critical,
                    title: "\(st.failedConsolidation) fait(s) définitivement en échec de consolidation",
                    detail: "Ils ne seront plus retentés automatiquement tant qu'on ne les remet pas en file.",
                    action: .recoverConsolidation, actionTitle: "Remettre en file"))
        }
        if let llm = s.llmHealth {
            let bad = llm.operations.filter { !$0.ok }
            if !bad.isEmpty {
                let names = bad.map { "\($0.operation) (\($0.status))" }.joined(separator: ", ")
                out.append(
                    Insight(
                        id: "llm-health", severity: .critical, title: "LLM injoignable ou mal configuré",
                        detail: names, action: .testLLM, actionTitle: "Retester"))
            }
        }
        // Réglages résolus POUR CETTE BANQUE (serveur → banque) d'abord : un override de banque peut
        // activer ce que le serveur désactive globalement (et inversement).
        let observationsEnabled = s.config?.config["enable_observations"]?.boolValue ?? s.version?.features.observations ?? true
        if observationsEnabled, st.pendingConsolidation > 0 {
            let stale: Bool
            if let last = s.lastConsolidation { stale = now.timeIntervalSince(last) > 24 * 3600 } else { stale = true }
            let running = s.activeConsolidations > 0
            out.append(
                Insight(
                    id: "pending-consolidation", severity: running ? .info : stale ? .warning : .info,
                    title: "\(st.pendingConsolidation) fait(s) attendent la consolidation",
                    detail: running
                        ? "Une consolidation est en cours : elle les traite. Suivi dans « Activité › Traitements »."
                        : s.lastConsolidation.map { "Dernière consolidation : \(Self.relative($0, now: now))." } ?? "Aucune consolidation enregistrée.",
                    action: running ? .openOperations(status: "processing") : .runConsolidation,
                    actionTitle: running ? "Voir l'avancement" : "Lancer la consolidation"))
        }
        if observationsEnabled, st.totalObservations == 0, s.rawFacts > 0, st.pendingConsolidation == 0,
            st.failedConsolidation == 0
        {
            out.append(
                Insight(
                    id: "no-observations", severity: .warning, title: "Aucune observation produite",
                    detail: "\(s.rawFacts) faits mais aucune observation consolidée : vérifiez la configuration de consolidation.",
                    action: .openOperations(status: nil), actionTitle: "Voir les opérations"))
        }
        if st.pendingOperations > 0 {
            out.append(
                Insight(
                    id: "pending-operations", severity: .info, title: "\(st.pendingOperations) opération(s) en file",
                    detail: "Le serveur les traite à son rythme.", action: .openOperations(status: "pending"),
                    actionTitle: "Suivre"))
        }
        if let auditOn = s.config?.config["audit_log_enabled"]?.boolValue ?? s.version?.features.auditLog, !auditOn {
            out.append(
                Insight(
                    id: "audit-disabled", severity: .info, title: "Journal d'audit désactivé",
                    detail: "On ne peut pas savoir qui accède à la banque tant qu'il est désactivé.",
                    action: .openAudit, actionTitle: "Voir comment l'activer"))
        }
        if let w = s.lastWrite, now.timeIntervalSince(w) > 7 * 24 * 3600 {
            out.append(
                Insight(
                    id: "stale-writes", severity: .info, title: "Aucune écriture récente",
                    detail: "Dernière écriture : \(Self.relative(w, now: now)).", action: nil, actionTitle: nil))
        }
        if out.allSatisfy({ $0.severity == .info }) {
            out.append(
                Insight(
                    id: "all-good", severity: .ok, title: "Rien d'urgent",
                    // « à jour » seulement s'il ne reste rien à consolider (sinon la ligne au-dessus en parle).
                    detail: st.pendingConsolidation > 0 ? "Aucun échec." : "Aucun échec, consolidation à jour.", action: nil,
                    actionTitle: nil))
        }
        // Tri stable : gravité d'abord, puis l'ordre dans lequel les règles ci-dessus ont été évaluées.
        return out.enumerated().sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }.map(\.element)
    }

    /// « il y a 3 jours » sans dépendre du fuseau ni de la locale (testable).
    public static func relative(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 0 { return "dans le futur" }
        if s < 90 { return "à l'instant" }
        if s < 3600 { return "il y a \(s / 60) min" }
        if s < 86400 { return "il y a \(s / 3600) h" }
        let d = s / 86400
        return d == 1 ? "hier" : "il y a \(d) jours"
    }
}
