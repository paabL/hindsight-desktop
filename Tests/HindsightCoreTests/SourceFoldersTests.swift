import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

/// Sources d'une banque : dossiers ordinaires et dossiers à catalogue, rattachement par la politique, migration
/// de l'ancien dossier commun à tout le Mac.
@MainActor
final class SourceFoldersTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Dépôt fictif : un collecteur, un catalogue dans `collection/` et un document du dépôt lui-même.
    private func catalogRepository(declaring bank: String?) throws -> URL {
        let root = try directory().appendingPathComponent("garden-archive")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("collection"), withIntermediateDirectories: true)
        try Data(#"{"version":1,"mode":"collection_only","records":[],"sources":[]}"#.utf8)
            .write(to: root.appendingPathComponent("collection/catalog.json"))
        try Data("# collector".utf8).write(to: root.appendingPathComponent("collect.py"))
        try Data("# Notes du jardin\n".utf8).write(to: root.appendingPathComponent("notes.md"))
        if let bank {
            try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": bank, "excluded_document_ids": [:], "deferred_document_ids": [:]])
                .write(to: root.appendingPathComponent("memory-policy.json"))
        }
        return root
    }

    func testOrdinaryFolderIsNeverACatalog() throws {
        let folder = try directory()
        try Data("# Note\n".utf8).write(to: folder.appendingPathComponent("note.md"))
        XCTAssertNil(SourceFolders.catalogURL(in: folder))
        XCTAssertFalse(SourceFolders.isCatalog(folder, for: "garden"))
        XCTAssertFalse(SourceFolders.isCatalog(folder, for: nil))
    }

    func testCatalogBelongsToTheBankDeclaredByItsPolicy() throws {
        let repository = try catalogRepository(declaring: "garden")
        XCTAssertEqual(SourceFolders.declaredBank(of: repository), "garden")
        XCTAssertTrue(SourceFolders.isCatalog(repository, for: "garden"))
        XCTAssertFalse(SourceFolders.isCatalog(repository, for: "kitchen"), "dans une autre banque, c'est un dossier ordinaire")
        XCTAssertTrue(SourceFolders.isCatalog(repository, for: nil), "hors connexion, le catalogue reste consultable")
        // Le dossier `collection` choisi seul désigne le même dépôt.
        let collection = repository.appendingPathComponent("collection")
        try Data(#"{"version":1,"mode":"collection_only","records":[],"sources":[]}"#.utf8).write(to: collection.appendingPathComponent("catalog.json"))
        XCTAssertEqual(SourceFolders.repository(of: collection).path, repository.path)
        XCTAssertTrue(SourceFolders.isCatalog(collection, for: "garden"))
    }

    func testUnboundCatalogBelongsToEveryBankThatTracksItUntilItsPolicyNamesOne() throws {
        let repository = try catalogRepository(declaring: nil)
        XCTAssertTrue(SourceFolders.isCatalog(repository, for: "garden"))
        XCTAssertTrue(SourceFolders.isCatalog(repository, for: "kitchen"))
        // Premier envoi : la politique désigne sa banque, l'autre banque le voit désormais comme un dossier ordinaire.
        try JSONSerialization.data(withJSONObject: ["version": 1, "bank_id": "garden", "excluded_document_ids": [:], "deferred_document_ids": [:]])
            .write(to: repository.appendingPathComponent("memory-policy.json"))
        XCTAssertTrue(SourceFolders.isCatalog(repository, for: "garden"))
        XCTAssertFalse(SourceFolders.isCatalog(repository, for: "kitchen"))
    }

    func testOnlyTheBanksOwnCatalogProvidesAPolicy() throws {
        let plain = try directory()
        let garden = try catalogRepository(declaring: "garden")
        let unbound = try catalogRepository(declaring: nil)
        XCTAssertNil(SourceFolders.policyURL(bank: "garden", roots: [CoverageRoot(path: plain.path), CoverageRoot(path: unbound.path)]))
        XCTAssertEqual(
            SourceFolders.policyURL(bank: "garden", roots: [CoverageRoot(path: plain.path), CoverageRoot(path: garden.path)])?.path,
            garden.appendingPathComponent("memory-policy.json").path)
        XCTAssertNil(SourceFolders.policyURL(bank: "kitchen", roots: [CoverageRoot(path: garden.path)]))
    }

    func testLegacyOrdinaryFolderIsDroppedWithoutBeingTracked() throws {
        let folder = try directory()
        let settings = InMemorySettingsStore([SettingsKey.memoryFolderPath: folder.path, SettingsKey.lastBank: "garden"])
        SourceFolders.migrateLegacyCatalogFolder(settings: settings)
        XCTAssertNil(settings.string(forKey: SettingsKey.memoryFolderPath), "le dossier commun à tout le Mac disparaît")
        XCTAssertNil(settings.string(forKey: "coverageRoots.garden"), "un dossier ordinaire n'est rattaché à aucune banque")
    }

    func testLegacyCatalogJoinsItsDeclaredBankOnce() throws {
        let repository = try catalogRepository(declaring: "garden")
        let settings = InMemorySettingsStore([SettingsKey.memoryFolderPath: repository.appendingPathComponent("collection").path,
                                              SettingsKey.lastBank: "kitchen"])
        SourceFolders.migrateLegacyCatalogFolder(settings: settings)
        XCTAssertEqual(FileCoverageViewModel.storedRoots(settings: settings, bank: "garden"), [CoverageRoot(path: repository.path)])
        XCTAssertTrue(FileCoverageViewModel.storedRoots(settings: settings, bank: "kitchen").isEmpty)
        XCTAssertNil(settings.string(forKey: SettingsKey.memoryFolderPath))
        // Déjà suivi : pas de doublon, les options existantes sont conservées.
        FileCoverageViewModel.saveRoots([CoverageRoot(path: repository.path, allFiles: true)], settings: settings, bank: "garden")
        settings.set(repository.path, forKey: SettingsKey.memoryFolderPath)
        SourceFolders.migrateLegacyCatalogFolder(settings: settings)
        XCTAssertEqual(FileCoverageViewModel.storedRoots(settings: settings, bank: "garden"), [CoverageRoot(path: repository.path, allFiles: true)])
    }

    func testLegacyUnboundCatalogJoinsTheLastSelectedBank() throws {
        let repository = try catalogRepository(declaring: nil)
        let settings = InMemorySettingsStore([SettingsKey.memoryFolderPath: repository.path, SettingsKey.lastBank: "kitchen"])
        SourceFolders.migrateLegacyCatalogFolder(settings: settings)
        XCTAssertEqual(FileCoverageViewModel.storedRoots(settings: settings, bank: "kitchen"), [CoverageRoot(path: repository.path)])
    }

    func testCatalogFolderIsNotScannedInItsBankButIsAnOrdinaryFolderElsewhere() async throws {
        let repository = try catalogRepository(declaring: testBank)
        let transport = MockTransport()
        transport.on("GET", "\(bankPath)/documents", json: #"{"items":[],"total":0,"limit":500,"offset":0}"#)
        transport.on("GET", "/v1/default/banks/other/documents", json: #"{"items":[],"total":0,"limit":500,"offset":0}"#)
        let bank = Lock<String?>(testBank)
        let vm = FileCoverageViewModel(settings: InMemorySettingsStore(), client: { makeClient(transport) }, bank: { bank.value })
        await vm.addRoots([repository])
        XCTAssertEqual(vm.roots, [CoverageRoot(path: repository.path)], "le dossier reste dans la liste de sa banque")
        XCTAssertEqual(vm.state.value?.entries.count, 0, "dans sa banque, il passe uniquement par son catalogue")

        bank.value = "other"
        vm.invalidateContext()
        await vm.addRoots([repository])
        XCTAssertEqual(vm.state.value?.entries.map(\.file.path), ["notes.md"], "dans une autre banque, ses fichiers sont comparés")
    }
}
