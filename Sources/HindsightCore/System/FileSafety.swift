import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Vérifications avant d'exécuter un fichier (script de lancement du serveur) : un script que d'autres
/// comptes peuvent modifier permettrait à n'importe qui d'exécuter du code sous votre identité.
public enum FileSafety {
    public enum Issue: Sendable, Hashable, CustomStringConvertible {
        case missing(String)
        case notRegularFile(String)
        case foreignOwner(String)
        case writableByOthers(String)
        case directoryWritableByOthers(String)
        case notExecutable(String)

        /// Les problèmes bloquants interdisent l'exécution ; `notExecutable` se corrige (chmod u+x).
        public var isBlocking: Bool {
            if case .notExecutable = self { return false }
            return true
        }

        public var description: String {
            switch self {
            case .missing(let p): return "Fichier introuvable : \(p)"
            case .notRegularFile(let p): return "\(p) n'est pas un fichier ordinaire."
            case .foreignOwner(let p): return "\(p) appartient à un autre utilisateur."
            case .writableByOthers(let p): return "\(p) est modifiable par d'autres comptes (corrigez avec chmod go-w)."
            case .directoryWritableByOthers(let p): return "Le dossier \(p) est modifiable par d'autres comptes : le script pourrait y être remplacé."
            case .notExecutable(let p): return "\(p) n'est pas exécutable (chmod u+x)."
            }
        }
    }

    struct Info {
        let mode: UInt32
        let uid: UInt32
    }

    static func info(_ path: String) -> Info? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Info(mode: UInt32(st.st_mode), uid: UInt32(st.st_uid))
    }

    static let typeMask: UInt32 = 0o170000
    static let regular: UInt32 = 0o100000
    static let directory: UInt32 = 0o040000
    static let sticky: UInt32 = 0o1000

    public static var currentUID: UInt32 { UInt32(getuid()) }

    /// Inspecte le fichier réel (liens symboliques suivis) et son dossier.
    public static func inspect(_ url: URL, uid: UInt32 = currentUID, requireExecutable: Bool = true) -> [Issue] {
        let real = url.resolvingSymlinksInPath().path
        guard let f = info(real) else { return [.missing(url.path)] }
        var issues: [Issue] = []
        if f.mode & typeMask != regular { issues.append(.notRegularFile(real)) }
        if f.uid != uid && f.uid != 0 { issues.append(.foreignOwner(real)) }
        if f.mode & 0o022 != 0 { issues.append(.writableByOthers(real)) }
        // Dossier du fichier réel, et celui du lien symbolique éventuel (qui pourrait être redirigé).
        var dirs = [(real as NSString).deletingLastPathComponent]
        let linkDir = url.deletingLastPathComponent().path
        if url.path != real && !dirs.contains(linkDir) { dirs.append(linkDir) }
        for dir in dirs {
            guard let d = info(dir) else { continue }
            let othersCanWrite = d.mode & 0o022 != 0 && d.mode & sticky == 0
            if othersCanWrite || (d.uid != uid && d.uid != 0) { issues.append(.directoryWritableByOthers(dir)) }
        }
        if requireExecutable && f.mode & 0o100 == 0 { issues.append(.notExecutable(real)) }
        return issues
    }
}

/// Masque les secrets courants dans un texte affiché (journaux du serveur, sortie de commandes).
public enum SecretMasker {
    private static let patterns: [NSRegularExpression] = [
        // NOM_KEY=valeur, "api_key": "valeur", token: valeur…
        #"(?i)\b([A-Z0-9_]*(?:API[_-]?KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIALS?)[A-Z0-9_]*)(["']?\s*[:=]\s*["']?)([^\s"',}]{4,})"#,
        // Authorization: Bearer xxx
        #"(?i)\b(bearer)(\s+)([A-Za-z0-9._~+/=-]{8,})"#,
        // Formats de clés connus (OpenAI/Anthropic sk-…, Google AIza…, GitHub gh?_…, Slack xox?-…, Hindsight Cloud hsk_…)
        #"()()\b(sk-[A-Za-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|hsk_[A-Za-z0-9_-]{16,})"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func mask(_ text: String) -> String {
        var out = text
        for re in patterns {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                let secret = m.range(at: 3)
                result += ns.substring(with: NSRange(location: last, length: secret.location - last))
                let value = ns.substring(with: secret)
                result += String(value.prefix(4)) + "••••"
                last = secret.location + secret.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}
