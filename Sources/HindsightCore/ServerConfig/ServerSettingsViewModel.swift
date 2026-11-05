import Foundation
import HindsightAPI
import Observation

/// Changement des modèles et réglages serveur : édition sûre du script de lancement (diff, sauvegarde,
/// confirmation), puis redémarrage optionnel et vérification que le serveur et ses LLM répondent.
///
/// Ces réglages sont des variables d'environnement du processus serveur : l'API ne permet ni de les lire
/// ni de les changer. L'app ne fait qu'éditer le fichier que l'utilisateur désigne.
@MainActor
@Observable
public final class ServerSettingsViewModel {
    public static let defaultScriptPath = "~/.hindsight/start-api.sh"

    public struct FieldState: Identifiable, Sendable, Hashable {
        public var id: String { name }
        public let name: String
        public let label: String
        public let help: String
        public let isSecret: Bool
        /// Valeur dans le brouillon (`nil` = non définie).
        public let value: String?
        public let original: String?
        public let occurrences: Int
        public let isDynamic: Bool
        public var isChanged: Bool { value != original }
    }

    public struct RoleState: Identifiable, Sendable, Hashable {
        public var id: String { role.id }
        public let role: ServerSettingsCatalog.Role
        public let fields: [FieldState]
        /// Résumé « fournisseur · modèle » effectif, héritage compris.
        public let effective: String
        public var isChanged: Bool { fields.contains { $0.isChanged } }
    }

    public enum RestartState: Sendable, Equatable {
        case idle
        case running(String)
        case succeeded(String)
        case failed(String)
    }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private var clientProvider: @MainActor () -> HindsightClient
    @ObservationIgnored private let bankProvider: @MainActor () -> String?
    @ObservationIgnored private let healthTimeout: TimeInterval
    @ObservationIgnored private let pollInterval: Duration
    public let connections: LLMConnections
    public private(set) var codexModelChoices: [LLMModelCatalog.Choice] = []

    public var scriptPath: String
    public var restartCommand: String

    public private(set) var state: LoadState<Void> = .idle
    public private(set) var original: LaunchScript?
    public private(set) var draft: LaunchScript?
    @ObservationIgnored private var originalText = ""
    public private(set) var backups: [LaunchScriptStore.Backup] = []
    /// Le fichier a été enregistré depuis le dernier redémarrage réussi.
    public private(set) var needsRestart = false
    public private(set) var restartState: RestartState = .idle
    public private(set) var restartLog = ""
    public private(set) var llmHealth: BankLlmHealthResponse?

    public var confirmation: ConfirmationRequest?
    public var actionMessage: String?
    /// Service géré par l'app : s'il est installé, il sert au redémarrage (sans commande à saisir), et chaque
    /// enregistrement confirmé ici vaut approbation du nouveau contenu du script.
    @ObservationIgnored public weak var service: HindsightServiceViewModel?

    public init(
        settings: SettingsStore, runner: CommandRunner = ShellCommandRunner(),
        client: @escaping @MainActor () -> HindsightClient, bank: @escaping @MainActor () -> String?,
        healthTimeout: TimeInterval = 90, pollInterval: Duration = .seconds(2),
        connections: LLMConnections? = nil
    ) {
        self.settings = settings
        self.runner = runner
        self.clientProvider = client
        self.bankProvider = bank
        self.healthTimeout = healthTimeout
        self.pollInterval = pollInterval
        self.connections = connections ?? LLMConnections()
        self.scriptPath = settings.string(forKey: SettingsKey.launchScriptPath) ?? Self.defaultScriptPath
        self.restartCommand = settings.string(forKey: SettingsKey.restartCommand) ?? ""
    }

    var store: LaunchScriptStore { LaunchScriptStore(url: LaunchScriptStore.expand(scriptPath)) }

    // MARK: Chargement

    public func load() async {
        settings.set(scriptPath, forKey: SettingsKey.launchScriptPath)
        state = .loading
        do {
            let text = try store.read()
            originalText = text
            original = LaunchScript(text: text)
            draft = original
            refreshModelCatalog()
            backups = store.backups()
            state = .loaded(())
        } catch {
            original = nil
            draft = nil
            state = .failed("\(error)")
        }
    }

