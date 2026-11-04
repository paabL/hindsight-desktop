import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Identité de l'app en cours d'exécution, lue dans son Info.plist (renseigné par scripts/make-app.sh).
public struct AppInfo: Sendable, Hashable {
    public static let bundleIdentifier = "local.hindsight.mac"
    /// Clés ajoutées à l'Info.plist au moment de la construction.
    public static let sourceKey = "HindsightSourceRepository"
    public static let commitKey = "HindsightGitCommit"
    public static let branchKey = "HindsightGitBranch"

    public let version: String
    public let build: String
    /// Commit compilé (absent pour `swift run`).
    public let commit: String?
    public let branch: String?
    /// Dossier du dépôt git à partir duquel l'app a été construite.
    public let sourceRepository: String?
    /// Emplacement du bundle `.app`, ou `nil` si l'app tourne comme exécutable SwiftPM.
    public let bundlePath: String?

    public init(version: String, build: String, commit: String? = nil, branch: String? = nil, sourceRepository: String? = nil, bundlePath: String? = nil) {
        self.version = version
        self.build = build
        self.commit = commit
        self.branch = branch
        self.sourceRepository = sourceRepository
        self.bundlePath = bundlePath
    }

    public init(infoDictionary info: [String: Any], bundlePath: String) {
        func value(_ k: String) -> String? {
            (info[k] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        self.init(
            version: value("CFBundleShortVersionString") ?? "dev", build: value("CFBundleVersion") ?? "0",
            commit: value(Self.commitKey), branch: value(Self.branchKey), sourceRepository: value(Self.sourceKey),
            bundlePath: bundlePath.hasSuffix(".app") ? bundlePath : nil)
    }

    public static var current: AppInfo {
        AppInfo(infoDictionary: Bundle.main.infoDictionary ?? [:], bundlePath: Bundle.main.bundleURL.path)
    }

    public var isBundled: Bool { bundlePath != nil }
    public var shortCommit: String? { commit.map { String($0.prefix(7)) } }

    /// « 0.2.0 (57 · a1b2c3d) »
    public var displayVersion: String {
        var details = [build]
        if let c = shortCommit { details.append(c) }
        return "\(version) (\(details.joined(separator: " · ")))"
    }
}

/// Règles d'acceptation de l'URL du serveur. Le trafic HTTP n'est pas chiffré : il est accepté vers ce Mac,
/// toléré sur le réseau local (avec un avertissement), refusé vers Internet.
public enum ServerURLPolicy {
    public enum Verdict: Sendable, Equatable {
        case ok
        case warning(String)
        case rejected(String)

        public var message: String? {
            switch self {
            case .ok: return nil
            case .warning(let m), .rejected(let m): return m
            }
        }
        public var isAccepted: Bool {
            if case .rejected = self { return false }
            return true
        }
    }

    public static func evaluate(_ url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .rejected("Seules les URL http:// et https:// sont acceptées.")
        }
        if url.user != nil || url.password != nil {
            return .rejected("N'incluez pas d'identifiants dans l'URL : ils seraient enregistrés en clair dans les préférences.")
        }
        if url.query != nil || url.fragment != nil {
            return .rejected("L'adresse du serveur ne doit contenir ni paramètres ni fragment.")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .rejected("URL sans nom d'hôte.") }
        if scheme == "https" || isLoopback(host) { return .ok }
        if isLocalNetwork(host) {
            return .warning("Connexion HTTP non chiffrée sur le réseau local : le contenu des banques y circule en clair. Préférez HTTPS ou un tunnel SSH.")
        }
        return .rejected("HTTP non chiffré vers Internet refusé : utilisez https:// (ou un tunnel SSH vers 127.0.0.1).")
    }

    static func isLoopback(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" { return true }
        if let parts = ipv4(h) { return parts[0] == 127 }
        if let bytes = ipv6(h) { return bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1 }
        return false
    }

    static func isLocalNetwork(_ host: String) -> Bool {
        if host.hasSuffix(".local") || !host.contains(".") && !host.contains(":") { return true }
        guard let parts = ipv4(host) else {
            // IPv6 lien local (fe80::/10) ou unique local (fc00::/7), jamais un nom DNS commençant par fd.
            guard let bytes = ipv6(host) else { return false }
            return bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true  // CGNAT (Tailscale…)
        default: return false
        }
    }

    private static func ipv4(_ host: String) -> [UInt8]? {
        let words = host.split(separator: ".", omittingEmptySubsequences: false)
        guard words.count == 4, words.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let bytes = words.compactMap { UInt8($0) }
        return bytes.count == 4 ? bytes : nil
    }

    private static func ipv6(_ host: String) -> [UInt8]? {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var address = in6_addr()
        guard h.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}
