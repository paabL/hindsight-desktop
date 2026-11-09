import type { Row, Section, Snapshot } from './types';
import { translate as t } from './i18n-core.ts';
import { changeModelWorkflowDemo, modelWorkflowDemo } from './model-workflow-demo';
import { exampleText, localizeExample } from './demo-en';

// Données entièrement fictives, accessibles uniquement par une activation explicite du mode exemple.
const timestamp = '2026-10-29T18:30:00Z';
const titles = [
  'Repenser la navigation de l’espace de travail',
  'Choisir une architecture simple et durable',
  'Retours sur le prototype et prochaines étapes',
  'Bilan de la première campagne de mesure',
  'Clarifier le parcours de collecte des sources',
  'Ajouter la provenance aux résultats de recherche',
  'Comparaison des stratégies de mémorisation',
  'Décisions de conception — octobre',
  'Préparer une évaluation reproductible',
  'Rapport de performance du modèle de référence',
  'Notes sur le confort thermique',
  'Conserver le contexte entre deux sessions',
];
export const demoRecords = titles.map((title, i) => ({
  id: `example-${i}`,
  title,
  kind: [
    'conversations',
    'conversations',
    'conversations',
    'wandb',
    'github',
    'github',
    'wandb',
    'github',
    'conversations',
    'benchmarks',
    'wandb',
    'conversations',
  ][i],
  project: i % 4 === 0 ? 'atelier' : 'horizon',
  project_name: i % 4 === 0 ? 'Atelier' : 'Projet Horizon',
  repository: i % 3 === 0 ? 'horizon-app' : 'horizon-research',
  collected_at: new Date(Date.parse(timestamp) - i * 3_600_000).toISOString(),
  source_updated_at: timestamp,
  change: i % 4 === 0 ? 'added' : 'unchanged',
  context: { provider: i % 2 ? 'claude-code' : 'codex', directory: 'horizon-app' },
  files: { 'document.md': `examples/${i}/document.md` },
  memory: {
    state: i === 11 ? 'excluded' : i % 4 === 0 ? 'new' : 'current',
    enabled: i !== 11,
    locked: false,
    stored: i % 4 !== 0,
    can_remove: i % 4 !== 0,
    document_id: `example-${i}`,
  },
}));
const sourceText =
  '# Décisions de conception\n\nNous construisons un espace où le contexte reste accessible et les décisions faciles à retrouver.\n\n## Ce que nous avons retenu\n\n- Une navigation centrée sur les tâches du quotidien.\n- Les sources restent consultables avant leur traitement.\n- Chaque connaissance garde un lien vers son origine.\n\n## Prochaine étape\n\nTester le parcours complet : collecter une source, retrouver un fait, puis consulter sa provenance.\n\n> Ceci est un document fictif du mode exemple.';
