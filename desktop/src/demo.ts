import type { Row, Section, Snapshot } from './types';
import { translate as t } from './i18n-core.ts';
import { changeModelWorkflowDemo, modelWorkflowDemo } from './model-workflow-demo';

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
    document_id: titles[i],
    created_at: timestamp,
    updated_at: timestamp,
    error_message:
      status === 'failed' ? 'Le fournisseur a temporairement limité les requêtes.' : null,
    progress: {
      stage: 'Extraction des faits',
      processed: status === 'completed' ? 24 : 8,
      total: 24,
    },
  }),
);
// Volume de la banque fictive : seuls quelques faits sont chargés, mais les totaux restent ceux de la banque.
const bankFacts: Record<string, number> = { world: 1546, experience: 916, observation: 186 };
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
  timeline: { facts, total: facts.length },
  graph: graphData(),
  coverage: {
    roots: [{ path: '/Exemple/horizon-app', allFiles: false, autoSync: false }],
    items: [],
  },
  operations: { items: operations, total: operations.length },
  dashboard: {
    snapshot: {
      stats: {
        total_nodes: bankFacts.world + bankFacts.experience + bankFacts.observation,
        total_documents: documents.length,
        total_observations: bankFacts.observation,
        total_links: 4820,
        // Mêmes comptes que la file de l’exemple (Activité › Traitements).
        pending_operations: operations.filter((operation) => operation.status === 'pending').length,
        failed_operations: operations.filter((operation) => operation.status === 'failed').length,
        nodes_by_fact_type: bankFacts,
      },
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
      consolidationUseDecisionModel: true,
      reflectUseDecisionModel: true,
      mentalModelRefreshUseDecisionModel: true,
      mentalModelDeltaUseDecisionModel: true,
      recallDecisionModelPrune: false,
      recallDecisionModelDedup: false,
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
let factQuery = '';
let factType = 'all';
let operationStatus = 'all';
function factsData() {
  const matching = facts.filter(
    (fact) =>
      (factType === 'all' || fact.type === factType) &&
      fact.text.toLocaleLowerCase().includes(factQuery.toLocaleLowerCase()),
  );
  // Comme le serveur : le total compte toute la banque (ou le type demandé), pas seulement les faits chargés.
  const total = factQuery
    ? matching.length
    : factType === 'all'
      ? bankFacts.world + bankFacts.experience + bankFacts.observation
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
  return { items: matching, total: matching.length, statusFilter: operationStatus, counts };
}
export function exampleSnapshot(section: Section): Snapshot {
  return {
    app: {
      connected: true,
      serverURL: 'http://127.0.0.1:8888',
      bank: selectedBank,
      banks: [
        { bank_id: 'horizon', name: 'Projet Horizon', fact_count: 2648 },
        { bank_id: 'atelier', name: 'Atelier', fact_count: 382 },
      ],
      folder: '/Exemple/horizon-memory',
      paused: [],
    },
    section,
    data: structuredClone(
      section === 'graph'
        ? graphData()
        : section === 'operations'
          ? operationsData()
          : section === 'facts'
            ? factsData()
            : section === 'model-settings'
              ? data.server || {}
              : data[section] || {},
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
  if (command === 'section' && args.section === 'facts') {
    factQuery = typeof args.query === 'string' ? args.query : '';
    factType = ['world', 'experience', 'observation'].includes(args.type) ? args.type : 'all';
  }
  if (command === 'bank.select') {
    selectedBank = args.id;
    factQuery = '';
    factType = 'all';
    operationStatus = 'all';
  }
  const snapshot = exampleSnapshot((command === 'section' ? args.section : section) as Section);
  if (command === 'model.open') return { model: models.find((m) => m.id === args.id) || models[0] };
  if (command === 'folder.read') return { text: sourceText, path: args.path };
  if (command === 'document.open')
    return {
      text: sourceText,
      document: documents.find((d) => d.id === args.id),
      facts: facts.slice(0, 3),
      history: [],
    };
  if (command === 'operation.open') return operations.find((o) => o.id === args.id);
  // Le lecteur sonde son état après une suppression : en exemple, rien n’est supprimé.
  if (command === 'document.status') return { open: true, confirming: false };
  if (command === 'search' || command === 'search.more') {
    snapshot.data.hits = facts;
    snapshot.data.total = facts.length;
    if (args.mode === 'reflect')
      snapshot.data.answer = {
        text: 'Le projet privilégie une **architecture simple**, une navigation claire et une provenance consultable pour chaque connaissance. Les sources sont rassemblées avant leur traitement, ce qui permet de garder une archive lisible et durable.\n\nLes prochaines étapes consistent à vérifier le parcours de bout en bout et à évaluer la qualité des résultats sur des cas représentatifs.',
      };
  } else if (command === 'graph.select') {
    snapshot.data.selectedNodeID = args.id;
    snapshot.data.nodeFacts =
      graphMode === 'facts' ? facts.filter((f) => f.id === args.id) : facts.slice(0, 3);
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
