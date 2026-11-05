import Foundation
import HindsightAPI
import HindsightTestSupport
import XCTest

@testable import HindsightCore

/// Faux exécuteur de programmes : chaque invocation est enregistrée et reçoit la réponse du gestionnaire.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [ProcessInvocation] = []
    var handler: @Sendable (ProcessInvocation) -> ProcessOutput

    init(_ handler: @escaping @Sendable (ProcessInvocation) -> ProcessOutput = { _ in ProcessOutput(status: 0) }) {
        self.handler = handler
    }

    var calls: [ProcessInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    /// Arguments des appels à un programme donné (ex. « /bin/launchctl »).
    func args(of executable: String) -> [[String]] { calls.filter { $0.executable == executable }.map(\.arguments) }

    private func record(_ invocation: ProcessInvocation) {
        lock.lock()
        _calls.append(invocation)
        lock.unlock()
    }

    func run(_ invocation: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        record(invocation)
        let out = handler(invocation)
        if !out.stdout.isEmpty { onOutput?(out.stdout) }
        return out
    }
}

/// Booléen partagé entre le test et les gestionnaires simulés.
final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Bool
    init(_ v: Bool = false) { self.v = v }
    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return v
        }
        set {
            lock.lock()
            v = newValue
            lock.unlock()
        }
    }
}

/// Captures a real fake-runner response, then releases it on demand to exercise stale completions.
actor LifecycleGateRunner: ProcessRunning {
    let base: any ProcessRunning
    private var verb: String?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var blocked = false

    init(_ base: any ProcessRunning) { self.base = base }
    func holdNext(_ verb: String) { self.verb = verb; blocked = false }
    func run(_ invocation: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        let shouldHold = invocation.arguments.first == verb && verb != nil
        if shouldHold { verb = nil }
        let output = try await base.run(invocation, onOutput: onOutput)
        if shouldHold {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                blocked = true
            }
        }
        return output
    }
    func release() { continuation?.resume(); continuation = nil; blocked = false }
}

func permissions(_ path: String) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

func setPermissions(_ path: String, _ mode: Int) {
    try! FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
}

final class SecurityPrimitivesTests: XCTestCase {
    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256.hex(Data(repeating: 0x61, count: 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    /// Le calcul sans dépendance (seul chemin sous Linux) doit rester identique à CryptoKit,
    /// notamment autour des frontières de bloc de 64 octets.
    func testPortableSHA256MatchesPlatformImplementation() {
        var bytes: [UInt8] = [], seed: UInt32 = 2_463_534_242
        for length in Array(0...130) + [1_000, 4_096, 65_537] {
            while bytes.count < length {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                bytes.append(UInt8(truncatingIfNeeded: seed))
            }
            let data = Data(bytes.prefix(length))
            XCTAssertEqual(SHA256.hash(data), SHA256.portableHash(data), "\(length) octets")
        }
    }

    func testSecretMaskerHidesCommonSecrets() {
        let text = """
            export HINDSIGHT_API_LLM_API_KEY="sk-ant-abcdefghijklmnopqrstuv"
            Authorization: Bearer abcdefgh12345678
            gemini key AIzaSyA1234567890abcdefghijk used
            {"api_key": "zzzzsecretvalue"}
            Your API key: hsk_Q2xvdWRLZXlGb3JUZXN0cw
            port=8888 model=claude-sonnet-4-5
            """
        let m = SecretMasker.mask(text)
        XCTAssertFalse(m.contains("Q2xvdWRLZXlGb3JUZXN0cw"), "clé Hindsight Cloud")
        XCTAssertFalse(m.contains("abcdefghijklmnopqrstuv"))
        XCTAssertFalse(m.contains("12345678"))
        XCTAssertFalse(m.contains("1234567890abcdefghijk"))
        XCTAssertFalse(m.contains("secretvalue"))
        XCTAssertTrue(m.contains("HINDSIGHT_API_LLM_API_KEY=\"sk-a••••"))
        XCTAssertTrue(m.contains("port=8888 model=claude-sonnet-4-5"), "le reste du texte est intact")
    }

    func testFileSafetyFlagsUnsafeScripts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-safe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        setPermissions(dir.path, 0o755)
        let f = dir.appendingPathComponent("start.sh")
        try Data("#!/bin/bash\n".utf8).write(to: f)
        let uid = FileSafety.currentUID

        setPermissions(f.path, 0o755)
        XCTAssertEqual(FileSafety.inspect(f, uid: uid), [])

        setPermissions(f.path, 0o644)
        XCTAssertEqual(FileSafety.inspect(f, uid: uid), [.notExecutable(f.path)])
        XCTAssertFalse(FileSafety.inspect(f, uid: uid).contains { $0.isBlocking })

        setPermissions(f.path, 0o777)
        XCTAssertEqual(FileSafety.inspect(f, uid: uid), [.writableByOthers(f.path)])

        setPermissions(f.path, 0o755)
        setPermissions(dir.path, 0o777)
        XCTAssertEqual(FileSafety.inspect(f, uid: uid), [.directoryWritableByOthers(dir.path)])
        setPermissions(dir.path, 0o755)

        // Propriétaire étranger (simulé en se déclarant un autre uid)
        if uid != 0 {
            XCTAssertTrue(FileSafety.inspect(f, uid: uid + 1).contains(.foreignOwner(f.path)))
        }
        XCTAssertEqual(FileSafety.inspect(dir.appendingPathComponent("absent.sh"), uid: uid), [.missing(dir.appendingPathComponent("absent.sh").path)])
        XCTAssertTrue(FileSafety.inspect(dir, uid: uid, requireExecutable: false).contains(.notRegularFile(dir.path)))
    }

    func testSystemRunnerPassesArgumentsWithoutShellAndTimesOut() async throws {
        let runner = SystemProcessRunner()
        let r = try await runner.run(ProcessInvocation("/bin/echo", ["a b; echo injecté $HOME"]))
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.stdout, "a b; echo injecté $HOME\n", "aucun shell n'interprète l'argument")
        let slow = try await runner.run(ProcessInvocation("/bin/sleep", ["5"], timeout: 0.3))
        XCTAssertTrue(slow.timedOut)
        XCTAssertFalse(slow.succeeded)
    }

