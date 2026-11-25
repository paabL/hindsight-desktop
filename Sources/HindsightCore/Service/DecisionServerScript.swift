// Généré par scripts/generate_decision_script.py depuis scripts/hindsight-decision-serve.py : ne pas modifier.
// L'app l'écrit dans ~/.hindsight/decision/serve.py à l'installation du modèle de décision local.
enum DecisionServerScript {
    static let source = #"""
#!/usr/bin/env python3
"""Serveur local de hs-decide-1-flash pour Hindsight (API System One), sans vLLM.

Le modèle est publié avec un greffon vLLM (dossier `serving/` du dépôt Hugging Face), que vLLM ne
fait pas tourner sur un Mac. Ce serveur reprend le rendu officiel du greffon (paquet
`hindsight_decision`, installé depuis ce dossier) et remplace seulement le pooling de vLLM : vLLM lit
l'état caché au jeton « : » de chaque question et le multiplie par les lignes de la tête de langue
des codes de réponse (`classifier_from_token`, sans post-traitement). Le même calcul est fait ici avec
PyTorch, sur le GPU du Mac (MPS) ou à défaut sur le CPU, ou avec MLX (`--engine mlx`, paquet `mlx-lm`) :
même rendu, mêmes questions, passe avant environ 1,6 fois plus rapide sur une puce Apple. `--engine auto`
(défaut) suit le choix « decision » du gestionnaire de modèles (~/.hindsight/models/selection.json) et
reste sur PyTorch sans ce fichier, ou si MLX ne se charge pas (`/health` dit alors le moteur réel).

Écoute 127.0.0.1 seulement. `POST /v1/systemone` exige `Authorization: Bearer <clé>`, la clé étant lue
dans `--key-file` ; `GET /health` ne renvoie aucun contenu de la mémoire. Rien du contenu des requêtes
n'est journalisé : une ligne par requête, avec le nombre de questions, de jetons et la durée.

Les requêtes passent une à une sur le modèle. Une recherche (recall, son dédoublonnage) passe avant les
lots de consolidation qui attendent : pendant une consolidation, elle n'attend plus que le lot en cours.

Les poids ne sont chargés qu'à la première requête, qui attend ce chargement (quelques secondes) au lieu
d'échouer : le démarrage ne prend que le tokenizer. Après `--idle-unload` secondes sans requête (20 min par
défaut), ils quittent la mémoire, celle du GPU comprise, et la requête suivante les recharge.

Usage : python hindsight-decision-serve.py --model <dossier du modèle> --key-file <fichier> [--port 8766]
        python hindsight-decision-serve.py --model <dossier du modèle> --check
"""

from __future__ import annotations

import argparse
import gc
import hmac
import json
import logging
import signal
import sys
import threading
import time
from collections.abc import Iterator
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import torch
from pydantic import ValidationError
from transformers import AutoModelForCausalLM, AutoTokenizer

from hindsight_decision import schema
from hindsight_decision.prompt import load_settings
from hindsight_decision.typed import classifier_ids, question_logits, slot_token
from hindsight_decision.typed_render import render_request

MODEL_NAME = "hs-decide-1-flash"
SELECTION = Path.home() / ".hindsight" / "models" / "selection.json"
ENGINES = ("torch", "mlx")
MAX_BODY_BYTES = 64 * 1024 * 1024
log = logging.getLogger("hindsight-decision")

# Exemple du README du modèle (réponses publiées : D00 ≈ 0,95, noul ≈ 0,97, D01 surtout au niveau 1).
CHECK_REQUEST = {
    "model": MODEL_NAME,
    "state": {
        "query": "When is the team offsite?",
        "documents": {
            "D00": "The offsite moved from April 10 to April 17.",
            "D01": "The team offsite is on April 10 in Denver.",
        },
    },
    "questions": {
        "latest": {
            "type": "choice",
            "instructions": "Which document gives the current offsite date?",
            "criteria": {"D00": None, "D01": None},
        },
        "moved": {"type": "noul", "instructions": "Did the offsite date change?"},
        "D01": {
            "type": "score",
            "instructions": "How well does document `documents.D01` answer `query`?",
            "criteria": ["about something else", "same topic, no help", "helps", "answers"],
        },
    },
}


def pick_device(requested: str) -> str:
    if requested != "auto":
        return requested
    return "mps" if torch.backends.mps.is_available() else "cpu"


def pick_engine(requested: str, selection: Path = SELECTION) -> str:
    """`auto` : le moteur choisi pour « decision » dans le gestionnaire de modèles, sinon PyTorch."""
    if requested != "auto":
        return requested
    try:
        choice = json.loads(selection.read_text()).get("decision", "")
    except (OSError, ValueError, AttributeError):
        return "torch"
    engine = choice.rpartition("/")[2] if isinstance(choice, str) else ""
    if engine not in ENGINES:
        return "torch"
    if engine == "mlx":
        try:
            import mlx_lm  # noqa: F401
        except ImportError:
            log.error("MLX choisi dans %s mais mlx-lm est absent : PyTorch à la place", selection)
            return "torch"
    return engine


def is_background(request: schema.SystemOneRequest) -> bool:
    """Lot de consolidation : le tri d'un fait nouveau parmi les observations existantes.

    Le serveur Hindsight ne dit pas qui l'appelle, mais la forme de l'état suffit : la consolidation envoie
    un état structuré avec `new_fact`, une recherche envoie le texte de sa question.
    """
    return isinstance(request.state, dict) and "new_fact" in request.state


class PriorityGate:
    """Verrou du modèle à deux files : une requête prioritaire passe avant les requêtes de fond en attente.

    Les recherches sont rares et courtes ; la consolidation reprend juste après. Le fil qui libère les
    poids passe en fond, lui aussi.
    """

