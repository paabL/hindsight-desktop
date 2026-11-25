// Généré par scripts/generate_model_manager_scripts.py depuis scripts/hindsight-models.py et
// scripts/hindsight-model-server.py : ne pas modifier. L'app les écrit dans ~/.hindsight/models/.
enum ModelManagerScripts {
    static let manager = #"""
#!/usr/bin/env python3
"""Gestionnaire des modèles locaux de Hindsight : reranker, embeddings, modèle de décision.

Un catalogue par rôle (modèle Hugging Face, moteur, mesures) et un seul fichier de sélection,
~/.hindsight/models/selection.json, lu au lancement par :
  - le script de lancement de l'API (`eval "$(… env)"`, ajouté par `hook`) ;
  - le serveur MPS compatible TEI (model-server.py --role reranker|embeddings) ;
  - le serveur de décision (serve.py --engine auto).

`apply <rôle> <option>` fait tout, dans l'ordre : télécharger, tester (réponse et latence sur une vraie
recherche), attendre qu'aucune opération ne tourne, activer, redémarrer ce qui dépend du rôle, vérifier
(recall réel, ou décision réelle) et, en cas d'échec, revenir seul au choix précédent. L'état du travail
en cours est dans job.json, l'historique dans history.jsonl. `start` lance `apply` détaché (l'app suit
job.json). Rien n'est écrit dans les banques : les vérifications ne font que des recall en lecture.

Usage : hindsight-models.py status | env | hook | start <rôle> <option> | apply <rôle> <option>
                            | rollback <rôle> | test <rôle> <option>
Stdlib seule (Python 3.9+) ; les calculs passent par les environnements Python de Hindsight.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

HOME = Path.home()
ROOT = HOME / ".hindsight"
MODELS = ROOT / "models"
SELECTION = MODELS / "selection.json"
HISTORY = MODELS / "history.jsonl"
JOB = MODELS / "job.json"
SERVER_SCRIPT = MODELS / "model-server.py"
LOGS = HOME / "Library" / "Logs" / "Hindsight"
AGENTS = HOME / "Library" / "LaunchAgents"
HS_PY = ROOT / "venv" / "bin" / "python"
DECISION = ROOT / "decision"
DEC_PY = DECISION / "venv" / "bin" / "python"
API = "http://127.0.0.1:8888"
API_LABEL = "local.hindsight.api"
DEC_LABEL = "local.hindsight.decision"
DEC_URL = "http://127.0.0.1:8766"
# Serveurs System One ouverts (StartLux-Decision, d3-edge…), installés à part dans ~/.hindsight/candidates/<nom>/
# avec un serve.sh <port> ; l'API les appelle par HINDSIGHT_API_DECISION_MODEL_BASE_URL.
CANDIDATES = ROOT / "candidates"
DECISION_ALT = {"label": "local.hindsight.decision-alt", "port": 8770, "test_port": 8779}
MLX_PACKAGE = "mlx-lm==0.32.2"
PROBE_QUERY = "transformée de Fourier"
HOOK_MARK = "hindsight-models.py\" env"
SERVERS = {
    "reranker": {"label": "local.hindsight.rerank", "port": 8767, "test_port": 8777},
    "embeddings": {"label": "local.hindsight.embed", "port": 8768, "test_port": 8778},
}
# Mesures du 17 nov. 2026 sur un M4 16 Go à vide : qualité nDCG@10 sur 15 requêtes réelles étiquetées de la
# banque savoirs (bench-rerank), latence médiane pour ~80 candidats ; embeddings : une requête et 64 passages ;
# décision : une passe de 5 500 jetons et des requêtes réelles de 2,5 à 3,7 k jetons.
CATALOG: Dict[str, List[Dict[str, Any]]] = {
    "reranker": [
        {"id": "hs-rerank-1/cpu", "label": "hs-rerank-1 · CPU dans Hindsight", "model": "hindsight-ai/hs-rerank-1",
         "engine": "cpu", "quality": 0.896, "latency": "1,8-2,4 s", "memory": "dans Hindsight",
         "note": "Le reranker par défaut de Hindsight, sans serveur à part."},
        {"id": "hs-rerank-1/mps", "label": "hs-rerank-1 · GPU (MPS)", "model": "hindsight-ai/hs-rerank-1",
         "engine": "mps", "fp16": True, "quality": 0.896, "latency": "0,46 s", "memory": "~1,2 Go",
         "note": "Même modèle, 4× plus rapide ; serveur local 127.0.0.1:8767, stable sur 300 requêtes."},
        {"id": "bge-reranker-v2-m3/mps", "label": "bge-reranker-v2-m3 · GPU (MPS)", "model": "BAAI/bge-reranker-v2-m3",
         "engine": "mps", "fp16": True, "quality": 0.917, "latency": "4,3 s", "memory": "~1 Go",
         "note": "Meilleure qualité mesurée (+0,02, écart non prouvé sur 15 requêtes), 10× plus lent."},
        {"id": "jina-reranker-v2/mps", "label": "jina-reranker-v2-multilingual · GPU (MPS)",
         "model": "jinaai/jina-reranker-v2-base-multilingual", "engine": "mps", "trust_remote_code": True,
         "quality": 0.895, "latency": "1,4 s", "memory": "~1,1 Go",
         "note": "Exécute du code du dépôt Hugging Face (trust_remote_code)."},
        {"id": "mmarco-mMiniLMv2/mps", "label": "mmarco-mMiniLMv2-L12 · GPU (MPS)",
         "model": "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1", "engine": "mps", "quality": 0.881,
         "latency": "0,50 s", "memory": "~1,1 Go", "note": "Petit modèle multilingue, un peu moins bon."},
    ],
    "embeddings": [
        {"id": "bge-m3/cpu", "label": "bge-m3 · CPU dans Hindsight", "model": "BAAI/bge-m3", "engine": "cpu",
         "dimension": 1024, "latency": "requête 0,14 s · 64 passages 14,5 s", "memory": "dans Hindsight",
         "note": "Le réglage d'origine."},
        {"id": "bge-m3/mps", "label": "bge-m3 · GPU (MPS)", "model": "BAAI/bge-m3", "engine": "mps", "fp16": True,
         "dimension": 1024, "latency": "requête 0,024 s · 64 passages 3,8 s", "memory": "~1,2 Go",
         "note": "Mêmes vecteurs (cosinus ≥ 0,9998), pas de réindexation ; serveur local 127.0.0.1:8768."},
    ],
    "decision": [
        {"id": "hs-decide-1-flash/torch", "label": "hs-decide-1-flash · PyTorch (MPS, bf16)",
         "model": "hindsight-ai/hs-decide-1-flash", "engine": "torch", "latency": "6,9 s / 5 500 jetons",
         "memory": "~2 Go", "note": "Le moteur d'origine du serveur de décision."},
        {"id": "hs-decide-1-flash/mlx", "label": "hs-decide-1-flash · MLX (fp16)",
         "model": "hindsight-ai/hs-decide-1-flash", "engine": "mlx", "latency": "4,4 s / 5 500 jetons",
         "memory": "~2 Go",
         "note": "1,6× plus rapide ; scores à 0,01 près de PyTorch, mêmes 5 premiers sur des requêtes réelles."},
        # Modèles System One ouverts, ≤ 1 B, mesurés le 17-18 nov. 2026 sur savoirs (tri : 15 requêtes étiquetées ;
        # doublons : 197 paires proches ; reflect : 2 reflects réels rejoués). Installés dans ~/.hindsight/candidates.
        {"id": "startlux-0.8b/mlx", "label": "StartLux-Decision v1.1 0.8B Instant · MLX 8-bit", "engine": "external",
         "candidate": "startlux-0.8b", "served_model": "StartLux-Decision-v1.1-0.8B-Instant-MLX-8bit",
         "model": "startlux-models/StartLux-Decision-v1.1-0.8B-Instant-MLX-8bit", "quality": 0.729,
         "latency": "reflect 227-305 s", "memory": "~1,9 Go",
         "note": "Tri moins bon que hs-decide (0,73 contre 0,87), 74 doublons signalés dont 1 vrai ; licence non commerciale."},
        {"id": "d3-edge/llamacpp", "label": "Decision 3.0 d3-edge · llama.cpp (GGUF Q8)", "engine": "external",
         "candidate": "d3-edge", "served_model": "ggml-org/vllm-d3-edge-GGUF", "model": "ggml-org/vllm-d3-edge-GGUF",
         "serve_args": ["-c", "16384", "-np", "1", "-b", "16384", "-ub", "16384"], "quality": 0.601,
         "latency": "reflect 139-182 s", "memory": "~1,5 Go",
         "note": "Tri 0,60, 81 doublons signalés dont 1 vrai ; refuse les requêtes de plus de 16 k jetons."},
        {"id": "opendecider-nano/onnx", "label": "opendecider-nano · ONNX CPU (decision-toolkit)", "engine": "external",
         "candidate": "dtk-opendecider-nano", "served_model": "opendecider-nano", "model": "manjunathshiva/opendecider-nano",
         "quality": 0.447, "latency": "reflect 272-411 s", "memory": "~2,5 Go",
         "note": "Tri 0,45, garde presque tout ; plafond de 2 048 jetons (requêtes de Hindsight tronquées)."},
    ],
}
DEFAULTS = {"reranker": "hs-rerank-1/cpu", "embeddings": "bge-m3/cpu", "decision": "hs-decide-1-flash/torch"}
ROLES = tuple(CATALOG)
HF_IGNORE = ["*.onnx", "onnx/*", "openvino/*", "*.msgpack", "*.h5", "flax_model*", "tf_model*", "*.ot",
             "*.gguf", "rust_model*", "coreml/*"]
DECISION_CHECK = {
    "model": "hs-decide-1-flash",
    "state": {"query": "When is the team offsite?",
              "documents": {"D00": "The offsite moved from April 10 to April 17.",
                            "D01": "The team offsite is on April 10 in Denver."}},
    "questions": {"latest": {"type": "choice", "instructions": "Which document gives the current offsite date?",
                             "criteria": {"D00": None, "D01": None}},
                  "moved": {"type": "noul", "instructions": "Did the offsite date change?"}},
}


class Failure(Exception):
    """Une étape a échoué ; le message est montré tel quel dans l'app."""


def now() -> str:
    return _dt.datetime.now().astimezone().isoformat(timespec="seconds")


def option(role: str, option_id: str) -> Dict[str, Any]:
    for o in CATALOG.get(role, []):
        if o["id"] == option_id:
            return o
    raise Failure(f"Option inconnue pour {role} : {option_id}")


# ------------------------------------------------------------------ sélection

def read_selection() -> Dict[str, Any]:
    try:
        data = json.loads(SELECTION.read_text())
    except (OSError, ValueError):
        data = {}
    for role in ROLES:
        if not any(o["id"] == data.get(role) for o in CATALOG[role]):
            data[role] = DEFAULTS[role]
    data["options"] = {role: option(role, data[role]) for role in ROLES}
    return data


def write_selection(sel: Dict[str, Any]) -> None:
    MODELS.mkdir(parents=True, exist_ok=True)
    out = {role: sel[role] for role in ROLES}
    out["options"] = {role: option(role, out[role]) for role in ROLES}
    out["updated"] = now()
    tmp = SELECTION.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, SELECTION)


