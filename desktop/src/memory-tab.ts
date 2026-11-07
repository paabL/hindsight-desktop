// Onglet de « Comportement de la mémoire » à ouvrir à la prochaine visite, quand un autre écran
// renvoie vers un réglage précis (par exemple Traitements vers « Créer des observations »).
let requested: string | null = null;

export function requestMemoryTab(tab: string) {
  requested = tab;
}

export function takeMemoryTab(fallback: string): string {
  const tab = requested ?? fallback;
  requested = null;
  return tab;
}
