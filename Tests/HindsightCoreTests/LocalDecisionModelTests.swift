import Foundation
import XCTest
@testable import HindsightCore

@MainActor
final class LocalDecisionModelTests: XCTestCase {
    private var dir: URL!
    private let launchctl = HindsightServiceViewModel.launchctl

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-decision-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private struct Env {
        let model: LocalDecisionModel
        let runner: FakeProcessRunner
        let paths: LocalDecisionModel.Paths
        let loaded: Switch
        let running: Switch
        let healthy: Switch
    }

    /// Faux uv, hf, python et launchctl : chaque étape crée ce que la vraie produirait.
    private func make(uv: String? = "/test/uv", failing: String? = nil) -> Env {
        let paths = LocalDecisionModel.Paths(
            root: dir.appendingPathComponent("decision"), launchAgents: dir.appendingPathComponent("LaunchAgents"),
            logs: dir.appendingPathComponent("Logs"))
        let loaded = Switch(), running = Switch(), healthy = Switch()
        let launchctl = launchctl
        let runner = FakeProcessRunner { inv in
            if let failing, inv.arguments.first == failing {
                return ProcessOutput(status: 1, stderr: "401 Unauthorized for hsk_abcdefghijklmnopqrstuvwxyz")
            }
            let fm = FileManager.default
            switch (inv.executable, inv.arguments.first) {
            case (launchctl, "print"):
                guard loaded.value else { return ProcessOutput(status: 113, stderr: "Could not find service") }
                return ProcessOutput(status: 0, stdout: running.value ? "\tstate = running\n\tpid = 7\n" : "\tstate = not running\n")
            case (launchctl, "bootstrap"): loaded.value = true
            case (launchctl, "kickstart"):
                running.value = true
                healthy.value = true
            case (launchctl, "bootout"):
                loaded.value = false
                running.value = false
                healthy.value = false
            case (_, "venv"):
                try? fm.createDirectory(at: paths.python.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: paths.python.path, contents: Data(), attributes: [.posixPermissions: 0o755])
            case (_, "download"):
                try? fm.createDirectory(at: paths.model, withIntermediateDirectories: true)
                fm.createFile(atPath: paths.weights.path, contents: Data())
            default: break
            }
            return ProcessOutput(status: 0, stdout: "ok\n")
        }
        let model = LocalDecisionModel(
            runner: runner, paths: paths, uid: 501, probe: { _ in healthy.value }, locate: { $0 == "uv" ? uv : nil },
            startTimeout: 2, pollInterval: .milliseconds(10))
        return Env(model: model, runner: runner, paths: paths, loaded: loaded, running: running, healthy: healthy)
    }

