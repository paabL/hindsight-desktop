import XCTest
@testable import HindsightCore

final class ServiceDiagnosticsTests: XCTestCase {
    func testRedirectedLogUsesLiteralVariablesWithoutExecutingShell() {
        let script = "ROOT=\"$HOME/.hindsight\"\nexec \"$ROOT/venv/bin/hindsight-api\" >> \"$ROOT/embedding2-api.log\" 2>&1\n"
        XCTAssertEqual(ServiceDiagnostics.redirectedLog(in: script, home: "/example")?.path, "/example/.hindsight/embedding2-api.log")
        XCTAssertNil(ServiceDiagnostics.redirectedLog(in: "ROOT=$(dangerous)\nexec server > \"$ROOT/log\""))
        XCTAssertNil(ServiceDiagnostics.redirectedLog(in: "# exec server > /private/log\n"))
    }
}
