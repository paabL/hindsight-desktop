import Foundation

/// Mode de correspondance des tags (`tags_match`).
public enum TagsMatch: String, CaseIterable, Sendable, Codable {
    case any, all
    case anyStrict = "any_strict"
    case allStrict = "all_strict"
    case exact
}

/// Filtre composé de tags : feuille `{tags, match, resolve}` ou `{and:[…]}`, `{or:[…]}`, `{not:…}`.
public indirect enum TagGroup: Codable, Sendable, Hashable {
    case leaf(TagGroupLeaf)
    case and([TagGroup])
    case or([TagGroup])
    case not(TagGroup)

    public static func tags(_ tags: [String], match: TagsMatch = .anyStrict) -> TagGroup {
        .leaf(TagGroupLeaf(tags: tags, match: match.rawValue))
    }

    private enum Keys: String, CodingKey { case and, or, not }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.and) { self = .and(try c.decode([TagGroup].self, forKey: .and)) }
        else if c.contains(.or) { self = .or(try c.decode([TagGroup].self, forKey: .or)) }
        else if c.contains(.not) { self = .not(try c.decode(TagGroup.self, forKey: .not)) }
        else { self = .leaf(try TagGroupLeaf(from: decoder)) }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .leaf(let l): try l.encode(to: encoder)
        case .and(let g):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(g, forKey: .and)
        case .or(let g):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(g, forKey: .or)
        case .not(let g):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(g, forKey: .not)
        }
    }
}