    public func loadIfNeeded() async {
        if original == nil, !state.isLoading, state.errorMessage == nil { await load() }
    }

    // MARK: Lecture du brouillon

    public var hasChanges: Bool { draft != nil && draft != original }

    public var connectionContext: LLMConnectionContext {
        func directory() -> String? {
            if let draft {
                for name in ["HINDSIGHT_API_LLM_CODEX_HOME", "CODEX_HOME"] {
                    guard let assignment = draft.assignment(name), !assignment.value.isEmpty else { continue }
                    let raw = LaunchScript.parse(draft.lines[assignment.line])?.rawValue ?? ""
                    return LLMConnectionContext.credentialsDirectory(assignment.value,
                        expandHome: assignment.isDynamic || raw == "~" || raw.hasPrefix("~/"))
                }
            }
            return LLMConnectionContext.credentialsDirectory(ProcessInfo.processInfo.environment["CODEX_HOME"], expandHome: false)
        }
        // Le script peut n'être qu'un relais (`exec bash autre-script.sh`) : emplacement d'installation usuel en repli.
        let usual = NSHomeDirectory() + "/.hindsight/venv/bin/hindsight-admin"
        let admin = LLMConnectionContext.hindsightAdmin(scriptLines: (draft ?? original)?.lines ?? [])
            ?? (FileManager.default.isExecutableFile(atPath: usual) ? usual : nil)
        return LLMConnectionContext(
            isLocalServer: ["localhost", "127.0.0.1", "::1", "[::1]"].contains(clientProvider().baseURL.host?.lowercased() ?? ""),
            codexHome: directory(), hindsightAdmin: admin)
    }

    public var modelRoles: [RoleState] { roles.filter { $0.role.isModelRole } }
    public var advancedRoles: [RoleState] { roles.filter { !$0.role.isModelRole } }

    public var providerChoices: [ServerSettingsCatalog.Provider] {
        let known = ServerSettingsCatalog.suggestedProviders
        let configured = Set(modelRoles.compactMap { role in role.fields.first { $0.name.hasSuffix("PROVIDER") && !$0.isDynamic }?.value })
        return known + configured.subtracting(known.map(\.id)).sorted().map { .init(id: $0, title: $0) }
    }

    public func refreshModelCatalog() {
        let context = connectionContext
        codexModelChoices = context.isLocalServer
            ? context.codexHome.map(LLMModelCatalog.readCodexModels(home:)) ?? [] : []
    }

    /// Menu previews for an uncommitted provider choice. Never changes the launch-script draft.
    public var modelsByProvider: [String: [LLMModelCatalog.Choice]] {
        var configured: [String: [String]] = [:]
        for script in [draft, original].compactMap({ $0 }) {
            for role in ServerSettingsCatalog.roles where role.isModelRole {
                guard let provider = configuredValue(role, suffix: "PROVIDER", in: script),
                      let model = configuredValue(role, suffix: "MODEL", in: script),
                      !provider.contains("$"), !model.contains("$") else { continue }
                configured[provider, default: []].append(model)
            }
        }
        let providers = Set(providerChoices.map(\.id)).union(configured.keys)
        return Dictionary(uniqueKeysWithValues: providers.map { provider in
            (provider, LLMModelCatalog.choices(for: provider, configured: configured[provider] ?? [], codexModels: codexModelChoices))
        })
    }

