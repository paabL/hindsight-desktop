import Foundation
import HindsightAPI

/// Quota d'abonnement ChatGPT tel que Codex le relève : Codex écrit dans ses fichiers de session, à chaque
/// réponse, l'état des limites de débit (`rate_limits` des événements `token_count`).
public struct CodexQuota: Sendable, Hashable {
    public struct Window: Sendable, Hashable {
        /// Part consommée de la fenêtre (0–100).
        public var usedPercent: Double
        public var windowMinutes: Int?
        public var resetsAt: Date?

        public init(usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
            self.usedPercent = usedPercent
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
        }

        /// « 5 h », « semaine ».
        public var title: String {
            guard let m = windowMinutes else { return "fenêtre" }
            if (9_000...11_000).contains(m) { return "semaine" }
            if m >= 1_440 { return "\(Int((Double(m) / 1_440).rounded())) j" }
            return "\(Int((Double(m) / 60).rounded())) h"
        }

        public func isExpired(now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    }

    /// Fenêtre courte (5 h) et longue (semaine).
    public var primary: Window?
    public var secondary: Window?
    /// Moment du relevé : le quota peut avoir bougé depuis (Hindsight ne le met pas à jour).
    public var observedAt: Date

    public init(primary: Window?, secondary: Window?, observedAt: Date) {
        self.primary = primary
        self.secondary = secondary
        self.observedAt = observedAt
    }
}

/// Lecture seule des sessions Codex (`$CODEX_HOME`, par défaut `~/.codex`) : rien n'y est jamais écrit.
public enum CodexRateLimits {
    public static func codexHome(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> URL {
        if let h = environment["CODEX_HOME"], h.hasPrefix("/") { return URL(fileURLWithPath: h) }
        return URL(fileURLWithPath: home).appendingPathComponent(".codex")
    }

    /// Dernier relevé de quota : dans la session Codex la plus récente qui en porte un (une session qui vient
    /// de commencer n'a pas encore de relevé).
    public static func latest(codexHome: URL = codexHome()) -> CodexQuota? {
        for file in recentSessionFiles(codexHome: codexHome, limit: 4) {
            if let q = read(file: file) { return q }
        }
        return nil
    }

    public static func latestSessionFile(codexHome: URL) -> URL? { recentSessionFiles(codexHome: codexHome, limit: 1).first }

    /// Sessions les plus récentes d'abord : `sessions/AAAA/MM/JJ/rollout-*.jsonl`, sans parcourir tout
    /// l'historique (les trois derniers jours de dossiers suffisent ; une session ouverte avant reste dans le
    /// dossier de son premier jour).
    public static func recentSessionFiles(codexHome: URL, limit: Int) -> [URL] {
        let fm = FileManager.default
        let sessions = codexHome.appendingPathComponent("sessions")
        func numericChildren(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { Int($0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        }
        var days: [URL] = []
        outer: for year in numericChildren(sessions) {
            for month in numericChildren(year) {
                for day in numericChildren(month) {
                    days.append(day)
                    if days.count == 3 { break outer }
                }
            }
        }
        // Sans arborescence datée (anciennes versions), le dossier lui-même.
        if days.isEmpty { days = [sessions] }
        var found: [(URL, Date)] = []
        for dir in days {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                found.append((f, (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Dernier relevé dans la fin du fichier (une session peut peser des dizaines de Mo).
    public static func read(file: URL, tailBytes: Int = 512 * 1024) -> CodexQuota? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        for line in text.split(separator: "\n").reversed() where line.contains("rate_limits") {
            if let q = parse(line: String(line), fallbackDate: modified) { return q }
        }
        return nil
    }

    /// Une ligne JSONL de session : cherche `rate_limits` (format `primary`/`secondary`, ou ancien format à plat).
    public static func parse(line: String, fallbackDate: Date = Date()) -> CodexQuota? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
            let limits = find("rate_limits", in: obj, depth: 4) as? [String: Any]
        else { return nil }
        let observed = (obj["timestamp"] as? String).flatMap(HSDate.parse) ?? fallbackDate
        func number(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let n = v as? NSNumber { return n.doubleValue }
            return nil
        }
        func window(_ v: Any?) -> CodexQuota.Window? {
            guard let w = v as? [String: Any], let used = number(w["used_percent"]) else { return nil }
            var reset: Date?
            if let at = number(w["resets_at"]) {
                reset = Date(timeIntervalSince1970: at)
            } else if let s = w["resets_at"] as? String {
                reset = HSDate.parse(s)
            } else if let inSeconds = number(w["resets_in_seconds"]) {
                reset = observed.addingTimeInterval(inSeconds)
            }
            return CodexQuota.Window(usedPercent: used, windowMinutes: number(w["window_minutes"]).map { Int($0) }, resetsAt: reset)
        }
        var primary = window(limits["primary"])
        var secondary = window(limits["secondary"])
        // Ancien format : `primary_used_percent`, `primary_window_minutes`…
        if primary == nil, let used = number(limits["primary_used_percent"]) {
            primary = CodexQuota.Window(usedPercent: used, windowMinutes: number(limits["primary_window_minutes"]).map { Int($0) })
        }
        if secondary == nil, let used = number(limits["secondary_used_percent"]) {
            secondary = CodexQuota.Window(usedPercent: used, windowMinutes: number(limits["secondary_window_minutes"]).map { Int($0) })
        }
        guard primary != nil || secondary != nil else { return nil }
        return CodexQuota(primary: primary, secondary: secondary, observedAt: observed)
    }

    static func find(_ key: String, in value: Any, depth: Int) -> Any? {
        guard depth > 0, let dict = value as? [String: Any] else { return nil }
        if let v = dict[key], !(v is NSNull) { return v }
        for v in dict.values {
            if let found = find(key, in: v, depth: depth - 1) { return found }
        }
        return nil
    }
}