    func testServerURLPolicy() {
        func v(_ s: String) -> ServerURLPolicy.Verdict { ServerURLPolicy.evaluate(URL(string: s)!) }
        XCTAssertEqual(v("http://127.0.0.1:8888"), .ok)
        XCTAssertEqual(v("http://localhost:8888"), .ok)
        XCTAssertEqual(v("http://[::1]:8888"), .ok)
        XCTAssertEqual(v("https://hindsight.example.com"), .ok)
        if case .warning = v("http://192.168.1.20:8888") {} else { XCTFail("réseau local : avertissement") }
        if case .warning = v("http://mac-mini.local:8888") {} else { XCTFail(".local : avertissement") }
        if case .warning = v("http://10.0.0.5:8888") {} else { XCTFail("10/8 : avertissement") }
        if case .rejected = v("http://hindsight.example.com") {} else { XCTFail("HTTP vers Internet refusé") }
        if case .rejected = v("http://8.8.8.8:8888") {} else { XCTFail("IP publique en HTTP refusée") }
        if case .rejected = v("https://user:pass@example.com") {} else { XCTFail("identifiants dans l'URL refusés") }
        if case .rejected = v("ftp://127.0.0.1") {} else { XCTFail("schéma refusé") }
        for address in ["http://127.example.com", "http://127.0.0.1.example.com", "http://fdpublic.example.com", "http://10.0.0.999", "https://memory.example.com?token=private", "https://memory.example.com#fragment"] {
            if case .rejected = v(address) {} else { XCTFail("adresse trompeuse ou ambiguë refusée : \(address)") }
        }
        for address in ["http://[fd00::1]:8888", "http://[fc00::1]:8888", "http://[fe80::1]:8888"] {
            if case .warning = v(address) {} else { XCTFail("IPv6 locale : avertissement") }
        }
    }

    func testAppInfoFromInfoPlist() {
        let info = AppInfo(
            infoDictionary: [
                "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "57", AppInfo.commitKey: "a1b2c3d4e5f6",
                AppInfo.sourceKey: "/Users/x/hindsight-mac", AppInfo.branchKey: "main",
            ], bundlePath: "/Applications/Hindsight.app")
        XCTAssertTrue(info.isBundled)
        XCTAssertEqual(info.displayVersion, "0.2.0 (57 · a1b2c3d)")
        XCTAssertEqual(info.sourceRepository, "/Users/x/hindsight-mac")
        let dev = AppInfo(infoDictionary: [:], bundlePath: "/work/.build/debug")
        XCTAssertFalse(dev.isBundled)
        XCTAssertEqual(dev.displayVersion, "dev (0)")
    }

    @MainActor
    func testAppModelRefusesUnencryptedRemoteURL() async {
        let app = AppModel(settings: InMemorySettingsStore(), transport: MockTransport(), runner: FakeRunner(), processRunner: FakeProcessRunner())
        let before = app.serverURL
        let ok = await app.applyServerURL("http://hindsight.example.com:8888")
        XCTAssertFalse(ok)
        XCTAssertEqual(app.serverURL, before)
        XCTAssertTrue(app.serverURLNotice?.contains("refusé") == true)
    }
}

final class LaunchAgentTests: XCTestCase {
    func testPlistRoundTrip() throws {
        let spec = LaunchAgentSpec(scriptPath: "/Users/x/.hindsight/start.sh", logPath: "/Users/x/Library/Logs/Hindsight/hindsight-api.log", runAtLoad: true, path: "/usr/bin:/bin")
        let data = try spec.data()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("<string>local.hindsight.api</string>"))
        XCTAssertEqual(LaunchAgentSpec.parse(data), spec)
        // Un chemin avec des caractères spéciaux reste une seule chaîne XML échappée (pas d'injection).
        let tricky = LaunchAgentSpec(scriptPath: "/tmp/a</string><string>-c", logPath: "/l", runAtLoad: false, path: "")
        XCTAssertEqual(LaunchAgentSpec.parse(try tricky.data())?.scriptPath, "/tmp/a</string><string>-c")
    }

    func testParsesLaunchctlPrint() {
        let running = """
            gui/501/local.hindsight.api = {
            \tactive count = 1
            \tpath = /Users/x/Library/LaunchAgents/local.hindsight.api.plist
            \tstate = running
            \tprogram = /Users/x/.hindsight/start.sh
            \tpid = 4242
            \tlast exit code = (never exited)
            \tendpoints = {
            \t\tstate = active
            \t}
            }
            """
        let s = LaunchJobStatus.parse(printOutput: running)
        XCTAssertEqual(s, LaunchJobStatus(loaded: true, running: true, pid: 4242, lastExitCode: nil))
        let stopped = LaunchJobStatus.parse(printOutput: "\tstate = not running\n\tlast exit code = 78: EX_CONFIG\n")
        XCTAssertFalse(stopped.running)
        XCTAssertNil(stopped.lastExitCode, "valeur non numérique ignorée")
        XCTAssertEqual(LaunchJobStatus.parse(printOutput: "\tstate = not running\n\tlast exit code = 1\n").lastExitCode, 1)
    }

    func testDetectsBackgroundedServer() {
        XCTAssertNil(LaunchScriptShape.backgroundingWarning(Fixture.string("start-api", ext: "sh")))
        XCTAssertNotNil(LaunchScriptShape.backgroundingWarning("#!/bin/bash\nnohup hindsight-api --port 8888 > /tmp/h.log 2>&1 &\n"))
        XCTAssertNotNil(LaunchScriptShape.backgroundingWarning("hindsight-api &   # en fond\n"))
        XCTAssertNil(LaunchScriptShape.backgroundingWarning("test -f x && exec hindsight-api\n# nohup ancien &\n"))
    }
}

@MainActor
final class HindsightServiceTests: XCTestCase {
    nonisolated(unsafe) var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-svc-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setPermissions(dir.path, 0o755)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    struct Env {
        let vm: HindsightServiceViewModel
        let runner: FakeProcessRunner
        let script: URL
        let store: InMemorySettingsStore
        let apiUp: Switch
        let jobRunning: Switch
        let paths: ServicePaths
    }