    public func modelChoices(forRole id: String) -> [LLMModelCatalog.Choice] {
        guard let provider = resolvedValue(for: id, suffix: "PROVIDER") else { return [] }
        var configured: [String] = []
        // Mettre le choix actuel en premier, puis les modèles du même fournisseur dans les autres usages.
        let relevantRoles = modelRoles.sorted { $0.id == id && $1.id != id }
        for role in relevantRoles {
            guard resolvedValue(for: role.id, suffix: "PROVIDER") == provider,
                  let field = role.fields.first(where: { $0.name.hasSuffix("_MODEL") }), !field.isDynamic,
                  let model = field.value else { continue }
            configured.append(model)
        }
        if let original {
            for role in ServerSettingsCatalog.roles where role.isModelRole {
                guard configuredValue(role, suffix: "PROVIDER", in: original) == provider,
                      let field = role.fields.first(where: { $0.name.hasSuffix("_MODEL") }),
                      let assignment = original.assignment(field.name), !assignment.isDynamic else { continue }
                configured.append(assignment.value)
            }
        }
        return LLMModelCatalog.choices(for: provider, configured: configured, codexModels: codexModelChoices)
    }

    public func resolvedValue(for roleID: String, suffix: String) -> String? {
        guard let role = ServerSettingsCatalog.roles.first(where: { $0.id == roleID }), let draft else { return nil }
        return configuredValue(role, suffix: suffix, in: draft)
    }

    private func configuredValue(_ role: ServerSettingsCatalog.Role, suffix: String, in script: LaunchScript) -> String? {
        if ["reranker", "embeddings"].contains(role.id) {
            let prefix = "HINDSIGHT_API_\(role.id.uppercased())_"
            let provider = script.value(prefix + "PROVIDER").flatMap { $0.isEmpty ? nil : $0 } ?? "local"
            if suffix == "PROVIDER" { return provider }
            if suffix == "MODEL" {
                if provider == "hindsight" { return role.id == "reranker" ? "hs-rerank-1" : "hs-embed-1" }
                let owner = role.id == "embeddings" && provider == "google" ? "GEMINI" : provider.uppercased()
                return script.value(prefix + owner + "_MODEL").flatMap { $0.isEmpty ? nil : $0 }
            }
        }
        if let field = role.fields.first(where: { $0.name.hasSuffix("_" + suffix) }),
           let value = script.value(field.name), !value.isEmpty { return value }
        if let fallback = ServerSettingsCatalog.roles.first(where: { $0.id == role.fallback }) {
            return configuredValue(fallback, suffix: suffix, in: script)
        }
        return nil
    }

    /// L'environnement inchangé est une information avancée ; son remplacement est un avertissement.
    public var actionableWarnings: [String] {
        guard let original, let draft else { return [] }
        var result: [String] = []
        if roles.contains(where: { $0.id == "embeddings" && $0.isChanged }),
           let caution = ServerSettingsCatalog.roles.first(where: { $0.id == "embeddings" })?.caution { result.append(caution) }
        for assignment in original.hindsightVariables where assignment.isDynamic && draft.value(assignment.name) != assignment.value {
            let field = ServerSettingsCatalog.roles.flatMap(\.fields).first { $0.name == assignment.name }
            result.append("\(field?.label ?? assignment.name) : la référence à l'environnement sera remplacée. Vous pouvez rétablir sa valeur d'origine.")
        }
        return result
    }

    public var roles: [RoleState] {
        guard let draft, let original else { return [] }
        return ServerSettingsCatalog.roles.map { role in
            let fields = role.fields.map { f -> FieldState in
                let a = draft.assignment(f.name)
                return FieldState(
                    name: f.name, label: f.label, help: f.help, isSecret: f.isSecret, value: a?.value,
                    original: original.value(f.name), occurrences: draft.occurrences(f.name), isDynamic: a?.isDynamic ?? false)
            }
            return RoleState(role: role, fields: fields, effective: effectiveSummary(role, in: draft))
        }
    }

    /// Variables HINDSIGHT_API_* du script absentes du catalogue.
    public var otherVariables: [FieldState] {
        guard let draft, let original else { return [] }
        let known = ServerSettingsCatalog.knownNames
        var names = Set(draft.hindsightVariables.map(\.name)).union(original.hindsightVariables.map(\.name))
        names.subtract(known)
        return names.sorted().map { n in
            let a = draft.assignment(n)
            return FieldState(
                name: n, label: n.replacingOccurrences(of: "HINDSIGHT_API_", with: ""), help: "",
                isSecret: LaunchScript.isSecret(n), value: a?.value, original: original.value(n),
                occurrences: draft.occurrences(n), isDynamic: a?.isDynamic ?? false)
        }
    }

