import Foundation
import HindsightAPI

/// Rythme de la consolidation, mesuré sur les tours récents de la banque.
///
/// Le serveur consolide une banque par tours de `consolidation_max_memories_per_round` faits, l'un après l'autre :
/// chaque tour est une opération dont `progress.processed` compte les faits traités. Un tour peut attendre dans la
/// file avant de démarrer ; son début réel est donc la fin du tour précédent quand celle-ci est plus tardive que sa
/// création. Seul le temps de travail de la fenêtre compte : une pause ne fausse pas le rythme.
public struct ConsolidationPace: Sendable, Equatable, Encodable {
    public let factsPerHour: Double
    /// Temps de travail réellement observé dans la fenêtre.
    public let measuredSeconds: Double
    /// Au même rythme, temps pour consolider les faits en attente ; nil s'il n'y en a pas.
    public let remainingSeconds: Double?

    /// Fenêtre de mesure et minimum de travail observé pour annoncer un rythme.
    public static let window: TimeInterval = 3600
    static let minimumMeasured: TimeInterval = 300

    public static func measure(
        completed: [OperationResponse], running: OperationResponse?, pendingFacts: Int, now: Date = Date()
    ) -> ConsolidationPace? {
        struct Round { let created: Date; let end: Date; let processed: Int }
        var rounds: [Round] = completed.compactMap { op in
            guard let created = HSDate.parse(op.createdAt), let end = HSDate.parse(op.updatedAt),
                  let processed = op.progress?.processed, processed > 0, end > created else { return nil }
            return Round(created: created, end: min(end, now), processed: processed)
        }
        if let op = running, let created = HSDate.parse(op.createdAt), let processed = op.progress?.processed, now > created {
            rounds.append(Round(created: created, end: now, processed: processed))
        }
        rounds.sort { $0.end < $1.end }
        let windowStart = now.addingTimeInterval(-window)
        var facts = 0.0, measured = 0.0
        var previousEnd: Date?
        for round in rounds {
            let start = max(round.created, previousEnd ?? round.created)
            previousEnd = round.end
            let duration = round.end.timeIntervalSince(start)
            guard duration > 0 else { continue }
            let overlap = round.end.timeIntervalSince(max(start, windowStart))
            guard overlap > 0 else { continue }
            facts += Double(round.processed) * min(1, overlap / duration)
            measured += min(overlap, duration)
        }
        guard measured >= minimumMeasured, facts > 0 else { return nil }
        let perSecond = facts / measured
        return ConsolidationPace(
            factsPerHour: perSecond * 3600, measuredSeconds: measured,
            remainingSeconds: pendingFacts > 0 ? Double(pendingFacts) / perSecond : nil)
    }
}
