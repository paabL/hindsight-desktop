import XCTest
import HindsightAPI
import HindsightTestSupport
@testable import HindsightCore

@MainActor
final class FactCurationTests: XCTestCase {
    func make(_ t: MockTransport, hit: FactHit) -> FactDetailViewModel {
        t.on("GET", "\(bankPath)/memories/m1", json: Fixture.string("memory_m1"))
        t.on("GET", "/v1/default/chunks/codex-abc-task-002_0", json: Fixture.string("chunk_m1"))
        t.on("PATCH", "\(bankPath)/memories/m1", json: #"{"success":true}"#)
        return FactDetailViewModel(client: makeClient(t), bank: testBank, hit: hit)
    }
    var m1: FactHit { FactHit(id: "m1", text: "Les tests de l'étape 1 ont échoué trois fois.", type: "experience", context: "task 002") }

    func testEditSendsOnlyChangedFieldsPlusTextAfterConfirmation() async throws {
        let t = MockTransport()
        let vm = make(t, hit: m1)
        await vm.load()
        var changed = 0
        vm.onChanged = { changed += 1 }
        XCTAssertTrue(vm.canCurate)
        vm.beginEdit()
        vm.edit?.occurredStart = "2026-10-17T19:00:00Z"
        vm.requestSaveEdit()
        XCTAssertTrue(vm.confirmation!.message.contains("exige le texte"))
        XCTAssertTrue(t.requests.filter { $0.method == "PATCH" }.isEmpty)
        await vm.confirmation!.perform()
        let body = try XCTUnwrap(t.requests.first { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(body["occurred_start"], "2026-10-17T19:00:00Z")
        XCTAssertEqual(body["text"], .string(m1.text))
        XCTAssertNil(body["context"], "champ inchangé omis")
        XCTAssertNil(body["fact_type"])
        XCTAssertNil(vm.edit)
        XCTAssertEqual(vm.actionMessage, "Fait corrigé.")
        XCTAssertEqual(changed, 1)
    }

    func testNoChangeMeansNoRequest() async {
        let t = MockTransport()
        let vm = make(t, hit: m1)
        await vm.load()
        vm.beginEdit()
        vm.requestSaveEdit()
        XCTAssertNil(vm.confirmation)
        XCTAssertNil(vm.edit)
    }

    func testInvalidateAndRevalidate() async throws {
        let t = MockTransport()
        let vm = make(t, hit: m1)
        vm.requestInvalidate(reason: "  doublon ")
        XCTAssertEqual(vm.confirmation?.severity, .destructive)
        await vm.confirmation!.perform()
        var body = try XCTUnwrap(t.requests.last { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(body["state"], "invalidated")
        XCTAssertEqual(body["reason"], "doublon")
        vm.requestRevalidate()
        await vm.confirmation!.perform()
        body = try XCTUnwrap(t.requests.last { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(body["state"], "valid")
    }

    func testObservationsCannotBeCurated() async {
        let vm = make(MockTransport(), hit: FactHit(id: "o", text: "x", type: "observation"))
        XCTAssertFalse(vm.canCurate)
    }

    func testRefusalIsReported() async {
        let t = MockTransport()
        let vm = make(t, hit: m1)
        t.on("PATCH", "\(bankPath)/memories/m1", json: #"{"detail":"Only world/experience facts can be curated"}"#, status: 400)
        vm.requestInvalidate(reason: "")
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage!.contains("can be curated"))
    }
}

@MainActor
final class DocumentAdminTests: XCTestCase {
    func reader(_ t: MockTransport) async -> DocumentReaderViewModel {
        t.installStandardRoutes()
        let c = makeClient(t)
        let r = DocumentReaderViewModel(client: c, bank: testBank, documentID: "codex-abc-task-002", attachmentLoader: AttachmentLoader(client: c))
        await r.load()
        return r
    }

    func testTagsReplaceTheWholeSet() async throws {
        let t = MockTransport()
        let r = await reader(t)
        t.on("PATCH", "\(bankPath)/documents/codex-abc-task-002", json: #"{"success":true}"#)
        r.requestUpdateTags(["task:002", "source:codex"])
        XCTAssertNil(r.confirmation, "même ensemble : rien à faire")
        r.requestUpdateTags(["task:002", "revu", " "])
        let c = try XCTUnwrap(r.confirmation)
        XCTAssertEqual(c.severity, .destructive, "un tag retiré")
        XCTAssertTrue(c.message.contains("Ajoutées : revu"))
        XCTAssertTrue(c.message.contains("Retirées : source:codex"))
        await c.perform()
        let body = try XCTUnwrap(t.requests.first { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(body["tags"], ["revu", "task:002"])
    }

    func testReprocessAndDeleteRequireConfirmationAndTypedID() async throws {
        let t = MockTransport()
        let r = await reader(t)
        t.on("POST", "\(bankPath)/documents/codex-abc-task-002/reprocess", json: #"{"success":true,"operation_id":"op9","items_count":1}"#)
        t.on("DELETE", "\(bankPath)/documents/codex-abc-task-002", json: #"{"success":true,"message":"ok","document_id":"codex-abc-task-002","memory_units_deleted":30}"#)
        await r.requestReprocess()
        XCTAssertTrue(r.confirmation!.message.hasPrefix("Ses 30 faits seront supprimés puis ré-extraits"))
        await r.confirmation!.perform()
        XCTAssertEqual(r.actionMessage, "Retraitement en file : suivez-le dans « Activité › Traitements ».", "pas d'identifiant technique")
        var deleted = false
        r.onDeleted = { deleted = true }
        r.requestDelete()
        let c = try XCTUnwrap(r.confirmation)
        XCTAssertFalse(c.isSatisfied(by: "codex"))
        XCTAssertTrue(c.isSatisfied(by: "codex-abc-task-002"))
        await c.perform()
        XCTAssertTrue(deleted)
        XCTAssertEqual(r.actionMessage, "Document supprimé (30 faits).")
    }
}

@MainActor
final class BankAdminTests: XCTestCase {
    func make(_ t: MockTransport) -> BankAdminViewModel {
        t.on("GET", "\(bankPath)/config", json: #"{"bank_id":"b","config":{"reflect_mission":"Aider l’utilisateur","disposition_skepticism":4,"disposition_literalism":3,"disposition_empathy":2,"audit_log_enabled":false},"overrides":{"disposition_skepticism":4}}"#)
        t.on("GET", "\(bankPath)/directives", json: #"{"items":[{"id":"d1","bank_id":"b","name":"Style","content":"Réponds en français","priority":0,"is_active":true,"tags":[]}],"total":1,"limit":100,"offset":0}"#)
        t.on("GET", "\(bankPath)/mental-models", json: #"{"items":[{"id":"mm1","bank_id":"b","name":"Synthèse","tags":[]}],"total":1,"limit":100,"offset":0}"#)
        t.on("PATCH", "\(bankPath)/config", json: #"{"bank_id":"b","config":{},"overrides":{}}"#)
        return BankAdminViewModel(client: makeClient(t), bank: testBank)
    }

    func testMentalModelDetailIsReadWithItsContentAndRefreshPolicy() async throws {
        let t = MockTransport()
        let vm = make(t)
        t.on("GET", "\(bankPath)/mental-models/mm1", json: ###"{"id":"mm1","bank_id":"b","name":"Synthèse","content":"## Titre\nTexte","tags":[],"trigger":{"mode":"delta","refresh_after_consolidation":true,"refresh_cron":"0 6 * * *","exclude_mental_models":true}}"###)
        await vm.loadMentalModel("mm1")
        let m = try XCTUnwrap(vm.mentalModelDetail.value)
        XCTAssertEqual(m.content, "## Titre\nTexte", "la liste ne transmet pas le contenu : il vient du détail")
        XCTAssertEqual(BankAdminViewModel.refreshPolicy(m.trigger), "Automatique : après chaque consolidation et selon l'horaire « 0 6 * * * »")
        XCTAssertEqual(BankAdminViewModel.refreshPolicy(nil), "À la main seulement")
        XCTAssertFalse(t.requests.contains { $0.method != "GET" }, "lire un modèle mental n'écrit rien")
    }

    func testLoadsDirectivesAndMentalModels() async throws {
        let vm = make(MockTransport())
        await vm.reload()
        XCTAssertEqual(vm.directives.value?.count, 1)
        XCTAssertEqual(vm.mentalModels.value?.first?.name, "Synthèse")
        XCTAssertNotNil(vm.config.value)
    }

    func testOverrideParsing() async {
        XCTAssertEqual(BankAdminViewModel.parseJSONValue("true"), .bool(true))
        XCTAssertEqual(BankAdminViewModel.parseJSONValue("12"), .int(12))
        XCTAssertEqual(BankAdminViewModel.parseJSONValue("\"x\""), .string("x"))
        XCTAssertEqual(BankAdminViewModel.parseJSONValue("texte libre"), .string("texte libre"))
        XCTAssertNil(BankAdminViewModel.parseJSONValue("  "))
        let vm = make(MockTransport())
        XCTAssertFalse(vm.requestSetOverride(key: " ", rawJSON: "1"))
        XCTAssertTrue(vm.requestSetOverride(key: "recall_max_tokens", rawJSON: "8000"))
        XCTAssertNotNil(vm.confirmation)
    }

    func testRefusedOverrideExplains() async {
        let t = MockTransport()
        let vm = make(t)
        t.on("PATCH", "\(bankPath)/config", json: #"{"detail":"llm_model is not configurable per bank"}"#, status: 400)
        vm.requestSetOverride(key: "llm_model", rawJSON: "\"x\"")
        await vm.confirmation!.perform()
        XCTAssertTrue(vm.actionMessage!.hasPrefix("Refusé par le serveur"))
    }

    func testExportArchiveWaitsAndDownloads() async throws {
        let t = MockTransport()
        let vm = make(t)
        t.on("POST", "\(bankPath)/transfer/export", json: #"{"operation_id":"exp1","status":"pending"}"#)
        let calls = Counter()
        t.on("GET", "\(bankPath)/operations/exp1") { _ in
            calls.increment() < 2
                ? .json(#"{"operation_id":"exp1","status":"processing","progress":{"stage":"documents","at":"x"}}"#)
                : .json(#"{"operation_id":"exp1","status":"completed","result_metadata":{"download_url":"/v1/default/files/download/banks%2Fb%2Fx.zip","filename":"b.zip","byte_size":4}}"#)
        }
        t.on("GET", "/v1/default/files/download/banks/b/x.zip") { _ in .bytes(Data("PK\u{3}\u{4}".utf8), contentType: "application/zip") }
        await vm.exportArchiveForTests()
        XCTAssertEqual(vm.exported?.filename, "b.zip")
        XCTAssertEqual(vm.exported?.data.count, 4)
        XCTAssertNil(vm.longTask)
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/transfer/export") }?.queryValue("include_history"), "false")
    }

    func testFailedExportIsReported() async {
        let t = MockTransport()
        let vm = make(t)
        t.on("POST", "\(bankPath)/transfer/export", json: #"{"operation_id":"exp1","status":"pending"}"#)
        t.on("GET", "\(bankPath)/operations/exp1", json: #"{"operation_id":"exp1","status":"failed","error_message":"disque plein"}"#)
        await vm.exportArchiveForTests()
        XCTAssertTrue(vm.actionMessage!.contains("disque plein"))
        XCTAssertNil(vm.exported)
    }

    func testFailedExportNeverReturnsThePreviousFile() async {
        let t = MockTransport()
        let vm = make(t)
        t.on("POST", "\(bankPath)/transfer/export", json: #"{"operation_id":"exp1","status":"pending"}"#)
        t.on("GET", "\(bankPath)/operations/exp1", json: #"{"operation_id":"exp1","status":"completed","result_metadata":{"download_url":"/v1/default/files/download/banks%2Fb%2Fx.zip","filename":"b.zip","byte_size":4}}"#)
        t.on("GET", "/v1/default/files/download/banks/b/x.zip") { _ in .bytes(Data("PK\u{3}\u{4}".utf8), contentType: "application/zip") }
        await vm.exportArchiveForTests()
        XCTAssertEqual(vm.exported?.filename, "b.zip")
        t.on("GET", "\(bankPath)/export", json: #"{"detail":"boom"}"#, status: 500)
        await vm.exportTemplate()
        XCTAssertNil(vm.exported, "l'archive précédente ne doit pas passer pour la structure demandée")
        XCTAssertTrue(vm.actionMessage!.hasPrefix("Échec de l'export"))
    }

    func testCloneAndDangerZoneNeedTypedBankID() async throws {
        let t = MockTransport()
        let vm = make(t)
        var refreshed = 0
        vm.onBanksChanged = { refreshed += 1 }
        t.on("POST", "\(bankPath)/clone", json: #"{"operation_id":"cl1"}"#)
        t.on("GET", "\(bankPath)/operations/cl1", json: #"{"operation_id":"cl1","status":"completed"}"#)
        vm.requestClone(targetBankID: testBank)
        XCTAssertNil(vm.confirmation, "même banque refusée")
        vm.requestClone(targetBankID: "copie", includeConfig: true)
        XCTAssertTrue(vm.confirmation!.message.contains("webhooks"))
        await vm.confirmation!.perform()
        XCTAssertEqual(t.requests.first { $0.path.hasSuffix("/clone") }?.queryValue("target_bank_id"), "copie")
        XCTAssertEqual(refreshed, 1)

        t.on("DELETE", "\(bankPath)", json: #"{"success":true}"#)
        var appMessages: [String] = []
        vm.onAppMessage = { appMessages.append($0) }
        vm.requestDeleteBank()
        XCTAssertEqual(vm.confirmation?.requiredText, testBank)
        XCTAssertFalse(vm.confirmation!.isSatisfied(by: "codex"))
        await vm.confirmation!.perform()
        XCTAssertEqual(refreshed, 2)
        XCTAssertEqual(appMessages, ["Banque supprimée."], "le message survit à la session de la banque supprimée")
        XCTAssertNotEqual(vm.actionMessage, "Banque supprimée.", "pas de doublon dans la session remplacée")
        t.on("DELETE", "\(bankPath)/memories", json: #"{"success":true,"deleted_count":4}"#)
        vm.requestDeleteMemories(type: "observation")
        XCTAssertEqual(vm.confirmation?.requiredText, testBank)
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "4 faits effacés.")
        XCTAssertEqual(refreshed, 3, "le nombre de faits de la banque est relu")
        vm.requestClearObservations()
        XCTAssertEqual(vm.confirmation?.requiredText, testBank)
    }

    func testTemplateDryRunThenApply() async throws {
        let t = MockTransport()
        let vm = make(t)
        t.on("POST", "\(bankPath)/import") { r in
            r.queryValue("dry_run") == "true"
                ? .json(#"{"bank_id":"b","config_applied":true,"directives_created":["Style"],"dry_run":true}"#)
                : .json(#"{"bank_id":"b","config_applied":true,"directives_created":["Style"],"dry_run":false}"#)
        }
        await vm.validateTemplate(Data(#"{"version":"1","directives":[{"name":"Style","content":"x"}]}"#.utf8))
        XCTAssertEqual(vm.templateDryRun?.directivesCreated, ["Style"])
        XCTAssertTrue(t.requests.allSatisfy { $0.queryValue("dry_run") != "false" })
        vm.requestApplyTemplate()
        XCTAssertTrue(vm.confirmation!.message.contains("1 directive créée"), vm.confirmation!.message)
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.actionMessage, "Gabarit appliqué.")
        await vm.validateTemplate(Data("pas du json".utf8))
        XCTAssertTrue(vm.actionMessage!.contains("invalide"))
    }
}

@MainActor
final class CreateBankTests: XCTestCase {
    func testCreateBankChecksExistenceThenPutsAndSelects() async throws {
        let t = MockTransport()
        t.installStandardRoutes()
        t.on("PUT", "/v1/default/banks/nouvelle", json: #"{"bank_id":"nouvelle","name":"N","disposition":{"skepticism":3,"literalism":3,"empathy":3},"mission":""}"#)
        t.on("PATCH", "/v1/default/banks/nouvelle/config", json: #"{"bank_id":"nouvelle","config":{},"overrides":{}}"#)
        let app = AppModel(settings: InMemorySettingsStore(), transport: t, runner: FakeRunner())
        await app.connect()
        XCTAssertNotNil(app.validateNewBankID(testBank))
        XCTAssertNotNil(app.validateNewBankID("a b"))
        XCTAssertNil(app.validateNewBankID("nouvelle"))
        app.requestCreateBank(id: "nouvelle", name: "N", mission: "Mémoire des sessions Codex")
        XCTAssertTrue(t.requests.allSatisfy { $0.method == "GET" })
        await app.confirmation!.perform()
        XCTAssertNotNil(t.requests.first { $0.method == "PUT" })
        let patch = try XCTUnwrap(t.requests.first { $0.method == "PATCH" }?.bodyJSON)
        XCTAssertEqual(patch["updates"]?["reflect_mission"], "Mémoire des sessions Codex")
        // La liste fixture ne contient pas « nouvelle » : la sélection retombe sur la première banque.
        XCTAssertNotNil(app.selectedBankID)
    }

    func testServerSettingsAreGlobal() async {
        let app = AppModel(settings: InMemorySettingsStore(), transport: MockTransport(), runner: FakeRunner())
        XCTAssertEqual(app.serverSettings.scriptPath, ServerSettingsViewModel.defaultScriptPath)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        n += 1
        return n - 1
    }
}