def api_env(sel: Dict[str, Any]) -> Dict[str, str]:
    """Variables de l'API pour la sélection : reranker, embeddings, et adresse du serveur de décision."""
    env: Dict[str, str] = {}
    r, e = sel["options"]["reranker"], sel["options"]["embeddings"]
    if r["engine"] == "mps":
        env.update({"HINDSIGHT_API_RERANKER_PROVIDER": "tei",
                    "HINDSIGHT_API_RERANKER_TEI_URL": f"http://127.0.0.1:{SERVERS['reranker']['port']}",
                    "HINDSIGHT_API_RERANKER_TEI_BATCH_SIZE": "200",
                    "HINDSIGHT_API_RERANKER_TEI_MAX_CONCURRENT": "2",
                    "HINDSIGHT_API_RERANKER_TEI_HTTP_TIMEOUT": "60"})
    else:
        env.update({"HINDSIGHT_API_RERANKER_PROVIDER": "local", "HINDSIGHT_API_RERANKER_LOCAL_MODEL": r["model"],
                    "HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU": "true",
                    "HINDSIGHT_API_RERANKER_LOCAL_TRUST_REMOTE_CODE": "true" if r.get("trust_remote_code") else "false"})
    if e["engine"] == "mps":
        env.update({"HINDSIGHT_API_EMBEDDINGS_PROVIDER": "tei",
                    "HINDSIGHT_API_EMBEDDINGS_TEI_URL": f"http://127.0.0.1:{SERVERS['embeddings']['port']}"})
    else:
        env.update({"HINDSIGHT_API_EMBEDDINGS_PROVIDER": "local", "HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL": e["model"]})
    d = sel["options"]["decision"]
    if d["engine"] == "external":
        env.update({"HINDSIGHT_API_DECISION_MODEL_BASE_URL": f"http://127.0.0.1:{DECISION_ALT['port']}",
                    "HINDSIGHT_API_DECISION_MODEL_MODEL": d["served_model"]})
    else:
        env.update({"HINDSIGHT_API_DECISION_MODEL_BASE_URL": DEC_URL,
                    "HINDSIGHT_API_DECISION_MODEL_MODEL": "hs-decide-1-flash"})
    return env


# ------------------------------------------------------------------ HTTP, launchd

def http(method: str, url: str, body: Any = None, timeout: float = 30, headers: Optional[Dict[str, str]] = None) -> Any:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data, {"Content-Type": "application/json", **(headers or {})}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read() or b"null")


