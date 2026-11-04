#!/usr/bin/env python3
"""Génère Sources/HindsightCore/Service/DecisionServerScript.swift depuis scripts/hindsight-decision-serve.py.

L'app écrit ce script dans ~/.hindsight/decision/serve.py à l'installation du modèle de décision local :
seul l'exécutable du pont est livré avec l'app, d'où la copie dans une chaîne Swift. Un test vérifie que
les deux sont identiques.

Usage : python3 scripts/generate_decision_script.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "scripts", "hindsight-decision-serve.py")
OUT = os.path.join(ROOT, "Sources", "HindsightCore", "Service", "DecisionServerScript.swift")

text = open(SOURCE, encoding="utf-8").read().rstrip("\n")
# Chaîne brute Swift #"""…"""# : le script ne doit contenir ni sa fin ni une interpolation brute.
assert '"""#' not in text and "\\#" not in text, "le script ne peut pas être copié dans une chaîne brute Swift"
swift = (
    "// Généré par scripts/generate_decision_script.py depuis scripts/hindsight-decision-serve.py : ne pas modifier.\n"
    "// L'app l'écrit dans ~/.hindsight/decision/serve.py à l'installation du modèle de décision local.\n"
    "enum DecisionServerScript {\n"
    '    static let source = #"""\n'
    f"{text}\n"
    '"""#\n'
    "}\n"
)
with open(OUT, "w", encoding="utf-8") as f:
    f.write(swift)
print(f"{len(text.splitlines())} lignes -> {os.path.relpath(OUT, ROOT)}")