const models = [
  'Architecture et choix techniques',
  'Priorités du projet',
  'Méthode de recherche',
  'Préférences et habitudes',
].map((name, i) => ({
  id: `model-${i}`,
  name,
  source_query: [
    'Quelles décisions structurent l’architecture du projet ?',
    'Quelles sont les prochaines étapes et les priorités ?',
    'Quel protocole suivre pour les expériences ?',
    'Comment organiser notre travail ?',
  ][i],
  tags: [i % 2 ? 'projet:horizon' : 'technique'],
  content: sourceText,
  last_refreshed_at: timestamp,
  is_stale: i === 3,
  // L'exemple montre les deux sortes : pages tenues par le serveur et modèles mentaux suivis.
  is_knowledge_page: i < 2,
  created_at: timestamp,
}));
const documents = demoRecords.map((r, i) => ({
  id: r.id,
  title: r.title,
  document_metadata: { title: r.title, repo: r.repository },
  tags: [`projet:${r.project}`, r.kind],
  text_length: 2400 + i * 1300,
  memory_unit_count: 6 + i * 3,
  updated_at: r.collected_at,
  created_at: r.collected_at,
}));
const facts = demoRecords.map((r, i) => ({
  id: `fact-${i}`,
  text: [
    'La navigation principale doit donner accès au dossier mémoire, aux connaissances et à la recherche en un clic.',
    'Les sources sont collectées dans une archive commune avant tout traitement par Hindsight.',
    'Une décision doit être reliée à sa source pour rester vérifiable et compréhensible dans le temps.',
    'Les expériences de recherche sont définies avant le lancement, puis vérifiées avec un test court.',
  ][i % 4],
  // Les trois types de la vue d’ensemble (faits du monde, expériences, observations) sont représentés.
  type: ['observation', 'world', 'experience'][i % 3],
  documentID: r.id,
  document_id: r.id,
  mentionedAt: r.collected_at,
  occurredStart: r.collected_at,
  tags: [`projet:${r.project}`],
  entities: ['Horizon', 'Mémoire'],
  score: 0.96 - i * 0.03,
}));
const events = Array.from({ length: 72 }, (_, i) => ({
  id: `event-${i}`,
  date: new Date(Date.parse(timestamp) - i * 1_800_000).toISOString(),
  bank: 'horizon',
  operation: i % 3 ? 'retain' : 'consolidation',
  provider: i % 4 ? 'openai-codex' : 'gemini',
  model: i % 4 ? 'gpt-6.1' : 'gemini-flash',
  tokens: { input: 2700 + i * 100, output: 350 + i * 10, cached: 900, thoughts: 0 },
  failed: false,
}));
const nodes = [
  'Horizon',
  'Mémoire',
  'Interface',
  'Architecture',
  'Recherche',
  'Sources',
  'Conversations',
  'Provenance',
  'Évaluation',
  'Confort',
  'Énergie',
  'Conception',
  'Décisions',
  'Protocole',
  'Modèle',
  'Expérience',
  'Rapport',
  'Contexte',
  'Collecte',
  'Synthèse',
].map((label, i) => ({
  id: `node-${i}`,
  label,
  weight: i === 0 ? 32 : 4 + (i % 9),
  kind: i % 3 === 0 ? 'observation' : 'entity',
  detail: `Les liens de ${label.toLowerCase()} dans cet exemple.`,
}));
const graphGroups = [
  [0, 2, 3, 7, 11, 12],
  [1, 5, 6, 17, 18, 19],
  [4, 8, 13, 14, 15, 16],
  [9, 10],
];
const edges = graphGroups
  .flatMap((group) =>
    group.flatMap((a, i) =>
      group.slice(i + 1).map((b, j) => ({
        source: `node-${a}`,
        target: `node-${b}`,
        weight: 6 + ((i + j) % 8),
        kind: 'cooccurrence',
      })),
    ),
  )
  .concat([
    { source: 'node-3', target: 'node-5', weight: 2, kind: 'cooccurrence' },
    { source: 'node-7', target: 'node-8', weight: 1, kind: 'cooccurrence' },
    { source: 'node-1', target: 'node-14', weight: 2, kind: 'cooccurrence' },
    { source: 'node-14', target: 'node-10', weight: 1, kind: 'cooccurrence' },
  ]);
