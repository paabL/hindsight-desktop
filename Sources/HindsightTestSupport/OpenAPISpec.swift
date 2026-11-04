import Foundation
import HindsightAPI

/// Lecture de `docs/openapi.json` pour les tests de conformité : opérations, échantillons synthétiques
/// de réponses/requêtes et mini-validateur de schéma.
public struct OpenAPISpec: Sendable {
    public let root: JSONValue

    public struct Parameter: Sendable {
        public let name: String
        public let location: String
        public let required: Bool
    }

    public struct Operation: Sendable {
        public let method: String
        public let pathTemplate: String
        public let operationID: String
        public let parameters: [Parameter]
        public let requestSchema: JSONValue?
        public let requestContentType: String?
        public let successStatus: Int?
        public let responseSchema: JSONValue?

        var regex: NSRegularExpression {
            var pattern = "^"
            var i = pathTemplate.startIndex
            while i < pathTemplate.endIndex {
                let ch = pathTemplate[i]
                if ch == "{", let close = pathTemplate[i...].firstIndex(of: "}") {
                    pattern += "[^/]+"
                    i = pathTemplate.index(after: close)
                    continue
                }
                pattern += NSRegularExpression.escapedPattern(for: String(ch))
                i = pathTemplate.index(after: i)
            }
            pattern += "$"
            return try! NSRegularExpression(pattern: pattern)
        }
    }

    public let operations: [Operation]