    func effectiveSummary(_ role: ServerSettingsCatalog.Role, in s: LaunchScript) -> String {
        guard let providerField = role.fields.first(where: { $0.name.hasSuffix("PROVIDER") }) else {
            let set = role.fields.compactMap { f in s.value(f.name).map { "\(f.label) = \($0)" } }
            return set.isEmpty ? "valeurs par défaut du serveur" : set.joined(separator: " · ")
        }
        let provider = configuredValue(role, suffix: "PROVIDER", in: s)
        let model = configuredValue(role, suffix: "MODEL", in: s)
        let inherited = s.value(providerField.name) == nil && role.fallback != nil
        guard let p = provider, !p.isEmpty else {
            return inherited || role.fallback != nil ? "hérite du défaut du serveur" : "non configuré (défaut du serveur)"
        }
        let defaultModel = role.isModelRole ? ServerSettingsCatalog.defaultModel(for: p) : nil
        let m = model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel.map { "\($0) (défaut)" } ?? "modèle par défaut"
        let source = role.fallback == "reflect" ? "Reflect" : "LLM par défaut"
        return "\(p) · \(m)" + (inherited ? " — hérité du \(source)" : "")
    }

    /// Fournisseur et modèle effectifs d'un rôle (héritage du LLM par défaut compris), d'après le script
    /// enregistré. Sert aux estimations de coût quand aucune trace LLM n'est disponible.
    public func providerAndModel(forRole id: String) -> (provider: String?, model: String?) {
        guard let s = original, let role = ServerSettingsCatalog.roles.first(where: { $0.id == id }) else { return (nil, nil) }
        let p = configuredValue(role, suffix: "PROVIDER", in: s)
        var m = configuredValue(role, suffix: "MODEL", in: s)
        if m == nil, role.isModelRole, let p { m = ServerSettingsCatalog.defaultModel(for: p) }
        return (p, m)
    }

    public var warnings: [String] {
        guard let draft else { return [] }
        var w = draft.warnings
        if let embeddings = roles.first(where: { $0.role.id == "embeddings" }), embeddings.isChanged, let c = embeddings.role.caution {
            w.insert(c, at: 0)
        }
        return w
    }

    /// Diff complet du brouillon, secrets masqués.
    public var diff: [DiffLine] {
        guard let original, let draft else { return [] }
        return LineDiff.diff(original.lines.map(LaunchScript.masked), draft.lines.map(LaunchScript.masked))
    }

    public var compactDiff: [DiffLine] { LineDiff.compact(diff) }

    /// Résumé lisible des changements (secrets masqués) pour la confirmation.
    public var changeSummary: [String] {
        guard let original, let draft else { return [] }
        let names = Set(original.hindsightVariables.map(\.name)).union(draft.hindsightVariables.map(\.name))
        return names.sorted().compactMap { n in
            let a = original.value(n), b = draft.value(n)
            guard a != b else { return nil }
            func show(_ v: String?) -> String { v.map { "« \(LaunchScript.maskValue(n, $0)) »" } ?? "(non défini)" }
            return "\(n) : \(show(a)) → \(show(b))"
        }
    }

    // MARK: Édition du brouillon

    /// Vide ou `nil` : la variable est désactivée (ligne commentée).
    public func setValue(_ name: String, _ value: String?) {
        guard var d = draft else { return }
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.value(name) == (v?.isEmpty == true ? nil : v) { return }
        if let v, !v.isEmpty { d.set(name, to: v) } else { d.unset(name) }
        draft = d
    }

