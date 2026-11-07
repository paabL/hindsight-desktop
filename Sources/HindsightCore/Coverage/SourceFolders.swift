import Foundation

/// Les sources d'une banque sont les dossiers de ce Mac qu'elle suit (réglage `coverageRoots.<banque>`). Un même
/// dossier peut alimenter plusieurs banques, chacune avec son propre état.
///
/// Un dossier est ordinaire (ses fichiers sont comparés aux documents de la banque) ou porte un catalogue : un
/// collecteur (`collect.py`) y rassemble conversations, commits et rapports dans `catalog.json`. Un dossier à
/// catalogue appartient à la banque déclarée par sa politique (`memory-policy.json`), ou, tant qu'aucune n'est
/// déclarée, à chaque banque qui le suit. Dans sa banque, il passe uniquement par son catalogue ; dans une autre
/// banque, c'est un dossier ordinaire.
@MainActor
public enum SourceFolders {
    /// `catalog.json` du dossier, à sa racine ou dans `collection/`.
    public static func catalogURL(in folder: URL) -> URL? {
        [folder.appendingPathComponent("catalog.json"), folder.appendingPathComponent("collection/catalog.json")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Dépôt du catalogue : le dossier lui-même, ou son parent quand le dossier choisi est le `collection`
    /// d'un dépôt qui contient `collect.py`.
    public static func repository(of folder: URL) -> URL {
        let parent = folder.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("catalog.json").path)
            && FileManager.default.fileExists(atPath: parent.appendingPathComponent("collect.py").path) ? parent : folder
    }

    /// Banque déclarée par la politique du dépôt. Une politique peut peser plusieurs centaines de kilo-octets :
    /// elle n'est relue que lorsque le fichier change.
    public static func declaredBank(of folder: URL) -> String? {
        let repository = repository(of: folder)
        let policy = repository.appendingPathComponent("memory-policy.json")
        guard let version = try? FileVersion(policy) else {
            declaredBanks[policy.path] = nil
            return nil
        }
        if let cached = declaredBanks[policy.path], cached.version == version { return cached.bank }
        let bank = MemoryWorkspace.declaredBank(in: repository)
        declaredBanks[policy.path] = (version, bank)
        return bank
    }

    private static var declaredBanks: [String: (version: FileVersion, bank: String?)] = [:]

    /// Ce dossier passe par son catalogue dans cette banque. Sans banque choisie (serveur déconnecté), tout
    /// catalogue reste consultable.
    public static func isCatalog(_ folder: URL, for bank: String?) -> Bool {
        guard catalogURL(in: folder) != nil else { return false }
        guard let bank, let declared = declaredBank(of: folder) else { return true }
        return declared == bank
    }

    /// Politique du catalogue rattaché à cette banque. Ses exclusions valent aussi pour les fichiers des dossiers
    /// ordinaires de la banque ; une banque sans catalogue n'en a pas.
    public static func policyURL(bank: String, roots: [CoverageRoot]) -> URL? {
        roots.lazy.map(\.url)
            .first { catalogURL(in: $0) != nil && declaredBank(of: $0) == bank }
            .map { repository(of: $0).appendingPathComponent("memory-policy.json") }
    }

    /// Avant la version 0.1.13, le Catalogue gardait un seul dossier pour tout le Mac (`memoryFolderPath`),
    /// affiché dans chaque banque. Un dossier à catalogue rejoint les dossiers de sa banque (déclarée, sinon la
    /// dernière choisie) ; un dossier ordinaire n'est rattaché à rien. Le réglage commun disparaît.
    public static func migrateLegacyCatalogFolder(settings: SettingsStore) {
        guard let path = settings.string(forKey: SettingsKey.memoryFolderPath) else { return }
        settings.set(nil, forKey: SettingsKey.memoryFolderPath)
        let folder = URL(fileURLWithPath: path).standardizedFileURL
        guard catalogURL(in: folder) != nil else { return }
        let repository = repository(of: folder)
        guard let bank = declaredBank(of: repository) ?? settings.string(forKey: SettingsKey.lastBank), !bank.isEmpty else { return }
        var roots = FileCoverageViewModel.storedRoots(settings: settings, bank: bank)
        let key = repository.path.precomposedStringWithCanonicalMapping
        guard !roots.contains(where: { $0.url.standardizedFileURL.path.precomposedStringWithCanonicalMapping == key }) else { return }
        roots.append(CoverageRoot(path: repository.path))
        FileCoverageViewModel.saveRoots(roots, settings: settings, bank: bank)
    }
}
