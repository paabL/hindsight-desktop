#!/usr/bin/env python3
"""Génère Sources/HindsightAPI/Generated/Models.swift depuis docs/openapi.json.

Règles (voir README « Régénérer les modèles ») :
  - requis et non nul            -> propriété non optionnelle (strict)
  - requis et nullable           -> Optional
  - non requis avec défaut simple-> non optionnelle, décodage tolérant (valeur absente => défaut)
  - non requis sans défaut / nul -> Optional
  - enum, date-time              -> String (tolérant aux valeurs futures du serveur)
  - objet libre / union exotique -> JSONValue
Les types à union récursive (TagGroup*, Content) sont écrits à la main dans Sources/HindsightAPI/Hand/.

Usage : python3 scripts/generate_models.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "docs", "openapi.json")
OUT = os.path.join(ROOT, "Sources", "HindsightAPI", "Generated", "Models.swift")

spec = json.load(open(SPEC))
SCHEMAS = spec["components"]["schemas"]

# Schémas non générés : écrits à la main (unions) ou multipart.
HAND = {"Content", "Budget", "Body_file_retain", "Body_import_bank_transfer", "Body_import_documents"}
HAND_PREFIX = ("TagGroupAnd", "TagGroupOr", "TagGroupNot")  # remplacés par l'enum TagGroup

KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
    "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
    "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
    "throw", "switch", "where", "while", "Any", "as", "await", "false", "is", "nil", "self", "Self",
    "super", "throws", "true", "try", "final", "async", "Type", "Protocol", "description", "hash",
}


def swift_type_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", name)


def camel(name: str) -> str:
    if "_" not in name:
        return name
    parts = name.split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def prop_name(name: str) -> str:
    c = camel(name)
    return f"`{c}`" if c in KEYWORDS else c


def is_null(s):
    return s.get("type") == "null"


def ref_name(s):
    return s["$ref"].split("/")[-1]


def ref_type(n):
    if n.startswith(HAND_PREFIX):
        return "TagGroup"
    if n == "Content":
        return "HSContent"
    if n == "Budget":
        return "String"
    target = SCHEMAS.get(n, {})
    if "enum" in target and target.get("type") in (None, "string"):
        return "String"  # énumération nommée : String, comme les énumérations en ligne
    return swift_type_name(n)


def swift_type(s):
    """Retourne (type Swift sans '?', nullable)."""
    if "$ref" in s:
        return ref_type(ref_name(s)), False
    if "anyOf" in s or "oneOf" in s:
        variants = s.get("anyOf") or s.get("oneOf")
        nullable = any(is_null(v) for v in variants)
        rest = [v for v in variants if not is_null(v)]
        if len(rest) == 1:
            t, n2 = swift_type(rest[0])
            return t, nullable or n2
        refs = [ref_name(v) for v in rest if "$ref" in v]
        if refs and len(refs) == len(rest) and all(r.startswith("TagGroup") for r in refs):
            return "TagGroup", nullable
        return "JSONValue", nullable
    if "allOf" in s and len(s["allOf"]) == 1:
        return swift_type(s["allOf"][0])
    t = s.get("type")
    if "enum" in s and t in (None, "string"):
        return "String", False
    if t == "string":
        return "String", False
    if t == "integer":
        return "Int", False
    if t == "number":
        return "Double", False
    if t == "boolean":
        return "Bool", False
    if t == "array":
        it, inull = swift_type(s.get("items", {}))
        return f"[{it}{'?' if inull else ''}]", False
    if t == "object" or "properties" in s:
        ap = s.get("additionalProperties")
        if isinstance(ap, dict) and "properties" not in s:
            vt, vnull = swift_type(ap)
            return f"[String: {vt}{'?' if vnull else ''}]", False
        return "[String: JSONValue]", False
    return "JSONValue", False


def swift_default(s, ty):
    """Littéral Swift du défaut si représentable pour un type non optionnel, sinon None."""
    if "default" not in s:
        return None
    d = s["default"]
    if d is None:
        return None
    if ty == "Bool" and isinstance(d, bool):
        return "true" if d else "false"
    if ty == "Int" and isinstance(d, int) and not isinstance(d, bool):
        return str(d)
    if ty == "Double" and isinstance(d, (int, float)) and not isinstance(d, bool):
        return repr(float(d))
    if ty == "String" and isinstance(d, str):
        return json.dumps(d, ensure_ascii=False)
    if ty.startswith("[String:") and d == {}:
        return "[:]"
    if ty.startswith("[") and not ty.startswith("[String:") and d == []:
        return "[]"
    return None


def gen_struct(name, schema):
    tname = swift_type_name(name)
    props = schema.get("properties") or {}
    required = set(schema.get("required", []))
    fields = []  # (json, swiftname, type, optional, default)
    for jname, ps in props.items():
        ty, nullable = swift_type(ps)
        if jname in required:
            opt = nullable
            default = None
        else:
            default = swift_default(ps, ty) if not nullable else None
            opt = default is None
        fields.append((jname, prop_name(jname), ty, opt, default))

    lines = []
    desc = (schema.get("description") or "").strip().splitlines()
    if desc:
        lines.append(f"/// {desc[0][:160]}")
    conf = ["Codable", "Sendable", "Hashable"]
    if any(f[0] == "id" and f[2] == "String" and not f[3] for f in fields):
        conf.append("Identifiable")
    lines.append(f"public struct {tname}: {', '.join(conf)} {{")
    for jname, sname, ty, opt, default in fields:
        d = (props[jname].get("description") or "").strip().splitlines()
        if d:
            lines.append(f"    /// {d[0][:140]}")
        lines.append(f"    public var {sname}: {ty}{'?' if opt else ''}")
    if fields:
        lines.append("")
    # init public
    params = []
    for jname, sname, ty, opt, default in fields:
        bare = sname.strip("`")
        p = f"{sname}: {ty}{'?' if opt else ''}"
        if opt:
            p += " = nil"
        elif default is not None:
            p += f" = {default}"
        params.append(p)
    lines.append(f"    public init({', '.join(params)}) {{")
    for jname, sname, ty, opt, default in fields:
        lines.append(f"        self.{sname} = {sname}")
    lines.append("    }")
    # CodingKeys
    if fields:
        lines.append("")
        lines.append("    enum CodingKeys: String, CodingKey {")
        for jname, sname, ty, opt, default in fields:
            bare = sname.strip("`")
            if bare == jname:
                lines.append(f"        case {sname}")
            else:
                lines.append(f"        case {sname} = {json.dumps(jname)}")
        lines.append("    }")
    # init(from:) tolérant seulement si défauts
    if any(f[4] is not None for f in fields):
        lines.append("")
        lines.append("    public init(from decoder: Decoder) throws {")
        lines.append("        let c = try decoder.container(keyedBy: CodingKeys.self)")
        for jname, sname, ty, opt, default in fields:
            if default is not None:
                lines.append(f"        self.{sname} = try c.decodeIfPresent({ty}.self, forKey: .{sname}) ?? {default}")
            elif opt:
                lines.append(f"        self.{sname} = try c.decodeIfPresent({ty}.self, forKey: .{sname})")
            else:
                lines.append(f"        self.{sname} = try c.decode({ty}.self, forKey: .{sname})")
        lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


def main():
    out = [
        "// Généré par scripts/generate_models.py depuis docs/openapi.json (version API "
        + spec["info"]["version"] + ").",
        "// NE PAS ÉDITER À LA MAIN : relancer le script.",
        "import Foundation",
        "",
    ]
    names = []
    for name, schema in SCHEMAS.items():
        if name in HAND or name.startswith(HAND_PREFIX):
            continue
        if schema.get("type") != "object" and "properties" not in schema:
            continue  # unions / enums : à la main ou mappés sur String
        if "anyOf" in schema or "oneOf" in schema:
            continue
        names.append(name)
        out.append(gen_struct(name, schema))
        out.append("")
    rendered = "\n".join(out)
    open(OUT, "w").write("\n".join(line.rstrip() for line in rendered.split("\n")))
    print(f"{len(names)} structs -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
