import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Un programme à exécuter, avec ses arguments en tableau : jamais de shell, donc aucune injection
/// possible par un chemin, un nom de branche ou une URL.
public struct ProcessInvocation: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    public var currentDirectory: String?
    /// Variables ajoutées à l'environnement (ou le remplaçant entièrement si `inheritEnvironment` est faux).
    public var environment: [String: String]
    public var inheritEnvironment: Bool
    public var timeout: TimeInterval

    public init(
        _ executable: String, _ arguments: [String] = [], in currentDirectory: String? = nil,
        environment: [String: String] = [:], inheritEnvironment: Bool = true, timeout: TimeInterval = 60
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.inheritEnvironment = inheritEnvironment
        self.timeout = timeout
    }

    /// Forme lisible pour l'affichage (chaque argument cité si besoin).
    public var display: String {
        ([executable] + arguments).map { a in
            a.isEmpty || a.contains(where: { " \"'$\\`;&|<>*?()".contains($0) }) ? "'" + a.replacingOccurrences(of: "'", with: "'\\''") + "'" : a
        }.joined(separator: " ")
    }
}

public struct ProcessOutput: Sendable, Hashable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(status: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { status == 0 && !timedOut }
    public var combined: String { stderr.isEmpty ? stdout : stdout.isEmpty ? stderr : stdout + "\n" + stderr }
}

/// Exécution de programmes (git, launchctl, compilation). Remplaçable dans les tests.
public protocol ProcessRunning: Sendable {
    /// `onOutput` reçoit la sortie au fil de l'eau (stdout et stderr), pour les opérations longues.
    func run(_ invocation: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput
}

extension ProcessRunning {
    public func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        try await run(invocation, onOutput: nil)
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    /// PATH fixe des programmes lancés : une app ouverte depuis le Finder n'hérite pas du PATH du terminal,
    /// d'où l'ajout des emplacements Homebrew et utilisateur, APRÈS ceux du système (un dossier modifiable
    /// par l'utilisateur ne doit pas masquer un outil système).
    public static func standardPath(home: String = NSHomeDirectory()) -> String {
        ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin"]
            .joined(separator: ":")
    }

    public func run(_ inv: ProcessInvocation, onOutput: (@Sendable (String) -> Void)?) async throws -> ProcessOutput {
        let h = Handles()
        let p = h.process
        p.executableURL = URL(fileURLWithPath: inv.executable)
        p.arguments = inv.arguments
        if let dir = inv.currentDirectory { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
        var env = inv.inheritEnvironment ? ProcessInfo.processInfo.environment : [:]
        env["PATH"] = Self.standardPath()
        for (k, v) in inv.environment { env[k] = v }
        p.environment = env
        p.standardOutput = h.out
        p.standardError = h.err
        p.standardInput = FileHandle.nullDevice
        let outBox = Buffer(), errBox = Buffer()
        h.out.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            outBox.append(d)
            if !d.isEmpty { onOutput?(String(decoding: d, as: UTF8.self)) }
        }
        h.err.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            errBox.append(d)
            if !d.isEmpty { onOutput?(String(decoding: d, as: UTF8.self)) }
        }
        let timedOut = Flag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessOutput, Error>) in
                h.process.terminationHandler = { proc in
                    h.stopReading()
                    outBox.append(h.out.fileHandleForReading.readDataToEndOfFile())
                    errBox.append(h.err.fileHandleForReading.readDataToEndOfFile())
                    cont.resume(returning: ProcessOutput(status: proc.terminationStatus, stdout: outBox.text, stderr: errBox.text, timedOut: timedOut.value))
                }
                do {
                    try h.process.run()
                } catch {
                    h.stopReading()
                    cont.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + inv.timeout) {
                    if h.process.isRunning {
                        timedOut.set()
                        h.stop()
                    }
                }
            }
        } onCancel: {
            h.stop()
        }
    }

    /// Processus et tubes partagés entre les fils d'exécution (gestionnaires de fin, délai, annulation).
    final class Handles: @unchecked Sendable {
        let process = Process()
        let out = Pipe()
        let err = Pipe()

        /// SIGTERM, puis SIGKILL après 2 s si le programme ignore (ou a hérité un masque bloquant) SIGTERM.
        func stop() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                if process.isRunning && process.processIdentifier == pid { kill(pid, SIGKILL) }
            }
        }

        func stopReading() {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }
    }

    final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) {
            lock.lock()
            data.append(d)
            if data.count > 2_000_000 { data = data.suffix(1_000_000) }
            lock.unlock()
        }
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var v = false
        func set() {
            lock.lock()
            v = true
            lock.unlock()
        }
        var value: Bool {
            lock.lock()
            defer { lock.unlock() }
            return v
        }
    }
}