    /// Ajoute une variable `HINDSIGHT_API_*` (le préfixe est ajouté si absent).
    @discardableResult
    public func addVariable(_ rawName: String, _ value: String) -> Bool {
        var name = rawName.trimmingCharacters(in: .whitespaces).uppercased()
        if !name.hasPrefix("HINDSIGHT_API_") { name = "HINDSIGHT_API_" + name }
        guard name.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) != nil, !value.isEmpty else { return false }
        setValue(name, value)
        return true
    }

    public func revert(_ name: String) {
        guard let original, var d = draft else { return }
        d.restore(name, from: original)
        draft = d
    }

    public func restoreDraft(_ snapshot: LaunchScript) { draft = snapshot }

    public func useInheritedSettings(forRole id: String) {
        guard let role = ServerSettingsCatalog.roles.first(where: { $0.id == id }), role.fallback != nil else { return }
        for field in role.fields { setValue(field.name, nil) }
    }

    public func selectProvider(_ provider: String, forRole id: String) {
        guard let role = ServerSettingsCatalog.roles.first(where: { $0.id == id }),
              let field = role.fields.first(where: { $0.name.hasSuffix("PROVIDER") }),
              provider != draft?.value(field.name) else { return }
        setValue(field.name, provider)
        if let modelField = role.fields.first(where: { $0.name.hasSuffix("_MODEL") }) {
            let suggestions = ["openai-codex", "chatgpt"].contains(provider) && !codexModelChoices.isEmpty
                ? codexModelChoices : LLMModelCatalog.suggestions(for: provider)
            setValue(modelField.name, suggestions.first?.id ?? ServerSettingsCatalog.defaultModel(for: provider))
        }
    }

    // MARK: Modèles Hindsight (décision et reranker, fournisseur `hindsight` du serveur 1.2.0)

    /// D'où vient un modèle, d'après le brouillon.
    public enum ModelSource: String, Sendable {
        /// Hindsight Inference, avec la clé de Hindsight Cloud.
        case cloud
        /// Sur ce Mac : serveur de décision local, reranker chargé par le serveur Hindsight.
        case local
        case off
        /// Autre fournisseur, ou réglage fait à la main.
        case other
    }

    enum Decision {
        static let provider = "HINDSIGHT_API_DECISION_MODEL_PROVIDER"
        static let model = "HINDSIGHT_API_DECISION_MODEL_MODEL"
        static let baseURL = "HINDSIGHT_API_DECISION_MODEL_BASE_URL"
        static let apiKey = "HINDSIGHT_API_DECISION_MODEL_API_KEY"
        /// Pour le serveur local : il répond à une requête à la fois, plus lentement qu'Hindsight Inference, et refuse
        /// au-delà de 8 192 jetons du modèle ; Hindsight compte avec un autre vocabulaire, d'où la marge.
        static let localTuning = [
            ("HINDSIGHT_API_DECISION_MODEL_MAX_CONCURRENT", "2"),
            ("HINDSIGHT_API_DECISION_MODEL_TIMEOUT", "120"),
            ("HINDSIGHT_API_DECISION_MODEL_MAX_REQUEST_TOKENS", "7000"),
        ]
    }

    enum Reranker {
        static let provider = "HINDSIGHT_API_RERANKER_PROVIDER"
        static let localModel = "HINDSIGHT_API_RERANKER_LOCAL_MODEL"
        static let apiKey = "HINDSIGHT_API_RERANKER_HINDSIGHT_API_KEY"
    }

    public var decisionModelSource: ModelSource {
        let provider = draft?.value(Decision.provider)?.lowercased() ?? ""
        if provider.isEmpty || provider == "none" { return .off }
        guard provider == "hindsight" else { return .other }
        switch draft?.value(Decision.baseURL) ?? "" {
        case "", HindsightInference.url: return .cloud
        case LocalDecisionModel.baseURL: return .local
        default: return .other
        }
    }

    /// Hindsight Inference : la clé vient de `hindsight-admin cloud login`. Une clé hsk_ ou une référence à
    /// l'environnement déjà dans le script est gardée ; une autre clé (serveur local, autre fournisseur) serait
    /// envoyée au cloud à la place de celle du compte.
    public func useCloudDecisionModel() {
        setValue(Decision.provider, "hindsight")
        setValue(Decision.model, nil)
        setValue(Decision.baseURL, nil)
        if let key = draft?.assignment(Decision.apiKey), !key.isDynamic, !key.value.hasPrefix("hsk_") { setValue(Decision.apiKey, nil) }
        for (name, value) in Decision.localTuning where draft?.value(name) == value { setValue(name, nil) }
    }

    /// Serveur de décision de ce Mac (`LocalDecisionModel`), avec sa clé.
    public func useLocalDecisionModel(apiKey: String) {
        setValue(Decision.provider, "hindsight")
        setValue(Decision.model, nil)
        setValue(Decision.baseURL, LocalDecisionModel.baseURL)
        setValue(Decision.apiKey, apiKey)
        for (name, value) in Decision.localTuning { setValue(name, value) }
    }

    /// Plus de modèle de décision : défaut du serveur (`none`), les appels LLM reprennent ces décisions.
    public func disableDecisionModel() { setValue(Decision.provider, nil) }

    /// Reranker Hindsight chargé par le serveur sur ce Mac (CPU) : ni clé, ni réseau, ni ré-indexation.
    public static let localHindsightReranker = "hindsight-ai/hs-rerank-1"

    public var rerankerSource: ModelSource {
        switch draft?.value(Reranker.provider)?.lowercased() ?? "" {
        case "hindsight": return .cloud
        case "local": return draft?.value(Reranker.localModel) == Self.localHindsightReranker ? .local : .other
        default: return .other
        }
    }

    /// Prépare le passage au reranker local ; les réglages Cohere restent dans le script pour revenir en arrière.
    public func useLocalHindsightReranker() {
        setValue(Reranker.provider, "local")
        setValue(Reranker.localModel, Self.localHindsightReranker)
    }

    /// hs-rerank-1 sur Hindsight Inference, avec la clé de Hindsight Cloud.
    public func useCloudReranker() { setValue(Reranker.provider, "hindsight") }

    /// Choix cloud sans clé dans le script : la clé vient de la connexion Hindsight Cloud, sans laquelle le
    /// serveur 1.2.0 refuse de démarrer.
    public var cloudModelsUseAccountKey: Bool {
        guard let draft else { return false }
        return (decisionModelSource == .cloud && (draft.value(Decision.apiKey) ?? "").isEmpty)
            || (rerankerSource == .cloud && (draft.value(Reranker.apiKey) ?? "").isEmpty)
    }

    public func revertAll() { draft = original }

    // MARK: Enregistrement / restauration (confirmés)

    public func requestSave() {
        guard hasChanges, let draft else { return }
        let summary = changeSummary
        confirmation = ConfirmationRequest(
            title: "Enregistrer le script de lancement ?",
            message:
                (summary.isEmpty ? "Le fichier change (voir le diff)." : summary.joined(separator: "\n"))
                + "\n\nUne copie de l'état actuel sera faite à côté du fichier avant l'écriture. Rien ne change pour le serveur tant qu'il n'est pas redémarré.",
            confirmTitle: "Enregistrer", severity: .normal
        ) { [weak self] in
            await self?.save(draft.text)
        }
    }

    private func save(_ text: String) async {
        do {
            let backup = try store.save(text, expecting: originalText)
            actionMessage = "Enregistré. Sauvegarde : \(backup.lastPathComponent). Redémarrez le serveur pour appliquer."
            needsRestart = true
            service?.approveCurrentScript()
            await load()
        } catch {
            actionMessage = "Échec : \(error)"
        }
    }

    public func requestRestore(_ backup: LaunchScriptStore.Backup) {
        confirmation = ConfirmationRequest(
            title: "Restaurer \(backup.url.lastPathComponent) ?",
            message: "Le script actuel sera remplacé par cette sauvegarde (il est lui-même sauvegardé d'abord). Redémarrez ensuite le serveur.",
            confirmTitle: "Restaurer"
        ) { [weak self] in
            guard let self else { return }
            do {
                try self.store.restore(backup)
                self.actionMessage = "Sauvegarde restaurée. Redémarrez le serveur pour appliquer."
                self.needsRestart = true
                self.service?.approveCurrentScript()
                await self.load()
            } catch {
                self.actionMessage = "Échec : \(error)"
            }
        }
    }

    // MARK: Redémarrage (confirmé) et vérification

    public func saveRestartCommand() {
        settings.set(restartCommand.isEmpty ? nil : restartCommand, forKey: SettingsKey.restartCommand)
    }

    /// Le redémarrage passe par le service de l'app s'il est installé et qu'aucune commande n'est indiquée.
    public var usesManagedService: Bool {
        restartCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && service?.isInstalled == true
    }

    public func requestRestart() {
        let cmd = restartCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if usesManagedService, let service {
            service.inspectScript()
            if let problem = service.blockingIssues.first {
                actionMessage = "Redémarrage refusé : \(problem)"
                return
            }
            let changed = service.scriptChangedSinceApproval
            confirmation = ConfirmationRequest(
                title: "Redémarrer le serveur Hindsight ?",
                message: (changed ? "Le script a été modifié hors de l'app depuis votre dernière approbation : vérifiez-le.\n\n" : "")
                    + "Le service de l'app relance \(service.scriptURL.path).\n\nLes requêtes en cours seront interrompues ; les opérations en file seront reprises par le serveur à son redémarrage. L'app attend ensuite que l'API réponde puis teste les LLM.",
                confirmTitle: changed ? "Approuver et redémarrer" : "Redémarrer"
            ) { [weak self] in
                if changed { service.approveCurrentScript() }
                await self?.restartManaged()
            }
            return
        }
        guard !cmd.isEmpty else {
            actionMessage = "Installez le service Hindsight (ci-dessus) ou indiquez la commande qui redémarre votre serveur."
            return
        }
        saveRestartCommand()
        confirmation = ConfirmationRequest(
            title: "Redémarrer le serveur Hindsight ?",
            message:
                "Commande exécutée sur ce Mac :\n\(cmd)\n\nLes requêtes en cours seront interrompues ; les opérations en file seront reprises par le serveur à son redémarrage. L'app attend ensuite que l'API réponde puis teste les LLM.",
            confirmTitle: "Redémarrer"
        ) { [weak self] in
            await self?.restart(cmd)
        }
    }

    func restartManaged() async {
        guard let service else { return }
        restartState = .running("Redémarrage du service…")
        restartLog = ""
        llmHealth = nil
        guard await service.restart() else {
            restartLog = service.logTail
            restartState = .failed(service.message ?? "Le serveur ne répond pas après le redémarrage.")
            return
        }
        await verifyAfterRestart(alreadyUp: true)
    }

    func restart(_ cmd: String) async {
        restartState = .running("Exécution de la commande…")
        restartLog = "$ \(cmd)\n"
        llmHealth = nil
        do {
            let r = try await runner.run(cmd, timeout: 60)
            restartLog += SecretMasker.mask(r.output)
            if r.status != 0 {
                restartState = .failed("La commande a échoué (code \(r.status)).")
                return
            }
        } catch {
            restartState = .failed("Impossible d'exécuter la commande : \(error.localizedDescription)")
            return
        }
        await verifyAfterRestart(alreadyUp: false)
    }

    func verifyAfterRestart(alreadyUp: Bool) async {
        restartState = .running("Attente de l'API…")
        let client = clientProvider()
        let deadline = Date().addingTimeInterval(healthTimeout)
        var up = alreadyUp
        while !up && Date() < deadline {
            if (try? await client.version()) != nil {
                up = true
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        guard up else {
            restartState = .failed("L'API ne répond pas après \(Int(healthTimeout)) s. Consultez la sortie ci-dessous et les journaux du serveur.")
            return
        }
        needsRestart = false
        if let bank = bankProvider() {
            restartState = .running("Test des LLM…")
            llmHealth = try? await client.llmHealth(bank)
        }
        let bad = llmHealth?.operations.filter { !$0.ok } ?? []
        restartState =
            bad.isEmpty
            ? .succeeded(llmHealth == nil ? "Serveur redémarré." : "Serveur redémarré ; tous les LLM répondent.")
            : .failed("Serveur redémarré, mais : " + bad.map { "\($0.operation) → \($0.status)" }.joined(separator: ", "))
    }
}
