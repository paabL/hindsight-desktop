import XCTest
@testable import HindsightCore

@MainActor
final class LocalModelManagerTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEmbeddedScriptsAreTheRepositoryScripts() throws {
        let hint = "relancer python3 scripts/generate_model_manager_scripts.py"
        XCTAssertEqual(ModelManagerScripts.manager + "\n",
                       try String(contentsOf: repository.appendingPathComponent("scripts/hindsight-models.py"), encoding: .utf8), hint)
        XCTAssertEqual(ModelManagerScripts.server + "\n",
                       try String(contentsOf: repository.appendingPathComponent("scripts/hindsight-model-server.py"), encoding: .utf8), hint)
    }

    func testInstallWritesTheScriptsAndOnlyUpdatesAnExistingDecisionServer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = LocalModelManager(paths: .init(root: root))

        try manager.installScripts()
        XCTAssertEqual(try String(contentsOf: manager.paths.manager, encoding: .utf8), ModelManagerScripts.manager + "\n")
        XCTAssertEqual(try String(contentsOf: manager.paths.server, encoding: .utf8), ModelManagerScripts.server + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.paths.decisionScript.path), "pas de serveur de décision créé ici")

        try FileManager.default.createDirectory(at: manager.paths.decisionScript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ancienne version\n".utf8).write(to: manager.paths.decisionScript)
        try manager.installScripts()
        XCTAssertEqual(try String(contentsOf: manager.paths.decisionScript, encoding: .utf8), DecisionServerScript.source + "\n")
    }
}