def try_http(url: str, timeout: float = 2) -> Optional[Any]:
    try:
        return http("GET", url, timeout=timeout)
    except (OSError, ValueError, urllib.error.URLError):
        return None


def wait_for(what: str, check: Callable[[], bool], timeout: float, every: float = 1.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(every)
    raise Failure(f"{what} : pas de réponse en {int(timeout)} s")


def launchctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True, timeout=60)


def domain() -> str:
    return f"gui/{os.getuid()}"


def loaded(label: str) -> bool:
    return launchctl("print", f"{domain()}/{label}").returncode == 0


def restart(label: str) -> None:
    r = launchctl("kickstart", "-k", f"{domain()}/{label}")
    if r.returncode != 0:
        raise Failure(f"launchctl kickstart {label} : {(r.stderr or r.stdout).strip()[:200]}")


def agent_plist(label: str) -> Path:
    return AGENTS / f"{label}.plist"


def server_plist(role: str) -> Path:
    return agent_plist(SERVERS[role]["label"])


def install_agent(label: str, program: List[str], log: str) -> None:
    """Service launchd (relancé s'il plante) ; redémarré s'il existe déjà à l'identique."""
    plist = {
        "Label": label, "ProgramArguments": program,
        "EnvironmentVariables": {"HF_HUB_OFFLINE": "1", "PYTORCH_ENABLE_MPS_FALLBACK": "1",
                                 "TOKENIZERS_PARALLELISM": "false", "PYTHONUNBUFFERED": "1"},
        "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False}, "ThrottleInterval": 30, "ExitTimeOut": 15,
        "StandardOutPath": str(LOGS / log), "StandardErrorPath": str(LOGS / log),
    }
    LOGS.mkdir(parents=True, exist_ok=True)
    path = agent_plist(label)
    new = plistlib.dumps(plist)
    if loaded(label) and path.exists() and path.read_bytes() == new:
        restart(label)
        return
    if loaded(label):
        launchctl("bootout", f"{domain()}/{label}")
    path.write_bytes(new)
    r = launchctl("bootstrap", domain(), str(path))
    if r.returncode != 0:
        raise Failure(f"launchctl bootstrap {label} : {(r.stderr or r.stdout).strip()[:200]}")


def remove_agent(label: str) -> None:
    if loaded(label):
        launchctl("bootout", f"{domain()}/{label}")
    try:
        agent_plist(label).unlink()
    except FileNotFoundError:
        pass


def install_server(role: str) -> None:
    """Serveur MPS du rôle ; il lit son modèle dans selection.json au démarrage."""
    if not SERVER_SCRIPT.exists():
        raise Failure(f"{SERVER_SCRIPT} manquant (réinstallez depuis Hindsight Desktop)")
    s = SERVERS[role]
    install_agent(s["label"], [str(HS_PY), "-I", str(SERVER_SCRIPT), "--role", role, "--port", str(s["port"])],
                  f"hindsight-{role}-server.log")


def remove_server(role: str) -> None:
    remove_agent(SERVERS[role]["label"])


def candidate_serve(o: Dict[str, Any]) -> Path:
    return CANDIDATES / o["candidate"] / "serve.sh"


def decision_check(url: str, model: str, timeout: float = 300) -> Dict[str, Any]:
    """La question de contrôle au serveur System One ; rend ses réponses (lève si le protocole échoue)."""
    key = (DECISION / "api-key").read_text().strip() if (DECISION / "api-key").exists() else "local"
    body = dict(DECISION_CHECK, model=model)
    a = http("POST", f"{url}/v1/systemone", body, timeout, {"Authorization": f"Bearer {key}"})
    answers = a.get("answers") or {}
    if "latest" not in answers or "moved" not in answers:
        raise Failure(f"réponse System One incomplète : {json.dumps(a)[:200]}")
    return answers


def check_is_right(answers: Dict[str, Any]) -> bool:
    latest, moved = answers.get("latest") or {}, answers.get("moved") or {}
    return latest.get("choice") == "D00" and (moved.get("noul") or 0) > 0.5


def wait_decision(url: str, model: str, timeout: float = 300) -> None:
    def ok() -> bool:
        try:
            decision_check(url, model, 60)
            return True
        except Exception:
            return False
    wait_for("serveur de décision", ok, timeout, 3)


def wait_server(role: str, model: str, timeout: float = 240) -> None:
    url = f"http://127.0.0.1:{SERVERS[role]['port']}/info"
    wait_for(f"serveur {role}", lambda: (try_http(url) or {}).get("model_id") == model, timeout, 2)


# ------------------------------------------------------------------ Hindsight

def api_up() -> bool:
    return try_http(f"{API}/health", 3) is not None


def banks() -> List[str]:
    data = http("GET", f"{API}/v1/default/banks", timeout=15)
    items = data.get("banks", data) if isinstance(data, dict) else data
    return [b.get("bank_id") or b.get("id") for b in items if isinstance(b, dict)]


def running_operations() -> List[str]:
    """Opérations en cours ou dues maintenant (une reprise programmée plus tard ne bloque pas)."""
    busy, t = [], _dt.datetime.now(_dt.timezone.utc)
    for bank in banks():
        ops = http("GET", f"{API}/v1/default/banks/{bank}/operations?status=pending&limit=100", timeout=15)
        for op in ops.get("operations", []):
            retry = op.get("next_retry_at")
            if retry:
                try:
                    if _dt.datetime.fromisoformat(retry.replace("Z", "+00:00")) > t:
                        continue
                except ValueError:
                    pass
            busy.append(f"{bank}:{op.get('operation_type') or op.get('task_type')}")
    return busy


def probe_bank() -> str:
    names = banks()
    if "savoirs" in names:
        return "savoirs"
    if not names:
        raise Failure("aucune banque pour vérifier la recherche")
    return names[0]


def recall(bank: str, budget: str = "mid") -> Dict[str, Any]:
    t = time.monotonic()
    d = http("POST", f"{API}/v1/default/banks/{bank}/memories/recall",
             {"query": PROBE_QUERY, "budget": budget, "max_tokens": 2000, "trace": True}, timeout=600)
    wall = time.monotonic() - t
    phases = d.get("trace", {}).get("summary", {}).get("phase_metrics", []) or []
    rr = next((p for p in phases if p.get("phase_name") == "reranking"), {})
    emb = next((p for p in phases if p.get("phase_name") == "generate_query_embedding"), {})
    return {"wall_s": round(wall, 2), "reranking_s": round(rr.get("duration_seconds", 0.0), 2),
            "embedding_s": round(emb.get("duration_seconds", 0.0), 2),
            "candidates": (rr.get("details") or {}).get("candidates_reranked"),
            "results": d.get("results", [])}


def api_log_since(offset: int) -> str:
    log = ROOT / "bge-m3-api.log"
    try:
        with open(log, "rb") as f:
            f.seek(offset)
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def api_log_size() -> int:
    try:
        return (ROOT / "bge-m3-api.log").stat().st_size
    except OSError:
        return 0