    func testEmbeddedServerIsTheRepositoryScript() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/hindsight-decision-serve.py")
        XCTAssertEqual(
            DecisionServerScript.source + "\n", try String(contentsOf: script, encoding: .utf8),
            "relancer python3 scripts/generate_decision_script.py")
    }

    func testInstallPreparesEverythingThenStartsTheService() async throws {
        let e = make()
        await e.model.refresh()
        XCTAssertEqual(e.model.phase, .notInstalled)

        e.model.requestInstall()
        let confirmation = try XCTUnwrap(e.model.confirmation)
        XCTAssertTrue(confirmation.message.contains(LocalDecisionModel.repository))
        XCTAssertTrue(confirmation.message.contains(String(LocalDecisionModel.revision.prefix(12))))
        XCTAssertTrue(e.runner.calls.isEmpty, "rien n'est téléchargé avant confirmation")
        await confirmation.perform()

        XCTAssertNil(e.model.problem)
        XCTAssertEqual(e.model.phase, .running)
        XCTAssertTrue(e.model.isInstalled)
        let steps = e.runner.calls.filter { $0.executable != launchctl }
        XCTAssertEqual(steps.map { [$0.executable] + $0.arguments.prefix(2) }, [
            ["/test/uv", "venv", "--allow-existing"],
            ["/test/uv", "pip", "install"],
            [e.paths.hf.path, "download", LocalDecisionModel.repository],
            ["/test/uv", "pip", "install"],
            [e.paths.python.path, "-I", e.paths.script.path],
        ])
        let download = steps[2].arguments
        XCTAssertEqual(download[download.firstIndex(of: "--revision")! + 1], LocalDecisionModel.revision, "révision figée")
        XCTAssertTrue(steps.prefix(4).allSatisfy { !$0.inheritEnvironment && $0.environment["HF_HUB_DISABLE_TELEMETRY"] == "1" })
        XCTAssertEqual(steps[4].arguments.last, "--check")
        XCTAssertEqual(steps[4].environment["HF_HUB_OFFLINE"], "1", "la vérification n'utilise pas le réseau")
        XCTAssertEqual(
            e.runner.args(of: launchctl).filter { $0.first != "print" },
            [["bootstrap", "gui/501", e.paths.plist.path], ["kickstart", "gui/501/local.hindsight.decision"]])

        XCTAssertEqual(try String(contentsOf: e.paths.script, encoding: .utf8), DecisionServerScript.source + "\n")
        let key = try e.model.apiKey()
        XCTAssertEqual(key.count, 64)
        XCTAssertEqual(permissions(e.paths.keyFile.path), 0o600)
        XCTAssertEqual(permissions(e.paths.root.path), 0o700)
        XCTAssertEqual(try e.model.apiKey(), key, "la clé est créée une fois, puis relue")

        XCTAssertFalse(try String(contentsOf: e.paths.plist, encoding: .utf8).contains(key), "la clé reste dans son fichier 0600")
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: e.paths.plist), format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, LocalDecisionModel.label)
        let arguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(Array(arguments.prefix(3)), [e.paths.python.path, "-I", e.paths.script.path])
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--key-file")! + 1], e.paths.keyFile.path)
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--port")! + 1], "8766")
        XCTAssertFalse(arguments.contains("--host"), "le serveur garde son adresse par défaut, 127.0.0.1")
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?["HF_HUB_OFFLINE"], "1")
    }

    func testFailedDownloadStopsBeforeTheServiceAndMasksTheLog() async throws {
        let e = make(failing: "download")
        await e.model.install()
        XCTAssertEqual(e.model.phase, .notInstalled)
        XCTAssertTrue(try XCTUnwrap(e.model.problem).contains("Téléchargement du modèle"))
        XCTAssertTrue(e.runner.args(of: launchctl).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.plist.path))
        XCTAssertTrue(e.model.log.contains("401 Unauthorized"))
        XCTAssertFalse(e.model.log.contains("abcdefghijklmnopqrstuvwxyz"))
    }

    func testInstallWithoutUvExplainsWhatIsMissing() async {
        let e = make(uv: nil)
        await e.model.install()
        XCTAssertTrue(e.runner.calls.isEmpty)
        XCTAssertEqual(e.model.phase, .notInstalled)
        XCTAssertTrue(e.model.problem?.contains("uv") ?? false)
    }

    func testPhasesFollowTheServiceThenUninstallRemovesEverything() async throws {
        let e = make()
        await e.model.install()
        XCTAssertEqual(e.model.phase, .running)

        e.healthy.value = false
        await e.model.refresh()
        XCTAssertEqual(e.model.phase, .starting, "lancé par launchd, le modèle se charge encore")
        e.running.value = false
        await e.model.refresh()
        XCTAssertEqual(e.model.phase, .stopped)

        e.model.requestStop()
        try await XCTUnwrap(e.model.confirmation).perform()
        XCTAssertEqual(e.model.phase, .stopped)
        XCTAssertFalse(e.loaded.value)
        await e.model.start()
        XCTAssertEqual(e.model.phase, .running)

        e.model.requestUninstall()
        let confirmation = try XCTUnwrap(e.model.confirmation)
        XCTAssertEqual(confirmation.severity, .destructive)
        await confirmation.perform()
        XCTAssertEqual(e.model.phase, .notInstalled)
        XCTAssertFalse(e.loaded.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.plist.path))
    }
}
