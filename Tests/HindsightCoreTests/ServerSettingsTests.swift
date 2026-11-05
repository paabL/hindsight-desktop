import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

final class LaunchScriptTests: XCTestCase {
    var sample: String { Fixture.string("start-api", ext: "sh") }

    func testParsesAssignmentsQuotesCommentsAndLastWins() {
        let s = LaunchScript(text: sample)
        XCTAssertEqual(s.value("HINDSIGHT_API_LLM_PROVIDER"), "claude-code")
        XCTAssertEqual(s.value("HINDSIGHT_API_VLM_PROVIDER"), "gemini")
        XCTAssertEqual(s.value("HINDSIGHT_API_LLM_MODEL"), "claude-sonnet-4-5-20250929", "la dernière affectation l'emporte")
        XCTAssertEqual(s.occurrences("HINDSIGHT_API_LLM_MODEL"), 2)
        XCTAssertEqual(s.value("HINDSIGHT_API_WORKER_MAX_SLOTS"), "2")
        XCTAssertFalse(s.assignment("HINDSIGHT_API_WORKER_MAX_SLOTS")!.exported)
        XCTAssertTrue(s.assignment("HINDSIGHT_API_RERANKER_COHERE_API_KEY")!.isDynamic)
        XCTAssertNil(s.value("HINDSIGHT_API_RETAIN_LLM_PROVIDER"))
        XCTAssertEqual(s.text, sample, "relecture sans perte")
    }

    func testWarnings() {
        let w = LaunchScript(text: sample + "HINDSIGHT_API_PORT=9000 exec other\n").warnings
        XCTAssertTrue(w.contains { $0.contains("charge un autre fichier") })
        XCTAssertTrue(w.contains { $0.contains("ligne de commande") })
        XCTAssertTrue(w.contains { $0.contains("HINDSIGHT_API_RERANKER_COHERE_API_KEY") && $0.contains("dépend de l'environnement") })
    }

