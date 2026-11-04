import Foundation

/// Liste de mise en route (premier lancement, puis accessible depuis le menu Aide).
public struct SetupItem: Identifiable, Sendable, Hashable {
    public enum State: Sendable, Hashable { case ok, todo, optional }
    public enum Action: Sendable, Hashable {
        case openSettings
        case installService
        case startService
        case openServerSection
    }

    public let id: String
    public let title: String
    public let detail: String
    public let state: State
    public let action: Action?
    public let actionTitle: String?
}

extension AppModel {
    public var showsOnboarding: Bool { settings.string(forKey: SettingsKey.onboardingDone) == nil }

    public func finishOnboarding() {
        settings.set("1", forKey: SettingsKey.onboardingDone)
    }

    /// État courant de l'installation, du plus important au facultatif.
    public func setupItems() -> [SetupItem] {
        var items: [SetupItem] = []
        let scriptExists = FileManager.default.fileExists(atPath: service.scriptURL.path)

        if let v = connection.version {
            items.append(SetupItem(
                id: "server", title: "Serveur Hindsight", detail: "Connecté à \(serverURL.absoluteString) (API \(v.apiVersion)).",
                state: .ok, action: nil, actionTitle: nil))
        } else if service.isInstalled {
            items.append(SetupItem(
                id: "server", title: "Serveur Hindsight", detail: "Injoignable à \(serverURL.absoluteString). Le service de l'app peut le démarrer.",
                state: .todo, action: .startService, actionTitle: "Démarrer le serveur"))
        } else {
            items.append(SetupItem(
                id: "server", title: "Serveur Hindsight",
                detail: "Injoignable à \(serverURL.absoluteString). Démarrez-le, ou vérifiez son adresse dans les réglages.",
                state: .todo, action: .openSettings, actionTitle: "Réglages…"))
        }

        if service.isInstalled {
            let login = service.installed?.runAtLoad == true ? "démarre à l'ouverture de session" : "démarrage manuel"
            items.append(SetupItem(
                id: "service", title: "Service géré par l'app", detail: "Installé (\(login)).", state: .ok, action: nil, actionTitle: nil))
        } else {
            items.append(SetupItem(
                id: "service", title: "Service géré par l'app",
                detail: scriptExists
                    ? "Facultatif : démarrer, arrêter et redémarrer le serveur depuis l'app, avec un journal."
                    : "Facultatif : nécessite d'abord le script de lancement du serveur.",
                state: .optional, action: .openServerSection, actionTitle: "Configurer…"))
        }

        items.append(
            scriptExists
                ? SetupItem(
                    id: "script", title: "Script de lancement", detail: "\(service.scriptURL.path) : les modèles LLM/VLM s'y règlent.",
                    state: .ok, action: nil, actionTitle: nil)
                : SetupItem(
                    id: "script", title: "Script de lancement",
                    detail: "Introuvable (\(service.scriptURL.path)). Nécessaire pour changer les modèles ou gérer le serveur.",
                    state: .optional, action: .openServerSection, actionTitle: "Choisir…"))

        return items
    }

    public func perform(_ action: SetupItem.Action) async {
        switch action {
        case .openSettings:
            break  // fenêtre des réglages : ouverte par l'interface
        case .openServerSection:
            selectedSection = .server
        case .installService:
            selectedSection = .server
            service.requestInstall(startAtLogin: true)
        case .startService:
            await service.refresh()
            service.requestStart()
        }
    }
}
