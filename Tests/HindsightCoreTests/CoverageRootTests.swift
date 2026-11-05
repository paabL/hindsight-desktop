import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

@MainActor
final class CoverageRootTests: XCTestCase {
    func testLegacyRootWithoutOptionsUsesSafeDefaults() async throws {
        let roots = try JSONDecoder().decode([CoverageRoot].self, from: Data(#"[{"path":"/example/Mémoire partagée"}]"#.utf8))
        XCTAssertEqual(roots, [CoverageRoot(path: "/example/Mémoire partagée")])
        XCTAssertFalse(roots[0].allFiles)
        XCTAssertFalse(roots[0].autoSync)
    }

    func testMissingOptionPreservesTheOtherSavedOption() async throws {
        let json = #"[{"path":"/example/a","allFiles":true},{"path":"/example/b","autoSync":true}]"#
        let roots = try JSONDecoder().decode([CoverageRoot].self, from: Data(json.utf8))
        XCTAssertEqual(roots, [
            CoverageRoot(path: "/example/a", allFiles: true),
            CoverageRoot(path: "/example/b", autoSync: true),
        ])
    }

    func testRoundTripPreservesOptionsAndLiteralFilePath() async throws {
        let original = CoverageRoot(path: "/example/Mémoire 100%/notes %20 #1", allFiles: true, autoSync: true)
        let restored = try JSONDecoder().decode(CoverageRoot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertTrue(restored.url.isFileURL)
        XCTAssertEqual(restored.url.path, original.path, "Le chemin enregistré est un chemin de fichier, pas une URL à désencoder")
    }

    func testLegacyRootsLoadOnlyForTheirBankWithoutRewritingThem() async throws {
        let saved = #"[{"path":"/example/ancien dossier"}]"#
        let settings = InMemorySettingsStore(["coverageRoots.first": saved])
        let transport = MockTransport()
        let selectedBank = Lock<String?>("first")
        let vm = FileCoverageViewModel(settings: settings, client: { makeClient(transport) }, bank: { selectedBank.value })
        vm.loadRoots()
        XCTAssertEqual(vm.roots, [CoverageRoot(path: "/example/ancien dossier")])
        XCTAssertEqual(settings.string(forKey: "coverageRoots.first"), saved)

        selectedBank.value = "second"
        vm.loadRoots()
        XCTAssertTrue(vm.roots.isEmpty)
        XCTAssertNil(settings.string(forKey: "coverageRoots.second"))
        selectedBank.value = nil
        vm.loadRoots()
        XCTAssertTrue(vm.roots.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty, "Lire les dossiers enregistrés ne contacte aucun serveur")
    }

    func testCatalogFolderDoesNotBecomeTrackedWithoutExplicitRegistration() async {
        let settings = InMemorySettingsStore([SettingsKey.memoryFolderPath: "/example/catalog"])
        let transport = MockTransport()
        let vm = FileCoverageViewModel(settings: settings, client: { makeClient(transport) }, bank: { "first" })
        vm.loadRoots()
        XCTAssertTrue(vm.roots.isEmpty)
        XCTAssertNil(settings.string(forKey: "coverageRoots.first"))
        XCTAssertEqual(settings.string(forKey: SettingsKey.memoryFolderPath), "/example/catalog")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testInvalidOptionTypesAreStillRejected() async {
        let json = #"[{"path":"/example/a","allFiles":"true"}]"#
        XCTAssertThrowsError(try JSONDecoder().decode([CoverageRoot].self, from: Data(json.utf8)))
    }
}