    func testSetPreservesStyleAndOtherLines() {
        var s = LaunchScript(text: sample)
        s.set("HINDSIGHT_API_LLM_MODEL", to: "claude-opus-4")
        s.set("HINDSIGHT_API_VLM_PROVIDER", to: "openai")
        let lines = s.lines
        XCTAssertTrue(lines.contains("export HINDSIGHT_API_LLM_MODEL=claude-opus-4"))
        XCTAssertTrue(lines.contains("export HINDSIGHT_API_VLM_PROVIDER='openai'"), "style de guillemets conservé")
        XCTAssertTrue(lines.contains(#"export HINDSIGHT_API_LLM_MODEL="claude-sonnet-4-5"   # modèle principal"#), "la première affectation n'est pas touchée")
        let diff = LineDiff.diff(LaunchScript(text: sample).lines, lines).filter { $0.kind != .same }
        XCTAssertEqual(diff.count, 4, "deux lignes retirées, deux ajoutées")
        XCTAssertTrue(s.text.hasSuffix("exec hindsight-api --port 8888\n"))
    }

    func testCommentsKeepTheirPlaceWhenEditingAQuotedValue() {
        var s = LaunchScript(text: "export HINDSIGHT_API_LLM_MODEL=\"a\"  # note\n")
        s.set("HINDSIGHT_API_LLM_MODEL", to: "b c")
        XCTAssertEqual(s.text, "export HINDSIGHT_API_LLM_MODEL=\"b c\"  # note\n")
        XCTAssertEqual(LaunchScript(text: s.text).value("HINDSIGHT_API_LLM_MODEL"), "b c")
    }

    func testQuotingRoundTripsAwkwardValues() {
        for v in ["simple", "avec espace", "l'apostrophe", #"guillemet " et $DOLLAR"#, "a\\b", "{\"json\": [1, 2]}", "x=y"] {
            var s = LaunchScript(text: "#!/bin/sh\nexec x\n")
            s.set("HINDSIGHT_API_X", to: v)
            XCTAssertEqual(LaunchScript(text: s.text).value("HINDSIGHT_API_X"), v, v)
            XCTAssertFalse(LaunchScript(text: s.text).assignment("HINDSIGHT_API_X")!.isDynamic, v)
        }
    }

    func testAddInsertsAfterLastHindsightAssignmentAndUnsetComments() {
        var s = LaunchScript(text: sample)
        s.set("HINDSIGHT_API_RETAIN_LLM_PROVIDER", to: "gemini")
        let i = s.lines.firstIndex(of: "export HINDSIGHT_API_RETAIN_LLM_PROVIDER=gemini")!
        XCTAssertEqual(s.lines[i - 1], "export HINDSIGHT_API_LLM_MODEL=claude-sonnet-4-5-20250929")
        s.unset("HINDSIGHT_API_LLM_MODEL")
        XCTAssertNil(s.value("HINDSIGHT_API_LLM_MODEL"))
        XCTAssertEqual(s.lines.filter { $0.hasPrefix("# export HINDSIGHT_API_LLM_MODEL=") }.count, 2)
        // Réactivation à la place de la ligne commentée.
        s.set("HINDSIGHT_API_LLM_MODEL", to: "m2")
        XCTAssertEqual(s.value("HINDSIGHT_API_LLM_MODEL"), "m2")
        var empty = LaunchScript(text: "#!/bin/bash\nset -e\nexec hindsight-api\n")
        empty.set("HINDSIGHT_API_LLM_PROVIDER", to: "openai")
        XCTAssertEqual(empty.lines, ["#!/bin/bash", "set -e", "export HINDSIGHT_API_LLM_PROVIDER=openai", "exec hindsight-api"])
    }

    func testSecretsAreMasked() {
        XCTAssertTrue(LaunchScript.isSecret("HINDSIGHT_API_VLM_API_KEY"))
        XCTAssertTrue(LaunchScript.isSecret("HINDSIGHT_API_MCP_AUTH_TOKEN"))
        XCTAssertFalse(LaunchScript.isSecret("HINDSIGHT_API_DECISION_MODEL_MAX_REQUEST_TOKENS"), "un nombre de jetons s'affiche")
        XCTAssertFalse(LaunchScript.isSecret("HINDSIGHT_API_TOKENIZER_ENCODING"))
        XCTAssertTrue(LaunchScript.isSecret("HINDSIGHT_API_DATABASE_URL"))
        XCTAssertFalse(LaunchScript.isSecret("HINDSIGHT_API_LLM_MODEL"))
        let m = LaunchScript.masked(#"export HINDSIGHT_API_VLM_API_KEY="AIzaFAKEFAKEFAKEFAKE1234""#)
        XCTAssertFalse(m.contains("AIza"))
        XCTAssertEqual(m, "export HINDSIGHT_API_VLM_API_KEY=••••34")
        XCTAssertFalse(LaunchScript.masked("# export HINDSIGHT_API_VLM_API_KEY=sk-private-secret").contains("sk-private"))
    }

    func testCompactDiff() {
        let old = (1...20).map { "l\($0)" }
        var new = old
        new[9] = "changé"
        let d = LineDiff.compact(LineDiff.diff(old, new), context: 1)
        XCTAssertEqual(d.map(\.text), ["l9", "l10", "changé", "l11"])  // suppression puis ajout
        XCTAssertEqual(d.first { $0.kind == .removed }?.oldNumber, 10)
        XCTAssertTrue(LineDiff.compact(LineDiff.diff(old, old)).isEmpty)
    }
}

final class LaunchScriptStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-store-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeScript(_ text: String = "#!/bin/sh\nexport HINDSIGHT_API_LLM_MODEL=a\n") -> URL {
        let u = dir.appendingPathComponent("start.sh")
        try! Data(text.utf8).write(to: u)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return u
    }

    func testSaveBacksUpAndKeepsPermissions() throws {
        let u = makeScript()
        let store = LaunchScriptStore(url: u)
        let original = try store.read()
        let backup = try store.save("#!/bin/sh\nexport HINDSIGHT_API_LLM_MODEL=b\n", expecting: original)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
        XCTAssertTrue(try store.read().contains("=b"))
        let perms = try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o755)
        XCTAssertEqual(store.backups().count, 1)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("start.sh.bak-"))
    }

