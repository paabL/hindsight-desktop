import Foundation
import HindsightAPI

public enum KPITone: Sendable { case normal, good, warning, critical }

/// Chiffre clé affiché sur le tableau de bord.
public struct KPI: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let value: String
    public let subtitle: String?
    public let tone: KPITone
}

/// Point d'une série temporelle (jour × type de fait).
public struct ChartPoint: Identifiable, Sendable, Hashable {
    public var id: String { "\(time.timeIntervalSince1970)-\(type)" }
    public let time: Date
    public let type: String
    public let count: Int
}

extension DashboardSnapshot {
    /// Les chiffres qui comptent, dans l'ordre d'importance.
    public func kpis(now: Date = Date()) -> [KPI] {
        let st = stats
        var out: [KPI] = []
        out.append(
            KPI(
                id: "facts", title: "Faits", value: Format.number(rawFacts),
                subtitle: "world \(Format.number(worldFacts)) · experience \(Format.number(experienceFacts))", tone: .normal))
        let coverage = consolidationCoverage.map { "consolidés à \(Format.percent($0))" }
        out.append(
            KPI(
                id: "observations", title: "Observations", value: Format.number(st.totalObservations),
                subtitle: coverage, tone: st.totalObservations == 0 && rawFacts > 0 ? .warning : .normal))
        out.append(KPI(id: "documents", title: "Documents", value: Format.number(st.totalDocuments), subtitle: nil, tone: .normal))
        out.append(
            KPI(
                id: "entities", title: "Entités", value: entityTotal.map(Format.number) ?? "—", subtitle: nil, tone: .normal))
        out.append(
            KPI(id: "links", title: "Liens", value: Format.number(st.totalLinks), subtitle: nil, tone: .normal))
        out.append(
            KPI(
                id: "pending-consolidation", title: "À consolider", value: Format.number(st.pendingConsolidation),
                subtitle: lastConsolidation.map { "dernière : \(DashboardInsights.relative($0, now: now))" },
                tone: st.pendingConsolidation > 0 ? .warning : .good))
        let failures = st.failedOperations + st.failedConsolidation
        out.append(
            KPI(
                id: "failures", title: "Échecs", value: Format.number(failures),
                subtitle: failures > 0 ? "\(Format.count(st.failedOperations, "opération")) · \(Format.count(st.failedConsolidation, "consolidation"))" : "aucun",
                tone: failures > 0 ? .critical : .good))
        out.append(
            KPI(
                id: "queue", title: "En file", value: Format.number(st.pendingOperations), subtitle: nil,
                tone: .normal))
        out.append(
            KPI(
                id: "last-write", title: "Dernière écriture",
                value: lastWrite.map { DashboardInsights.relative($0, now: now) } ?? "—",
                subtitle: lastWrite.map { Format.dateTime($0) }, tone: .normal))
        return out
    }

    /// Série prête pour un graphique empilé (un point par jour et par type non vide).
    public var chartPoints: [ChartPoint] {
        var pts: [ChartPoint] = []
        for b in timeseries?.buckets ?? [] {
            guard let t = HSDate.parse(b.time) else { continue }
            if b.world > 0 { pts.append(ChartPoint(time: t, type: "world", count: b.world)) }
            if b.experience > 0 { pts.append(ChartPoint(time: t, type: "experience", count: b.experience)) }
            if b.observation > 0 { pts.append(ChartPoint(time: t, type: "observation", count: b.observation)) }
        }
        return pts
    }
}