def api_script() -> Path:
    plist = AGENTS / f"{API_LABEL}.plist"
    try:
        return Path(plistlib.loads(plist.read_bytes())["ProgramArguments"][0])
    except (OSError, KeyError, IndexError, ValueError):
        raise Failure(f"service {API_LABEL} introuvable : le gestionnaire ne gère qu'un serveur lancé sur ce Mac")


def hook_installed() -> bool:
    try:
        return HOOK_MARK in api_script().read_text()
    except (OSError, Failure):
        return False


def install_hook() -> str:
    """Ajoute au script de lancement de l'API la lecture de la sélection (sauvegarde datée avant)."""
    script = api_script()
    text = script.read_text()
    if HOOK_MARK in text:
        return "déjà en place"
    lines = text.splitlines(keepends=True)
    at = max((i for i, l in enumerate(lines) if l.lstrip().startswith("exec ")), default=None)
    if at is None:
        raise Failure(f"{script} : pas de ligne exec où insérer la sélection des modèles")
    while at > 0 and lines[at - 1].lstrip().startswith("cd "):
        at -= 1
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = script.with_name(f"{script.name}.bak-{stamp}-gestionnaire-modeles")
    shutil.copy2(script, backup)
    hook = (
        f"# {_dt.date.today().isoformat()} : modèles locaux (reranker, embeddings) choisis dans Hindsight Desktop › Modèles.\n"
        "# ~/.hindsight/models/selection.json, lu par hindsight-models.py ; sans lui, les réglages ci-dessus restent.\n"
        f"# Retour : {backup.name}.\n"
        'if MODELS_ENV="$("$HOME/.hindsight/venv/bin/python" -I "$HOME/.hindsight/models/hindsight-models.py" env)"; then\n'
        '  eval "$MODELS_ENV"\n'
        "fi\n"
    )
    lines.insert(at, hook)
    tmp = script.with_suffix(".tmp-models")
    tmp.write_text("".join(lines))
    shutil.copymode(script, tmp)
    if subprocess.run(["/bin/bash", "-n", str(tmp)]).returncode != 0:
        tmp.unlink()
        raise Failure("le script modifié ne passe pas bash -n ; rien n'a changé")
    os.replace(tmp, script)
    return f"ajouté (sauvegarde {backup.name})"


# ------------------------------------------------------------------ travail suivi (job.json)

class Job:
    STEPS = ("download", "test", "wait", "activate", "verify")
    TITLES = {"download": "Télécharger", "test": "Tester", "wait": "Attendre la fin des opérations",
              "activate": "Activer et redémarrer", "verify": "Vérifier", "rollback": "Revenir en arrière"}

    def __init__(self, role: str, target: str, previous: str) -> None:
        self.data: Dict[str, Any] = {
            "role": role, "option": target, "previous": previous, "status": "running", "pid": os.getpid(),
            "started": now(), "finished": None, "message": None, "measures": {},
            "steps": [{"id": s, "title": self.TITLES[s], "status": "pending", "detail": None} for s in self.STEPS],
            "log": [],
        }
        self.save()

    def save(self) -> None:
        MODELS.mkdir(parents=True, exist_ok=True)
        tmp = JOB.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=2, ensure_ascii=False))
        os.replace(tmp, JOB)

    def step(self, sid: str, status: str, detail: Optional[str] = None) -> None:
        steps = self.data["steps"]
        found = next((s for s in steps if s["id"] == sid), None)
        if found is None:
            found = {"id": sid, "title": self.TITLES.get(sid, sid), "status": status, "detail": detail}
            steps.append(found)
        found["status"], found["detail"] = status, detail
        self.say(f"{found['title']} : {status}{' — ' + detail if detail else ''}")

    def say(self, line: str) -> None:
        stamp = _dt.datetime.now().strftime("%H:%M:%S")
        self.data["log"] = (self.data["log"] + [f"{stamp} {line}"])[-80:]
        self.save()
        print(json.dumps({"t": stamp, "line": line}, ensure_ascii=False), flush=True)

    def finish(self, status: str, message: str) -> None:
        self.data.update(status=status, message=message, finished=now())
        self.say(message)


def current_job() -> Optional[Dict[str, Any]]:
    try:
        job = json.loads(JOB.read_text())
    except (OSError, ValueError):
        return None
    if job.get("status") == "running":
        try:
            os.kill(int(job.get("pid", 0)), 0)
        except (OSError, ValueError):
            job.update(status="failed", message="Le travail s'est arrêté sans finir (processus disparu).")
    return job


def history(role: Optional[str] = None) -> List[Dict[str, Any]]:
    try:
        rows = [json.loads(l) for l in HISTORY.read_text().splitlines() if l.strip()]
    except (OSError, ValueError):
        rows = []
    return [r for r in rows if role is None or r.get("role") == role]


def remember(entry: Dict[str, Any]) -> None:
    MODELS.mkdir(parents=True, exist_ok=True)
    with open(HISTORY, "a") as f:
        f.write(json.dumps({"at": now(), **entry}, ensure_ascii=False) + "\n")


# ------------------------------------------------------------------ étapes

def run_py(python: Path, code: str, payload: Any, timeout: float, env: Optional[Dict[str, str]] = None) -> Any:
    """Exécute `code` dans un environnement Python de Hindsight ; entrée et sortie en JSON (dernière ligne)."""
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "step.py"
        script.write_text(code)
        r = subprocess.run([str(python), "-I", str(script)], input=json.dumps(payload), capture_output=True,
                           text=True, timeout=timeout, cwd=tmp, env={**os.environ, **(env or {})})
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-3:]
        raise Failure(" / ".join(tail)[:400] or f"code {r.returncode}")
    return json.loads(r.stdout.strip().splitlines()[-1])


DOWNLOAD_CODE = """
import json, sys
from huggingface_hub import snapshot_download
p = json.load(sys.stdin)
path = snapshot_download(p["repo"], ignore_patterns=p["ignore"])
print(json.dumps({"path": path}))
"""


def find_uv() -> str:
    for c in (shutil.which("uv"), str(HOME / ".local/bin/uv"), "/opt/homebrew/bin/uv", str(HOME / ".cargo/bin/uv")):
        if c and Path(c).exists():
            return c
    raise Failure("uv introuvable : il faut uv pour ajouter MLX à l'environnement du modèle de décision")