    func testRefusesToOverwriteAConcurrentEdit() throws {
        let u = makeScript()
        let store = LaunchScriptStore(url: u)
        let original = try store.read()
        try Data("modifié ailleurs\n".utf8).write(to: u)
        XCTAssertThrowsError(try store.save("x\n", expecting: original)) { e in
            XCTAssertTrue("\(e)".contains("modifié sur le disque"))
        }
        XCTAssertEqual(try store.read(), "modifié ailleurs\n")
        XCTAssertTrue(store.backups().isEmpty)
    }

    func testRestoreBacksUpCurrentFirst() throws {
        let u = makeScript()
        let store = LaunchScriptStore(url: u)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try store.save("v2\n", expecting: try store.read(), now: t0)
        let b = store.backups()[0]
        try store.restore(b, now: t0.addingTimeInterval(1))
        XCTAssertTrue(try store.read().contains("=a"))
        XCTAssertEqual(store.backups().count, 2)
    }

    func testMissingFile() {
        let store = LaunchScriptStore(url: dir.appendingPathComponent("absent.sh"))
        XCTAssertThrowsError(try store.read()) { XCTAssertTrue("\($0)".contains("introuvable")) }
    }

    func testSymlinkIsFollowed() throws {
        let real = makeScript()
        let link = dir.appendingPathComponent("link.sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = LaunchScriptStore(url: link)
        try store.save("v2\n", expecting: try store.read())
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "v2\n")
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink, "le lien reste un lien")
    }
}

/// Faux exécuteur de commande.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    var commands: [String] = []
    var result = CommandResult(status: 0, output: "ok\n")
    var onRun: (() -> Void)?
    func run(_ command: String, timeout: TimeInterval) async throws -> CommandResult {
        commands.append(command)
        onRun?()
        return result
    }
}

@MainActor
final class ServerSettingsViewModelTests: XCTestCase {
    nonisolated(unsafe) var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-vm-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func make(_ t: MockTransport = MockTransport(), runner: FakeRunner = FakeRunner()) -> (ServerSettingsViewModel, URL, InMemorySettingsStore) {
        let u = dir.appendingPathComponent("start-api.sh")
        try! Data(Fixture.string("start-api", ext: "sh").utf8).write(to: u)
        let store = InMemorySettingsStore([SettingsKey.launchScriptPath: u.path])
        let client = makeClient(t)
        let vm = ServerSettingsViewModel(
            settings: store, runner: runner, client: { client }, bank: { testBank }, healthTimeout: 2, pollInterval: .milliseconds(50))
        return (vm, u, store)
    }

    func testRolesShowEffectiveValuesWithInheritance() async throws {
        let (vm, _, _) = make()
        await vm.load()
        let roles = Dictionary(uniqueKeysWithValues: vm.roles.map { ($0.role.id, $0) })
        XCTAssertEqual(roles["default"]?.effective, "claude-code · claude-sonnet-4-5-20250929")
        XCTAssertEqual(roles["retain"]?.effective, "claude-code · claude-sonnet-4-5-20250929 — hérité du LLM par défaut")
        XCTAssertEqual(roles["vlm"]?.effective, "gemini · gemini-3.5-flash (défaut)")
        XCTAssertEqual(roles["default"]?.fields.first { $0.name == "HINDSIGHT_API_LLM_MODEL" }?.occurrences, 2)
        XCTAssertEqual(vm.otherVariables.map(\.name), ["HINDSIGHT_API_WORKER_MAX_SLOTS"])
        XCTAssertFalse(vm.hasChanges)
        XCTAssertEqual(vm.warnings.count, 2)
    }

