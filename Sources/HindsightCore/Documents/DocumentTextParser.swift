import Foundation
import HindsightAPI

/// Référence à une pièce jointe rencontrée dans le texte (`⟦hs-att:<id>⟧`).
public struct AttachmentRef: Sendable, Hashable {
    /// Contenu brut du jeton, sans les délimiteurs.
    public let token: String
    /// Identifiant extrait du jeton (préfixe du sha256).
    public let id: String
    /// Métadonnées si la pièce jointe est connue du document / des chunks ; `nil` sinon.
    public let attachment: ChunkAttachment?

    public var isImage: Bool {
        guard let a = attachment else { return false }
        return a.kind == "image" || a.mediaType.hasPrefix("image/")
    }
}

/// Un bloc affichable du document : un morceau de texte ou une pièce jointe, à sa place d'origine.
public struct ReaderBlock: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case text(String)
        case attachment(AttachmentRef)
    }

    public let id: Int
    public let kind: Kind
    /// Intervalle dans le texte source, en unités UTF-16.
    public let range: Range<Int>

    public var text: String? {
        if case .text(let t) = kind { return t }
        return nil
    }
    public var attachmentRef: AttachmentRef? {
        if case .attachment(let a) = kind { return a }
        return nil
    }
}

public enum DocumentTextParser {
    static let tokenPattern = try! NSRegularExpression(pattern: "\u{27E6}hs-att:([^\u{27E7}]*)\u{27E7}")

    /// Découpe `text` en blocs : texte (morceaux de `maxTextBlock` caractères au plus, coupés aux retours à la
    /// ligne pour garder un rendu fluide sur de très longs documents) et pièces jointes.
    public static func parse(text: String, attachments: [ChunkAttachment], maxTextBlock: Int = 4000) -> [ReaderBlock] {
        let ns = NSString(string: text)
        let full = NSRange(location: 0, length: ns.length)
        var blocks: [ReaderBlock] = []
        var cursor = 0

        func appendText(_ range: NSRange) {
            var start = range.location
            let end = range.location + range.length
            while start < end {
                var stop = min(start + maxTextBlock, end)
                if stop < end {
                    let window = NSRange(location: start, length: stop - start)
                    let nl = ns.range(of: "\n", options: .backwards, range: window)
                    if nl.location != NSNotFound, nl.location > start { stop = nl.location + 1 }
                    // Évite de couper au milieu d'une paire de substitution UTF-16.
                    else if stop > start, UTF16.isLeadSurrogate(ns.character(at: stop - 1)) { stop -= 1 }
                }
                let piece = ns.substring(with: NSRange(location: start, length: stop - start))
                blocks.append(ReaderBlock(id: blocks.count, kind: .text(piece), range: start..<stop))
                start = stop
            }
        }

        for m in tokenPattern.matches(in: text, range: full) {
            if m.range.location > cursor { appendText(NSRange(location: cursor, length: m.range.location - cursor)) }
            let inner = ns.substring(with: m.range(at: 1))
            let ref = resolve(token: inner, attachments: attachments)
            blocks.append(
                ReaderBlock(
                    id: blocks.count, kind: .attachment(ref), range: m.range.location..<(m.range.location + m.range.length)))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length { appendText(NSRange(location: cursor, length: ns.length - cursor)) }
        return blocks
    }

    /// Fait correspondre le contenu d'un jeton à une pièce jointe connue.
    public static func resolve(token: String, attachments: [ChunkAttachment]) -> AttachmentRef {
        let separators = CharacterSet(charactersIn: ":|, \t\n/")
        let first = token.components(separatedBy: separators).first(where: { !$0.isEmpty }) ?? token
        let match =
            attachments.first { $0.id == first }
            ?? attachments.first { !$0.id.isEmpty && token.contains($0.id) }
            ?? attachments.first { first.count >= 6 && $0.hash.hasPrefix(first) }
        return AttachmentRef(token: token, id: first, attachment: match)
    }

    /// Pièces jointes connues mais absentes du texte (aucun jeton) : ajoutées en fin de document pour
    /// qu'aucune image ne reste invisible.
    public static func unreferencedBlocks(attachments: [ChunkAttachment], after blocks: [ReaderBlock], textLength: Int)
        -> [ReaderBlock]
    {
        let referenced = Set(blocks.compactMap { $0.attachmentRef?.attachment?.id })
        var out: [ReaderBlock] = []
        for a in attachments where !referenced.contains(a.id) {
            let ref = AttachmentRef(token: a.id, id: a.id, attachment: a)
            out.append(ReaderBlock(id: blocks.count + out.count, kind: .attachment(ref), range: textLength..<textLength))
        }
        return out
    }

    /// Union dédupliquée (par id) de listes de pièces jointes, en conservant l'ordre.
    public static func merge(_ lists: [[ChunkAttachment]?]) -> [ChunkAttachment] {
        var seen = Set<String>()
        var out: [ChunkAttachment] = []
        for l in lists {
            for a in l ?? [] where seen.insert(a.id).inserted { out.append(a) }
        }
        return out
    }

    /// Texte sans jetons, pour la recherche plein texte ou les extraits (« [image] » à la place).
    public static func plain(_ text: String) -> String {
        let ns = NSString(string: text)
        return tokenPattern.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "[pièce jointe]")
    }
}
