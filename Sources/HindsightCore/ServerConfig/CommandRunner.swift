import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
}

/// Exécution d'une commande shell (redémarrage du serveur). Remplaçable dans les tests.
public protocol CommandRunner: Sendable {
    func run(_ command: String, timeout: TimeInterval) async throws -> CommandResult
}

/// Lance `command` via le shell de connexion de l'utilisateur (zsh sur macOS), sortie standard et
/// d'erreur réunies. Les commandes qui démarrent un serveur en arrière-plan (`nohup … &`) rendent la main.
public struct ShellCommandRunner: CommandRunner {
    public init() {}

    public func run(_ command: String, timeout: TimeInterval = 60) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            let shell = FileManager.default.fileExists(atPath: "/bin/zsh") ? "/bin/zsh" : "/bin/sh"
            p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = ["-lc", command]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            let box = OutputBox()
            pipe.fileHandleForReading.readabilityHandler = { h in box.append(h.availableData) }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                box.append(pipe.fileHandleForReading.readDataToEndOfFile())
                cont.resume(returning: CommandResult(status: proc.terminationStatus, output: box.text))
            }
            do {
                try p.run()
            } catch {
                cont.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) {
            lock.lock()
            data.append(d)
            lock.unlock()
        }
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data.suffix(20_000), as: UTF8.self)
        }
    }
}
