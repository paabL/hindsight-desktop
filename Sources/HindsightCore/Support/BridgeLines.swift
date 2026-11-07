import Foundation

/// Lignes JSON échangées entre la coque et le pont natif.
///
/// U+2028, U+2029 et U+0085 sont permis tels quels dans une chaîne JSON, mais `AsyncLineSequence`
/// (et le `readline` de Node) y voient une fin de ligne : un texte collé depuis un traitement de texte
/// ou un PDF coupait la requête en deux, et la coque abandonnait le pont. On ne coupe donc que sur
/// « \n », et les réponses écrivent ces caractères échappés.
public struct BridgeLineReader {
    public enum Line: Equatable {
        case request(Data)
        /// Ligne plus longue que la limite : ignorée en entier, sans garder ses octets en mémoire.
        case oversized
    }

    private let limit: Int
    private var buffer = Data()
    private var oversized = false

    public init(limit: Int = 16_000_000) {
        self.limit = limit
    }

    /// Ajoute un octet lu ; renvoie la ligne quand l'octet est « \n ».
    public mutating func consume(_ byte: UInt8) -> Line? {
        guard byte == 10 else {
            if buffer.count < limit { buffer.append(byte) } else { oversized = true }
            return nil
        }
        defer {
            buffer = Data()
            oversized = false
        }
        return oversized ? .oversized : .request(buffer)
    }

    /// Réponse prête à écrire sur une ligne : mêmes valeurs JSON, séparateurs Unicode échappés.
    /// Ces octets n'apparaissent que dans des chaînes (la structure JSON est en ASCII), et UTF-8 ne
    /// laisse aucune autre lecture possible de ces séquences.
    public static func lineSafe(_ data: Data) -> Data {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data in
            let bytes = raw.bindMemory(to: UInt8.self)
            var out: Data?
            var copied = 0
            var i = 0
            while i < bytes.count {
                var escape: String?
                var width = 1
                if bytes[i] == 0xE2, i + 2 < bytes.count, bytes[i + 1] == 0x80, bytes[i + 2] == 0xA8 || bytes[i + 2] == 0xA9 {
                    escape = bytes[i + 2] == 0xA8 ? "\\u2028" : "\\u2029"
                    width = 3
                } else if bytes[i] == 0xC2, i + 1 < bytes.count, bytes[i + 1] == 0x85 {
                    escape = "\\u0085"
                    width = 2
                }
                if let escape {
                    if out == nil { out = Data(capacity: bytes.count + 16) }
                    out!.append(contentsOf: UnsafeRawBufferPointer(rebasing: raw[copied..<i]))
                    out!.append(contentsOf: Array(escape.utf8))
                    copied = i + width
                }
                i += width
            }
            guard var result = out else { return data }
            result.append(contentsOf: UnsafeRawBufferPointer(rebasing: raw[copied..<bytes.count]))
            return result
        }
    }
}
