import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Lecture / écriture sûre du script de lancement : sauvegarde horodatée avant toute écriture,
/// écriture atomique (fichier temporaire + rename), permissions d'origine conservées.
public struct LaunchScriptStore: Sendable {
    public enum StoreError: Error, CustomStringConvertible {
        case notFound(String)
        case changedOnDisk
        case io(String)

        public var description: String {
            switch self {
            case .notFound(let p): return "Fichier introuvable : \(p)"
            case .changedOnDisk: return "Le fichier a été modifié sur le disque depuis son ouverture : rechargez-le avant d'enregistrer."
            case .io(let m): return "Erreur d'écriture : \(m)"
            }
        }
    }

    public struct Backup: Identifiable, Sendable, Hashable {
        public var id: String { url.path }
        public let url: URL
        public let date: Date
    }

    public let url: URL
    public static let backupMarker = ".bak-"

    /// Un lien symbolique est suivi : c'est le fichier réel qui est sauvegardé et remplacé.
    public init(url: URL) { self.url = url.resolvingSymlinksInPath() }

    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    public func read() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreError.notFound(url.path) }
        do { return try String(contentsOf: url, encoding: .utf8) } catch { throw StoreError.io(error.localizedDescription) }
    }

    static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: d)
    }

    /// Écrit `newText` après avoir vérifié que le fichier contient toujours `expected` et l'avoir sauvegardé.
    /// Retourne l'URL de la sauvegarde.
    @discardableResult
    public func save(_ newText: String, expecting expected: String, now: Date = Date()) throws -> URL {
        let current = try read()
        guard current == expected else { throw StoreError.changedOnDisk }
        let fm = FileManager.default
        var backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + Self.backupMarker + Self.stamp(now))
        var n = 1
        while fm.fileExists(atPath: backup.path) {
            backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + Self.backupMarker + Self.stamp(now) + "-\(n)")
            n += 1
        }
        do {
            try fm.copyItem(at: url, to: backup)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
            try Data(newText.utf8).write(to: tmp)
            if let perms = attrs[.posixPermissions] { try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path) }
            if rename(tmp.path, url.path) != 0 {
                try? fm.removeItem(at: tmp)
                throw StoreError.io(String(cString: strerror(errno)))
            }
        } catch let e as StoreError {
            throw e
        } catch {
            throw StoreError.io(error.localizedDescription)
        }
        return backup
    }

    /// Sauvegardes existantes, de la plus récente à la plus ancienne.
    public func backups() -> [Backup] {
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + Self.backupMarker
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.compactMap { name -> Backup? in
            let u = dir.appendingPathComponent(name)
            let d = (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate] as? Date) ?? nil
            return Backup(url: u, date: d ?? .distantPast)
        }.sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    /// Restaure une sauvegarde (l'état courant est lui-même sauvegardé d'abord).
    @discardableResult
    public func restore(_ backup: Backup, now: Date = Date()) throws -> URL {
        let text: String
        do { text = try String(contentsOf: backup.url, encoding: .utf8) } catch { throw StoreError.io(error.localizedDescription) }
        return try save(text, expecting: try read(), now: now)
    }
}