    def __init__(self) -> None:
        self._condition = threading.Condition()
        self._busy = False
        self._urgent = 0

    @contextmanager
    def hold(self, urgent: bool) -> Iterator[None]:
        with self._condition:
            if urgent:
                self._urgent += 1
            try:
                while self._busy or (not urgent and self._urgent):
                    self._condition.wait()
            finally:
                if urgent:
                    self._urgent -= 1
            self._busy = True
        try:
            yield
        finally:
            with self._condition:
                self._busy = False
                self._condition.notify_all()


class Decider:
    """Le modèle et ses requêtes, qui passent l'une après l'autre (verrou à priorité).

    Les poids se chargent à la première requête. Avec `idle_unload` > 0, un fil de fond les libère après
    autant de secondes sans requête, et la requête suivante les recharge. Le tokenizer reste chargé.
    """

    def __init__(self, folder: Path, device: str, max_tokens: int, idle_unload: float = 0,
                 engine: str = "torch") -> None:
        self.folder = folder
        self.engine = engine
        self.tokenizer = AutoTokenizer.from_pretrained(folder, local_files_only=True)
        self.settings = load_settings(folder)
        self.device = device
        self.ids = classifier_ids(self.tokenizer)
        self.slot_id = slot_token(self.tokenizer)
        self.max_tokens = min(max_tokens, self.settings.max_request_tokens)
        self.idle_unload = idle_unload
        self.lock = PriorityGate()
        self.decoder: Any = None
        self.head: Any = None
        self.last_used = time.monotonic()
        if idle_unload > 0:
            threading.Thread(target=self._unload_when_idle, name="idle-unload", daemon=True).start()

    @property
    def loaded(self) -> bool:
        return self.decoder is not None

    def _load(self) -> None:
        """Charge les poids sur l'appareil (verrou tenu)."""
        started = time.monotonic()
        if self.engine == "mlx":
            import mlx.core as mx
            from mlx_lm import load

