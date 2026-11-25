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