let graphMode = 'entities';
function graphData() {
  if (graphMode === 'facts')
    return {
      mode: 'facts',
      totalNodes: 86,
      totalEdges: 240,
      nodes: facts.map((f) => ({
        id: f.id,
        label: f.text.slice(0, 60),
        detail: f.text,
        kind: f.type,
        weight: 3,
        mentionedAt: f.mentionedAt,
      })),
      edges: facts.slice(1).map((f, i) => ({
        source: facts[Math.floor(i / 3)].id,
        target: f.id,
        kind: i % 3 === 0 ? 'temporal' : 'semantic',
        weight: 0.55 + (i % 4) * 0.1,
      })),
    };
  return {
    mode: 'entities',
    nodes: nodes.map((n) => ({ ...n, kind: 'entity' })),
    edges,
    totalNodes: 128,
    totalEdges: 480,
  };
}
const operations = ['completed', 'processing', 'pending', 'completed', 'failed', 'completed'].map(
  (status, i) => ({
    id: `op-${i}`,
    status,
    task_type: i % 2 ? 'consolidation' : 'retain',
    operation_type: i % 2 ? 'consolidation' : 'retain',
    // Une consolidation porte sur toute la banque, pas sur un document.
    document_id: i % 2 ? null : titles[i],
    created_at: timestamp,
    updated_at: timestamp,
    error_message:
      status === 'failed' ? 'Le fournisseur a temporairement limité les requêtes.' : null,
    progress: {
      // Étape cohérente avec le type : une consolidation ne passe pas par l’extraction.
      stage: i % 2 ? 'Consolidation des faits' : 'Extraction des faits',
      processed: status === 'completed' ? 24 : 8,
      total: 24,
    },
  }),
);
// Volume de la banque fictive : seuls quelques faits sont chargés, mais les totaux restent ceux de la banque.
// Répartition par banque : la somme vaut le `fact_count` de la barre latérale (2 648 et 382).
const factsByBank: Record<string, Record<string, number>> = {
  horizon: { world: 1546, experience: 916, observation: 186 },
  atelier: { world: 223, experience: 132, observation: 27 },
};
let bankFacts: Record<string, number> = factsByBank.horizon;
const totalFacts = () => bankFacts.world + bankFacts.experience + bankFacts.observation;
const pendingConsolidation = 18;
const countOperations = (status: string) =>
  operations.filter((operation) => operation.status === status).length;
