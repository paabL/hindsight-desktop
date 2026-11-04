import Foundation
import Observation

/// Noms donnés par l'utilisateur aux clients HTTP non identifiés (signature → nom), conservés dans les
/// réglages de l'app. Le serveur ne journalise pas l'identité des appels HTTP : c'est le seul moyen de
/// distinguer, par exemple, un agent Codex de l'app elle-même.
@MainActor
@Observable
public final class CallerDirectory {
    @ObservationIgnored private let settings: SettingsStore
    public private(set) var names: [String: String]

    public init(settings: SettingsStore) {
        self.settings = settings
        let raw = settings.string(forKey: SettingsKey.callerNames) ?? "{}"
        names = (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
    }

    public func setName(_ name: String, for signature: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[signature] = n.isEmpty ? nil : n
        if let data = try? JSONEncoder().encode(names) { settings.set(String(decoding: data, as: UTF8.self), forKey: SettingsKey.callerNames) }
    }
}
