import Foundation
import XCTest
@testable import HindsightCore

@MainActor
final class DockShortcutRepairTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hindsight-dock-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Hindsight Desktop.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return app
    }

    private func tile(_ app: URL, bookmark: Data? = nil, identifier: String = DockShortcutRepair.identifier) -> [String: Any] {
        var info: [String: Any] = ["file-data": ["_CFURLStringType": 15, "_CFURLString": app.absoluteString],
            "bundle-identifier": identifier, "file-label": "My memory", "custom-value": "kept"]
        info["book"] = bookmark
        return ["tile-type": "file-tile", "tile-data": info, "GUID": 42]
    }

    func testMissingShortcutDoesNotPinAnAppOrChangeOtherEntries() throws {
        let app = try fixture()
        let others: [[String: Any]] = [["tile-type": "spacer-tile"], ["tile-data": ["file-label": "Other app"]]]
        let result = try DockShortcutRepair.plan(others, app: app)
        XCTAssertEqual(result.repaired, 0)
        XCTAssertTrue((result.items as NSArray).isEqual(to: others))
    }

    func testFreshBookmarkIsUnchanged() throws {
        let app = try fixture()
        let bookmark = try app.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let original = [tile(app, bookmark: bookmark)]
        let result = try DockShortcutRepair.plan(original, app: app)
        XCTAssertEqual(result.repaired, 0)
        XCTAssertTrue((result.items as NSArray).isEqual(to: original))
    }

    func testStaleShortcutIsRepairedInPlaceWithoutChangingOtherAppsOrLabel() throws {
        let app = try fixture()
        var stale = tile(app, bookmark: Data("old".utf8))
        var info = stale["tile-data"] as! [String: Any]
        info["file-mod-date"] = 123
        info["parent-mod-date"] = 456
        stale["tile-data"] = info
        let other: [String: Any] = ["tile-type": "file-tile", "tile-data": ["bundle-identifier": "example.other", "book": Data([1, 2, 3])]]
        let original = [other, stale, ["tile-type": "spacer-tile"]]
        let result = try DockShortcutRepair.plan(original, app: app, resolveBookmark: { _ in
            DockShortcutRepair.Bookmark(url: app, stale: true)
        })
        XCTAssertEqual(result.repaired, 1)
        XCTAssertEqual(result.items.count, original.count)
        XCTAssertTrue((result.items[0] as NSDictionary).isEqual(to: original[0]))
        XCTAssertTrue((result.items[2] as NSDictionary).isEqual(to: original[2]))
        XCTAssertEqual(result.items[1]["GUID"] as? Int, 42)
        let updated = result.items[1]["tile-data"] as! [String: Any]
        XCTAssertEqual(updated["file-label"] as? String, "My memory")
        XCTAssertEqual(updated["custom-value"] as? String, "kept")
        XCTAssertNil(updated["file-mod-date"])
        let fresh = try DockShortcutRepair.resolve(XCTUnwrap(updated["book"] as? Data))
        XCTAssertFalse(fresh.stale)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fresh.url.path)[.systemFileNumber] as? NSNumber,
                       try FileManager.default.attributesOfItem(atPath: app.path)[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(result.originals.first?["index"] as? Int, 1)
    }

    func testAnotherCopyWithTheSameBundleIdentifierIsNotRetargeted() throws {
        let app = try fixture()
        let copy = app.deletingLastPathComponent().appendingPathComponent("Another copy.app")
        let original = [tile(copy, bookmark: Data([0]))]
        let result = try DockShortcutRepair.plan(original, app: app)
        XCTAssertEqual(result.repaired, 0)
        XCTAssertTrue((result.items as NSArray).isEqual(to: original))
    }

    func testDifferentApplicationAtTheSamePathIsNotModified() throws {
        let app = try fixture()
        let original = [tile(app, bookmark: Data([0]), identifier: "example.other")]
        let result = try DockShortcutRepair.plan(original, app: app)
        XCTAssertEqual(result.repaired, 0)
        XCTAssertTrue((result.items as NSArray).isEqual(to: original))
    }

    func testActualBundleReplacementMakesOldBookmarkRepairable() throws {
        let app = try fixture()
        let bytes = try app.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let old = app.deletingLastPathComponent().appendingPathComponent("old.app")
        try FileManager.default.moveItem(at: app, to: old)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let original = [tile(app, bookmark: bytes)]
        let result = try DockShortcutRepair.plan(original, app: app)
        XCTAssertEqual(result.repaired, 1)
        let info = result.items[0]["tile-data"] as! [String: Any]
        let repaired = try DockShortcutRepair.resolve(XCTUnwrap(info["book"] as? Data))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: repaired.url.path)[.systemFileNumber] as? NSNumber,
                       try FileManager.default.attributesOfItem(atPath: app.path)[.systemFileNumber] as? NSNumber)
        XCTAssertFalse(repaired.stale)
    }
}

final class ApplicationRelaunchTests: XCTestCase {
    func testRestartWaitsUntilTheOldProcessStops() async throws {
        let start = ContinuousClock().now
        try await ApplicationRelaunch.waitForExit(pid: 2000000000, timeout: .seconds(1), isRunning: { _ in
            ContinuousClock().now - start < .milliseconds(120)
        })
        XCTAssertGreaterThanOrEqual(ContinuousClock().now - start, .milliseconds(120))
    }

    func testStillRunningProcessTimesOutRatherThanOpeningAnotherInstance() async {
        do {
            try await ApplicationRelaunch.waitForExit(pid: 2000000000, timeout: .milliseconds(10), isRunning: { _ in true })
            XCTFail("A live process must not authorize the relaunch")
        } catch ApplicationRelaunch.Failure.parentStillRunning {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testSystemAndHelperProcessIDsAreRejected() async {
        for pid: Int32 in [0, 1, -1, getpid()] {
            do {
                try await ApplicationRelaunch.waitForExit(pid: pid, isRunning: { _ in false })
                XCTFail("Invalid PID must never authorize a relaunch")
            } catch ApplicationRelaunch.Failure.invalidProcess {} catch { XCTFail("Unexpected error") }
        }
    }
}
