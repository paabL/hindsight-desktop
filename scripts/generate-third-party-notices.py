#!/usr/bin/env python3
"""Assemble les notices des dépendances installées, sans accès réseau.

Usage: python3 scripts/generate-third-party-notices.py CARGO_METADATA_JSON
Produire ce JSON avec cargo metadata --locked --offline --filter-platform
aarch64-apple-darwin --format-version 1 depuis desktop/src-tauri.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
from html.parser import HTMLParser

ROOT = pathlib.Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "desktop/public"
metadata = json.loads(pathlib.Path(sys.argv[1]).read_text())
nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
packages = {p["id"]: p for p in metadata["packages"]}
root_id = metadata["resolve"]["root"]
seen, pending = set(), [root_id]
while pending:
    ident = pending.pop()
    if ident in seen:
        continue
    seen.add(ident)
    pending.extend(d["pkg"] for d in nodes[ident]["deps"]
                   if any(k["kind"] is None for k in d["dep_kinds"]))

texts, inventory = {}, []


def register(text):
    text = text.strip() + "\n"
    ident = hashlib.sha256(text.encode()).hexdigest()[:16]
    texts.setdefault(ident, text)
    return ident


def license_files(folder):
    return sorted(f for f in folder.iterdir() if f.is_file() and
                  f.name.lower().startswith(("license", "licence", "copying", "copyright", "notice")))


mit_body = (ROOT / "LICENSE").read_text().split("Permission is hereby granted", 1)[1]
mit_body = "MIT License\n\nPermission is hereby granted" + mit_body
mpl_file = next(pathlib.Path(p["manifest_path"]).parent / "LICENSE"
                for p in packages.values() if p["name"] == "cssparser")

for ident in sorted(seen - {root_id}, key=lambda i: (packages[i]["name"], packages[i]["version"])):
    p = packages[ident]
    folder = pathlib.Path(p["manifest_path"]).parent
    files = license_files(folder)
    refs = [register(f.read_text(errors="replace")) for f in files]
    extra = ""
    if p["name"] == "alloc-stdlib":
        refs.append(register((ROOT / "docs/legal/alloc-stdlib-BSD.txt").read_text()))
    elif p["name"] == "plist":
        refs.append(register((ROOT / "docs/legal/plist-MIT.txt").read_text()))
    elif p["name"] in {"objc2", "block2", "dispatch2"} or p["name"].startswith("objc2-"):
        refs.extend([register((ROOT / "docs/legal/objc2-LICENSE.md").read_text()), register(mit_body)])
        extra = "Attribution: Mads Marquart, Mary and the objc2 project contributors.\n"
    if "MPL-2.0" in (p["license"] or ""):
        refs.append(register(mpl_file.read_text()))
        extra += "MPL-covered source files are unmodified; source is available at the URL below.\n"
        # Preserve per-file notices in packages that omit a root license file.
        if not files:
            header = (folder / "lib.rs").read_text().split("\n\n", 1)[0]
            refs.append(register(header))
    if not refs:
        raise SystemExit(f"Notice absente : {p['name']} {p['version']}")
    inventory.append(f"Rust: {p['name']} {p['version']}\nLicense: {p['license']}\n"
                     f"Source: https://crates.io/api/v1/crates/{p['name']}/{p['version']}/download\n"
                     f"Repository: {p.get('repository') or ''}\n{extra}"
                     f"License text references: {', '.join(dict.fromkeys(refs))}\n")

lock = json.loads((ROOT / "desktop/package-lock.json").read_text())
for path, p in sorted(lock["packages"].items()):
    if not path or p.get("dev"):
        continue
    folder = ROOT / "desktop" / path
    info = json.loads((folder / "package.json").read_text())
    refs = [register(f.read_text(errors="replace")) for f in license_files(folder)]
    if not refs:
        raise SystemExit(f"Notice absente : {path}")
    name = info["name"]
    inventory.append(f"JavaScript: {name} {p['version']}\nLicense: {p.get('license', info.get('license', ''))}\n"
                     f"Source: https://www.npmjs.com/package/{name}/v/{p['version']}\n"
                     f"License text references: {', '.join(refs)}\n")

upstream = register((ROOT / "docs/legal/hindsight-MIT.txt").read_text())
apache = next(f for p in packages.values()
              for f in license_files(pathlib.Path(p["manifest_path"]).parent)
              if f.name.upper() == "LICENSE-APACHE")
apache_ref = register(apache.read_text())
header = f"""Hindsight Desktop — third-party notices
Generated from the installed dependency versions and Cargo's macOS dependency graph.
This inventory includes runtime dependency source packages; a listed dependency
may contain files not linked into the final executable. Development tools are
not distributed in the app.

Hindsight API specification and generated models
Copyright (c) 2025 Vectorize AI, Inc.
Source: https://github.com/vectorize-io/hindsight/tree/v1.2.0
Upstream repository: MIT. Included OpenAPI specification also declares Apache-2.0.
License text references: {upstream}, {apache_ref}
The generated Swift models are adapted for Hindsight Desktop. The server and
model weights are not bundled. No trademark rights or endorsement are granted.

Multi-licensed dependencies are used under MIT where available. Combined-license
requirements and original notices are preserved below. MPL-2.0 source package
download links identify the unmodified covered source used in this build.

Rust standard library notices are in RUST_STANDARD_LIBRARY_NOTICES.txt alongside
this file. Apple system frameworks are supplied by macOS.

COMPONENT INVENTORY
===================

"""
body = header + "\n".join(inventory) + "\nLICENSE TEXTS\n=============\n"
for ident, text in texts.items():
    body += f"\n--- License text {ident} ---\n\n{text}"
PUBLIC.mkdir(exist_ok=True)
(PUBLIC / "THIRD_PARTY_NOTICES.txt").write_text(body)


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


rust_docs = list((ROOT / "desktop/.toolchain/rustup/toolchains").glob("*/share/doc/rust/COPYRIGHT-library.html"))
if not rust_docs:
    try:
        sysroot = pathlib.Path(subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip())
        candidate = sysroot / "share/doc/rust/COPYRIGHT-library.html"
        if candidate.is_file():
            rust_docs = [candidate]
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
if not rust_docs:
    raise SystemExit("Notices de la bibliothèque standard Rust absentes")
parser = PlainText()
parser.feed(rust_docs[0].read_text())
(PUBLIC / "RUST_STANDARD_LIBRARY_NOTICES.txt").write_text("\n".join(parser.parts))
print(f"{len(inventory)} composants ; {len(texts)} textes de licence ; notices Rust incluses")