            model, _ = load(str(self.folder), model_config={"model_type": "qwen3_5"})
            model.set_dtype(mx.float16)
            self.decoder = model.language_model.model
            # Tête liée aux plongements d'entrée (tie_word_embeddings) : mêmes lignes que sous PyTorch.
            self.head = self.decoder.embed_tokens.weight[mx.array(self.ids)].astype(mx.float32)
            log.info("model loaded with MLX (float16) in %.1f s", time.monotonic() - started)
            return
        dtype = torch.bfloat16 if self.device != "cpu" else torch.float32
        model = AutoModelForCausalLM.from_pretrained(self.folder, dtype=dtype, local_files_only=True)
        model.to(self.device).eval()
        self.decoder = model.get_decoder()
        # Lignes de la tête de langue des codes de réponse : le classifieur que vLLM en tire.
        self.head = model.get_output_embeddings().weight[self.ids].detach().clone()
        log.info("model loaded on %s in %.1f s", self.device, time.monotonic() - started)

    def _unload(self) -> None:
        """Rend la mémoire des poids, GPU compris (verrou tenu)."""
        self.decoder = self.head = None
        gc.collect()
        if self.engine == "mlx":
            import mlx.core as mx

            mx.clear_cache()
        elif self.device == "mps":
            torch.mps.empty_cache()

    def _unload_when_idle(self) -> None:
        while True:
            with self.lock.hold(urgent=False):
                remaining = self.last_used + self.idle_unload - time.monotonic()
                if self.loaded and remaining <= 0:
                    self._unload()
                    log.info("model unloaded after %.0f s without requests", self.idle_unload)
            time.sleep(remaining if remaining > 0 else self.idle_unload)

    def _torch_logits(self, ids: list[int], slots: list[int]) -> list[list[float]]:
        """États cachés aux jetons « : » des questions, multipliés par les lignes de la tête (verrou tenu)."""
        with torch.inference_mode():
            hidden = self.decoder(input_ids=torch.tensor([ids], device=self.device), use_cache=False).last_hidden_state[0]
            logits = (hidden[slots] @ self.head.T).float().cpu().tolist()
        if self.device == "mps" and len(ids) > 4096:
            torch.mps.empty_cache()
        return logits

    def _mlx_logits(self, ids: list[int], slots: list[int]) -> list[list[float]]:
        """Le même calcul avec MLX (float16, produit par la tête en float32)."""
        import mlx.core as mx

        hidden = self.decoder(mx.array([ids]))[0]
        logits = hidden[mx.array(slots)].astype(mx.float32) @ self.head.T
        mx.eval(logits)
        if len(ids) > 4096:
            mx.clear_cache()
        return logits.tolist()

    def respond(self, request: schema.SystemOneRequest) -> dict[str, Any]:
        rendered = render_request(self.tokenizer, request, self.settings)
        if rendered.tokens() > self.max_tokens:
            raise schema.ContextOverflow(
                f"{rendered.tokens()} tokens is over this server's limit of {self.max_tokens} tokens"
            )
        slots = [question.slot for question in rendered.questions]
        if any(rendered.ids[slot] != self.slot_id for slot in slots):
            raise RuntimeError("a question slot is not a ':' token")
        with self.lock.hold(urgent=not is_background(request)):
            try:
                if not self.loaded:
                    self._load()
                compute = self._mlx_logits if self.engine == "mlx" else self._torch_logits
                logits = compute(rendered.ids, slots)
            finally:
                self.last_used = time.monotonic()
        answers = {}
        for question, row in zip(
            rendered.questions, question_logits(logits, rendered, self.ids), strict=True
        ):
            answers[question.id] = schema.answer(request.questions[question.id], schema.softmax(row))
        return {
            "model": request.model,
            "answers": answers,
            "usage": {"input_tokens": rendered.tokens(), "output_tokens": 0},
        }


def error_detail(message: str) -> dict[str, Any]:
    return {"detail": [{"loc": ["body"], "msg": message, "type": "value_error"}]}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "hindsight-decision-local"
    decider: Decider
    key: str

    def send_json(self, status: int, body: dict[str, Any]) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorized(self) -> bool:
        given = self.headers.get("Authorization", "")
        return hmac.compare_digest(given.encode(), f"Bearer {self.key}".encode())

