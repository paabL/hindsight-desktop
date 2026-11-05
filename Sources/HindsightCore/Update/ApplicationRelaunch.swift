import Foundation
import Darwin

/// The old GUI must finish exiting before LaunchServices opens the installed bundle.
public enum ApplicationRelaunch {
    public enum Failure: Error { case invalidProcess, parentStillRunning, launchFailed }

    public static func waitForExit(pid: Int32, timeout: Duration = .seconds(30),
                                   isRunning: @Sendable (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) async throws {
        guard pid > 1, pid != getpid() else { throw Failure.invalidProcess }
        let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: timeout)
        while isRunning(pid) {
            guard clock.now < deadline else { throw Failure.parentStillRunning }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    public static func relaunch(app: URL, after pid: Int32) async throws {
        try BundleInstaller.validate(app, identifier: DockShortcutRepair.identifier)
        try await waitForExit(pid: pid)
        try Task.checkCancellation()
        _ = try? DockShortcutRepair.repair(app: app)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // No -n: reuse a concurrent normal launch instead of creating another instance.
        process.arguments = [app.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.launchFailed }
    }
}