def download(job: Job, role: str, o: Dict[str, Any]) -> None:
    if role == "decision":
        if not (DECISION / "hs-decide-1-flash" / "model.safetensors").exists() or not DEC_PY.exists():
            raise Failure("Installez d'abord le modèle de décision sur ce Mac (Modèles › Modèle de décision sur ce Mac).")
        if o["engine"] == "external":
            if not os.access(candidate_serve(o), os.X_OK):
                raise Failure(f"{o['label']} n'est pas installé ({candidate_serve(o)} absent) : voir ~/.hindsight/candidates/README.md")
            return
        if o["engine"] == "mlx":
            has = subprocess.run([str(DEC_PY), "-I", "-c", "import mlx_lm"], capture_output=True).returncode == 0
            if not has:
                job.say(f"ajout de {MLX_PACKAGE} à l'environnement du modèle de décision")
                r = subprocess.run([find_uv(), "pip", "install", "--python", str(DEC_PY), MLX_PACKAGE],
                                   capture_output=True, text=True, timeout=1800)
                if r.returncode != 0:
                    raise Failure(f"installation de MLX : {(r.stderr or r.stdout).strip()[-300:]}")
            return
        return
    out = run_py(HS_PY, DOWNLOAD_CODE, {"repo": o["model"], "ignore": HF_IGNORE}, 7200, {"HF_HUB_OFFLINE": "0"})
    job.say(f"{o['model']} présent : {out['path']}")


RERANK_CPU_CODE = """
import asyncio, json, sys, time
from hindsight_api.engine.cross_encoder import LocalSTCrossEncoder
p = json.load(sys.stdin)
async def main():
    enc = LocalSTCrossEncoder(p["model"], max_concurrent=1, force_cpu=True, bucket_batching=True,
                              trust_remote_code=p["trust"])
    enc.max_tokens_per_candidate = 512
    await enc.initialize()
    s = await enc.predict(p["sanity"])
    lat = []
    for _ in range(3):
        t = time.monotonic(); await enc.predict([(p["query"], d) for d in p["texts"]]); lat.append(time.monotonic() - t)
    print(json.dumps({"sanity": s, "latency": sorted(lat)[1]}))
asyncio.run(main())
"""

EMBED_CPU_CODE = """
import json, sys, time
from sentence_transformers import SentenceTransformer
p = json.load(sys.stdin)
m = SentenceTransformer(p["model"], device="cpu"); m.max_seq_length = 512
v = m.encode([p["query"]], normalize_embeddings=True)
lat = []
for _ in range(3):
    t = time.monotonic(); m.encode(p["texts"], batch_size=32, normalize_embeddings=True); lat.append(time.monotonic() - t)
print(json.dumps({"vector": [float(x) for x in v[0]], "latency": sorted(lat)[1]}))
"""

SANITY = [("Quand a lieu le séminaire de l'équipe ?", "Le séminaire de l'équipe a lieu le 17 avril à Lyon."),
          ("Quand a lieu le séminaire de l'équipe ?", "La recette de la tarte aux pommes demande trois pommes.")]


def probe_texts() -> List[str]:
    """Faits réels pour mesurer la latence : ceux que la recherche actuelle renvoie (lecture seule)."""
    try:
        res = recall(probe_bank(), "low")["results"]
        texts = [r.get("text", "") for r in res if r.get("text")]
    except Exception:
        texts = []
    return (texts * 8)[:80] or [s[1] for s in SANITY] * 40


def temp_server(role: str, o: Dict[str, Any]) -> subprocess.Popen:
    port = SERVERS[role]["test_port"]
    args = [str(HS_PY), "-I", str(SERVER_SCRIPT), "--task", "rerank" if role == "reranker" else "embed",
            "--model", o["model"], "--port", str(port)]
    if o.get("fp16"):
        args.append("--fp16")
    if o.get("trust_remote_code"):
        args.append("--trust-remote-code")
    LOGS.mkdir(parents=True, exist_ok=True)
    out = open(LOGS / f"hindsight-{role}-test.log", "ab")
    proc = subprocess.Popen(args, stdout=out, stderr=out, env={**os.environ, "HF_HUB_OFFLINE": "1",
                                                              "PYTORCH_ENABLE_MPS_FALLBACK": "1"})
    try:
        wait_for("serveur d'essai", lambda: proc.poll() is None and try_http(f"http://127.0.0.1:{port}/info") is not None,
                 240, 2)
    except Failure:
        proc.kill()
        raise Failure(f"le serveur d'essai ne démarre pas (journal : {LOGS / f'hindsight-{role}-test.log'})")
    return proc


def test(job: Job, role: str, o: Dict[str, Any]) -> str:
    texts = probe_texts() if role != "decision" else []
    if role == "decision" and o["engine"] == "external":
        port = DECISION_ALT["test_port"]
        LOGS.mkdir(parents=True, exist_ok=True)
        out = open(LOGS / "hindsight-decision-test.log", "ab")
        proc = subprocess.Popen([str(candidate_serve(o)), str(port), *o.get("serve_args", [])], stdout=out, stderr=out,
                                start_new_session=True)
        try:
            url = f"http://127.0.0.1:{port}"
            wait_decision(url, o["served_model"], 600)
            t = time.monotonic(); answers = decision_check(url, o["served_model"]); dt = time.monotonic() - t
        finally:
            os.killpg(proc.pid, signal.SIGTERM); proc.wait(30)
        job.data["measures"]["test_latency_s"] = round(dt, 2)
        right = "juste" if check_is_right(answers) else "fausse (le protocole marche)"
        return f"question de contrôle {right} en {dt:.2f} s"
    if role == "decision":
        args = [str(DEC_PY), "-I", str(DECISION / "serve.py"), "--model", str(DECISION / "hs-decide-1-flash"),
                "--engine", o["engine"], "--check"]
        r = subprocess.run(args, capture_output=True, text=True, timeout=600,
                           env={**os.environ, "HF_HUB_OFFLINE": "1", "PYTORCH_ENABLE_MPS_FALLBACK": "1"})
        if "unrecognized arguments: --engine" in r.stderr:
            raise Failure("serve.py ne connaît pas l'option --engine : mettez à jour le modèle de décision depuis l'app")
        last = (r.stdout.strip().splitlines() or [""])[-1]
        if r.returncode != 0 or not last.startswith("OK"):
            raise Failure(f"réponse de contrôle fausse : {last or r.stderr.strip()[-200:]}")
        return last
    if role == "reranker":
        if o["engine"] == "cpu":
            out = run_py(HS_PY, RERANK_CPU_CODE, {"model": o["model"], "trust": bool(o.get("trust_remote_code")),
                                                  "sanity": SANITY, "query": PROBE_QUERY, "texts": texts}, 900,
                         {"HF_HUB_OFFLINE": "1"})
            sanity, latency = out["sanity"], out["latency"]
        else:
            proc = temp_server(role, o)
            try:
                url = f"http://127.0.0.1:{SERVERS[role]['test_port']}/rerank"
                ranked = http("POST", url, {"query": SANITY[0][0], "texts": [s[1] for s in SANITY]})
                sanity = [next(x["score"] for x in ranked if x["index"] == i) for i in range(2)]
                http("POST", url, {"query": PROBE_QUERY, "texts": texts}, timeout=120)
                lat = []
                for _ in range(3):
                    t = time.monotonic(); http("POST", url, {"query": PROBE_QUERY, "texts": texts}, timeout=120)
                    lat.append(time.monotonic() - t)
                latency = sorted(lat)[1]
            finally:
                proc.terminate(); proc.wait(30)
        if not sanity[0] > sanity[1]:
            raise Failure(f"classement absurde sur la paire de contrôle ({sanity[0]:.2f} ≤ {sanity[1]:.2f})")
        job.data["measures"]["test_latency_s"] = round(latency, 2)
        return f"{len(texts)} faits réels classés en {latency:.2f} s ; paire de contrôle bien classée"
    # embeddings : mêmes vecteurs que le modèle de référence sur CPU, sinon les banques ne se retrouvent plus
    ref = run_py(HS_PY, EMBED_CPU_CODE, {"model": o["model"], "query": PROBE_QUERY, "texts": texts[:64]}, 900,
                 {"HF_HUB_OFFLINE": "1"})
    if o["engine"] == "cpu":
        latency, cos = ref["latency"], 1.0
    else:
        proc = temp_server(role, o)
        try:
            url = f"http://127.0.0.1:{SERVERS[role]['test_port']}/embed"
            v = http("POST", url, {"inputs": [PROBE_QUERY]})[0]
            lat = []
            for _ in range(3):
                t = time.monotonic(); http("POST", url, {"inputs": texts[:64]}, timeout=300); lat.append(time.monotonic() - t)
            latency = sorted(lat)[1]
        finally:
            proc.terminate(); proc.wait(30)
        if len(v) != len(ref["vector"]):
            raise Failure(f"dimension {len(v)} au lieu de {len(ref['vector'])} : il faudrait réindexer les banques")
        cos = sum(a * b for a, b in zip(v, ref["vector"]))
        if cos < 0.999:
            raise Failure(f"vecteurs différents de la référence (cosinus {cos:.4f}) : refusé")
    job.data["measures"]["test_latency_s"] = round(latency, 2)
    return f"{min(64, len(texts))} faits encodés en {latency:.2f} s ; cosinus avec la référence {cos:.4f}"


