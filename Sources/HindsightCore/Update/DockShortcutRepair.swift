import Foundation
import CoreServices
import Darwin
import HindsightAPI

/// Repairs an existing shortcut after an older updater replaced the app's directory.
/// Never adds a pinned app or resets the user's Dock layout.
@MainActor
public enum DockShortcutRepair {
    public static let identifier = "local.hindsight.desktop.tauri"

    struct Bookmark {
        let url: URL
        let stale: Bool
    }
    struct Plan {
        let items: [[String: Any]]
        let repaired: Int
        let originals: [[String: Any]]
    }
    public struct Report: Sendable {
        public let repaired: Int
        public let refreshed: Bool
    }

    static func resolve(_ data: Data) throws -> Bookmark {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        return Bookmark(url: url, stale: stale)
    }

    static func plan(_ original: [[String: Any]], app: URL,
                     resolveBookmark: ((Data) throws -> Bookmark)? = nil) throws -> Plan {
        let app = app.standardizedFileURL.resolvingSymlinksInPath()
        var items = original, repaired = 0, originals: [[String: Any]] = []
        for index in items.indices {
            guard var tile = items[index]["tile-data"] as? [String: Any],
                  tile["bundle-identifier"] == nil || tile["bundle-identifier"] as? String == identifier,
                  let file = tile["file-data"] as? [String: Any],
                  let text = file["_CFURLString"] as? String,
                  let url = URL(string: text), url.isFileURL,
                  url.standardizedFileURL.resolvingSymlinksInPath().path == app.path else { continue }
            if let bytes = tile["book"] as? Data, let bookmark = try? (resolveBookmark ?? { try resolve($0) })(bytes),
               !bookmark.stale, bookmark.url.standardizedFileURL.resolvingSymlinksInPath().path == app.path { continue }
            let bookmark = try app.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            originals.append(["index": index, "entry": items[index]])
            tile["book"] = bookmark
            tile["file-data"] = ["_CFURLStringType": 15, "_CFURLString": app.absoluteString]
            tile["bundle-identifier"] = identifier
            // Dock rebuilds its own icon-cache timestamps when reloading the shortcut.
            tile["file-mod-date"] = nil
            tile["parent-mod-date"] = nil
            items[index]["tile-data"] = tile
            repaired += 1
        }
        return Plan(items: items, repaired: repaired, originals: originals)
    }

    /// Current user's Dock only. A brief Dock refresh is needed for legacy cached shortcuts;
    /// future content-only updates keep the app directory identity and do not enter this path.
    public static func repair(app: URL, refreshDock: Bool = true) throws -> Report {
        try BundleInstaller.validate(app, identifier: identifier)
        let domain = "com.apple.dock" as CFString, key = "persistent-apps" as CFString
        guard let original = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] else {
            return Report(repaired: 0, refreshed: false)
        }
        let update = try plan(original, app: app)
        guard update.repaired > 0 else { return Report(repaired: 0, refreshed: false) }
        guard let latest = CFPreferencesCopyAppValue(key, domain) as? NSArray,
              latest.isEqual(to: original) else { return Report(repaired: 0, refreshed: false) }
        // Back up only this application's affected entries, never the other pinned apps.
        let backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HindsightDesktop/repair-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try PropertyListSerialization.data(fromPropertyList: update.originals, format: .binary, options: 0)
        let file = backup.appendingPathComponent("dock-\(UUID().uuidString).plist")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        CFPreferencesSetAppValue(key, update.items as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw HindsightError.refused("Le raccourci du Dock n’a pas pu être enregistré.")
        }
        LSRegisterURL(app as CFURL, true)
        guard refreshDock else { return Report(repaired: update.repaired, refreshed: false) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", String(getuid()), "Dock"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return Report(repaired: update.repaired, refreshed: process.terminationStatus == 0)
    }
}