    public init(data: Data) throws {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        self.root = root
        var ops: [Operation] = []
        for (path, item) in root["paths"]?.objectValue ?? [:] {
            for (method, op) in item.objectValue ?? [:] {
                guard ["get", "post", "put", "patch", "delete"].contains(method), let o = op.objectValue else { continue }
                let params = (o["parameters"]?.arrayValue ?? []).map {
                    Parameter(
                        name: $0["name"]?.stringValue ?? "", location: $0["in"]?.stringValue ?? "",
                        required: $0["required"]?.boolValue ?? false)
                }
                var reqSchema: JSONValue?
                var reqCT: String?
                if let content = o["requestBody"]?["content"]?.objectValue, let (ct, c) = content.first {
                    reqSchema = c["schema"]
                    reqCT = ct
                }
                var status: Int?
                var respSchema: JSONValue?
                for (code, r) in (o["responses"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                    if let n = Int(code), (200..<300).contains(n) {
                        status = n
                        respSchema = r["content"]?.objectValue?.first?.value["schema"]
                        break
                    }
                }
                ops.append(
                    Operation(
                        method: method.uppercased(), pathTemplate: path, operationID: o["operationId"]?.stringValue ?? "",
                        parameters: params, requestSchema: reqSchema, requestContentType: reqCT, successStatus: status,
                        responseSchema: respSchema))
            }
        }
        self.operations = ops.sorted { ($0.pathTemplate, $0.method) < ($1.pathTemplate, $1.method) }
    }

    /// Spécification embarquée dans le dépôt (`docs/openapi.json`), retrouvée depuis l'emplacement de ce fichier.
    public static func repository(filePath: String = #filePath) throws -> OpenAPISpec {
        var url = URL(fileURLWithPath: filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // …/Sources/HindsightTestSupport/ -> racine
        let spec = url.appendingPathComponent("docs/openapi.json")
        return try OpenAPISpec(data: Data(contentsOf: spec))
    }

    public func operation(method: String, path: String) -> Operation? {
        let m = method.uppercased()
        return operations.first { op in
            guard op.method == m else { return false }
            let range = NSRange(path.startIndex..., in: path)
            return op.regex.firstMatch(in: path, range: range) != nil
        }
    }

    public func operation(id: String) -> Operation? { operations.first { $0.operationID == id } }

    // MARK: Schémas

    public func resolve(_ schema: JSONValue) -> JSONValue {
        var s = schema
        var guardCount = 0
        while let ref = s["$ref"]?.stringValue, guardCount < 20 {
            let name = ref.split(separator: "/").last.map(String.init) ?? ""
            s = root["components"]?["schemas"]?[name] ?? .null
            guardCount += 1
        }
        return s
    }

    public enum SampleMode: Sendable { case full, minimal }

    /// Instance JSON valide pour `schema` : tous les champs (`full`) ou seulement les requis (`minimal`).
    public func sample(_ schema: JSONValue, mode requested: SampleMode = .full, depth: Int = 0) -> JSONValue {
        let s = resolve(schema)
        if depth > 24 { return fallbackSample(s) }
        // Au-delà d'une certaine profondeur on passe en « minimal » pour garantir l'arrêt des schémas récursifs.
        let mode: SampleMode = depth > 10 ? .minimal : requested
        if let e = s["enum"]?.arrayValue, let first = e.first { return first }
        if let variants = (s["anyOf"] ?? s["oneOf"])?.arrayValue {
            let nonNull = variants.filter { resolve($0)["type"]?.stringValue != "null" }
            guard let pick = nonNull.first else { return .null }
            return sample(pick, mode: mode, depth: depth + 1)
        }
        if let all = s["allOf"]?.arrayValue, let first = all.first { return sample(first, mode: mode, depth: depth) }
        if let d = s["default"], !d.isNull, mode == .full, s["type"]?.stringValue != "object" { return d }
        switch s["type"]?.stringValue {
        case "string":
            switch s["format"]?.stringValue {
            case "date-time": return "2025-03-01T10:20:30.123456Z"
            case "date": return "2025-03-01"
            case "binary": return "binary"
            default: return "texte"
            }
        case "integer": return .int(max(1, s["minimum"]?.intValue ?? 1))
        case "number": return .double(0.5)
        case "boolean": return true
        case "array":
            if mode == .minimal { return .array([]) }
            return .array([sample(s["items"] ?? .object([:]), mode: mode, depth: depth + 1)])
        case "object", nil:
            if let props = s["properties"]?.objectValue {
                let required = Set((s["required"]?.arrayValue ?? []).compactMap(\.stringValue))
                var out: [String: JSONValue] = [:]
                for (k, p) in props {
                    if mode == .minimal && !required.contains(k) { continue }
                    if mode == .minimal, isNullable(p) { out[k] = .null; continue }
                    out[k] = sample(p, mode: mode, depth: depth + 1)
                }
                return .object(out)
            }
            if let ap = s["additionalProperties"], ap.objectValue != nil {
                if mode == .minimal { return .object([:]) }
                return .object(["clé": sample(ap, mode: mode, depth: depth + 1)])
            }
            return mode == .minimal ? .object([:]) : .object(["clé": "valeur"])
        default:
            return .null
        }
    }

    private func fallbackSample(_ s: JSONValue) -> JSONValue {
        switch s["type"]?.stringValue {
        case "array": return .array([])
        case "object": return .object([:])
        case "string": return "x"
        case "integer": return 1
        case "number": return 0.5
        case "boolean": return false
        default: return .null
        }
    }

    public func isNullable(_ schema: JSONValue) -> Bool {
        let s = resolve(schema)
        if let v = (s["anyOf"] ?? s["oneOf"])?.arrayValue {
            return v.contains { resolve($0)["type"]?.stringValue == "null" }
        }
        return s["type"]?.stringValue == "null"
    }

    // MARK: Mini-validateur

    /// Valide `value` contre `schema` ; retourne la liste des écarts (vide = conforme).
    /// Vérifie type, requis, propriétés inconnues (si `additionalProperties:false` ou absence de propriétés déclarées ignorée),
    /// énumérations, éléments de tableau, unions (au moins une variante valide).
    public func validate(_ value: JSONValue, against schema: JSONValue, path: String = "$", depth: Int = 0) -> [String] {
        let s = resolve(schema)
        if depth > 12 { return [] }
        if let variants = (s["anyOf"] ?? s["oneOf"])?.arrayValue {
            var best: [String]?
            for v in variants {
                let errs = validate(value, against: v, path: path, depth: depth + 1)
                if errs.isEmpty { return [] }
                if best == nil || errs.count < best!.count { best = errs }
            }
            return best.map { ["\(path): aucune variante ne convient (" + $0.first! + ")"] } ?? []
        }
        if let all = s["allOf"]?.arrayValue { return all.flatMap { validate(value, against: $0, path: path, depth: depth + 1) } }
        if let e = s["enum"]?.arrayValue, !e.contains(value) { return ["\(path): \(value) hors énumération"] }
        let t = s["type"]?.stringValue
        if t == nil, s["properties"] == nil, value.objectValue == nil { return [] }
        switch (t, value) {
        case ("null", .null): return []
        case (_, .null): return t == nil ? [] : ["\(path): null interdit"]
        case ("string", .string): return []
        case ("integer", .int): return []
        case ("number", .int), ("number", .double): return []
        case ("boolean", .bool): return []
        case ("array", .array(let items)):
            return items.enumerated().flatMap { validate($1, against: s["items"] ?? .object([:]), path: "\(path)[\($0)]", depth: depth + 1) }
        case ("object", .object(let obj)), (nil, .object(let obj)):
            var errs: [String] = []
            let props = s["properties"]?.objectValue ?? [:]
            for r in (s["required"]?.arrayValue ?? []).compactMap(\.stringValue) where obj[r] == nil {
                errs.append("\(path): champ requis manquant « \(r) »")
            }
            for (k, v) in obj {
                if let p = props[k] { errs += validate(v, against: p, path: "\(path).\(k)", depth: depth + 1) }
                else if let ap = s["additionalProperties"], ap.objectValue != nil {
                    errs += validate(v, against: ap, path: "\(path).\(k)", depth: depth + 1)
                } else if !props.isEmpty, s["additionalProperties"]?.boolValue != true {
                    errs.append("\(path): champ inconnu « \(k) »")
                }
            }
            return errs
        default:
            return ["\(path): type \(t ?? "?") attendu, reçu \(value)"]
        }
    }
}
