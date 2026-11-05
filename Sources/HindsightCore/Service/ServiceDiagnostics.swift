import Foundation

/// Resolves only literal paths and simple variables. Never sources or executes the script.
enum ServiceDiagnostics {
    static func redirectedLog(in text: String, home: String = NSHomeDirectory()) -> URL? {
        var variables = ["HOME": home]
        func expand(_ raw: String) -> String? {
            var value = raw
            for (name, replacement) in variables {
                value = value.replacingOccurrences(of: "${\(name)}", with: replacement)
                value = value.replacingOccurrences(of: "$\(name)/", with: replacement + "/")
            }
            guard !value.contains("$"), !value.contains("`"), !value.contains("\n") else { return nil }
            return value
        }
        let script = LaunchScript(text: text)
        for line in script.lines {
            if let assignment = LaunchScript(text: line).assignments.first,
               let value = expand(assignment.value) { variables[assignment.name] = value }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("exec "),
                  let range = trimmed.range(of: #">{1,2}\s*(?:"([^"]+)"|'([^']+)'|([^\s;&]+))"#, options: .regularExpression) else { continue }
            let fragment = String(trimmed[range]).drop { $0 == ">" || $0.isWhitespace }
            let raw = fragment.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let path = expand(raw), path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func tail(_ url: URL, after offset: UInt64 = 0) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? file.close() }
        let size = (try? file.seekToEnd()) ?? 0
        // A rotated/replaced log can be shorter than the previous attempt's offset.
        let start = max(size > 65_536 ? size - 65_536 : 0, offset <= size ? offset : 0)
        try? file.seek(toOffset: start)
        return SecretMasker.mask(String(decoding: (try? file.readToEnd()) ?? Data(), as: UTF8.self))
    }

    static func error(in log: String) -> String? {
        log.split(separator: "\n").reversed().first {
            $0.range(of: #"(?:Error|Exception):|Address already in use|command not found|No such file"#, options: .regularExpression) != nil
        }.map { String($0.prefix(600)) }
    }
}
