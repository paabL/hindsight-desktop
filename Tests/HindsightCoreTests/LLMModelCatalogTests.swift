import Foundation
import XCTest
@testable import HindsightCore

final class LLMModelCatalogTests: XCTestCase {
    func testConfiguredModelsRemainSelectableWithoutDuplicatingSuggestions() {
        let choices = LLMModelCatalog.choices(for: "claude-code", configured: ["my-deployment", "sonnet", "my-deployment"])
        XCTAssertEqual(choices.map(\.id), ["my-deployment", "sonnet", "opus", "haiku"])
        XCTAssertEqual(choices.first { $0.id == "sonnet" }?.title, "Claude Sonnet")
        XCTAssertFalse(choices.contains { $0.id.hasPrefix("gemini-") })
    }

    func testCodexCacheFiltersHiddenModelsAndOrdersVisibleChoices() {
        let data = Data(#"{"models":[{"slug":"second","display_name":"Second model","visibility":"list","priority":2},{"slug":"internal","visibility":"hide","priority":0},{"slug":"first","display_name":"First model","visibility":"list","priority":1},{"slug":"first","visibility":"list","priority":3},{"slug":"","visibility":"list","priority":0}]}"#.utf8)
        let models = LLMModelCatalog.codexModels(from: data)
        XCTAssertEqual(models.map(\.id), ["first", "second"])
        XCTAssertEqual(models.first?.title, "First model")
        let choices = LLMModelCatalog.choices(for: "openai-codex", configured: ["old-configured-model"], codexModels: models)
        XCTAssertEqual(choices.map(\.id), ["old-configured-model", "first", "second"])
        XCTAssertFalse(choices.contains { $0.id == "internal" })
        XCTAssertTrue(LLMModelCatalog.choices(for: "gemini", configured: [], codexModels: models).allSatisfy { $0.id.hasPrefix("gemini-") })
    }

    func testCatalogRemainsShortAndFallsBackWhenCacheIsUnavailable() throws {
        let rows = (0..<20).map { ["slug": "model-\($0)", "visibility": "list", "priority": $0] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["models": rows])
        XCTAssertEqual(LLMModelCatalog.codexModels(from: data).count, 8)
        XCTAssertTrue(LLMModelCatalog.codexModels(from: Data("invalid".utf8)).isEmpty)
        let fallback = LLMModelCatalog.choices(for: "openai-codex", configured: ["my-model"])
        XCTAssertEqual(fallback.first?.id, "my-model")
        XCTAssertGreaterThan(fallback.count, 1)
    }

    func testCodexModelCacheIsReadOnlyAndUsesTheChosenProfile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = Data(#"{"models":[{"slug":"profile-model","visibility":"list"}]}"#.utf8)
        try cache.write(to: dir.appendingPathComponent("models_cache.json"))
        XCTAssertEqual(LLMModelCatalog.readCodexModels(home: dir.path).map(\.id), ["profile-model"])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("models_cache.json")), cache)
        XCTAssertTrue(LLMModelCatalog.readCodexModels(home: dir.appendingPathComponent("missing").path).isEmpty)
    }
}
