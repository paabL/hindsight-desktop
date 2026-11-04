import Foundation
import HindsightAPI

/// Formatage d'affichage (nombres, tailles, dates) — locale de l'utilisateur.
public enum Format {
    // Formateurs partagés : en créer un par appel coûte cher dans les longues listes.
    // Les formateurs Foundation sont sûrs en lecture concurrente pour le formatage.
    nonisolated(unsafe) private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    nonisolated(unsafe) private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public static func number(_ n: Int) -> String {
        numberFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// « 1 fait », « 12 faits » : nombre et nom accordé (pluriel régulier par défaut).
    public static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number(n)) \(n > 1 ? (plural ?? singular + "s") : singular)"
    }

    public static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    /// « 18 oct. 2026 à 21:31 » depuis une date ISO de l'API ; renvoie la chaîne brute si illisible, « — » si absente.
    public static func dateTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        guard let d = HSDate.parse(iso) else { return iso }
        return dateTime(d)
    }

    public static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Heure seule (« 14:30 ») le jour même, date et heure sinon.
    public static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? timeFormatter.string(from: date) : dateTimeFormatter.string(from: date)
    }

    /// « à l'instant », « il y a 12 min », « il y a 3 h », puis la date.
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "à l'instant" }
        if s < 3_600 { return "il y a \(Int(s / 60)) min" }
        if s < 86_400 { return "il y a \(Int(s / 3_600)) h" }
        return "le " + dateTime(date)
    }

    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Durée lisible : « 850 ms », « 12,3 s », « 2 min 05 s ».
    public static func duration(milliseconds ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let s = Double(ms) / 1000
        if s < 60 { return String(format: "%.1f s", s) }
        let m = Int(s) / 60
        return String(format: "%d min %02d s", m, Int(s) % 60)
    }
}