    func testLocalHindsightRerankerIsPreparedInTheDraftOnly() async throws {
        let (vm, u, _) = make()
        await vm.load()
        XCTAssertEqual(vm.rerankerSource, .other, "Cohere")
        vm.useLocalHindsightReranker()
        XCTAssertEqual(vm.rerankerSource, .local)
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_RERANKER_PROVIDER"), "local")
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_RERANKER_LOCAL_MODEL"), "hindsight-ai/hs-rerank-1")
        XCTAssertNotNil(vm.draft?.value("HINDSIGHT_API_RERANKER_COHERE_API_KEY"), "Cohere reste dans le script")
        XCTAssertFalse(try String(contentsOf: u, encoding: .utf8).contains("hs-rerank-1"), "rien n'est écrit avant l'enregistrement confirmé")
        vm.useCloudReranker()
        XCTAssertEqual(vm.rerankerSource, .cloud)
        vm.revertAll()
        XCTAssertEqual(vm.rerankerSource, .other)
    }

    func testServiceSummariesSelectOnlyTheActiveProvidersModel() async throws {
        let (vm, file, _) = make()
        await vm.load()
        let saved = try String(contentsOf: file, encoding: .utf8)
        func summary(_ id: String) -> String { vm.roles.first { $0.id == id }!.effective }
        vm.setValue("HINDSIGHT_API_RERANKER_COHERE_MODEL", "saved-cohere")
        vm.setValue("HINDSIGHT_API_RERANKER_LOCAL_MODEL", "saved-local")
        vm.setValue("HINDSIGHT_API_RERANKER_GOOGLE_MODEL", "google-ranking")
        for (provider, model) in [("local", "saved-local"), ("hindsight", "hs-rerank-1"), ("cohere", "saved-cohere"), ("google", "google-ranking")] {
            vm.setValue("HINDSIGHT_API_RERANKER_PROVIDER", provider)
            XCTAssertEqual(summary("reranker"), "\(provider) · \(model)")
        }
        vm.setValue("HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL", "saved-gemini")
        vm.setValue("HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY", "1536")
        vm.setValue("HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL", "saved-openai")
        for (provider, model) in [("openai", "saved-openai"), ("hindsight", "hs-embed-1"), ("google", "saved-gemini")] {
            vm.setValue("HINDSIGHT_API_EMBEDDINGS_PROVIDER", provider)
            XCTAssertEqual(summary("embeddings"), "\(provider) · \(model)")
            XCTAssertEqual(vm.modelWorkflow?.embeddings, model + (provider == "google" ? " · 1536" : ""))
        }
        vm.setValue("HINDSIGHT_API_EMBEDDINGS_PROVIDER", "litellm")
        XCTAssertEqual(summary("embeddings"), "litellm · modèle par défaut", "Do not borrow a text-generation model default")
        vm.setValue("HINDSIGHT_API_RERANKER_PROVIDER", nil)
        XCTAssertEqual(summary("reranker"), "local · saved-local")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), saved)
    }

    func testDecisionModelPresetsSwitchBetweenCloudLocalAndOff() async throws {
        let (vm, _, _) = make()
        await vm.load()
        XCTAssertEqual(vm.decisionModelSource, .off)
        vm.useLocalDecisionModel(apiKey: "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(vm.decisionModelSource, .local)
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_DECISION_MODEL_PROVIDER"), "hindsight")
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_DECISION_MODEL_BASE_URL"), "http://127.0.0.1:8766")
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_DECISION_MODEL_MAX_CONCURRENT"), "2")
        XCTAssertTrue(vm.diff.allSatisfy { !$0.text.contains("0123456789abcdef") }, "clé masquée dans le diff")

        XCTAssertFalse(vm.cloudModelsUseAccountKey)
        vm.useCloudDecisionModel()
        XCTAssertEqual(vm.decisionModelSource, .cloud)
        for name in ["BASE_URL", "API_KEY", "MAX_CONCURRENT", "TIMEOUT", "MAX_REQUEST_TOKENS"] {
            XCTAssertNil(vm.draft?.value("HINDSIGHT_API_DECISION_MODEL_" + name), "\(name) : la clé locale n'irait pas au cloud")
        }
        XCTAssertTrue(vm.cloudModelsUseAccountKey, "sans clé dans le script, le serveur prend celle du compte")
        vm.setValue("HINDSIGHT_API_DECISION_MODEL_API_KEY", "hsk_0123456789abcdefghij")
        vm.useCloudDecisionModel()
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_DECISION_MODEL_API_KEY"), "hsk_0123456789abcdefghij", "clé du compte gardée")
        XCTAssertFalse(vm.cloudModelsUseAccountKey)
        vm.useCloudReranker()
        XCTAssertTrue(vm.cloudModelsUseAccountKey, "le reranker cloud n'a pas de clé à lui")
        vm.useLocalHindsightReranker()

        vm.disableDecisionModel()
        XCTAssertEqual(vm.decisionModelSource, .off)
        vm.setValue("HINDSIGHT_API_DECISION_MODEL_PROVIDER", "typesafe")
        XCTAssertEqual(vm.decisionModelSource, .other)
    }

    func testEditingShowsMaskedDiffAndSummary() async throws {
        let (vm, _, _) = make()
        await vm.load()
        vm.setValue("HINDSIGHT_API_RETAIN_LLM_PROVIDER", "gemini")
        vm.setValue("HINDSIGHT_API_RETAIN_LLM_MODEL", "gemini-3.5-flash")
        vm.setValue("HINDSIGHT_API_VLM_API_KEY", "AIzaNEWNEWNEWNEW9999")
        XCTAssertTrue(vm.hasChanges)
        let roles = Dictionary(uniqueKeysWithValues: vm.roles.map { ($0.role.id, $0) })
        XCTAssertEqual(roles["retain"]?.effective, "gemini · gemini-3.5-flash")
        XCTAssertTrue(roles["retain"]!.isChanged)
        let diffText = vm.diff.map(\.text).joined(separator: "\n")
        XCTAssertFalse(diffText.contains("AIza"), "aucun secret dans le diff")
        XCTAssertTrue(vm.changeSummary.contains("HINDSIGHT_API_RETAIN_LLM_MODEL : (non défini) → « gemini-3.5-flash »"))
        XCTAssertTrue(vm.changeSummary.contains { $0.hasPrefix("HINDSIGHT_API_VLM_API_KEY : « ••••34 » → « ••••99 »") })
        vm.revert("HINDSIGHT_API_VLM_API_KEY")
        XCTAssertEqual(vm.changeSummary.count, 2)
        vm.revertAll()
        XCTAssertFalse(vm.hasChanges)
    }

    func testDynamicValuesAreUnchangedUntilExplicitlyReplacedAndCanBeRestoredExactly() async throws {
        let (vm, url, _) = make()
        let script = """
        #!/bin/sh
        export HINDSIGHT_API_LLM_PROVIDER=claude-code
        # export HINDSIGHT_API_LLM_API_KEY=old
        export HINDSIGHT_API_LLM_API_KEY="${MY_TOKEN}" # keep this reference
        export HINDSIGHT_API_LLM_CODEX_HOME="$HOME/.codex-team"
        exec hindsight-api

        """
        try Data(script.utf8).write(to: url)
        await vm.load()
        for field in vm.roles.flatMap(\.fields) where field.isDynamic { vm.setValue(field.name, field.value) }
        XCTAssertFalse(vm.hasChanges)
        XCTAssertTrue(vm.actionableWarnings.isEmpty)
        XCTAssertEqual(vm.connectionContext.codexHome, NSHomeDirectory() + "/.codex-team")
        vm.setValue("HINDSIGHT_API_LLM_API_KEY", "replacement")
        XCTAssertEqual(vm.actionableWarnings.count, 1)
        vm.revert("HINDSIGHT_API_LLM_API_KEY")
        XCTAssertEqual(vm.draft?.text, script)
        XCTAssertEqual(vm.draft?.assignment("HINDSIGHT_API_LLM_API_KEY")?.isDynamic, true)
        vm.setValue("HINDSIGHT_API_LLM_API_KEY", nil)
        vm.revert("HINDSIGHT_API_LLM_API_KEY")
        XCTAssertEqual(vm.draft?.text, script)
        XCTAssertFalse(vm.hasChanges)
    }

    func testCompactProviderChoicesKeepCustomProvidersAndRoleInheritanceFollowsReflect() async throws {
        let (vm, _, _) = make()
        await vm.load()
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_PROVIDER", "custom-proxy")
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_MODEL", "my-model")
        XCTAssertEqual(vm.providerChoices.count, ServerSettingsCatalog.suggestedProviders.count + 1)
        XCTAssertTrue(vm.providerChoices.contains { $0.id == "custom-proxy" })
        XCTAssertEqual(vm.resolvedValue(for: "mental_model", suffix: "MODEL"), "my-model")
        XCTAssertTrue(vm.modelRoles.first { $0.id == "mental_model" }!.effective.contains("custom-proxy · my-model"))
        XCTAssertEqual(vm.modelRoles.count, 6)
        let before = vm.draft
        vm.selectProvider("openai-codex", forRole: "retain")
        XCTAssertEqual(vm.resolvedValue(for: "retain", suffix: "PROVIDER"), "openai-codex")
        XCTAssertTrue(vm.hasChanges)
        vm.restoreDraft(before!)
        XCTAssertEqual(vm.draft, before)
        vm.useInheritedSettings(forRole: "reflect")
        XCTAssertEqual(vm.resolvedValue(for: "mental_model", suffix: "PROVIDER"), "claude-code")
    }

    func testConnectionDirectoryRespectsShellQuotingAndEmptyOverrideFallback() async throws {
        let (vm, url, _) = make()
        try Data("""
        export CODEX_HOME=/tmp/hs-profile
        export HINDSIGHT_API_LLM_CODEX_HOME=""
        """.utf8).write(to: url)
        await vm.load()
        XCTAssertEqual(vm.connectionContext.codexHome, "/tmp/hs-profile")
        try Data("export HINDSIGHT_API_LLM_CODEX_HOME='$HOME/.codex'\n".utf8).write(to: url)
        await vm.load()
        XCTAssertNil(vm.connectionContext.codexHome, "une chaîne littérale ne devient pas une expansion shell")
        try Data("export HINDSIGHT_API_LLM_CODEX_HOME=\"~/.codex\"\n".utf8).write(to: url)
        await vm.load()
        XCTAssertNil(vm.connectionContext.codexHome, "un tilde entre guillemets n'est pas développé par le shell")
    }

    func testModelMenuPreservesCurrentSettingsAndWritesTheSelectedIdentifier() async throws {
        let (vm, _, _) = make()
        await vm.load()
        let before = try XCTUnwrap(vm.draft)
        let choices = vm.modelChoices(forRole: "default")
        XCTAssertTrue(choices.contains { $0.id == "claude-sonnet-4-5-20250929" })
        let haiku = try XCTUnwrap(choices.first { $0.title == "Claude Haiku" })
        XCTAssertEqual(vm.draft, before, "ouvrir le menu ne change pas le modèle")
        XCTAssertFalse(vm.hasChanges)
        vm.setValue("HINDSIGHT_API_LLM_MODEL", haiku.id)
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_LLM_MODEL"), "haiku")
        vm.revert("HINDSIGHT_API_LLM_MODEL")
        XCTAssertEqual(vm.draft, before)
        vm.selectProvider("gemini", forRole: "retain")
        vm.setValue("HINDSIGHT_API_RETAIN_LLM_MODEL", "custom-gemini-model")
        let gemini = vm.modelChoices(forRole: "retain")
        XCTAssertTrue(gemini.contains { $0.id == "custom-gemini-model" })
        XCTAssertTrue(gemini.contains { $0.id == "gemini-3.8-flash" })
        XCTAssertFalse(gemini.contains { $0.id == "haiku" })
    }

    func testModelMenusPreviewEachProviderWithoutChangingDraft() async throws {
        let (vm, file, _) = make()
        await vm.load()
        let originalFile = try String(contentsOf: file, encoding: .utf8)
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_PROVIDER", "custom-proxy")
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_MODEL", "custom-model")
        let before = vm.draft
        let menus = vm.modelsByProvider
        XCTAssertTrue(menus["claude-code"]!.contains { $0.id == "claude-sonnet-4-5-20250929" })
        XCTAssertTrue(menus["openai-codex"]!.contains { $0.id.hasPrefix("gpt-") })
        XCTAssertFalse(menus["openai-codex"]!.contains { $0.id.contains("claude") || $0.id == "custom-model" })
        XCTAssertEqual(menus["custom-proxy"]?.map(\.id), ["custom-model"])
        XCTAssertEqual(vm.draft, before, "ouvrir un menu ne prépare aucun changement")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), originalFile)
    }

    func testEmbeddingChangeWarns() async {
        let (vm, _, _) = make()
        await vm.load()
        vm.setValue("HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY", "768")
        XCTAssertTrue(vm.warnings.first?.contains("incompatibles") == true)
    }

    func testNewCloudRerankerWithoutCredentialsCannotOverwriteWorkingScript() async throws {
        let (vm, url, _) = make()
        await vm.load()
        let before = try Data(contentsOf: url)
        vm.useCloudReranker()
        XCTAssertFalse(vm.configurationProblems.isEmpty)
        vm.requestSave()
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(try Data(contentsOf: url), before)
        vm.useLocalHindsightReranker()
        XCTAssertTrue(vm.configurationProblems.isEmpty)
        vm.requestSave()
        let confirmation = try XCTUnwrap(vm.confirmation)
        await confirmation.perform()
        XCTAssertEqual(LaunchScript(text: try String(contentsOf: url, encoding: .utf8)).value("HINDSIGHT_API_RERANKER_PROVIDER"), "local")
    }

    func testRestartNoticeClearsOnlyForTheConfirmedScriptThatActuallyStarted() async throws {
        let (vm, file, _) = make()
        await vm.load()
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_MODEL", "fixture-model")
        vm.requestSave()
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.needsRestart)
        let hash = SHA256.hex(try Data(contentsOf: file))
        vm.acknowledgeStartedScript("older-script")
        XCTAssertTrue(vm.needsRestart)
        let saved = try Data(contentsOf: file)
        try Data("# externally modified\n".utf8).write(to: file)
        vm.acknowledgeStartedScript(hash)
        XCTAssertTrue(vm.needsRestart)
        try saved.write(to: file)
        vm.acknowledgeStartedScript(hash)
        XCTAssertFalse(vm.needsRestart)
    }

    func testExplicitCloudKeyIsAccepted() async {
        let (vm, _, _) = make()
        await vm.load()
        vm.useCloudReranker()
        vm.setValue("HINDSIGHT_API_RERANKER_HINDSIGHT_API_KEY", "fixture-key-only")
        XCTAssertTrue(vm.configurationProblems.isEmpty)
    }

    func testSaveRequiresConfirmationAndBacksUp() async throws {
        let (vm, url, _) = make()
        await vm.load()
        vm.setValue("HINDSIGHT_API_REFLECT_LLM_MODEL", "claude-opus-4")
        vm.requestSave()
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(c.message.contains("HINDSIGHT_API_REFLECT_LLM_MODEL"))
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("REFLECT"), "rien n'est écrit avant confirmation")
        await c.perform()
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("export HINDSIGHT_API_REFLECT_LLM_MODEL=claude-opus-4"))
        XCTAssertEqual(vm.backups.count, 1)
        XCTAssertTrue(vm.needsRestart)
        XCTAssertFalse(vm.hasChanges, "rechargé après enregistrement")
        XCTAssertTrue(vm.actionMessage!.contains(".bak-"))
    }

    func testAddVariableValidatesName() async {
        let (vm, _, _) = make()
        await vm.load()
        XCTAssertFalse(vm.addVariable("bad name", "x"))
        XCTAssertFalse(vm.addVariable("LLM_TIMEOUT", ""))
        XCTAssertTrue(vm.addVariable("llm_timeout", "120"))
        XCTAssertEqual(vm.draft?.value("HINDSIGHT_API_LLM_TIMEOUT"), "120")
    }

    func testMissingScriptIsReported() async {
        let store = InMemorySettingsStore([SettingsKey.launchScriptPath: dir.appendingPathComponent("nope.sh").path])
        let c = makeClient(MockTransport())
        let vm = ServerSettingsViewModel(settings: store, runner: FakeRunner(), client: { c }, bank: { nil })
        await vm.load()
        XCTAssertTrue(vm.state.errorMessage?.contains("introuvable") == true)
        XCTAssertTrue(vm.roles.isEmpty)
    }

    func testRestartRunsCommandWaitsForAPIAndTestsLLMs() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("POST", "\(bankPath)/health/llm", json: #"{"bank_id":"b","operations":[{"operation":"retain","ok":true,"status":"connected"},{"operation":"reflect","ok":false,"status":"auth_failed"}]}"#)
        let runner = FakeRunner()
        let (vm, _, store) = make(t, runner: runner)
        await vm.load()
        vm.requestRestart()
        XCTAssertNil(vm.confirmation, "pas de commande configurée")
        XCTAssertNotNil(vm.actionMessage)
        vm.restartCommand = "launchctl kickstart -k gui/501/local.hindsight"
        vm.requestRestart()
        XCTAssertTrue(runner.commands.isEmpty)
        XCTAssertEqual(store.string(forKey: SettingsKey.restartCommand), "launchctl kickstart -k gui/501/local.hindsight")
        await vm.confirmation!.perform()
        XCTAssertEqual(runner.commands, ["launchctl kickstart -k gui/501/local.hindsight"])
        guard case .failed(let msg) = vm.restartState else { return XCTFail("\(vm.restartState)") }
        XCTAssertTrue(msg.contains("reflect → auth_failed"), msg)
        XCTAssertEqual(vm.llmHealth?.operations.count, 2)
        XCTAssertTrue(vm.restartLog.contains("ok"))
    }

    func testRestartReportsAPINotComingBack() async throws {
        let t = MockTransport()
        t.on("GET", "/version", json: #"{"detail":"down"}"#, status: 502)
        let (vm, _, _) = make(t)
        await vm.restart("true")
        guard case .failed(let msg) = vm.restartState else { return XCTFail("\(vm.restartState)") }
        XCTAssertTrue(msg.contains("ne répond pas"))
    }

    func testRestartReportsFailingCommand() async {
        let runner = FakeRunner()
        runner.result = CommandResult(status: 127, output: "command not found\n")
        let (vm, _, _) = make(runner: runner)
        await vm.restart("nope")
        XCTAssertEqual(vm.restartState, .failed("La commande a échoué (code 127)."))
        XCTAssertTrue(vm.restartLog.contains("command not found"))
    }

    func testShellRunnerCapturesOutput() async throws {
        let r = try await ShellCommandRunner().run("echo bonjour; echo erreur >&2; exit 3", timeout: 10)
        XCTAssertEqual(r.status, 3)
        XCTAssertTrue(r.output.contains("bonjour"))
        XCTAssertTrue(r.output.contains("erreur"))
    }
}

/// Serveur 1.1.0 : fournisseur chatgpt (abonnement) et modèle de décision.
@MainActor
final class Server110CatalogTests: XCTestCase {
    func testChatGPTIsASubscriptionAndDecisionRoleUsesServerNames() {
        XCTAssertTrue(PriceBook.defaults.subscriptionProviders.contains("chatgpt"))
        let store = InMemorySettingsStore()
        var old = PriceBook.defaults
        old.subscriptionProviders = ["claude-code"]
        old.save(to: store)
        XCTAssertTrue(PriceBook.load(from: store).subscriptionProviders.contains("chatgpt"), "grille enregistrée avant 1.1.0")
        let decision = ServerSettingsCatalog.roles.first { $0.id == "decision" }
        XCTAssertEqual(decision?.fields.first?.name, "HINDSIGHT_API_DECISION_MODEL_PROVIDER")
        XCTAssertTrue(ServerSettingsCatalog.suggestedProviders.contains { $0.id == "chatgpt" })
        XCTAssertEqual(SubscriptionNames.title("chatgpt"), "ChatGPT")
    }
}
