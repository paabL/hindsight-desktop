import Foundation

/// Bloc d'un contenu multimodal à retenir (texte, image, fichier), dans l'ordre d'apparition.
public enum ContentBlock: Codable, Sendable, Hashable {
    case text(TextContentBlock)
    case image(ImageContentBlock)
    case file(FileContentBlock)

    private enum Keys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .type)
        switch type {
        case "image": self = .image(try ImageContentBlock(from: decoder))
        case "file": self = .file(try FileContentBlock(from: decoder))
        default: self = .text(try TextContentBlock(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b): try b.encode(to: encoder)
        case .image(let b): try b.encode(to: encoder)
        case .file(let b): try b.encode(to: encoder)
        }
    }
}

/// `content` d'un item à retenir : chaîne simple ou liste de blocs.
public enum HSContent: Codable, Sendable, Hashable {
    case text(String)
    case blocks([ContentBlock])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .blocks(try c.decode([ContentBlock].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .blocks(let b): try c.encode(b)
        }
    }
}