def wait_idle(job: Job, timeout: float = 1800) -> str:
    if not api_up():
        return "API arrêtée : rien à attendre"
    deadline = time.monotonic() + timeout
    while True:
        busy = running_operations()
        if not busy:
            return "aucune opération en cours"
        if time.monotonic() > deadline:
            raise Failure(f"Hindsight reste occupé ({', '.join(busy[:3])}) : rien n'a été changé")
        job.say(f"en attente : {', '.join(busy[:3])}")
        time.sleep(20)


def activate(job: Job, role: str, sel: Dict[str, Any], before_env: Dict[str, str]) -> Dict[str, Any]:
    """Écrit la sélection et redémarre ce qui en dépend. Rend le contexte de vérification."""
    o = sel["options"][role]
    write_selection(sel)
    ctx: Dict[str, Any] = {"log_offset": api_log_size(), "api_restarted": False}
    if role == "decision":
        if o["engine"] == "external":
            install_agent(DECISION_ALT["label"], [str(candidate_serve(o)), str(DECISION_ALT["port"]), *o.get("serve_args", [])],
                          "hindsight-decision-alt.log")
            wait_decision(f"http://127.0.0.1:{DECISION_ALT['port']}", o["served_model"], 600)
        else:
            if not loaded(DEC_LABEL):
                launchctl("bootstrap", domain(), str(agent_plist(DEC_LABEL)))
            restart(DEC_LABEL)
            wait_for("serveur de décision",
                     lambda: (try_http(f"{DEC_URL}/health") or {}).get("engine") == o["engine"], 120, 2)
        if api_env(read_selection()) != before_env:
            if not hook_installed():
                job.say(f"script de lancement : lecture de la sélection {install_hook()}")
            restart(API_LABEL)
            ctx["api_restarted"] = True
            time.sleep(3)
            wait_for("API Hindsight", api_up, 600, 3)
        return ctx
    if o["engine"] == "mps":
        install_server(role)
        wait_server(role, o["model"])
        job.say(f"serveur {SERVERS[role]['label']} prêt (127.0.0.1:{SERVERS[role]['port']})")
    if api_env(read_selection()) != before_env:
        if not hook_installed():
            job.say(f"script de lancement : lecture de la sélection {install_hook()}")
        restart(API_LABEL)
        ctx["api_restarted"] = True
        time.sleep(3)
        wait_for("API Hindsight", api_up, 600, 3)
    return ctx


def verify(job: Job, role: str, o: Dict[str, Any], ctx: Dict[str, Any]) -> str:
    # Essai du retour arrière : HINDSIGHT_MODELS_FAIL_VERIFY=<option> fait échouer la vérification de cette option.
    if os.environ.get("HINDSIGHT_MODELS_FAIL_VERIFY") == o["id"]:
        raise Failure("échec simulé de la vérification (essai du retour arrière)")
    if role == "decision" and o["engine"] == "external":
        t = time.monotonic()
        answers = decision_check(f"http://127.0.0.1:{DECISION_ALT['port']}", o["served_model"])
        dt = time.monotonic() - t
        if ctx.get("api_restarted") and f"model={o['served_model']}" not in api_log_since(ctx["log_offset"]):
            raise Failure(f"le journal de l'API ne montre pas le modèle de décision {o['served_model']}")
        job.data["measures"]["decision_check_s"] = round(dt, 2)
        return f"serveur System One {o['served_model']} branché ; contrôle {'juste' if check_is_right(answers) else 'faux'} en {dt:.2f} s"
    if role == "decision":
        key = (DECISION / "api-key").read_text().strip()
        t = time.monotonic()
        a = http("POST", f"{DEC_URL}/v1/systemone", DECISION_CHECK, 300, {"Authorization": f"Bearer {key}"})
        dt = time.monotonic() - t
        if a["answers"]["latest"]["choice"] != "D00" or a["answers"]["moved"]["noul"] <= 0.5:
            raise Failure("le serveur de décision répond faux à la question de contrôle")
        engine = (try_http(f"{DEC_URL}/health") or {}).get("engine")
        if engine != o["engine"]:
            raise Failure(f"le serveur tourne avec {engine} au lieu de {o['engine']}")
        job.data["measures"]["decision_check_s"] = round(dt, 2)
        return f"décision juste en {dt:.2f} s (moteur {engine})"
    r = recall(probe_bank())
    if not r["results"]:
        raise Failure("la recherche de contrôle ne renvoie rien")
    if role == "reranker" and r["reranking_s"] > 30:
        raise Failure(f"reranking trop lent ({r['reranking_s']} s)")
    if ctx.get("api_restarted"):
        log = api_log_since(ctx["log_offset"])
        expect = {("reranker", "mps"): f"TEI provider initialized (model: {o['model']})",
                  ("reranker", "cpu"): f"initializing local provider with model {o['model']}",
                  ("embeddings", "mps"): "Embeddings: provider=tei",
                  ("embeddings", "cpu"): "Embeddings: provider=local"}[(role, o["engine"])]
        if expect not in log:
            raise Failure(f"le journal de l'API ne montre pas « {expect} »")
    job.data["measures"].update(recall_mid_s=r["wall_s"], reranking_s=r["reranking_s"], embedding_s=r["embedding_s"])
    return (f"recall mid « {PROBE_QUERY} » : {len(r['results'])} résultats en {r['wall_s']} s "
            f"(reranking {r['reranking_s']} s, {r['candidates']} candidats ; embedding {r['embedding_s']} s)")


