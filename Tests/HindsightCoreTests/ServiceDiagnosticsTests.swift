import XCTest
@testable import HindsightCore

final class ServiceDiagnosticsTests: XCTestCase {
    func testRedirectedLogUsesLiteralVariablesWithoutExecutingShell() {
        let script = "ROOT=\"$HOME/.hindsight\"\nexec \"$ROOT/venv/bin/hindsight-api\" >> \"$ROOT/embedding2-api.log\" 2>&1\n"
        XCTAssertEqual(ServiceDiagnostics.redirectedLog(in: script, home: "/example")?.path, "/example/.hindsight/embedding2-api.log")
        XCTAssertNil(ServiceDiagnostics.redirectedLog(in: "ROOT=$(dangerous)\nexec server > \"$ROOT/log\""))
        XCTAssertNil(ServiceDiagnostics.redirectedLog(in: "# exec server > /private/log\n"))
    }

    func testLargeLogTailIsBoundedAndReportsOnlyTheNewestMaskedError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hs-diagnostic-stress-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = "ValueError: obsolete failure\n" + String(repeating: "synthetic log line\n", count: 750_000)
        try Data(old.utf8).write(to: url)
        let offset = UInt64(old.utf8.count)
        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        try file.write(contentsOf: Data("ValueError: API_KEY=fixture-private-credential newest failure\n".utf8))
        try file.close()
        let tail = ServiceDiagnostics.tail(url)
        XCTAssertLessThanOrEqual(tail.utf8.count, 65_536)
        XCTAssertTrue(tail.contains("newest failure"))
        XCTAssertFalse(tail.contains("obsolete failure"))
        XCTAssertFalse(tail.contains("fixture-private-credential"))
        XCTAssertTrue(ServiceDiagnostics.error(in: ServiceDiagnostics.tail(url, after: offset))?.contains("newest failure") == true)
        try Data("RuntimeError: rotated file\n".utf8).write(to: url)
        XCTAssertEqual(ServiceDiagnostics.tail(url, after: offset), "RuntimeError: rotated file\n")
    }
}
