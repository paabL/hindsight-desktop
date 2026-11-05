import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class ModelWorkflowTests: XCTestCase {
    let p = "HINDSIGHT_API_"
    func make(_ extra: String = "") async throws -> (ServerSettingsViewModel, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("models-workflow-\(UUID()).sh")
        let script = """
        #!/bin/bash
        export HINDSIGHT_API_LLM_PROVIDER=openai-codex
        export HINDSIGHT_API_LLM_MODEL=gpt-6-luna
        export HINDSIGHT_API_REFLECT_LLM_PROVIDER=claude-code
        export HINDSIGHT_API_REFLECT_LLM_MODEL=claude-sonnet-5-5
        export HINDSIGHT_API_EMBEDDINGS_PROVIDER=google
        export HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL=gemini-embedding-2
        export HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY=1536
        export HINDSIGHT_API_EMBEDDINGS_GEMINI_API_KEY="$SYNTHETIC_KEY"
        export HINDSIGHT_API_DECISION_MODEL_PROVIDER=hindsight
        export HINDSIGHT_API_DECISION_MODEL_BASE_URL=http://127.0.0.1:8766
        export HINDSIGHT_API_DECISION_MODEL_API_KEY=synthetic-do-not-display
        \(extra)
        exec hindsight-api

        """
        try Data(script.utf8).write(to: file)
        let client = makeClient(MockTransport())
        let vm = ServerSettingsViewModel(settings: InMemorySettingsStore([SettingsKey.launchScriptPath: file.path]), client: { client }, bank: { testBank })
        await vm.load()
        return (vm, file)
    }
    func testRecallIsOptInAndDoesNotDisableReflectWhenTurnedOff() async throws {
        let (vm, file) = try await make(); defer { try? FileManager.default.removeItem(at: file) }
        let original = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(vm.modelWorkflow!.decisions["reflect"]!.enabled)
        XCTAssertFalse(vm.modelWorkflow!.decisions["recall"]!.enabled)
        try vm.prepareModelWorkflow([p + "RECALL_DECISION_MODEL_PROVIDER": "hindsight"], revision: vm.modelWorkflow!.revision)
        XCTAssertTrue(vm.modelWorkflow!.decisions["recall"]!.enabled)
        XCTAssertEqual(vm.modelWorkflow!.decisions["recall"]!.model, "hs-decide-1-flash")
        XCTAssertEqual(vm.modelWorkflow!.decisions["recall"]!.source, "local")
        try vm.prepareModelWorkflow([p + "REFLECT_USE_DECISION_MODEL": "false"], revision: vm.modelWorkflow!.revision)
        XCTAssertTrue(vm.modelWorkflow!.decisions["recall"]!.enabled)
        XCTAssertFalse(vm.modelWorkflow!.decisions["reflect"]!.enabled)
        XCTAssertTrue(vm.modelWorkflow!.decisions["pages"]!.enabled)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original, "Only a draft, no implicit save")
        let wire = String(decoding: try JSONEncoder().encode(vm.modelWorkflow), as: UTF8.self)
        XCTAssertFalse(wire.contains("synthetic-do-not-display"))
        XCTAssertFalse(wire.contains("SYNTHETIC_KEY"))
    }
    func testPerOperationOverridesAreResolvedWithoutBorrowingAnotherProvidersSettings() async throws {
        let (vm, file) = try await make("""
        export HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER=openai
        export HINDSIGHT_API_REFLECT_DECISION_MODEL_MODEL=custom-decision
        export HINDSIGHT_API_REFLECT_DECISION_MODEL_BASE_URL=https://example.invalid
        export HINDSIGHT_API_REFLECT_DECISION_MODEL_API_KEY=separate-private-key
        """); defer { try? FileManager.default.removeItem(at: file) }
        let w = vm.modelWorkflow!
        XCTAssertEqual(w.decisions["recall"]!.model, "", "Must not inherit hindsight model across providers")
        XCTAssertEqual(w.decisions["recall"]!.source, "other")
        XCTAssertFalse(w.decisions["recall"]!.shared)
        XCTAssertEqual(w.decisions["reflect"]!.model, "custom-decision")
        XCTAssertEqual(w.decisions["pages"]!.model, "custom-decision", "Pages share reflect's decision client")
        XCTAssertFalse(w.decisions["reflect"]!.shared)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(w), as: UTF8.self).contains("separate-private-key"))
    }
    func testAtomicValidationStaleRevisionAndDynamicVariables() async throws {
        let (vm, file) = try await make("export HINDSIGHT_API_REFLECT_USE_DECISION_MODEL=$EXTERNAL_FLAG"); defer { try? FileManager.default.removeItem(at: file) }
        let before = vm.draft!, revision = vm.modelWorkflow!.revision
        XCTAssertTrue(vm.modelWorkflow!.decisions["reflect"]!.uncertain)
        XCTAssertThrowsError(try vm.prepareModelWorkflow([p + "REFLECT_LLM_MODEL": "other", p + "EMBEDDINGS_GEMINI_MODEL": "wrong"], revision: revision))
        XCTAssertEqual(vm.draft, before)
        XCTAssertThrowsError(try vm.prepareModelWorkflow([p + "REFLECT_USE_DECISION_MODEL": "true"], revision: revision))
        XCTAssertThrowsError(try vm.prepareModelWorkflow([p + "RECALL_DECISION_MODEL_PRUNE": "maybe"], revision: revision))
        try vm.prepareModelWorkflow([p + "REFLECT_LLM_MODEL": "other"], revision: revision)
        let updated = vm.draft
        XCTAssertThrowsError(try vm.prepareModelWorkflow([p + "RECALL_DECISION_MODEL_DEDUP": "true"], revision: revision))
        XCTAssertEqual(vm.draft, updated)
    }
    func testConfirmedSavePreservesEmbeddingLinesAndProducesBackup() async throws {
        let (vm, file) = try await make(); defer { try? FileManager.default.removeItem(at: file); for backup in vm.backups { try? FileManager.default.removeItem(at: backup.url) } }
        let original = vm.original!.text
        let embeddings = vm.original!.lines.filter { $0.contains("EMBEDDINGS_") }
        try vm.prepareModelWorkflow([p + "REFLECT_LLM_MODEL": "claude-haiku-5-5", p + "RECALL_DECISION_MODEL_PRUNE": "true", p + "RECALL_DECISION_MODEL_DEDUP": "true"], revision: vm.modelWorkflow!.revision)
        vm.requestSave()
        XCTAssertNotNil(vm.confirmation)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
        await vm.confirmation?.perform()
        XCTAssertTrue(vm.needsRestart)
        XCTAssertFalse(vm.hasChanges)
        XCTAssertEqual(vm.original!.lines.filter { $0.contains("EMBEDDINGS_") }, embeddings)
        XCTAssertEqual(vm.backups.count, 1)
        XCTAssertEqual(try String(contentsOf: vm.backups[0].url, encoding: .utf8), original)
    }
    func testMixedPageOptionsAndUnsupportedReflectProviderAreNotDisplayedAsActive() async throws {
        let (vm, file) = try await make("export HINDSIGHT_API_MENTAL_MODEL_REFRESH_USE_DECISION_MODEL=false"); defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(vm.modelWorkflow!.decisions["pages"]!.partial)
        vm.setValue(p + "REFLECT_DECISION_MODEL_PROVIDER", "openai")
        XCTAssertFalse(vm.modelWorkflow!.decisions["reflect"]!.configured)
        XCTAssertFalse(vm.modelWorkflow!.decisions["pages"]!.enabled)
        XCTAssertTrue(vm.modelWorkflow!.decisions["consolidation"]!.enabled)
    }
}