def cleanup(sel: Dict[str, Any]) -> None:
    for role in SERVERS:
        if sel["options"][role]["engine"] != "mps":
            remove_server(role)
    if sel["options"]["decision"]["engine"] != "external":
        remove_agent(DECISION_ALT["label"])


def apply(role: str, target: str) -> int:
    if role not in ROLES:
        raise Failure(f"rôle inconnu : {role}")
    o = option(role, target)
    running = current_job()
    if running and running.get("status") == "running" and running.get("pid") != os.getpid():
        raise Failure("un autre changement de modèle est en cours")
    sel = read_selection()
    previous = sel[role]
    job = Job(role, target, previous)
    before_env = api_env(sel)
    step = "download"
    try:
        job.step("download", "running")
        download(job, role, o)
        job.step("download", "ok")
        step = "test"
        job.step("test", "running")
        job.step("test", "ok", test(job, role, o))
        step = "wait"
        job.step("wait", "running")
        job.step("wait", "ok", wait_idle(job))
    except Exception as e:  # rien n'a encore changé
        job.step(step, "failed", str(e))
        job.finish("failed", f"Échec avant activation : {e}. Rien n'a changé.")
        remember({"role": role, "from": previous, "to": target, "result": "failed", "reason": str(e)})
        return 1
    new = dict(sel)
    new[role] = target
    new["options"] = {r: option(r, new[r]) for r in ROLES}
    step = "activate"
    try:
        job.step("activate", "running")
        ctx = activate(job, role, new, before_env)
        job.step("activate", "ok")
        step = "verify"
        job.step("verify", "running")
        job.step("verify", "ok", verify(job, role, o, ctx))
    except Exception as e:
        job.step(step, "failed", str(e))
        reason = str(e)
        job.step("rollback", "running", f"retour à {previous}")
        try:
            back = dict(sel)
            ctx = activate(job, role, back, api_env(new))
            verify(job, role, back["options"][role], ctx)
            cleanup(back)
            job.step("rollback", "ok", f"{previous} de nouveau actif et vérifié")
            job.finish("rolled_back", f"Échec ({reason}) : retour automatique à {previous}, vérifié.")
            remember({"role": role, "from": previous, "to": target, "result": "rolled_back", "reason": reason})
        except Exception as e2:
            job.step("rollback", "failed", str(e2))
            job.finish("failed", f"Échec ({reason}) puis échec du retour arrière ({e2}). Voir README › Dépannage.")
            remember({"role": role, "from": previous, "to": target, "result": "rollback_failed", "reason": f"{reason} / {e2}"})
        return 1
    cleanup(new)
    job.finish("ok", f"{o['label']} actif et vérifié.")
    remember({"role": role, "from": previous, "to": target, "result": "ok", "measures": job.data["measures"]})
    return 0


def previous_choice(role: str) -> str:
    current = read_selection()[role]
    for row in reversed(history(role)):
        if row.get("result") == "ok" and row.get("to") == current and row.get("from") != current:
            return row["from"]
    raise Failure(f"aucun choix précédent connu pour {role}")


def status() -> Dict[str, Any]:
    sel = read_selection()
    servers = {}
    for role, s in SERVERS.items():
        info = try_http(f"http://127.0.0.1:{s['port']}/info", 1)
        servers[role] = {"label": s["label"], "port": s["port"], "installed": server_plist(role).exists(),
                         "model": (info or {}).get("model_id"), "running": info is not None}
    alt = sel["options"]["decision"]
    if alt["engine"] == "external":
        servers["decision-alt"] = {"label": DECISION_ALT["label"], "port": DECISION_ALT["port"],
                                   "installed": agent_plist(DECISION_ALT["label"]).exists(),
                                   "model": alt["served_model"], "running": loaded(DECISION_ALT["label"])}
    dec = try_http(f"{DEC_URL}/health", 1)
    servers["decision"] = {"label": DEC_LABEL, "port": 8766, "installed": (AGENTS / f"{DEC_LABEL}.plist").exists(),
                           "engine": (dec or {}).get("engine", "torch" if dec else None), "running": dec is not None}
    prev: Dict[str, Optional[str]] = {}
    for r in ROLES:
        try:
            prev[r] = previous_choice(r)
        except Failure:
            prev[r] = None
    return {"catalog": CATALOG, "selection": {r: sel[r] for r in ROLES}, "updated": sel.get("updated"),
            "selectionFile": str(SELECTION), "hook": hook_installed(), "servers": servers,
            "previous": prev, "job": current_job(), "history": history()[-10:], "apiUp": api_up()}


def start(role: str, target: str) -> Dict[str, Any]:
    option(role, target)
    job = current_job()
    if job and job.get("status") == "running":
        raise Failure("un autre changement de modèle est en cours")
    LOGS.mkdir(parents=True, exist_ok=True)
    log = open(LOGS / "hindsight-models.log", "ab")
    proc = subprocess.Popen([sys.executable, "-I", str(Path(__file__).resolve()), "apply", role, target],
                            stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True)
    # Rendre la main une fois job.json au nom du nouveau travail : l'app le suit dès sa première lecture.
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and proc.poll() is None:
        if (current_job() or {}).get("pid") == proc.pid:
            break
        time.sleep(0.2)
    return {"started": True, "pid": proc.pid}


