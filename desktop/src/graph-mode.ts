// Mode du graphe demandé par une autre vue (la carte « Liens » de la Vue d'ensemble ouvre les faits).
let requested: string | null = null;

export function requestGraphMode(mode: 'facts' | 'entities') {
  requested = mode;
}

/** Le mode demandé, une seule fois ; null si aucune vue n'a rien demandé (le pont garde le dernier mode). */
export function takeGraphMode(): string | null {
  const mode = requested;
  requested = null;
  return mode;
}
