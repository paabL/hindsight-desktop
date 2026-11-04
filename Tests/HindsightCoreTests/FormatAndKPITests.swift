import XCTest
import HindsightAPI
@testable import HindsightCore

@MainActor
final class FormatAndKPITests: XCTestCase {
    let now = HSDate.parse("2026-10-18T12:00:00Z")!

    func snapshot() -> DashboardSnapshot {
        let stats = try! JSONDecoder().decode(BankStatsResponse.self, from: Data(Fixture.string("bank_stats").utf8))
        var s = DashboardSnapshot(stats: stats, fetchedAt: now)
        s.entityTotal = 3800
        s.timeseries = try! JSONDecoder().decode(MemoriesTimeseriesResponse.self, from: Data(Fixture.string("timeseries").utf8))
        return s
    }

    func testKPIs() async {
        let k = Dictionary(uniqueKeysWithValues: snapshot().kpis(now: now).map { ($0.id, $0) })
        XCTAssertEqual(k["entities"]?.value.filter(\.isNumber), "3800")
        XCTAssertEqual(k["failures"]?.tone, .critical)
        XCTAssertTrue(k["failures"]!.subtitle!.contains("3 opération"))
        XCTAssertEqual(k["pending-consolidation"]?.tone, .warning)
        XCTAssertEqual(k["pending-consolidation"]?.subtitle, "dernière : il y a 3 jours")
        XCTAssertEqual(k["last-write"]?.value, "il y a 15 h")
        XCTAssertTrue(k["observations"]!.subtitle!.hasPrefix("consolidés à 97"))
        XCTAssertEqual(k["facts"]?.value.filter(\.isNumber), "7600")
    }

    func testChartPointsSkipEmptyBuckets() async {
        let pts = snapshot().chartPoints
        XCTAssertEqual(pts.count, 5)  // 16/10 : world+experience ; 17/10 : world+experience+observation
        XCTAssertEqual(pts.filter { $0.type == "observation" }.map(\.count), [4])
        XCTAssertEqual(Set(pts.map(\.id)).count, pts.count)
    }

    func testFormatting() async {
        XCTAssertEqual(Format.percent(0.9666), "97 %")
        XCTAssertEqual(Format.duration(milliseconds: 850), "850 ms")
        XCTAssertEqual(Format.duration(milliseconds: 12_340), "12.3 s")
        XCTAssertEqual(Format.duration(milliseconds: 125_000), "2 min 05 s")
        XCTAssertEqual(Format.dateTime(nil), "—")
        XCTAssertEqual(Format.dateTime("n'importe quoi"), "n'importe quoi")
        XCTAssertFalse(Format.dateTime("2026-10-18T12:00:00Z").isEmpty)
        XCTAssertTrue(Format.number(8012).filter(\.isNumber) == "8012")
    }

    func testConfirmationRequiredText() async {
        let c = ConfirmationRequest(title: "t", message: "m", confirmTitle: "ok", requiredText: "codex-diag") {}
        XCTAssertFalse(c.isSatisfied(by: ""))
        XCTAssertFalse(c.isSatisfied(by: "codex"))
        XCTAssertTrue(c.isSatisfied(by: "codex-diag"))
        let free = ConfirmationRequest(title: "t", message: "m", confirmTitle: "ok") {}
        XCTAssertTrue(free.isSatisfied(by: ""))
    }
}