def main(argv: List[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "status"
    try:
        if cmd == "status":
            print(json.dumps(status(), ensure_ascii=False))
        elif cmd == "env":
            for k, v in api_env(read_selection()).items():
                print(f"export {k}={v}")
        elif cmd == "hook":
            print(install_hook())
        elif cmd == "init":
            if not SELECTION.exists():
                write_selection(read_selection())
            print(SELECTION)
        elif cmd == "apply" and len(argv) == 4:
            return apply(argv[2], argv[3])
        elif cmd == "start" and len(argv) == 4:
            print(json.dumps(start(argv[2], argv[3])))
        elif cmd == "rollback" and len(argv) == 3:
            return apply(argv[2], previous_choice(argv[2]))
        elif cmd == "start-rollback" and len(argv) == 3:
            print(json.dumps(start(argv[2], previous_choice(argv[2]))))
        elif cmd == "test" and len(argv) == 4:
            o = option(argv[2], argv[3])
            job = Job(argv[2], argv[3], read_selection()[argv[2]])
            download(job, argv[2], o)
            job.finish("ok", test(job, argv[2], o))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except Failure as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    sys.exit(main(sys.argv))
"""#

    static let server = #"""
#!/usr/bin/env python3
"""Serveur local, compatible TEI, d'un reranker ou d'un modèle d'embeddings sur le GPU du Mac (MPS).

Hindsight refuse MPS dans son propre processus (fuites sous des longueurs variables, plantages sous
concurrence). Ici le modèle vit dans un processus à part, les requêtes passent une à une et la mémoire
du GPU est rendue après chacune ; Hindsight l'appelle par son fournisseur `tei`
(`HINDSIGHT_API_RERANKER_TEI_URL` ou `HINDSIGHT_API_EMBEDDINGS_TEI_URL`).

Routes (sous-ensemble de text-embeddings-inference) :
  GET  /health, GET /info                      -> {"model_id", ...}
  POST /rerank {"query", "texts"}              -> [{"index", "score"}], score = logit brut, trié
  POST /embed  {"inputs": str | [str]}         -> [[float]] normalisés (L2)

Les scores du reranker sont des logits bruts, comme ceux du reranker local de Hindsight : le recall leur
applique la sigmoïde. Rien du contenu des requêtes n'est journalisé.

Usage : python hindsight-model-server.py --task rerank --model hindsight-ai/hs-rerank-1 --port 8767
        python hindsight-model-server.py --role reranker --port 8767   (modèle lu dans selection.json)
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

MAX_BODY_BYTES = 32 * 1024 * 1024
log = logging.getLogger("hindsight-model-server")


class Model:
    """Un modèle chargé une fois ; un verrou fait passer les requêtes l'une après l'autre."""

    def __init__(self, task: str, name: str, device: str, fp16: bool, max_length: int, trust: bool) -> None:
        import torch

        self.torch, self.task, self.name, self.device = torch, task, name, device
        self.lock = threading.Lock()
        started = time.monotonic()
        if task == "rerank":
            from sentence_transformers import CrossEncoder

            self.model = CrossEncoder(name, device=device, max_length=max_length, trust_remote_code=trust,
                                      activation_fn=torch.nn.Identity())
            inner = self.model.model
        else:
            from sentence_transformers import SentenceTransformer

            self.model = SentenceTransformer(name, device=device, trust_remote_code=trust)
            self.model.max_seq_length = max_length
            inner = self.model
        if fp16 and device != "cpu":
            inner.half()
        self.dimension = None if task == "rerank" else self.model.get_sentence_embedding_dimension()
        log.info("%s chargé sur %s%s en %.1f s", name, device, " (fp16)" if fp16 else "", time.monotonic() - started)

    def _release(self) -> None:
        if self.device == "mps":
            self.torch.mps.empty_cache()

    def rerank(self, query: str, texts: list[str]) -> list[dict[str, Any]]:
        with self.lock:
            try:
                scores = self.model.predict([(query, t) for t in texts], batch_size=32, show_progress_bar=False)
            finally:
                self._release()
        ranked = sorted(enumerate(float(s) for s in scores), key=lambda p: -p[1])
        return [{"index": i, "score": s} for i, s in ranked]

    def embed(self, inputs: list[str]) -> list[list[float]]:
        with self.lock:
            try:
                vectors = self.model.encode(inputs, batch_size=32, normalize_embeddings=True, show_progress_bar=False)
            finally:
                self._release()
        return [[float(x) for x in v] for v in vectors]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "hindsight-model-server"
    model: Model

    def send_json(self, status: int, body: Any) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        m = self.model
        if self.path in ("/health", "/info"):
            self.send_json(200, {"status": "ok", "model_id": m.name, "task": m.task, "device": m.device,
                                 "model_type": {"reranker": {}} if m.task == "rerank" else {"embedding": {}},
                                 "dimension": m.dimension})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY_BYTES:
            self.send_json(413, {"error": "body too large"})
            self.close_connection = True
            return
        try:
            body = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self.send_json(400, {"error": "invalid JSON"})
            return
        started = time.monotonic()
        try:
            if self.path == "/rerank" and self.model.task == "rerank":
                query, texts = body.get("query"), body.get("texts")
                if not isinstance(query, str) or not isinstance(texts, list) or not all(isinstance(t, str) for t in texts):
                    self.send_json(422, {"error": "expected {query: str, texts: [str]}"})
                    return
                result, count = self.model.rerank(query, texts), len(texts)
            elif self.path == "/embed" and self.model.task == "embed":
                inputs = body.get("inputs")
                inputs = [inputs] if isinstance(inputs, str) else inputs
                if not isinstance(inputs, list) or not all(isinstance(t, str) for t in inputs):
                    self.send_json(422, {"error": "expected {inputs: str | [str]}"})
                    return
                result, count = self.model.embed(inputs), len(inputs)
            else:
                self.send_json(404, {"error": "not found"})
                return
        except Exception:
            log.exception("échec du calcul")
            self.send_json(500, {"error": "inference failed; see the server log"})
            return
        log.info("%s : %d textes, %.0f ms", self.path[1:], count, (time.monotonic() - started) * 1000)
        self.send_json(200, result)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        pass


def from_selection(role: str, selection: Path) -> dict[str, Any]:
    """Réglages du modèle choisi pour `role` dans le gestionnaire (selection.json + catalogue)."""
    data = json.loads(selection.read_text())
    option = data.get("options", {}).get(role)
    if not option or option.get("engine") != "mps":
        raise SystemExit(f"{selection} : aucun modèle MPS choisi pour {role}")
    return option


def main() -> int:
    parser = argparse.ArgumentParser(description="Serveur local compatible TEI (reranker ou embeddings, MPS)")
    parser.add_argument("--role", choices=["reranker", "embeddings"], help="Lit le modèle choisi dans --selection")
    parser.add_argument("--selection", type=Path, default=Path.home() / ".hindsight/models/selection.json")
    parser.add_argument("--task", choices=["rerank", "embed"])
    parser.add_argument("--model")
    parser.add_argument("--device", default="mps", choices=["mps", "cpu"])
    parser.add_argument("--fp16", action="store_true")
    parser.add_argument("--trust-remote-code", action="store_true")
    parser.add_argument("--max-length", type=int, default=512)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if args.host not in ("127.0.0.1", "::1", "localhost"):
        parser.error("this server only listens on the loopback interface")
    if args.role:
        o = from_selection(args.role, args.selection)
        task, name, fp16 = ("rerank" if args.role == "reranker" else "embed"), o["model"], bool(o.get("fp16"))
        trust, max_length = bool(o.get("trust_remote_code")), int(o.get("max_length", 512))
    else:
        if not (args.task and args.model):
            parser.error("--role, or --task and --model")
        task, name, fp16, trust, max_length = args.task, args.model, args.fp16, args.trust_remote_code, args.max_length
    Handler.model = Model(task, name, args.device, fp16, max_length, trust)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    log.info("listening on http://%s:%d (%s)", args.host, args.port, task)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""#
}
