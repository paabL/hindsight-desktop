import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Remplacement sûr de Hindsight.app par une version fraîchement construite.
public enum BundleInstaller {
    public enum InstallError: Error, CustomStringConvertible, Equatable {
        case invalidBundle(String)
        case io(String)

        public var description: String {
            switch self {
            case .invalidBundle(let m): return "Application construite invalide : \(m)"
            case .io(let m): return m
            }
        }
    }

    /// Vérifie que `app` est bien un bundle Hindsight (identifiant attendu, exécutable présent).
    public static func validate(_ app: URL, identifier: String = AppInfo.bundleIdentifier) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { throw InstallError.invalidBundle("Info.plist illisible") }
        guard info["CFBundleIdentifier"] as? String == identifier else {
            throw InstallError.invalidBundle("identifiant « \(info["CFBundleIdentifier"] as? String ?? "?") » au lieu de « \(identifier) »")
        }
        guard let exe = info["CFBundleExecutable"] as? String,
            FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(exe)").path)
        else { throw InstallError.invalidBundle("exécutable absent") }
    }

    /// Garde le répertoire `.app` existant : les raccourcis du Dock suivent son identité de fichier.
    /// Seul `Contents` est échangé ; une première installation crée normalement le bundle.
    public static func replace(_ current: URL, with new: URL, identifier: String = AppInfo.bundleIdentifier) throws {
        try validate(new, identifier: identifier)
        let fm = FileManager.default
        let dir = current.deletingLastPathComponent()
        let token = UUID().uuidString.prefix(8)
        let staged = dir.appendingPathComponent(".\(current.lastPathComponent).new-\(token)")
        let old = dir.appendingPathComponent(".\(current.lastPathComponent).old-\(token)")
        let hadCurrent = fm.fileExists(atPath: current.path)
        if hadCurrent { try validate(current, identifier: identifier) }
        do {
            try fm.copyItem(at: new, to: staged)
        } catch {
            try? fm.removeItem(at: staged)
            throw InstallError.io("Copie impossible dans \(dir.path) : \(error.localizedDescription)")
        }
        if hadCurrent {
            let currentContents = current.appendingPathComponent("Contents")
            let stagedContents = staged.appendingPathComponent("Contents")
            guard (try? fm.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) == .typeDirectory,
                  (try? fm.attributesOfItem(atPath: currentContents.path)[.type] as? FileAttributeType) == .typeDirectory,
                  (try? fm.attributesOfItem(atPath: stagedContents.path)[.type] as? FileAttributeType) == .typeDirectory else {
                try? fm.removeItem(at: staged)
                throw InstallError.invalidBundle("le dossier de l’app ou son contenu n’est pas un répertoire ordinaire")
            }
            #if canImport(Darwin)
            if renamex_np(currentContents.path, stagedContents.path, UInt32(RENAME_SWAP)) == 0 {
                try? fm.removeItem(at: staged)
                return
            }
            let swapError = errno
            guard [ENOTSUP, EOPNOTSUPP, ENOSYS, EINVAL].contains(swapError) else {
                try? fm.removeItem(at: staged)
                throw InstallError.io("Impossible de remplacer le contenu de l’app : \(String(cString: strerror(swapError)))")
            }
            #endif
            let backup = staged.appendingPathComponent("previous-Contents")
            guard rename(currentContents.path, backup.path) == 0 else {
                let reason = String(cString: strerror(errno))
                try? fm.removeItem(at: staged)
                throw InstallError.io("Impossible de sauvegarder l’ancienne version : \(reason)")
            }
            guard rename(stagedContents.path, currentContents.path) == 0 else {
                let reason = String(cString: strerror(errno))
                if rename(backup.path, currentContents.path) != 0 {
                    throw InstallError.io("Installation interrompue. Ancienne version conservée dans \(backup.path) : \(reason)")
                }
                try? fm.removeItem(at: staged)
                throw InstallError.io("Impossible d’installer la nouvelle version : \(reason)")
            }
            try? fm.removeItem(at: staged)
            return
        }
        if hadCurrent, rename(current.path, old.path) != 0 {
            let reason = String(cString: strerror(errno))
            try? fm.removeItem(at: staged)
            throw InstallError.io("Impossible de déplacer l'ancienne version : \(reason)")
        }
        if rename(staged.path, current.path) != 0 {
            let reason = String(cString: strerror(errno))
            if hadCurrent { _ = rename(old.path, current.path) }
            try? fm.removeItem(at: staged)
            throw InstallError.io("Impossible d'installer la nouvelle version : \(reason)")
        }
        if hadCurrent { try? fm.removeItem(at: old) }
    }
}
