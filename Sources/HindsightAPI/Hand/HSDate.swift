import Foundation

/// Dates ISO 8601 de l'API (parfois sans fuseau, parfois avec microsecondes).
public enum HSDate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func format(_ date: Date) -> String { fractional.string(from: date) }

    /// Analyse tolérante : avec/sans fuseau, avec/sans fraction, microsecondes. Sans fuseau => UTC.
    public static func parse(_ s: String?) -> Date? {
        guard var s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: " ", with: "T", options: [], range: s.range(of: " "))
        // Tronque la fraction à 3 chiffres (ISO8601DateFormatter n'accepte pas 6).
        if let dot = s.firstIndex(of: ".") {
            let after = s.index(after: dot)
            var end = after
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            let digits = s[after..<end]
            if digits.count != 3 {
                var d = String(digits.prefix(3))
                while d.count < 3 { d += "0" }
                s = String(s[..<after]) + d + String(s[end...])
            }
        }
        let hasZone = s.hasSuffix("Z") || endsWithASCIIOffset(s) || s.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if !hasZone, s.contains("T") { s += "Z" }
        if !hasZone, !s.contains("T") { s += "T00:00:00Z" }
        return canonicalDate(s) ?? fractional.date(from: s) ?? plain.date(from: s)
    }

    /// `±HH:MM` en chiffres ASCII en fin de chaîne : cas courant, que l'expression régulière accepte aussi.
    private static func endsWithASCIIOffset(_ s: String) -> Bool {
        let tail = Array(s.utf8.suffix(6))
        func digit(_ i: Int) -> Bool { tail[i] >= 48 && tail[i] <= 57 }
        return tail.count == 6 && (tail[0] == 43 || tail[0] == 45) && digit(1) && digit(2) && tail[3] == 58 && digit(4) && digit(5)
    }

    /// Forme canonique `AAAA-MM-JJTHH:MM:SS[.mmm](Z|±HH:MM)` d'une date valide : même instant que le
    /// formateur (millisecondes UTC entières, converties comme CoreFoundation), sans son coût d'environ
    /// 50 µs par date. Toute autre forme (date impossible, seconde 60, autre siècle…) lui est laissée.
    static func canonicalDate(_ s: String) -> Date? {
        let b = Array(s.utf8)
        func number(_ start: Int, _ count: Int) -> Int? {
            guard start + count <= b.count else { return nil }
            var value = 0
            for c in b[start..<start + count] {
                guard c >= 48, c <= 57 else { return nil }
                value = value * 10 + Int(c - 48)
            }
            return value
        }
        guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58,
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              (1900...2999).contains(year), (1...12).contains(month), hour < 24, minute < 60, second < 60 else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= lengths[month - 1] else { return nil }
        var i = 19, millis = 0
        if b.count > i, b[i] == 46 {
            guard let fraction = number(i + 1, 3) else { return nil }
            millis = fraction
            i += 4
        }
        var offset = 0
        if b.count == i + 1, b[i] == 90 {
            offset = 0
        } else if b.count == i + 6, b[i] == 43 || b[i] == 45, b[i + 3] == 58,
                  let h = number(i + 1, 2), let m = number(i + 4, 2), h < 24, m < 60 {
            offset = (h * 60 + m) * 60 * (b[i] == 43 ? 1 : -1)
        } else {
            return nil
        }
        // Jours depuis 1970 (« days from civil », H. Hinnant), années positives seulement.
        let y = month <= 2 ? year - 1 : year
        let era = y / 400, yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
        let milliseconds = (days * 86_400 + hour * 3_600 + minute * 60 + second - offset) * 1_000 + millis
        return Date(timeIntervalSinceReferenceDate: Double(milliseconds) / 1_000 - 978_307_200)
    }
}
