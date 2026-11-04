import Foundation
import HindsightAPI

/// Granularité des regroupements de la frise.
public enum TimelineGranularity: String, CaseIterable, Sendable, Identifiable {
    case day, week, month
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: return "Jour"
        case .week: return "Semaine"
        case .month: return "Mois"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// Une période de la frise et ses faits (du plus ancien au plus récent).
public struct TimelinePeriod: Identifiable, Sendable, Hashable {
    public var id: Date { start }
    public let start: Date
    public let facts: [FactHit]
    public let countsByType: [String: Int]
    public var count: Int { facts.count }
}

/// Barre de l'histogramme (période × type).
public struct TimelineBar: Identifiable, Sendable, Hashable {
    public var id: String { "\(start.timeIntervalSince1970)-\(type)" }
    public let start: Date
    public let type: String
    public let count: Int
}

public enum TimelineBuilder {
    public struct Result: Sendable {
        public let periods: [TimelinePeriod]
        /// Faits sans date exploitable sur l'axe choisi.
        public let undated: [FactHit]
    }

    public static func build(
        _ facts: [FactHit], axis: TimeAxis, granularity: TimelineGranularity, calendar: Calendar = .current
    ) -> Result {
        var buckets: [Date: [(Date, FactHit)]] = [:]
        var undated: [FactHit] = []
        for f in facts {
            guard let d = f.date(for: axis) else {
                undated.append(f)
                continue
            }
            let start = calendar.dateInterval(of: granularity.component, for: d)?.start ?? d
            buckets[start, default: []].append((d, f))
        }
        let periods = buckets.keys.sorted().map { start -> TimelinePeriod in
            let items = buckets[start]!.sorted { $0.0 < $1.0 }.map(\.1)
            var counts: [String: Int] = [:]
            for f in items { counts[f.type ?? "?", default: 0] += 1 }
            return TimelinePeriod(start: start, facts: items, countsByType: counts)
        }
        return Result(periods: periods, undated: undated)
    }

    public static func bars(_ periods: [TimelinePeriod]) -> [TimelineBar] {
        periods.flatMap { p in
            p.countsByType.keys.sorted().map { TimelineBar(start: p.start, type: $0, count: p.countsByType[$0]!) }
        }
    }
}
