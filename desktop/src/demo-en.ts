import type { Row } from './types';
import { getLanguage } from './i18n-core.ts';

// Contenu fictif du mode exemple en anglais, pour qu’un exemple ouvert en anglais le soit en entier.
// Seul le contenu (titres, faits, connaissances, missions) passe ici ; les identifiants, les chemins
// et les étiquettes restent tels quels.
const english: Record<string, string> = {
  // Banques et projets.
  'Projet Horizon': 'Horizon Project',
  Atelier: 'Workshop',
  // Sources et documents.
  'Repenser la navigation de l’espace de travail': 'Rethinking workspace navigation',
  'Choisir une architecture simple et durable': 'Choosing a simple, lasting architecture',
  'Retours sur le prototype et prochaines étapes': 'Prototype feedback and next steps',
  'Bilan de la première campagne de mesure': 'Review of the first measurement campaign',
  'Clarifier le parcours de collecte des sources': 'Clarifying the source collection flow',
  'Ajouter la provenance aux résultats de recherche': 'Adding provenance to search results',
  'Comparaison des stratégies de mémorisation': 'Comparing memory strategies',
  'Décisions de conception — octobre': 'Design decisions — October',
  'Préparer une évaluation reproductible': 'Preparing a reproducible evaluation',
  'Rapport de performance du modèle de référence': 'Baseline model performance report',
  'Notes sur le confort thermique': 'Notes on thermal comfort',
  'Conserver le contexte entre deux sessions': 'Keeping context between sessions',
  '# Décisions de conception\n\nNous construisons un espace où le contexte reste accessible et les décisions faciles à retrouver.\n\n## Ce que nous avons retenu\n\n- Une navigation centrée sur les tâches du quotidien.\n- Les sources restent consultables avant leur traitement.\n- Chaque connaissance garde un lien vers son origine.\n\n## Prochaine étape\n\nTester le parcours complet : collecter une source, retrouver un fait, puis consulter sa provenance.\n\n> Ceci est un document fictif du mode exemple.':
    '# Design decisions\n\nWe are building a space where context stays accessible and decisions are easy to find again.\n\n## What we kept\n\n- Navigation built around everyday tasks.\n- Sources stay readable before they are processed.\n- Every piece of knowledge keeps a link to its origin.\n\n## Next step\n\nTest the full journey: collect a source, find a fact, then check where it came from.\n\n> This is a fictional document from the example mode.',
  // Connaissances.
  'Architecture et choix techniques': 'Architecture and technical choices',
  'Priorités du projet': 'Project priorities',
  'Méthode de recherche': 'Research method',
  'Préférences et habitudes': 'Preferences and habits',
  'Quelles décisions structurent l’architecture du projet ?':
    'Which decisions shape the project’s architecture?',
  'Quelles sont les prochaines étapes et les priorités ?':
    'What are the next steps and priorities?',
  'Quel protocole suivre pour les expériences ?': 'Which protocol should experiments follow?',
  'Comment organiser notre travail ?': 'How should we organize our work?',
  // Faits.
  'La navigation principale doit donner accès au dossier mémoire, aux connaissances et à la recherche en un clic.':
    'The main navigation must reach the memory folder, knowledge and search in one click.',
  'Les sources sont collectées dans une archive commune avant tout traitement par Hindsight.':
    'Sources are collected into a shared archive before any processing by Hindsight.',
  'Une décision doit être reliée à sa source pour rester vérifiable et compréhensible dans le temps.':
    'A decision must stay linked to its source to remain verifiable and understandable over time.',
  'Les expériences de recherche sont définies avant le lancement, puis vérifiées avec un test court.':
    'Research experiments are defined before launch, then checked with a short test.',
  // Entités du graphe.
  Mémoire: 'Memory',
  Recherche: 'Research',
  Évaluation: 'Evaluation',
  Confort: 'Comfort',
  Énergie: 'Energy',
  Conception: 'Design',
  Décisions: 'Decisions',
  Protocole: 'Protocol',
  Modèle: 'Model',
  Expérience: 'Experiment',
  Rapport: 'Report',
  Contexte: 'Context',
  Collecte: 'Collection',
  Synthèse: 'Synthesis',
  // Traitements.
  'Le fournisseur a temporairement limité les requêtes.':
    'The provider temporarily rate-limited requests.',
  'Extraction des faits': 'Fact extraction',
  'Consolidation des faits': 'Consolidation',
  // Directives et comportement de la mémoire.
  'Toujours citer les sources': 'Always cite sources',
  'Relier les conclusions aux documents qui les soutiennent.':
    'Link conclusions to the documents that support them.',
  'Conserver les décisions, leur contexte et les raisons de nos choix.':
    'Keep decisions, their context and the reasons behind our choices.',
  'Relier les idées qui se complètent.': 'Connect ideas that complement each other.',
  'Répondre clairement, en français, avec les sources.':
    'Answer clearly, in English, with sources.',
  // Réponse de la recherche.
  'Le projet privilégie une **architecture simple**, une navigation claire et une provenance consultable pour chaque connaissance. Les sources sont rassemblées avant leur traitement, ce qui permet de garder une archive lisible et durable.\n\nLes prochaines étapes consistent à vérifier le parcours de bout en bout et à évaluer la qualité des résultats sur des cas représentatifs.':
    'The project favors a **simple architecture**, clear navigation and visible provenance for every piece of knowledge. Sources are gathered before processing, which keeps the archive readable and lasting.\n\nThe next steps are to check the journey end to end and to evaluate result quality on representative cases.',
  // Serveur de l’exemple.
  'Exemple : le serveur est prêt.': 'Example: the server is ready.',
  'Exemple : 3 questions, 412 tokens, 180 ms': 'Example: 3 questions, 412 tokens, 180 ms',
};

// La langue des données fictives est fixée à l’ouverture de l’exemple : changer de langue ensuite
// traduit l’interface, pas les documents, exactement comme pour une vraie banque.
let contentLanguage: string | null = null;
export function startExampleContent() {
  contentLanguage = getLanguage();
}
const inEnglish = () => (contentLanguage ??= getLanguage()) === 'en';

/** Un texte fictif de l’exemple dans la langue choisie à son ouverture. */
export function exampleText(text: string): string {
  if (!inEnglish()) return text;
  if (Object.hasOwn(english, text)) return english[text];
  // « Les liens de mémoire dans cet exemple. » : détail d’un nœud du graphe.
  const links = /^Les liens de (.+) dans cet exemple\.$/.exec(text);
  if (links) {
    const label = Object.keys(english).find((key) => key.toLocaleLowerCase() === links[1]);
    return `Links for ${label ? english[label].toLocaleLowerCase() : links[1]} in this example.`;
  }
  // Libellés tronqués d’un fait (graphe des faits, lectures) : même début, même longueur.
  if (text.length >= 30)
    for (const [french, translated] of Object.entries(english))
      if (french.startsWith(text)) return translated.slice(0, text.length).trimEnd();
  return text;
}

/** Copie des données de l’exemple, textes fictifs traduits ; clés et autres valeurs inchangées. */
export function localizeExample<T>(value: T): T {
  if (!inEnglish()) return value;
  const visit = (item: unknown): unknown => {
    if (typeof item === 'string') return exampleText(item);
    if (Array.isArray(item)) return item.map(visit);
    if (item && typeof item === 'object')
      return Object.fromEntries(Object.entries(item as Row).map(([key, x]) => [key, visit(x)]));
    return item;
  };
  return visit(value) as T;
}