    func make(scriptMode: Int = 0o755, apiInitiallyUp: Bool = false) -> Env {
        let script = dir.appendingPathComponent("start-api.sh")
        try! Data(Fixture.string("start-api", ext: "sh").utf8).write(to: script)
        setPermissions(script.path, scriptMode)
        let apiUp = Switch(apiInitiallyUp), jobRunning = Switch(false), loaded = Switch(false), restarted = Switch(false)
        let t = MockTransport()
        t.on("GET", "/version") { _ in
            apiUp.value ? .json(Fixture.string("version")) : .json(#"{"detail":"down"}"#, status: 503)
        }
        let runner = FakeProcessRunner { inv in
            guard inv.executable == HindsightServiceViewModel.launchctl else { return ProcessOutput(status: 1) }
            switch inv.arguments.first {
            case "print":
                guard loaded.value else { return ProcessOutput(status: 113, stderr: "Could not find service") }
                return ProcessOutput(status: 0, stdout: jobRunning.value ? "\tstate = running\n\tpid = \(restarted.value ? 43 : 42)\n" : "\tstate = not running\n\tlast exit code = 0\n")
            case "bootstrap":
                loaded.value = true
                return ProcessOutput(status: 0)
            case "bootout":
                loaded.value = false
                jobRunning.value = false
                apiUp.value = false
                return ProcessOutput(status: 0)
            case "kickstart":
                if inv.arguments.contains("-k") { restarted.value = !restarted.value }
                jobRunning.value = true
                apiUp.value = true
                return ProcessOutput(status: 0)
            case "kill":
                jobRunning.value = false
                apiUp.value = false
                return ProcessOutput(status: 0)
            default:
                return ProcessOutput(status: 0)
            }
        }
        let store = InMemorySettingsStore()
        let paths = ServicePaths(launchAgents: dir.appendingPathComponent("LaunchAgents"), logs: dir.appendingPathComponent("Logs/Hindsight"))
        let client = makeClient(t)
        let vm = HindsightServiceViewModel(
            settings: store, runner: runner, paths: paths, client: { client }, scriptPath: { script.path },
            startTimeout: 2, stopTimeout: 2, pollInterval: .milliseconds(20))
        return Env(vm: vm, runner: runner, script: script, store: store, apiUp: apiUp, jobRunning: jobRunning, paths: paths)
    }

    func testInstallWritesAgentAndStartsServer() async throws {
        let e = make()
        await e.vm.refresh()
        XCTAssertEqual(e.vm.status, .notInstalled)
        var reconnected = false
        e.vm.onServerStarted = { reconnected = true }

        e.vm.requestInstall(startAtLogin: true)
        let c = try XCTUnwrap(e.vm.confirmation)
        XCTAssertTrue(c.message.contains(e.script.path))
        XCTAssertTrue(c.message.contains("SHA-256"))
        XCTAssertTrue(e.runner.args(of: HindsightServiceViewModel.launchctl).allSatisfy { $0.first == "print" }, "rien n'est lancé avant confirmation")
        await c.perform()

        let uid = FileSafety.currentUID
        let calls = e.runner.args(of: HindsightServiceViewModel.launchctl).filter { $0.first != "print" }
        XCTAssertEqual(calls, [["bootstrap", "gui/\(uid)", e.paths.plist.path], ["kickstart", "gui/\(uid)/local.hindsight.api"]])
        XCTAssertEqual(e.vm.status, .running(pid: 42))
        XCTAssertTrue(reconnected)
        XCTAssertEqual(permissions(e.paths.plist.path), 0o644)
        XCTAssertEqual(permissions(e.paths.logs.path), 0o700)
        XCTAssertEqual(permissions(e.paths.log.path), 0o600)
        let spec = try XCTUnwrap(LaunchAgentSpec.parse(Data(contentsOf: e.paths.plist)))
        XCTAssertEqual(spec.scriptPath, e.script.path)
        XCTAssertTrue(spec.runAtLoad)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: e.paths.plist), format: nil) as? [String: Any])
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?["HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH"], "true")
        XCTAssertEqual(e.store.string(forKey: SettingsKey.serviceScriptHash), SHA256.hex(try Data(contentsOf: e.script)))

        e.vm.setStartAtLogin(false)
        XCTAssertEqual(LaunchAgentSpec.parse(try Data(contentsOf: e.paths.plist))?.runAtLoad, false)
    }

    func testInstallMakesScriptExecutable() async throws {
        let e = make(scriptMode: 0o644)
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        let c = try XCTUnwrap(e.vm.confirmation)
        XCTAssertTrue(c.message.contains("chmod u+x"))
        await c.perform()
        XCTAssertEqual(permissions(e.script.path), 0o744)
        XCTAssertEqual(e.vm.status, .running(pid: 42))
    }

    func testRefusesScriptWritableByOthers() async {
        let e = make(scriptMode: 0o666)
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: true)
        XCTAssertNil(e.vm.confirmation)
        XCTAssertTrue(e.vm.message?.contains("modifiable par d'autres") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.plist.path))
    }

    func testChangedScriptRequiresReapproval() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        e.vm.confirmation = nil
        // Arrêt, puis modification du script hors de l'app
        await e.vm.stop()
        XCTAssertEqual(e.vm.message, "Serveur arrêté.")
        try Data("#!/bin/bash\nexec evil\n".utf8).write(to: e.script)
        await e.vm.refresh()
        XCTAssertTrue(e.vm.scriptChangedSinceApproval)

        e.vm.requestStart()
        let c = try XCTUnwrap(e.vm.confirmation, "le démarrage redemande confirmation")
        XCTAssertEqual(c.confirmTitle, "Approuver et démarrer")
        await c.perform()
        XCTAssertFalse(e.vm.scriptChangedSinceApproval)
        XCTAssertEqual(e.vm.status, .running(pid: 42))
    }

    func testStartRefusedWhenAnotherServerAnswers() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        e.apiUp.value = true  // serveur lancé hors de l'app
        await e.vm.refresh()
        XCTAssertEqual(e.vm.status, .runningExternally)
        XCTAssertFalse(e.vm.canStart)
        await e.vm.start()
        XCTAssertTrue(e.vm.message?.contains("répond déjà") == true)
    }

    func testStartFailureReportsLog() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        // Le serveur ne répond jamais ; le journal contient une clé, masquée à l'affichage.
        try Data("Traceback: invalid HINDSIGHT_API_LLM_API_KEY=sk-ant-abcdefghijklmnopqrstuv\n".utf8).write(to: e.paths.log)
        let base = e.runner.handler
        e.runner.handler = { inv in
            if inv.arguments.first == "kickstart" { return ProcessOutput(status: 0) }
            return base(inv)
        }
        await e.vm.start()
        XCTAssertTrue(e.vm.message?.contains("ne répond pas") == true)
        XCTAssertTrue(e.vm.logTail.contains("Traceback"))
        XCTAssertFalse(e.vm.logTail.contains("abcdefghijklmnop"))
    }

    func testStartPublishesBusyBeforeReturningAndIgnoresRepeatedClicks() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        e.vm.requestStart()
        XCTAssertTrue(e.vm.isBusy)
        XCTAssertEqual(e.vm.phase, "starting")
        e.vm.requestStart()
        for _ in 0..<100 where e.vm.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(e.vm.isBusy)
        XCTAssertTrue(e.vm.apiReachable)
    }

    func testFailedStartReadsRedirectedLogAndIgnoresEarlierFailure() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        let redirected = dir.appendingPathComponent("actual-api.log")
        try Data("ValueError: obsolete failure\n".utf8).write(to: redirected)
        let original = try String(contentsOf: e.script, encoding: .utf8)
        try (original + "\nexec server >> \"\(redirected.path)\" 2>&1\n").write(to: e.script, atomically: true, encoding: .utf8)
        e.vm.approveCurrentScript()
        let base = e.runner.handler
        e.runner.handler = { invocation in
            if invocation.arguments.first == "kickstart" {
                do {
                    let file = try FileHandle(forWritingTo: redirected)
                    try file.seekToEnd()
                    try file.write(contentsOf: Data("ValueError: missing reranker credential\n".utf8))
                    try file.close()
                    return ProcessOutput(status: 0)
                } catch { return ProcessOutput(status: 1, stderr: "Fixture log failed") }
            }
            return base(invocation)
        }
        await e.vm.start()
        XCTAssertEqual(e.vm.phase, "failed")
        XCTAssertTrue(e.vm.failure?.contains("missing reranker credential") == true)
        XCTAssertFalse(e.vm.failure?.contains("obsolete failure") == true)
        XCTAssertTrue(e.vm.logTail.contains("actual-api.log"))
        XCTAssertFalse(e.vm.isBusy)
    }

    func testMigratingAnOldAgentDoesNotKillTheNewRunAtLoadProcess() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: true)
        await e.vm.confirmation!.perform()
        var plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: e.paths.plist), format: nil) as? [String: Any])
        var environment = plist["EnvironmentVariables"] as! [String: String]
        environment["HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH"] = nil
        plist["EnvironmentVariables"] = environment
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: e.paths.plist)
        let base = e.runner.handler
        let fresh = Switch(false)
        e.runner.handler = { invocation in
            if invocation.arguments.first == "bootstrap" {
                let result = base(invocation)
                fresh.value = true
                e.jobRunning.value = true
                e.apiUp.value = true
                return result
            }
            if invocation.arguments.starts(with: ["kickstart", "-k"]), fresh.value {
                return ProcessOutput(status: 1, stderr: "Fresh startup was interrupted")
            }
            return base(invocation)
        }
        let success = await e.vm.restart()
        XCTAssertTrue(success)
        XCTAssertTrue(e.vm.apiReachable)
        XCTAssertEqual(e.runner.args(of: HindsightServiceViewModel.launchctl).last(where: { $0.first == "kickstart" }), ["kickstart", "gui/\(FileSafety.currentUID)/local.hindsight.api"])
    }

    func testScheduledLaunchIgnoresThePreviousProcessExitCode() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        let base = e.runner.handler
        let began = Date()
        let scheduled = Switch(false)
        e.runner.handler = { invocation in
            if invocation.arguments.first == "kickstart" { scheduled.value = true; return ProcessOutput(status: 0) }
            if invocation.arguments.first == "print", scheduled.value {
                if Date().timeIntervalSince(began) < 1.2 {
                    return ProcessOutput(status: 0, stdout: "state = spawn scheduled\nlast exit code = 1\n")
                }
                e.apiUp.value = true
                e.jobRunning.value = true
            }
            return base(invocation)
        }
        await e.vm.start()
        XCTAssertTrue(e.vm.apiReachable)
        XCTAssertNil(e.vm.failure)
    }

    func testUninstallRemovesAgent() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        e.vm.requestUninstall()
        await e.vm.confirmation!.perform()
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.plist.path))
        XCTAssertEqual(e.vm.status, .notInstalled)
        XCTAssertTrue(e.runner.args(of: HindsightServiceViewModel.launchctl).contains { $0.first == "bootout" })
    }

    func testServerSettingsRestartUsesManagedService() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()

        let t = MockTransport()
        t.installStandardRoutes()
        let client = makeClient(t)
        let store = InMemorySettingsStore([SettingsKey.launchScriptPath: e.script.path])
        let settingsVM = ServerSettingsViewModel(
            settings: store, runner: FakeRunner(), client: { client }, bank: { nil }, healthTimeout: 2, pollInterval: .milliseconds(20))
        settingsVM.service = e.vm
        XCTAssertTrue(settingsVM.usesManagedService)
        settingsVM.requestRestart()
        await settingsVM.confirmation!.perform()
        XCTAssertTrue(e.runner.args(of: HindsightServiceViewModel.launchctl).contains { $0.starts(with: ["kickstart", "-k"]) })
        XCTAssertEqual(settingsVM.restartState, .succeeded("Serveur redémarré."))
    }

    /// Geler la file : l'agent est réécrit avec HINDSIGHT_API_WORKER_ENABLED=false (pas le script), rechargé, et
    /// le reste à la réinstallation ; le dégel retire la variable.
    func testFreezingQueueRewritesAgentEnvironmentAndReloadsIt() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: true)
        await e.vm.confirmation!.perform()
        let scriptBefore = try Data(contentsOf: e.script)

        let frozen = await e.vm.setWorkerPaused(true)
        XCTAssertTrue(frozen)
        XCTAssertTrue(e.vm.isWorkerPaused)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: e.paths.plist), format: nil) as? [String: Any])
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?["HINDSIGHT_API_WORKER_ENABLED"], "false")
        XCTAssertEqual(try Data(contentsOf: e.script), scriptBefore, "le script de l'utilisateur n'est pas touché")
        let verbs = e.runner.args(of: HindsightServiceViewModel.launchctl).map { $0.first ?? "" }.filter { $0 != "print" }
        XCTAssertEqual(Array(verbs.suffix(3)), ["bootout", "bootstrap", "kickstart"], "launchd ne relit l'environnement qu'au chargement")
        XCTAssertEqual(e.vm.status, .running(pid: 42))

        e.vm.requestInstall(startAtLogin: true)
        await e.vm.confirmation!.perform()
        XCTAssertTrue(e.vm.isWorkerPaused, "une réinstallation ne dégèle pas la file")

        let resumed = await e.vm.setWorkerPaused(false)
        XCTAssertTrue(resumed)
        XCTAssertEqual(LaunchAgentSpec.parse(try Data(contentsOf: e.paths.plist))?.workerPaused, false)
    }

    /// Un serveur arrêté reste arrêté : le gel ne s'applique qu'à son prochain démarrage.
    func testFreezingAStoppedServerDoesNotStartIt() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: true)
        await e.vm.confirmation!.perform()
        e.vm.requestStop()
        await e.vm.confirmation!.perform()
        XCTAssertFalse(e.jobRunning.value)
        let before = e.runner.args(of: HindsightServiceViewModel.launchctl).count
        let ok = await e.vm.setWorkerPaused(true)
        XCTAssertTrue(ok)
        let verbs = e.runner.args(of: HindsightServiceViewModel.launchctl).dropFirst(before).map { $0.first ?? "" }.filter { $0 != "print" }
        XCTAssertEqual(verbs, [], "l'arrêt a déjà déchargé l'agent ; le gel ne le recharge et ne le relance pas")
        XCTAssertFalse(e.jobRunning.value)
        XCTAssertTrue(e.vm.isWorkerPaused)
    }

    private func clone(_ e: Env, runner: any ProcessRunning) -> HindsightServiceViewModel {
        let transport = MockTransport()
        transport.on("GET", "/version") { _ in
            e.apiUp.value ? .json(Fixture.string("version")) : .json("{}", status: 503)
        }
        let client = makeClient(transport)
        return HindsightServiceViewModel(settings: e.store, runner: runner, paths: e.paths,
            client: { client }, scriptPath: { e.script.path }, startTimeout: 0.2, stopTimeout: 0.2, pollInterval: .milliseconds(2))
    }

    func testInstallRejectsScriptChangedAfterConfirmation() async throws {
        let e = make()
        await e.vm.refresh()
        e.vm.requestInstall(startAtLogin: false)
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        try Data("#!/bin/sh\nexec unreviewed\n".utf8).write(to: e.script)
        await confirmation.perform()
        XCTAssertFalse(FileManager.default.fileExists(atPath: e.paths.plist.path))
        XCTAssertNil(e.store.string(forKey: SettingsKey.serviceScriptHash))
        XCTAssertTrue(e.runner.calls.isEmpty)
        XCTAssertTrue(e.vm.message?.contains("changé") == true)
    }

    func testReapprovalCannotApproveALaterVersionOfTheScript() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        await e.vm.stop()
        let approved = e.store.string(forKey: SettingsKey.serviceScriptHash)
        try Data("#!/bin/sh\nexec reviewed\n".utf8).write(to: e.script)
        e.vm.requestStart()
        let confirmation = try XCTUnwrap(e.vm.confirmation)
        let before = e.runner.calls.count
        try Data("#!/bin/sh\nexec unreviewed\n".utf8).write(to: e.script)
        await confirmation.perform()
        XCTAssertEqual(e.store.string(forKey: SettingsKey.serviceScriptHash), approved)
        XCTAssertEqual(e.runner.calls.count, before)
        XCTAssertFalse(e.vm.isBusy)
    }

    func testBootoutFailurePreservesInstallationAndReportsFailureEvenWithReachableAPI() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let plist = try Data(contentsOf: e.paths.plist)
        let base = e.runner.handler
        e.runner.handler = { invocation in
            invocation.arguments.first == "bootout" ? ProcessOutput(status: 1, stderr: "Permission denied") : base(invocation)
        }
        await e.vm.stop()
        XCTAssertEqual(e.vm.phase, "failed")
        XCTAssertTrue(e.vm.job.running)
        await e.vm.refresh()
        XCTAssertEqual(e.vm.phase, "failed", "a healthy API cannot erase a failed stop")
        await e.vm.uninstall()
        XCTAssertEqual(e.vm.phase, "failed")
        XCTAssertEqual(try Data(contentsOf: e.paths.plist), plist)
        XCTAssertTrue(e.vm.isInstalled)
        XCTAssertFalse(e.vm.isBusy)
    }

    func testUnreadableJobStatusIsNotTreatedAsAnAbsentServiceDuringUninstall() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let plist = try Data(contentsOf: e.paths.plist)
        let base = e.runner.handler
        e.runner.handler = { invocation in
            invocation.arguments.first == "print"
                ? ProcessOutput(status: 1, stderr: "Permission denied hsk_abcdefghijklmnopqrstuvwxyz") : base(invocation)
        }
        let before = e.runner.calls.count
        await e.vm.uninstall()
        XCTAssertEqual(try Data(contentsOf: e.paths.plist), plist)
        XCTAssertTrue(e.vm.isInstalled)
        XCTAssertEqual(e.vm.phase, "failed")
        XCTAssertTrue(e.vm.message?.contains("launchctl print") == true)
        XCTAssertFalse(e.vm.message?.contains("abcdefghijklmnopqrstuvwxyz") == true)
        XCTAssertTrue(e.runner.calls.dropFirst(before).allSatisfy { $0.arguments.first == "print" })
    }

    func testPauseReservesServiceBeforeAwaitAndIgnoresRapidRepeatedControls() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let gate = LifecycleGateRunner(e.runner)
        let vm = clone(e, runner: gate)
        await vm.refresh()
        await gate.holdNext("print")
        let pause = Task { await vm.setWorkerPaused(true) }
        for _ in 0..<1000 { if await gate.blocked { break }; await Task.yield() }
        XCTAssertTrue(vm.isBusy)
        let before = e.runner.calls.count
        for _ in 0..<100 {
            vm.requestStart(); vm.requestStop(); vm.requestRestart(); vm.setStartAtLogin(true)
        }
        await vm.stop()
        let restarted = await vm.restart()
        XCTAssertFalse(restarted)
        XCTAssertEqual(e.runner.calls.count, before)
        XCTAssertNil(vm.confirmation)
        await gate.release()
        let paused = await pause.value
        XCTAssertTrue(paused)
        XCTAssertTrue(vm.isWorkerPaused)
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(LaunchAgentSpec.parse(try Data(contentsOf: e.paths.plist))?.runAtLoad, false)
    }

    func testOlderRefreshCannotOverwriteANewerStoppedState() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let gate = LifecycleGateRunner(e.runner)
        let vm = clone(e, runner: gate)
        await vm.refresh()
        await gate.holdNext("print")
        let older = Task { await vm.refresh() }
        for _ in 0..<1000 { if await gate.blocked { break }; await Task.yield() }
        e.jobRunning.value = false
        e.apiUp.value = false
        await vm.refresh()
        XCTAssertEqual(vm.status, .stopped(lastExitCode: 0))
        await gate.release()
        await older.value
        XCTAssertEqual(vm.status, .stopped(lastExitCode: 0))
        XCTAssertFalse(vm.job.running)
    }

    func testStopCancelsScheduledSpawn() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let pending = Switch(true)
        let base = e.runner.handler
        e.apiUp.value = false
        e.jobRunning.value = false
        e.runner.handler = { invocation in
            if invocation.arguments.first == "print", pending.value {
                return ProcessOutput(status: 0, stdout: "state = spawn scheduled\nlast exit code = 1\n")
            }
            if invocation.arguments.first == "bootout" { pending.value = false }
            return base(invocation)
        }
        await e.vm.refresh()
        XCTAssertTrue(e.vm.canStop)
        await e.vm.stop()
        XCTAssertEqual(e.vm.message, "Serveur arrêté.")
        XCTAssertFalse(e.vm.job.loaded)
        XCTAssertFalse(e.vm.job.pending)
    }

    func testExternalAPIIsNotProofThatTheManagedRestartSucceeded() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        e.jobRunning.value = false
        let base = e.runner.handler
        e.runner.handler = { invocation in
            invocation.arguments.first == "kickstart" ? ProcessOutput(status: 0) : base(invocation)
        }
        let vm = clone(e, runner: e.runner)
        await vm.refresh()
        var callbacks = 0
        vm.onServerStarted = { callbacks += 1 }
        let success = await vm.restart()
        XCTAssertFalse(success)
        XCTAssertEqual(callbacks, 0)
        XCTAssertNil(vm.startedScriptHash)
        XCTAssertTrue(vm.apiReachable)
        XCTAssertEqual(vm.status, .runningExternally)
        XCTAssertEqual(vm.phase, "failed")
    }

    func testRemoteAPIIsNeverUsedToProveLocalServiceReadinessOrAuthorizeQueueChanges() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let transport = MockTransport()
        transport.installStandardRoutes()
        let client = HindsightClient(baseURL: URL(string: "https://remote.invalid")!, transport: transport)
        let vm = HindsightServiceViewModel(settings: e.store, runner: e.runner, paths: e.paths,
            client: { client }, scriptPath: { e.script.path })
        await vm.refresh()
        XCTAssertFalse(vm.apiReachable)
        XCTAssertTrue(transport.requests.isEmpty)
        let before = e.runner.calls.count
        let restarted = await vm.restart()
        let paused = await vm.setWorkerPaused(true)
        vm.requestStart()
        vm.requestInstall(startAtLogin: true)
        XCTAssertFalse(restarted)
        XCTAssertFalse(paused)
        XCTAssertNil(vm.confirmation)
        XCTAssertEqual(e.runner.calls.count, before)
        XCTAssertTrue(vm.message?.contains("adresse locale") == true)
        XCTAssertTrue(e.jobRunning.value)
    }

    func testRestartWaitsForReplacementPIDBeforeAcknowledgingTheNewScript() async throws {
        let e = make()
        e.vm.requestInstall(startAtLogin: false)
        await e.vm.confirmation!.perform()
        let restarting = Switch(), oldPIDSeen = Switch()
        let base = e.runner.handler
        e.runner.handler = { invocation in
            if invocation.arguments.starts(with: ["kickstart", "-k"]) { restarting.value = true; return ProcessOutput(status: 0) }
            if invocation.arguments.first == "print", restarting.value {
                let pid = oldPIDSeen.value ? 43 : 42
                oldPIDSeen.value = true
                return ProcessOutput(status: 0, stdout: "state = running\npid = \(pid)\n")
            }
            return base(invocation)
        }
        let success = await e.vm.restart()
        XCTAssertTrue(success)
        XCTAssertEqual(e.vm.job.pid, 43, "the old process can still answer briefly after kickstart")
    }

    func testFastRunAtLoadDuringInstallIsRecognizedAsOurOwnStartup() async throws {
        let e = make()
        let base = e.runner.handler
        e.runner.handler = { invocation in
            let output = base(invocation)
            if invocation.arguments.first == "bootstrap" { e.apiUp.value = true; e.jobRunning.value = true }
            return output
        }
        e.vm.requestInstall(startAtLogin: true)
        await e.vm.confirmation!.perform()
        XCTAssertEqual(e.vm.status, .running(pid: 42))
        XCTAssertNil(e.vm.failure)
        XCTAssertNotNil(e.vm.startedScriptHash)
        XCTAssertTrue(e.vm.message?.contains("API répond") == true)
    }
}

