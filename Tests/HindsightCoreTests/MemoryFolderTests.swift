import Foundation
import XCTest
@testable import HindsightCore

@MainActor
final class MemoryFolderTests: XCTestCase {
    func testChosenFolderIsNeitherSavedNorDiscoveredAndCanBeClosed() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = MemoryFolderViewModel()
        XCTAssertNil(vm.folder, "aucun dossier n'est ouvert ni deviné au démarrage")
        vm.choose(root)
        XCTAssertNotNil(vm.catalogURL)
        XCTAssertNil(MemoryFolderViewModel().folder, "le choix n'est pas enregistré pour tout le Mac")
        vm.choose(nil)
        XCTAssertNil(vm.folder)
        XCTAssertNil(vm.catalogURL)
        XCTAssertNil(vm.repository)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("collection"), withIntermediateDirectories: true)
        try Data(#"{"version":1,"mode":"collection_only","records":[],"sources":[]}"#.utf8)
            .write(to: root.appendingPathComponent("collection/catalog.json"))
        try Data("<html>catalog</html>".utf8).write(to: root.appendingPathComponent("collection/index.html"))
        try Data("# local collector".utf8).write(to: root.appendingPathComponent("collect.py"))
        return root
    }

    func testFolderAndCollectionAreReadableWithoutAServerOrAProcess() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner { _ in XCTFail("Reading a catalog must run nothing"); return ProcessOutput(status: 1) }
        let vm = MemoryFolderViewModel(runner: runner)
        vm.choose(root)
        XCTAssertNotNil(vm.indexURL)
        XCTAssertNil(vm.error)
        vm.choose(root.appendingPathComponent("collection"))
        XCTAssertEqual(vm.repository?.path, root.path)
        XCTAssertNotNil(vm.indexURL)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCollectionOnlyRunsAfterConfirmationAndNeverInvokesSync() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0) }
        let vm = MemoryFolderViewModel(runner: runner, python: "/example/python3")
        vm.choose(root)
        vm.requestCollection()
        XCTAssertTrue(runner.calls.isEmpty)
        let request = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(request.message.contains("Aucun envoi ni traitement Hindsight"))
        await request.perform()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.executable, "/example/python3")
        XCTAssertEqual(runner.calls.first?.arguments, [root.appendingPathComponent("collect.py").path])
        XCTAssertEqual(runner.calls.first?.currentDirectory, root.path)
        XCTAssertFalse(vm.collecting)
        XCTAssertNil(vm.error)
    }

    func testChangedCollectorCannotReuseApproval() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner { _ in XCTFail("Changed script must not run"); return ProcessOutput(status: 1) }
        let vm = MemoryFolderViewModel(runner: runner)
        vm.choose(root)
        vm.requestCollection()
        let request = try XCTUnwrap(vm.confirmation)
        try Data("# changed".utf8).write(to: root.appendingPathComponent("collect.py"))
        await request.perform()
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(vm.error?.contains("changé") == true)
    }

    func testIncompleteCollectionStillDisplaysItsCatalog() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 1, stderr: "one source unavailable") }
        let vm = MemoryFolderViewModel(runner: runner)
        vm.choose(root)
        vm.requestCollection()
        await vm.confirmation?.perform()
        XCTAssertNotNil(vm.indexURL)
        XCTAssertTrue(vm.error?.contains("incomplète") == true)
    }

    func testUnsupportedOrBrokenCatalogIsNotPresentedAsCurrent() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"version":99,"mode":"collection_only"}"#.utf8).write(to: root.appendingPathComponent("collection/catalog.json"))
        let vm = MemoryFolderViewModel()
        vm.choose(root)
        XCTAssertNil(vm.indexURL)
        XCTAssertNotNil(vm.error)
    }

    func testManualImportUsesOnlySelectedFilesAndWaitsForConfirmation() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note avec espaces.tex")
        try Data("\\section{Local}".utf8).write(to: file)
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 0, stdout: #"{"imported":1,"unchanged":0}"#) }
        let vm = MemoryFolderViewModel(runner: runner, python: "/example/python3")
        vm.choose(root)
        vm.requestImport(paths: [file.path], project: "nomad")
        XCTAssertTrue(runner.calls.isEmpty)
        let request = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(request.message.contains("Aucun envoi ni traitement Hindsight"))
        await request.perform()
        XCTAssertEqual(runner.calls.first?.arguments, [root.appendingPathComponent("collect.py").path, "--project", "nomad", "--import-file", file.path])
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertFalse(vm.importing)
        XCTAssertFalse(vm.collecting)
        XCTAssertTrue(vm.importSummary?.contains("1 document") == true)
    }

    func testInvalidManualImportDoesNotExecuteAnything() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let unsupported = root.appendingPathComponent("script.sh")
        try Data("echo local".utf8).write(to: unsupported)
        let runner = FakeProcessRunner { _ in XCTFail("Invalid import must run nothing"); return ProcessOutput(status: 1) }
        let vm = MemoryFolderViewModel(runner: runner)
        vm.choose(root)
        vm.requestImport(paths: [unsupported.path], project: "nomad")
        XCTAssertNil(vm.confirmation)
        XCTAssertNotNil(vm.error)
        vm.requestImport(paths: [unsupported.path], project: "../outside")
        XCTAssertNil(vm.confirmation)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testManualImportRejectsAChangedCollectorAndShowsFailure() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try Data("# Local".utf8).write(to: file)
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 1, stderr: "Projet inconnu") }
        let vm = MemoryFolderViewModel(runner: runner)
        vm.choose(root)
        vm.requestImport(paths: [file.path], project: "nomad")
        let stale = try XCTUnwrap(vm.confirmation)
        try Data("# changed".utf8).write(to: root.appendingPathComponent("collect.py"))
        await stale.perform()
        XCTAssertTrue(runner.calls.isEmpty)
        vm.requestImport(paths: [file.path], project: "nomad")
        await vm.confirmation?.perform()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(vm.error?.contains("Projet inconnu") == true)
        XCTAssertNil(vm.importSummary)
    }

}
