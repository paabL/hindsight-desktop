#!/usr/bin/env python3
"""Génère Sources/HindsightCore/Service/ModelManagerScripts.swift depuis scripts/hindsight-models.py et
scripts/hindsight-model-server.py.

L'app écrit ces deux scripts dans ~/.hindsight/models/ (gestionnaire des modèles locaux, serveur MPS
compatible TEI) : seul l'exécutable du pont est livré avec l'app, d'où la copie dans des chaînes Swift.
Un test vérifie qu'elles sont identiques aux scripts.

Usage : python3 scripts/generate_model_manager_scripts.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = {"manager": "hindsight-models.py", "server": "hindsight-model-server.py"}
OUT = os.path.join(ROOT, "Sources", "HindsightCore", "Service", "ModelManagerScripts.swift")

parts = []
for name, file in SOURCES.items():
    text = open(os.path.join(ROOT, "scripts", file), encoding="utf-8").read().rstrip("\n")
    # Chaîne brute Swift #"""…"""# : le script ne doit contenir ni sa fin ni une interpolation brute.
    assert '"""#' not in text and "\\#" not in text, f"{file} ne peut pas être copié dans une chaîne brute Swift"
    parts.append(f'    static let {name} = #"""\n{text}\n"""#\n')
swift = (
    "// Généré par scripts/generate_model_manager_scripts.py depuis scripts/hindsight-models.py et\n"
    "// scripts/hindsight-model-server.py : ne pas modifier. L'app les écrit dans ~/.hindsight/models/.\n"
    "enum ModelManagerScripts {\n" + "\n".join(parts) + "}\n"
)
with open(OUT, "w", encoding="utf-8") as f:
    f.write(swift)
print(f"{len(SOURCES)} scripts -> {os.path.relpath(OUT, ROOT)}")