    def do_GET(self) -> None:  # noqa: N802 (nom imposé par http.server)
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "model": MODEL_NAME, "engine": self.decider.engine,
                                 "device": "mlx" if self.decider.engine == "mlx" else self.decider.device,
                                 "max_tokens": self.decider.max_tokens, "loaded": self.decider.loaded})
        elif self.path == "/v1/models":
            if not self.authorized():
                self.send_json(401, {"error": "invalid API key"})
            else:
                self.send_json(200, {"object": "list", "data": [{"id": MODEL_NAME, "object": "model"}]})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/systemone":
            self.send_json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY_BYTES:
            self.send_json(413, {"error": "the body is too large"})
            self.close_connection = True
            return
        raw = self.rfile.read(length)
        if not self.authorized():
            self.send_json(401, {"error": "invalid API key"})
            return
        started = time.monotonic()
        try:
            body = json.loads(raw)
            if not isinstance(body, dict):
                self.send_json(400, {"error": "the body must be a JSON object"})
                return
            request = schema.SystemOneRequest.model_validate(body)
            response = self.decider.respond(request)
        except json.JSONDecodeError:
            self.send_json(400, {"error": "the body is not valid JSON"})
            return
        except ValidationError as error:
            self.send_json(422, {"detail": error.errors(include_url=False)})
            return
        except schema.ContextOverflow as error:
            log.info("refused: %s", error)
            self.send_json(400, schema.overflow_body(str(error)))
            return
        except schema.Unanswerable as error:
            self.send_json(422, error_detail(str(error)))
            return
        except Exception:
            log.exception("decision failed")
            self.send_json(500, {"error": "the decision failed; see the server log"})
            return
        log.info("%d questions, %d tokens, %.0f ms%s", len(request.questions),
                 response["usage"]["input_tokens"], (time.monotonic() - started) * 1000,
                 " (consolidation)" if is_background(request) else "")
        self.send_json(200, response)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 (signature de http.server)
        pass  # une ligne par décision suffit ; pas de chemin ni d'en-tête dans le journal


def check(decider: Decider) -> int:
    started = time.monotonic()
    answers = decider.respond(schema.SystemOneRequest.model_validate(CHECK_REQUEST))["answers"]
    print(json.dumps(answers, indent=2, ensure_ascii=False))
    ok = answers["latest"]["choice"] == "D00" and answers["moved"]["noul"] > 0.5
    where = "mlx" if decider.engine == "mlx" else decider.device
    print(f"{'OK' if ok else 'ÉCHEC'} en {(time.monotonic() - started) * 1000:.0f} ms ({where})")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="hs-decide-1-flash local server (System One API)")
    parser.add_argument("--model", type=Path, required=True, help="Dossier du modèle téléchargé")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--key-file", type=Path, help="Fichier contenant la clé attendue")
    parser.add_argument("--max-tokens", type=int, default=8192,
                        help="Au-delà, refus max_tokens_exceeded : Hindsight découpe alors la requête")
    parser.add_argument("--device", default="auto", choices=["auto", "mps", "cpu"])
    parser.add_argument("--engine", default="auto", choices=["auto", *ENGINES],
                        help="Moteur de calcul ; auto : choix du gestionnaire de modèles, sinon torch")
    parser.add_argument("--idle-unload", type=float, default=1200,
                        help="Secondes sans requête avant de libérer les poids (0 : jamais) ; "
                             "la requête suivante les recharge")
    parser.add_argument("--check", action="store_true", help="Répond à l'exemple du modèle puis quitte")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    engine = pick_engine(args.engine)
    decider = Decider(args.model.expanduser(), pick_device(args.device), args.max_tokens,
                      0 if args.check else args.idle_unload, engine)
    if args.check:
        return check(decider)
    if args.host not in ("127.0.0.1", "::1", "localhost"):
        parser.error("this server only listens on the loopback interface")
    if not args.key_file:
        parser.error("--key-file is required to serve")
    key = args.key_file.expanduser().read_text().strip()
    if len(key) < 16:
        parser.error("the key file must hold a key of at least 16 characters")

    Handler.decider, Handler.key = decider, key
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    log.info("listening on http://%s:%d (engine %s)", args.host, args.port, decider.engine)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
"""#
}
