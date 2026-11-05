import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

/** Client de protocole partagé avec les tests ; aucune commande système fournie par le renderer. */
export class BridgeClient {
  #child;
  #next = 0;
  #pending = new Map();
  #closed = false;

  constructor(executable, args = []) {
    this.#child = spawn(executable, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    const lines = createInterface({ input: this.#child.stdout });
    lines.on('line', (line) => {
      try {
        const reply = JSON.parse(line);
        const pending = this.#pending.get(reply.id);
        if (!pending) return;
        this.#pending.delete(reply.id);
        clearTimeout(pending.timer);
        if (reply.error) pending.reject(new Error(reply.error));
        else pending.resolve(reply.result);
      } catch {
        this.#fail(new Error('Réponse illisible du moteur Hindsight.'));
      }
    });
    // stderr est drainé, sans imprimer de contenu de documents ou de jetons dans la console.
    this.#child.stderr.on('data', (data) => {
      if (process.env.HINDSIGHT_TEST_DIAGNOSTICS === '1') process.stderr.write(data);
    });
    this.#child.stdin.on('error', (error) => this.#fail(error));
    this.#child.on('error', (error) => this.#fail(error));
    this.#child.on('exit', (code, signal) => {
      if (process.env.HINDSIGHT_TEST_DIAGNOSTICS === '1')
        process.stderr.write(`Bridge exit: ${code} ${signal}\n`);
      this.#fail(new Error('Le moteur Hindsight est arrêté. Rouvrez la fenêtre.'));
    });
  }

  request(command, args = {}) {
    if (this.#closed) return Promise.reject(new Error('Le moteur Hindsight est arrêté.'));
    if (
      typeof command !== 'string' ||
      !/^[a-zA-Z.]+$/.test(command) ||
      command.length > 80 ||
      !args ||
      typeof args !== 'object' ||
      Array.isArray(args)
    ) {
      return Promise.reject(new Error('Action invalide.'));
    }
    const id = ++this.#next;
    if (process.env.HINDSIGHT_TEST_DIAGNOSTICS === '1')
      process.stderr.write(`Request ${id}: ${command}\n`);
    const line = JSON.stringify({ id, command, args });
    if (Buffer.byteLength(line) > 16_000_000)
      return Promise.reject(new Error('Ce fichier dépasse la limite de 16 Mo.'));
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => {
          // Une action coûteuse n'est jamais relancée automatiquement après une interruption.
          this.#pending.delete(id);
          reject(
            new Error('Le moteur ne répond plus. Vérifiez les opérations avant de réessayer.'),
          );
        },
        125 * 60 * 1000,
      );
      timer.unref();
      this.#pending.set(id, { resolve, reject, timer });
      this.#child.stdin.write(line + '\n');
    });
  }

  #fail(error) {
    this.#closed = true;
    for (const { reject, timer } of this.#pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    this.#pending.clear();
  }

  close() {
    this.#fail(new Error('Fenêtre fermée.'));
    this.#child.kill();
  }

  get pid() {
    return this.#child.pid;
  }
}