// Consolidation de l’exemple : même état dans la Vue d’ensemble et dans la vue Consolidation.
function consolidationData(): Row {
  const consolidations = (status: string) =>
    operations.filter(
      (operation) => operation.operation_type === 'consolidation' && operation.status === status,
    ).length;
  const running = consolidations('processing');
  const queued = consolidations('pending');
  return {
    enabled: true,
    automatic: false,
    pendingFacts: pendingConsolidation,
    failedFacts: 0,
    lastConsolidatedAt: timestamp,
    running,
    queued,
    active: running + queued,
    phase: running ? 'running' : queued ? 'queued' : pendingConsolidation ? 'pending' : 'upToDate',
  };
}
const data: Partial<Record<Section, Row>> = {
  sources: {
    folder: '/Exemple/horizon-memory',
    canCollect: true,
    catalog: {
      version: 1,
      mode: 'collection_only',
      generated_at: timestamp,
      records: demoRecords,
      sources: ['conversations', 'github', 'wandb', 'benchmarks'].map((kind, i) => ({
        id: `source-${i}`,
        kind,
        status: 'ok',
        count: demoRecords.filter((r) => r.kind === kind).length,
        last_success_at: timestamp,
        project: 'horizon',
      })),
    },
  },
  models: { models },
  admin: {
    models,
    directives: [
      {
        id: 'd1',
        name: 'Toujours citer les sources',
        content: 'Relier les conclusions aux documents qui les soutiennent.',
        is_active: true,
        priority: 0,
      },
    ],
    config: {
      config: {
        retain_mission: 'Conserver les décisions, leur contexte et les raisons de nos choix.',
      },
      overrides: {},
    },
  },
  documents: { items: documents, total: documents.length },
  search: { hits: [], total: 0, serverIs120: true },
  facts: { facts, total: facts.length, truncated: false, query: '' },
  timeline: { facts, total: 2648 },
  graph: graphData(),
  operations: { items: operations, total: operations.length },
  dashboard: {
    snapshot: {
      stats: {
        total_nodes: totalFacts(),
        total_documents: documents.length,
        total_observations: bankFacts.observation,
        total_links: 4820,
        // Mêmes comptes que la file de l’exemple (Activité › Traitements).
        pending_operations: countOperations('pending'),
        failed_operations: countOperations('failed'),
        pending_consolidation: pendingConsolidation,
        last_consolidated_at: timestamp,
        nodes_by_fact_type: bankFacts,
      },
      operationCounts: {
        pending: countOperations('pending'),
        processing: countOperations('processing'),
        failed: countOperations('failed'),
      },
      consolidation: consolidationData(),
      recentDocuments: documents.slice(0, 5),
      topTags: [
        { tag: 'projet:horizon', count: 28 },
        { tag: 'architecture', count: 14 },
      ],
      timeseries: {},
    },
    insights: [],
  },
  consumption: {
    services: [
      { kind: 'decision', model: 'hs-decide-1-flash', calls: 42, tokens: 1000000, dollars: 0.02 },
      { kind: 'rerank', model: 'hs-rerank-1', calls: 18, tokens: 200000, dollars: 0.003 },
      { kind: 'embedding', model: 'hs-embed-1', calls: 12, tokens: 100000, dollars: 0.0005 },
    ],
    summary: {
      today: {
        dollars: 0.42,
        calls: 38,
        tokens: { input: 224000, output: 18000 },
        subscriptionTokens: 206000,
      },
      rate: { tokensPerMinute: 4200 },
      lastHour: { calls: 12 },
    },
    events,
    queues: [{ bank: 'horizon', pending: 1, processing: 1 }],
    budgets: {
      dailyDollars: 5,
      warnAt: 0.8,
      action: 'alert',
      actionConfirmed: false,
    },
    prices: { models: [] },
    lastPoll: timestamp,
  },
  memory: {
    serverIs120: true,
    // Ce dans quoi la recherche puise, avec ou sans « Préférer les observations ».
    searchPool: { facts: 2462, observations: 186, notYetConsolidated: 37 },
    draft: {
      retainMission: 'Conserver les décisions, leur contexte et les raisons de nos choix.',
      extractionMode: 'concise',
      chunkSize: 3000,
      enableObservations: true,
      enableAutoConsolidation: false,
      observationsMission: 'Relier les idées qui se complètent.',
      reflectMission: 'Répondre clairement, en français, avec les sources.',
      skepticism: 3,
      literalism: 3,
      empathy: 3,
      enableTextSearch: true,
      enableTemporalRetrieval: true,
      enableGraphRetrieval: true,
      enableReranking: true,
      recallDecisionModelPrune: false,
      recallDecisionModelDedup: false,
      recallPreferObservations: false,
      storeDocumentText: true,
      entitiesAllowFreeForm: true,
    },
  },
  audit: {
    reads: facts.slice(0, 6).map((f, i) => ({
      id: `read-${i}`,
      who: i % 2 ? 'Claude Code' : 'Codex',
      action: 'recall',
      query: f.text.slice(0, 65),
      date: timestamp,
      items: [f],
    })),
    traces: events.slice(0, 10).map((e) => ({
      ...e,
      started_at: e.date,
      status: 'success',
      input_tokens: e.tokens.input,
      output_tokens: e.tokens.output,
    })),
    audit: [],
  },
  server: {
    scriptPath: '~/.hindsight/start-api.sh',
    service: {
      installed: true,
      running: true,
      reachable: true,
      canStop: true,
      log: 'Exemple : le serveur est prêt.',
    },
    ...modelWorkflowDemo(),
    warnings: [],
    backups: [],
    accounts: [
      {
        id: 'claude-code',
        title: 'Claude Code',
        status: 'Session OAuth disponible',
        state: 'connected',
        connected: true,
        canDisconnect: false,
      },
      {
        id: 'openai-codex',
        title: 'ChatGPT / Codex',
        status: 'Non connecté',
        state: 'disconnected',
        connected: false,
        canDisconnect: false,
      },
      {
        id: 'hindsight',
        title: 'Hindsight Cloud',
        status: 'Connecté à Exemple',
        state: 'connected',
        connected: true,
        canDisconnect: true,
      },
    ],
    hindsightModels: {
      serverIs120: true,
      decision: 'local',
      reranker: 'local',
      cloudConnected: true,
      needsCloudAccount: false,
      local: {
        phase: 'running',
        summary: 'En marche sur ce Mac',
        installed: true,
        busy: false,
        log: 'Exemple : 3 questions, 412 tokens, 180 ms',
        root: '~/.hindsight/decision',
        logPath: '~/Library/Logs/Hindsight/hindsight-decision.log',
      },
    },
  },
};

