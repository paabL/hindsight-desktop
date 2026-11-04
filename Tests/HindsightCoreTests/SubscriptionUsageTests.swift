import Foundation
import XCTest

@testable import HindsightCore

/// Quotas d'abonnement : réponses des endpoints d'usage, cache de Claude Code, jetons expirés.
final class SubscriptionUsageTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesClaudeUsageWithMicroseconds() throws {
        let json = #"{"five_hour": {"utilization": 18, "resets_at": "2027-01-15T08:00:00.458950+00:00"}, "seven_day": {"utilization": 49.5, "resets_at": null}}"#
        let q = try XCTUnwrap(SubscriptionUsage.parseClaude(Data(json.utf8), now: t0))
        XCTAssertEqual(q.primary?.usedPercent, 18)
        XCTAssertEqual(q.primary?.title, "5 h")
        XCTAssertEqual(q.primary?.resetsAt, ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z"))
        XCTAssertEqual(q.secondary?.title, "semaine")
        XCTAssertNil(q.secondary?.resetsAt)
        XCTAssertEqual(q.observedAt, t0)
        XCTAssertNil(SubscriptionUsage.parseClaude(Data(#"{"error": "x"}"#.utf8), now: t0))
    }

    func testParsesCodexUsage() throws {
        let json = #"""
            {"plan_type": "prolite", "rate_limit": {"allowed": true, "primary_window": {"used_percent": 7, "limit_window_seconds": 604800,
             "reset_after_seconds": 600, "reset_at": 1800000600}, "secondary_window": null}}
            """#
        let q = try XCTUnwrap(SubscriptionUsage.parseCodex(Data(json.utf8), now: t0))
        XCTAssertEqual(q.primary?.usedPercent, 7)
        XCTAssertEqual(q.primary?.title, "semaine")
        XCTAssertEqual(q.primary?.resetsAt, t0.addingTimeInterval(600))
        XCTAssertNil(q.secondary)
    }

    func testReadsClaudeCodeCacheWithItsDate() throws {
        let json = #"{"cachedUsageUtilization": {"fetchedAtMs": 1800000000000, "utilization": {"five_hour": {"utilization": 3}}}}"#
        let q = try XCTUnwrap(SubscriptionUsage.claudeCache(Data(json.utf8)))
        XCTAssertEqual(q.observedAt, t0, "la date du relevé de Claude Code, pas celle de la lecture")
        XCTAssertEqual(q.primary?.usedPercent, 3)
    }

    func testExpiredTokensAreNeverUsed() {
        let expired = #"{"claudeAiOauth": {"accessToken": "a", "expiresAt": 1799999999000}}"#
        let valid = #"{"claudeAiOauth": {"accessToken": "a", "expiresAt": 1800000600000}}"#
        XCTAssertThrowsError(try SubscriptionUsage.claudeToken(credentials: Data(expired.utf8), now: t0).get())
        XCTAssertEqual(try SubscriptionUsage.claudeToken(credentials: Data(valid.utf8), now: t0).get(), "a")

        func jwt(exp: Int) -> String {
            let payload = Data(#"{"exp": \#(exp)}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            return "h.\(payload).s"
        }
        func auth(_ token: String) -> Data { Data(#"{"tokens": {"access_token": "\#(token)", "account_id": "acc"}}"#.utf8) }
        XCTAssertThrowsError(try SubscriptionUsage.codexToken(auth: auth(jwt(exp: 1_799_999_000)), now: t0).get())
        let ok = try? SubscriptionUsage.codexToken(auth: auth(jwt(exp: 1_800_001_000)), now: t0).get()
        XCTAssertEqual(ok?.1, "acc")
        XCTAssertThrowsError(try SubscriptionUsage.codexToken(auth: Data(#"{"OPENAI_API_KEY": null}"#.utf8), now: t0).get())
    }

    func testNewestReadingWins() {
        let live = CodexQuota(primary: .init(usedPercent: 1), secondary: nil, observedAt: t0)
        let session = CodexQuota(primary: .init(usedPercent: 2), secondary: nil, observedAt: t0.addingTimeInterval(-60))
        XCTAssertEqual(ConsumptionMonitor.newest(live, session), live)
        XCTAssertEqual(ConsumptionMonitor.newest(nil, session), session)
    }
}
