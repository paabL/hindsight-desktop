import Foundation

/// Choix courts pour le sélecteur. Un catalogue propose des modèles ; le test LLM du serveur
/// reste la vérification de leur accès effectif pour le compte configuré.
public enum LLMModelCatalog {
    public struct Choice: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String

        public init(_ id: String, _ title: String? = nil) {
            self.id = id
            self.title = title ?? id
        }
    }

    /// Références vérifiées le 20 octobre 2026 : docs OpenAI Models, Claude Code Model configuration
    /// et Gemini API Models. Les identifiants déjà configurés sont conservés même hors de cette liste.
    /// Les alias de Claude Code suivent la dernière version de chaque famille (5.5 au 8 novembre 2026) :
    /// le titre la nomme, l'alias enregistré reste celui qui suit les mises à jour.
    public static func suggestions(for provider: String) -> [Choice] {
        switch provider {
        case "claude-code":
            return [Choice("sonnet", "Claude Sonnet 5.5"), Choice("opus", "Claude Opus 5.5"), Choice("haiku", "Claude Haiku 5.5")]
        case "gemini":
            return [Choice("gemini-3.8-flash", "Gemini 3.8 Flash"), Choice("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite"),
                    Choice("gemini-4-argon", "Gemini 4 Argon")]
        case "openai", "openai-responses", "openai-codex", "chatgpt":
            return [Choice("gpt-6.1-sol", "GPT-6.1 Sol"), Choice("gpt-6-astra", "GPT-6 Astra"), Choice("gpt-6-luna", "GPT-6 Luna")]
        case "lmstudio":
            return [Choice("local-model", "Modèle chargé dans LM Studio")]
        default:
            return ServerSettingsCatalog.defaultModel(for: provider).map { [Choice($0)] } ?? []
        }
    }

    public static func choices(for provider: String, configured: [String], codexModels: [Choice] = []) -> [Choice] {
        let suggestions = ["openai-codex", "chatgpt"].contains(provider) && !codexModels.isEmpty ? codexModels : suggestions(for: provider)
        let titles = Dictionary(suggestions.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        return (configured.map { Choice($0, titles[$0] ?? readableTitle($0)) } + suggestions).filter {
            validID($0.id) && seen.insert($0.id).inserted
        }
    }

    /// Nom lisible d'un identifiant hors catalogue : « claude-haiku-5-5 » → « Claude Haiku 5.5 »,
    /// « gpt-6-luna » → « GPT-6 Luna ». Un identifiant inconnu reste tel quel plutôt que d'être deviné.
    public static func readableTitle(_ id: String) -> String? {
        let parts = id.lowercased().split(separator: "-").map(String.init)
        if parts.count >= 4, parts[0] == "claude", Int(parts[2]) != nil, Int(parts[3]) != nil {
            return "Claude \(parts[1].capitalized) \(parts[2]).\(parts[3])"
        }
        if parts.count >= 3, parts[0] == "claude", Int(parts[2]) != nil {
            return "Claude \(parts[1].capitalized) \(parts[2])"
        }
        if parts.count >= 2, parts[0] == "gpt", parts[1].first?.isNumber == true {
            return (["GPT-\(parts[1])"] + parts.dropFirst(2).map(\.capitalized)).joined(separator: " ")
        }
        return nil
    }

    /// Lecture du catalogue public local uniquement, jamais d'auth.json ni de config contenant des secrets.
    public static func readCodexModels(home: String) -> [Choice] {
        let file = URL(fileURLWithPath: home).appendingPathComponent("models_cache.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: file) else { return [] }
        return codexModels(from: data)
    }

    static func codexModels(from data: Data) -> [Choice] {
        struct Cache: Decodable { let models: [Model] }
        struct Model: Decodable {
            let slug: String
            let display_name: String?
            let visibility: String?
            let priority: Int?
        }
        guard data.count <= 2_000_000, let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }
        let models = cache.models.filter { $0.visibility == "list" && validID($0.slug) }.sorted {
            if ($0.priority ?? Int.max) != ($1.priority ?? Int.max) { return ($0.priority ?? Int.max) < ($1.priority ?? Int.max) }
            return $0.slug < $1.slug
        }
        var seen: Set<String> = []
        return Array(models.filter { seen.insert($0.slug).inserted }.prefix(8)).map {
            Choice($0.slug, $0.display_name.flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 && !id.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue == 0 })
    }
}