@MainActor
final class AppUpdateTests: XCTestCase {
    nonisolated(unsafe) var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-upd-\(UUID().uuidString)")
        let fm = FileManager.default
        try! fm.createDirectory(at: dir.appendingPathComponent("repo/.git"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: dir.appendingPathComponent("repo/scripts"), withIntermediateDirectories: true)
        try! Data("// products: HindsightMac\n".utf8).write(to: dir.appendingPathComponent("repo/Package.swift"))
        try! Data("#!/bin/bash\n".utf8).write(to: dir.appendingPathComponent("repo/scripts/make-app.sh"))
        try! fm.createDirectory(at: dir.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        makeBundle(at: dir.appendingPathComponent("Applications/Hindsight.app"), version: "old")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    nonisolated func makeBundle(at app: URL, version: String, identifier: String = AppInfo.bundleIdentifier) {
        let fm = FileManager.default
        try! fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "HindsightMac", "CFBundleShortVersionString": version]
        try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let exe = app.appendingPathComponent("Contents/MacOS/HindsightMac")
        try! Data("bin".utf8).write(to: exe)
        try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    }

    nonisolated static let head = "1111111111111111111111111111111111111111"
    nonisolated static let tip = "2222222222222222222222222222222222222222"

    struct Git: Sendable {
        var remote = "https://github.com/exemple/hindsight-mac.git"
        var branch = "main"
        var dirty = false
        var ancestor = true
        var commits = "\(AppUpdateTests.tip)\u{1f}Alice\u{1f}2026-10-18\u{1f}Graphe : légende\n3333333333333333333333333333333333333333\u{1f}Bob\u{1f}2026-10-17\u{1f}Corrige l'import"
    }

    func make(_ git: Git = Git(), bundled: Bool = true, tauri: Bool = false) -> (AppUpdateViewModel, FakeProcessRunner, InMemorySettingsStore) {
        let repo = dir.appendingPathComponent("repo")
        let built = repo.appendingPathComponent(tauri ? "desktop/.update-target/release/bundle/macos/Hindsight Desktop.app" : "build/Hindsight.app")
        if tauri {
            makeBundle(at: dir.appendingPathComponent("Applications/Hindsight.app"), version: "old", identifier: "local.hindsight.desktop.tauri")
            try! FileManager.default.createDirectory(at: repo.appendingPathComponent("desktop/src-tauri"), withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: repo.appendingPathComponent("desktop/scripts"), withIntermediateDirectories: true)
            try! Data("{}".utf8).write(to: repo.appendingPathComponent("desktop/src-tauri/tauri.conf.json"))
            try! Data("// fixture".utf8).write(to: repo.appendingPathComponent("desktop/scripts/update-build.mjs"))
        }
        let runner = FakeProcessRunner { [weak self] inv in
            if inv.executable == AppUpdateViewModel.bash || inv.arguments.first?.hasSuffix("update-build.mjs") == true {
                self?.makeBundle(at: built, version: "new", identifier: tauri ? "local.hindsight.desktop.tauri" : AppInfo.bundleIdentifier)
                return ProcessOutput(status: 0, stdout: "OK : build/Hindsight.app\n")
            }
            guard inv.executable == AppUpdateViewModel.git, inv.arguments.count > 2 else { return ProcessOutput(status: 1) }
            let a = Array(inv.arguments.dropFirst(2))
            switch a.first {
            case "rev-parse":
                if a.contains("--abbrev-ref") { return ProcessOutput(status: 0, stdout: git.branch + "\n") }
                return ProcessOutput(status: 0, stdout: (a.last!.hasPrefix("FETCH_HEAD") ? AppUpdateTests.tip : AppUpdateTests.head) + "\n")
            case "config": return ProcessOutput(status: 0, stdout: "origin\n")
            case "remote": return ProcessOutput(status: 0, stdout: git.remote + "\n")
            case "fetch": return ProcessOutput(status: 0)
            case "log": return ProcessOutput(status: 0, stdout: git.commits)
            case "merge-base": return ProcessOutput(status: git.ancestor ? 0 : 1)
            case "status": return ProcessOutput(status: 0, stdout: git.dirty ? " M README.md\n" : "")
            case "merge", "stash": return ProcessOutput(status: 0)
            default: return ProcessOutput(status: 1, stderr: "inattendu")
            }
        }
        let store = InMemorySettingsStore()
        let info = AppInfo(
            version: "0.2.0", build: "1", commit: Self.head, sourceRepository: repo.path,
            bundlePath: bundled ? dir.appendingPathComponent("Applications/Hindsight.app").path : nil)
        return (AppUpdateViewModel(settings: store, runner: runner, appInfo: info, tauri: tauri), runner, store)
    }

    func testTauriRebuildUsesSeparateDestinationAndInstallsCorrectBundle() async throws {
        let (vm, runner, _) = make(tauri: true)
        vm.requestRebuild()
        XCTAssertNotNil(vm.confirmation)
        XCTAssertFalse(runner.calls.contains { $0.arguments.first?.hasSuffix("update-build.mjs") == true })
        await vm.confirmation!.perform()
        XCTAssertEqual(vm.phase, .readyToRelaunch)
        XCTAssertTrue(runner.calls.contains { $0.executable != AppUpdateViewModel.bash && $0.arguments.first?.hasSuffix("desktop/scripts/update-build.mjs") == true })
        try BundleInstaller.validate(dir.appendingPathComponent("Applications/Hindsight.app"), identifier: "local.hindsight.desktop.tauri")
    }

    func testTauriBlocksDirtyCopyWithoutStashingOrMerging() async {
        var g = Git(); g.dirty = true
        let (vm, runner, _) = make(g, tauri: true)
        await vm.check(); vm.requestUpdate()
        XCTAssertNil(vm.confirmation)
        if case .failed = vm.phase {} else { XCTFail("Une copie modifiée doit être refusée") }
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("stash") || $0.arguments.contains("merge") })
    }

    func testTauriRefusesChangesAfterApproval() async throws {
        let (vm, runner, _) = make(tauri: true)
        await vm.check(); vm.requestUpdate()
        let confirmation = try XCTUnwrap(vm.confirmation)
        vm.repositoryPath = dir.appendingPathComponent("other-repo").path
        await confirmation.perform()
        if case .failed = vm.phase {} else { XCTFail("Le dépôt a changé") }
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("merge") })
    }

    func testCheckListsPendingCommitsWithoutShell() async {
        let (vm, runner, _) = make()
        await vm.check()
        XCTAssertEqual(vm.phase, .available)
        XCTAssertEqual(vm.pending.map(\.subject), ["Graphe : légende", "Corrige l'import"])
        XCTAssertEqual(vm.pending.first?.short, "2222222")
        XCTAssertTrue(runner.calls.allSatisfy { $0.executable == AppUpdateViewModel.git })
        XCTAssertTrue(runner.calls.allSatisfy { $0.environment["GIT_TERMINAL_PROMPT"] == "0" })
        XCTAssertTrue(runner.calls.contains { $0.arguments.suffix(5) == ["fetch", "--no-tags", "--quiet", "origin", "main"] })
    }

    func testUpdateFastForwardsToShownCommitRebuildsAndReplacesApp() async throws {
        let (vm, runner, store) = make()
        await vm.check()
        vm.requestUpdate()
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(c.message.contains("https://github.com/exemple/hindsight-mac.git"))
        XCTAssertTrue(c.message.contains("2222222  Graphe : légende — Alice, 2026-10-18"))
        XCTAssertTrue(c.message.contains("compilé puis exécuté"))
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("merge") }, "rien avant confirmation")
        await c.perform()
        XCTAssertTrue(runner.calls.contains { $0.arguments.suffix(4) == ["merge", "--ff-only", "--quiet", Self.tip] })
        XCTAssertTrue(runner.calls.contains { $0.executable == AppUpdateViewModel.bash && $0.arguments.first?.hasSuffix("scripts/make-app.sh") == true })
        XCTAssertEqual(vm.phase, .readyToRelaunch)
        let installed = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: dir.appendingPathComponent("Applications/Hindsight.app/Contents/Info.plist")), format: nil) as? [String: Any]
        XCTAssertEqual(installed?["CFBundleShortVersionString"] as? String, "new")
        XCTAssertEqual(store.string(forKey: SettingsKey.updateApprovedRemote), "https://github.com/exemple/hindsight-mac.git")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Applications").path)
        XCTAssertEqual(leftovers, ["Hindsight.app"], "aucune copie temporaire laissée")
    }

    func testRefusesUnencryptedOrUnsafeRemotes() async {
        var g = Git()
        g.remote = "http://example.com/hindsight-mac.git"
        var (vm, _, _) = make(g)
        await vm.check()
        guard case .failed(let m) = vm.phase else { return XCTFail() }
        XCTAssertTrue(m.contains("non chiffré"))

        g = Git()
        g.branch = "--upload-pack=evil"
        (vm, _, _) = make(g)
        await vm.check()
        guard case .failed(let m2) = vm.phase else { return XCTFail() }
        XCTAssertTrue(m2.contains("inattendu"))

        XCTAssertNil(AppUpdateViewModel.remoteProblem("git@github.com:exemple/hindsight-mac.git"))
        XCTAssertNil(AppUpdateViewModel.remoteProblem("ssh://git@github.com/exemple/hindsight-mac.git"))
        XCTAssertNotNil(AppUpdateViewModel.remoteProblem("ext::sh -c evil"))
        XCTAssertNotNil(AppUpdateViewModel.remoteProblem("/tmp/repo"))
    }

    func testDirtyRepositoryIsStashedBeforeUpdate() async throws {
        var g = Git()
        g.dirty = true
        let (vm, runner, _) = make(g)
        await vm.check()
        XCTAssertEqual(vm.dirtyFiles, ["README.md"])
        vm.requestUpdate()
        let c = try XCTUnwrap(vm.confirmation)
        XCTAssertTrue(c.message.contains("git stash") && c.message.contains("README.md"))
        XCTAssertEqual(c.confirmTitle, "Mettre de côté et mettre à jour")
        await c.perform()
        let calls = runner.calls.map { Array($0.arguments.dropFirst(2)) }
        let stash = try XCTUnwrap(calls.firstIndex { $0.first == "stash" })
        let merge = try XCTUnwrap(calls.firstIndex { $0.first == "merge" })
        XCTAssertLessThan(stash, merge, "mises de côté avant d'appliquer les commits")
        XCTAssertEqual(calls[stash].prefix(3), ["stash", "push", "--quiet"])
        XCTAssertFalse(vm.isDirty)
    }

    func testRefusesDivergedRepository() async {
        var g = Git()
        g.ancestor = false
        let (vm, runner, _) = make(g)
        await vm.check()
        vm.requestUpdate()
        XCTAssertNil(vm.confirmation)
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("merge") })
    }

    func testSignalsRemoteChangeSinceLastUpdate() async throws {
        let (vm, _, store) = make()
        store.set("https://github.com/autre/hindsight-mac.git", forKey: SettingsKey.updateApprovedRemote)
        await vm.check()
        XCTAssertTrue(vm.remoteChangedSinceApproval)
        vm.requestUpdate()
        XCTAssertTrue(try XCTUnwrap(vm.confirmation).message.contains("a changé depuis la dernière mise à jour"))
    }

    func testUpToDateAndRebuildAvailable() async {
        var g = Git()
        g.commits = ""
        let (vm, _, _) = make(g)
        await vm.check()
        XCTAssertEqual(vm.phase, .upToDate)

        // Copie locale avancée à la main : HEAD ≠ commit compilé
        let repo = dir.appendingPathComponent("repo")
        let info = AppInfo(version: "0.2.0", build: "1", commit: "9999999", sourceRepository: repo.path, bundlePath: "/Applications/Hindsight.app")
        let runner = FakeProcessRunner { inv in
            let a = Array(inv.arguments.dropFirst(2))
            switch a.first {
            case "rev-parse": return ProcessOutput(status: 0, stdout: a.contains("--abbrev-ref") ? "main" : Self.head)
            case "config": return ProcessOutput(status: 0, stdout: "origin")
            case "remote": return ProcessOutput(status: 0, stdout: "https://github.com/exemple/hindsight-mac.git")
            default: return ProcessOutput(status: 0)
            }
        }
        let vm2 = AppUpdateViewModel(settings: InMemorySettingsStore(), runner: runner, appInfo: info)
        await vm2.check()
        XCTAssertEqual(vm2.phase, .rebuildAvailable)
    }

    func testInvalidRepositoryAndUnbundledBuild() async {
        let (vm, _, _) = make(bundled: false)
        vm.repositoryPath = dir.path
        await vm.check()
        guard case .failed(let m) = vm.phase else { return XCTFail() }
        XCTAssertTrue(m.contains("n'est pas un dépôt git"))

        vm.repositoryPath = dir.appendingPathComponent("repo").path
        await vm.rebuild()
        XCTAssertEqual(vm.phase, .built(dir.appendingPathComponent("repo/build/Hindsight.app").path))
    }

    func testBundleInstallerRejectsForeignBundle() async throws {
        let foreign = dir.appendingPathComponent("Other.app")
        makeBundle(at: foreign, version: "x", identifier: "com.example.other")
        let current = dir.appendingPathComponent("Applications/Hindsight.app")
        XCTAssertThrowsError(try BundleInstaller.replace(current, with: foreign))
        let still = try PropertyListSerialization.propertyList(from: Data(contentsOf: current.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
        XCTAssertEqual(still?["CFBundleShortVersionString"] as? String, "old", "l'app en place est intacte")
    }
}

@MainActor
final class SetupTests: XCTestCase {
    func testSetupItemsReflectState() async {
        let store = InMemorySettingsStore([SettingsKey.launchScriptPath: "/nonexistent/start.sh"])
        let t = MockTransport()
        let app = AppModel(settings: store, transport: t, runner: FakeRunner(), processRunner: FakeProcessRunner())
        await app.connect()
        XCTAssertTrue(app.showsOnboarding)
        let items = app.setupItems()
        XCTAssertEqual(items.map(\.id), ["server", "service", "script"])
        XCTAssertEqual(items[0].state, .todo)
        XCTAssertEqual(items[0].action, .openSettings)
        XCTAssertEqual(items[2].state, .optional)
        app.finishOnboarding()
        XCTAssertFalse(app.showsOnboarding)

        t.installStandardRoutes()
        await app.connect()
        XCTAssertEqual(app.setupItems().first?.state, .ok)
    }
}
