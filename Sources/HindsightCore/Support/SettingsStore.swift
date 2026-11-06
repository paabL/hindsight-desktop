import Foundation

/// Stockage des réglages de l'app (URL du serveur, dernière banque…). Rien de secret ici.
@MainActor
public protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

@MainActor
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }

    public func set(_ value: String?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

@MainActor
public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: String] = [:]
    public init(_ initial: [String: String] = [:]) { values = initial }
    public func string(forKey key: String) -> String? { values[key] }
    public func set(_ value: String?, forKey key: String) { values[key] = value }
}

public enum SettingsKey {
    public static let memoryFolderPath = "memoryFolderPath"
    public static let serverURL = "serverURL"
    public static let lastBank = "lastBank"
    public static let launchScriptPath = "launchScriptPath"
    public static let restartCommand = "restartCommand"
    /// Chemin résolu du script de lancement enregistré depuis le dernier redémarrage réussi du serveur.
    public static let launchScriptRestartPending = "launchScriptRestartPending"
    /// Empreinte SHA-256 du script de lancement approuvé pour le service.
    public static let serviceScriptHash = "serviceScriptHash"
    /// Dépôt git source des mises à jour (sinon celui inscrit dans l'Info.plist à la construction).
    public static let updateRepository = "updateRepository"
    /// URL du dépôt distant approuvée lors de la dernière mise à jour.
    public static let updateApprovedRemote = "updateApprovedRemote"
    public static let updateCheckAtLaunch = "updateCheckAtLaunch"
    public static let onboardingDone = "onboardingDone"
    /// Grille tarifaire des modèles (JSON), si modifiée.
    public static let priceBook = "priceBook"
    /// Noms des clients HTTP non identifiés (JSON signature → nom).
    public static let callerNames = "callerNames"
}