let selectedBank = 'horizon';
// Sources de l’exemple : les dossiers de chaque banque fictive et le dossier ouvert.
let openFolder: string | null = null;
const exampleFolders: Record<string, Row[]> = {
  horizon: [
    {
      path: '/Exemple/horizon-memory',
      name: 'horizon-memory',
      kind: 'catalog',
      sources: demoRecords.length,
      collectedAt: timestamp,
      catalogBank: 'horizon',
      exists: true,
      allFiles: false,
      autoSync: false,
    },
    {
      path: '/Exemple/horizon-app',
      name: 'horizon-app',
      kind: 'folder',
      files: 4,
      toSend: 2,
      modified: 1,
      queued: 0,
      exists: true,
      allFiles: false,
      autoSync: false,
    },
  ],
  atelier: [
    {
      path: '/Exemple/atelier-notes',
      name: 'atelier-notes',
      kind: 'folder',
      files: 2,
      toSend: 1,
      modified: 0,
      queued: 0,
      exists: true,
      allFiles: false,
      autoSync: false,
    },
  ],
};
function exampleFile(path: string, state: string, facts: number): Row {
  const parts = path.split('/');
  const title = parts.pop() || path;
  return {
    id: `example:${path}`,
    title,
    location: parts.join('/'),
    state,
    canSend: ['notSent', 'modified', 'noFacts'].includes(state),
    facts,
    documents: state === 'notSent' ? [] : [{ id: `doc:${path}` }],
  };
}
const exampleFiles: Record<string, Row[]> = {
  '/Exemple/horizon-app': [
    exampleFile('horizon-app/README.md', 'current', 6),
    exampleFile('horizon-app/docs/architecture.md', 'modified', 11),
    exampleFile('horizon-app/docs/decisions.md', 'current', 9),
    exampleFile('horizon-app/docs/roadmap.md', 'notSent', 0),
  ],
  '/Exemple/atelier-notes': [
    exampleFile('atelier-notes/inventaire.md', 'current', 4),
    exampleFile('atelier-notes/projets.md', 'notSent', 0),
  ],
};
function sourcesData(): Row {
  const folders = exampleFolders[selectedBank] || [];
  const open = folders.find((folder) => folder.path === openFolder);
  const base = {
    folders,
    bank: selectedBank,
    listBank: selectedBank,
    open: open?.path || null,
    openKind: open?.kind || null,
    foldersLoading: false,
    warnings: [],
  };
  if (open?.kind === 'catalog')
    return { ...data.sources, ...base, folder: open.path, boundBank: selectedBank };
  if (open) return { ...base, items: exampleFiles[open.path] || [], compared: true };
  // Page Documents : sous les dossiers, les documents de la banque.
  return { ...base, documents: bankSectionData('documents') };
}
let factQuery = '';
let factType = 'all';
let operationStatus = 'all';
function factsData() {
  const matching = facts.filter(
    (fact) =>
      (factType === 'all' || fact.type === factType) &&
      exampleText(fact.text).toLocaleLowerCase().includes(factQuery.toLocaleLowerCase()),
  );
  // Comme le serveur : le total compte toute la banque (ou le type demandé), pas seulement les faits chargés.
  const total = factQuery
    ? matching.length
    : factType === 'all'
      ? totalFacts()
      : bankFacts[factType];
  return {
    facts: matching,
    total,
    truncated: false,
    query: factQuery,
    type: factType,
  };
}
function operationsData() {
  const matching =
    operationStatus === 'all'
      ? operations
      : operations.filter((operation) => operation.status === operationStatus);
  const counts: Row = {};
  for (const operation of operations)
    counts[operation.status] = (counts[operation.status] || 0) + 1;
  return {
    items: matching,
    total: matching.length,
    statusFilter: operationStatus,
    counts,
    consolidation: consolidationData(),
  };
}
// Vue d'ensemble et chronologie suivent la banque choisie, comme la barre latérale.
function bankSectionData(section: Section): Row {
  const base = structuredClone(data[section] || {});
  if (section === 'dashboard' && base.snapshot)
    base.snapshot.stats = {
      ...base.snapshot.stats,
      total_nodes: totalFacts(),
      total_observations: bankFacts.observation,
      nodes_by_fact_type: { ...bankFacts },
    };
  if (section === 'timeline') base.total = totalFacts();
  return base;
}
// Consolidation de l’exemple : état, rythme, portées et changements. Les différences de texte sont
// calculées ici, sur les textes dans la langue de l’exemple, comme le moteur le fait sur le serveur.
let consolidationPeriod = 'day';
function wordDiff(before: string, after: string): Row[] {
  const a = before.match(/\S+\s*/g) || [];
  const b = after.match(/\S+\s*/g) || [];
  const key = (word: string) => word.trim();
  const table = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--)
      table[i][j] =
        key(a[i]) === key(b[j])
          ? table[i + 1][j + 1] + 1
          : Math.max(table[i + 1][j], table[i][j + 1]);
  const out: Row[] = [];
  const push = (kind: string, text: string) => {
    const last = out.at(-1);
    if (last?.kind === kind) last.text += text;
    else out.push({ kind, text });
  };
  let i = 0,
    j = 0;
  while (i < a.length && j < b.length) {
    if (key(a[i]) === key(b[j])) (push('same', b[j++]), i++);
    else if (table[i + 1][j] >= table[i][j + 1]) push('removed', a[i++]);
    else push('added', b[j++]);
  }
  while (i < a.length) push('removed', a[i++]);
  while (j < b.length) push('added', b[j++]);
  return out;
}
function consolidationSectionData(): Row {
  const status = consolidationData();
  const raw = bankFacts.world + bankFacts.experience;
  const observations = bankFacts.observation || 0;
  const scale = consolidationPeriod === 'hour' ? 0.15 : consolidationPeriod === 'week' ? 6 : 1;
  const source = (i: number, type: string, text = facts[i % facts.length].text) => ({
    id: `fact-${i}`,
    text: exampleText(text),
    type,
  });
  const changed = (
    id: string,
    before: string,
    after: string,
    minutesAgo: number,
    removedValues: string[] = [],
    added = source(1, 'world'),
  ) => {
    const previousText = exampleText(before);
    const text = exampleText(after);
    return {
      id,
      kind: 'updated',
      text,
      previousText,
      textChanged: true,
      diff: wordDiff(previousText, text),
      removedValues,
      updates: 1,
      newSources: [added],
      newSourceCount: 1,
      proofCount: 3,
      sourceCount: 3,
      tags: ['projet:horizon'],
      updatedAt: new Date(Date.parse(timestamp) - minutesAgo * 60_000).toISOString(),
    };
  };
  const changes = [
    {
      id: 'obs-created',
      kind: 'created',
      text: exampleText(facts[0].text),
      updates: 0,
      textChanged: false,
      newSources: [],
      newSourceCount: 0,
      removedValues: [],
      proofCount: 2,
      sourceCount: 2,
      tags: ['projet:horizon'],
      updatedAt: new Date(Date.parse(timestamp) - 4 * 60_000).toISOString(),
    },
    changed(
      'obs-rewritten',
      'Les sources sont collectées dans une archive avant leur traitement.',
      'Les sources sont collectées dans une archive commune avant tout traitement par Hindsight.',
      9,
    ),
    changed(
      'obs-values',
      'Le prototype a été testé avec 12 participants le 2026-10-14 ; la recherche aboutit en moins de 30 secondes.',
      'Le prototype a été testé avec des participants ; la recherche aboutit rapidement.',
      17,
      ['12', '2026-10-14', '30'],
      // Le fait source arrivé est plus vague : la réécriture perd les valeurs précises, que le badge signale.
      source(
        7,
        'experience',
        'Lors du test du prototype, les participants ont trouvé rapidement ce qu’ils cherchaient.',
      ),
    ),
    {
      id: 'obs-confirmed',
      kind: 'updated',
      text: exampleText(facts[2].text),
      previousText: exampleText(facts[2].text),
      textChanged: false,
      updates: 1,
      newSources: [source(6, 'experience')],
      newSourceCount: 1,
      removedValues: [],
      proofCount: 4,
      sourceCount: 4,
      tags: ['projet:horizon'],
      updatedAt: new Date(Date.parse(timestamp) - 26 * 60_000).toISOString(),
    },
  ];
  const scopeParts: [string[], number][] = [
    [['projet:horizon'], 0.58],
    [[], 0.24],
    [['projet:horizon', 'équipe:design'], 0.11],
    [['projet:horizon', 'équipe:recherche'], 0.05],
  ];
  return {
    loaded: true,
    status,
    rawFacts: raw,
    consolidatedFacts: raw - status.pendingFacts - status.failedFacts,
    lastConsolidatedAt: timestamp,
    observationTotal: observations,
    pace: status.pendingFacts
      ? {
          factsPerHour: 42,
          measuredSeconds: 3600,
          remainingSeconds: (status.pendingFacts / 42) * 3600,
        }
      : null,
    scopes: {
      scopes: scopeParts.map(([tags, part]) => ({ tags, count: Math.round(observations * part) })),
      total: 6,
      limit: 6,
      offset: 0,
    },
    period: consolidationPeriod,
    counts: { created: Math.round(14 * scale), updated: Math.round(9 * scale) },
    changes: consolidationPeriod === 'hour' ? changes.slice(0, 2) : changes,
    canLoadMore: false,
    partialErrors: [],
  };
}
// Serveur de l’exemple : ses libellés passent par la traduction des messages du moteur ; seuls ses
// journaux fictifs sont traduits ici.
function serverData(): Row {
  const server = structuredClone(data.server || {});
  if (server.service) server.service.log = exampleText(server.service.log);
  if (server.hindsightModels?.local)
    server.hindsightModels.local.log = exampleText(server.hindsightModels.local.log);
  return server;
}
export function exampleSnapshot(section: Section): Snapshot {
  bankFacts = factsByBank[selectedBank] || factsByBank.horizon;
  return {
    app: {
      connected: true,
      serverURL: 'http://127.0.0.1:8888',
      bank: selectedBank,
      banks: [
        { bank_id: 'horizon', name: exampleText('Projet Horizon'), fact_count: 2648 },
        { bank_id: 'atelier', name: exampleText('Atelier'), fact_count: 382 },
      ],
      folder: (exampleFolders[selectedBank] || []).find(
        (folder) => folder.path === openFolder && folder.kind === 'catalog',
      )?.path,
      pause: { all: false, banks: [] },
    },
    section,
    data:
      section === 'server' || section === 'model-settings'
        ? serverData()
        : localizeExample(
            structuredClone(
              section === 'graph'
                ? graphData()
                : section === 'operations'
                  ? operationsData()
                  : section === 'facts'
                    ? factsData()
                    : section === 'consolidation'
                      ? consolidationSectionData()
                      : section === 'sources'
                        ? sourcesData()
                        : bankSectionData(section),
            ),
          ),
    messages: [],
    confirmations: [],
  };
}
export async function exampleRequest(command: string, args: Row, section: Section): Promise<any> {
  await new Promise((resolve) => setTimeout(resolve, 130));
  if (data.server && changeModelWorkflowDemo(data.server, command, args)) {
    const snapshot = exampleSnapshot(section);
    if (command === 'server.save')
      snapshot.confirmations = [
        {
          id: 'example-model-save',
          title: t('Enregistrer les modèles ?', 'Save models?'),
          message: t(
            'Démonstration : aucune donnée réelle ne sera modifiée.',
            'Example: no real data will be changed.',
          ),
          confirmTitle: t('Enregistrer', 'Save'),
          destructive: false,
        },
      ];
    return snapshot;
  }
  if (command === 'section' && args.section === 'operations' && typeof args.status === 'string')
    operationStatus = args.status;
  if (command === 'section' && args.section === 'graph' && args.mode) graphMode = args.mode;
  if (command === 'section' && args.section === 'consolidation' && typeof args.period === 'string')
    consolidationPeriod = ['hour', 'day', 'week'].includes(args.period) ? args.period : 'day';
  if (command === 'bank.select') consolidationPeriod = 'day';
  if (command === 'section' && args.section === 'facts') {
    factQuery = typeof args.query === 'string' ? args.query : '';
    factType = ['world', 'experience', 'observation'].includes(args.type) ? args.type : 'all';
  }
  if (command === 'folder.choose')
    openFolder = (exampleFolders[selectedBank] || []).some((folder) => folder.path === args.path)
      ? args.path
      : null;
  if (command === 'folder.close') openFolder = null;
  if (command === 'bank.select') {
    selectedBank = args.id;
    openFolder = null;
    factQuery = '';
    factType = 'all';
    operationStatus = 'all';
  }
  const snapshot = exampleSnapshot((command === 'section' ? args.section : section) as Section);
  if (command === 'model.open')
    return localizeExample({ model: models.find((m) => m.id === args.id) || models[0] });
  if (command === 'folder.read') return { text: exampleText(sourceText), path: args.path };
  if (command === 'document.open')
    return localizeExample({
      text: sourceText,
      document: documents.find((d) => d.id === args.id),
      facts: facts.slice(0, 3),
      // Le document compte plus de faits que les trois montrés : le lecteur dit « 3 sur N ».
      factsTotal: documents.find((d) => d.id === args.id)?.memory_unit_count ?? 3,
      history: [],
    });
  if (command === 'consolidation.sources')
    return localizeExample({
      sources: [facts[0], facts[3]].map((fact, i) => ({
        id: fact.id,
        text: fact.text,
        type: i ? 'experience' : 'world',
      })),
    });
  if (command === 'operation.open')
    return localizeExample(operations.find((o) => o.id === args.id));
  // Le lecteur sonde son état après une suppression : en exemple, rien n’est supprimé.
  if (command === 'document.status') return { open: true, confirming: false };
  if (command === 'search' || command === 'search.more') {
    snapshot.data.hits = localizeExample(facts);
    snapshot.data.total = facts.length;
    if (args.mode === 'reflect')
      snapshot.data.answer = {
        text: exampleText(
          'Le projet privilégie une **architecture simple**, une navigation claire et une provenance consultable pour chaque connaissance. Les sources sont rassemblées avant leur traitement, ce qui permet de garder une archive lisible et durable.\n\nLes prochaines étapes consistent à vérifier le parcours de bout en bout et à évaluer la qualité des résultats sur des cas représentatifs.',
        ),
      };
  } else if (command === 'graph.select') {
    snapshot.data.selectedNodeID = args.id;
    snapshot.data.nodeFacts = localizeExample(
      graphMode === 'facts' ? facts.filter((f) => f.id === args.id) : facts.slice(0, 3),
    );
  } else if (command === 'confirm') {
    snapshot.messages = [
      t('Exemple : aucune donnée réelle n’a été modifiée.', 'Example: no real data was changed.'),
    ];
  } else if (
    ![
      'bootstrap',
      'connect',
      'snapshot',
      'section',
      'cancel',
      'bank.select',
      'document.close',
      'folder.choose',
      'folder.close',
    ].includes(command)
  ) {
    snapshot.messages = [
      t(
        'Cette action est disponible avec vos données dans l’application desktop. Aucune donnée réelle n’est modifiée en mode exemple.',
        'This action is available with your own data in the desktop app. No real data is changed in example mode.',
      ),
    ];
  }
  return snapshot;
}
