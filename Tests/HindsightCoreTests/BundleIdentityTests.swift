import Foundation
import XCTest
@testable import HindsightCore

final class BundleIdentityTests: XCTestCase {
    private let identifier = "local.hindsight.desktop.tauri"

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hindsight-bundle-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func app(_ root: URL, name: String, version: String, identifier: String? = nil) throws -> URL {
        let app = root.appendingPathComponent(name + ".app", isDirectory: true)
        let executable = app.appendingPathComponent("Contents/MacOS/test")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info = ["CFBundleIdentifier": identifier ?? self.identifier, "CFBundleExecutable": "test", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(version.utf8).write(to: app.appendingPathComponent("Contents/payload"))
        return app
    }

    func testTwoUpdatesPreserveThePinnedBundleIdentityAndBookmark() throws {
        let root = try fixture()
        let current = try app(root, name: "Installed", version: "1")
        let before = try FileManager.default.attributesOfItem(atPath: current.path)[.systemFileNumber] as! NSNumber
        let bookmark = try current.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        for version in ["2", "3"] {
            let new = try app(root, name: "New\(version)", version: version)
            try BundleInstaller.replace(current, with: new, identifier: identifier)
            let after = try FileManager.default.attributesOfItem(atPath: current.path)[.systemFileNumber] as! NSNumber
            XCTAssertEqual(before, after)
            XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("Contents/payload"), encoding: .utf8), version)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            XCTAssertFalse(stale, "An existing Dock shortcut must remain valid after every update")
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: resolved.path)[.systemFileNumber] as? NSNumber, before)
        }
    }

    func testInvalidPayloadLeavesTheExistingBundleAndIdentityIntact() throws {
        let root = try fixture(), current = try app(root, name: "Installed", version: "1")
        let alien = try app(root, name: "Alien", version: "2", identifier: "example.other")
        let before = try FileManager.default.attributesOfItem(atPath: current.path)[.systemFileNumber] as! NSNumber
        XCTAssertThrowsError(try BundleInstaller.replace(current, with: alien, identifier: identifier))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: current.path)[.systemFileNumber] as? NSNumber, before)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("Contents/payload"), encoding: .utf8), "1")
    }

    func testAnExistingForeignAppIsNotOverwritten() throws {
        let root = try fixture()
        let foreign = try app(root, name: "Foreign", version: "1", identifier: "example.other")
        let new = try app(root, name: "New", version: "2")
        XCTAssertThrowsError(try BundleInstaller.replace(foreign, with: new, identifier: identifier))
        XCTAssertEqual(try String(contentsOf: foreign.appendingPathComponent("Contents/payload"), encoding: .utf8), "1")
    }

    func testFirstInstallationStillWorks() throws {
        let root = try fixture(), new = try app(root, name: "New", version: "1")
        let destination = root.appendingPathComponent("Installed.app")
        try BundleInstaller.replace(destination, with: new, identifier: identifier)
        try BundleInstaller.validate(destination, identifier: identifier)
    }
}
