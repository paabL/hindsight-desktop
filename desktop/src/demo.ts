import type { Row, Section, Snapshot } from './types';

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
    'La navigation principale doit donner accès au dossier mémoire, aux synthèses et à la recherche en un clic.',
    'Les sources sont collectées dans une archive commune avant tout traitement par Hindsight.',
    'Une décision doit être reliée à sa source pour rester vérifiable et compréhensible dans le temps.',
    'Les expériences de recherche sont définies avant le lancement, puis vérifiées avec un test court.',
  ][i % 4],
  type: i % 3 ? 'world' : 'observation',
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
      edges: facts
        .slice(1)
        .map((f, i) => ({
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
  coverage: {
    roots: [{ path: '/Exemple/horizon-app', allFiles: false, autoSync: false }],
    items: [],
  },
  search: { hits: [], total: 0, serverIs120: true },
  timeline: { facts, total: facts.length },
  graph: graphData(),
  operations: { items: operations, total: operations.length },
  dashboard: {
    snapshot: {
      stats: {
        total_nodes: 2648,
        total_documents: documents.length,
        total_observations: 186,
        total_links: 4820,
        pending_operations: 2,
        failed_operations: 1,
        nodes_by_fact_type: { world: 1546, experience: 916, observation: 186 },
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
    codexQuota: {
      primary: { usedPercent: 36, windowMinutes: 300, resetsAt: '2026-10-29T23:30:00Z' },
      secondary: { usedPercent: 58, windowMinutes: 10080, resetsAt: '2026-11-03T12:00:00Z' },
      observedAt: timestamp,
    },
    claudeQuota: {
      primary: { usedPercent: 18, windowMinutes: 300 },
      secondary: { usedPercent: 42, windowMinutes: 10080 },
      observedAt: timestamp,
    },
    events,
    queues: [{ bank: 'horizon', pending: 1, processing: 1 }],
    budgets: {
      dailyDollars: 5,
      codexQuotaPercent: 90,
      warnAt: 0.8,
      subscriptions: {},
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
    roles: ['Retain', 'Consolidation', 'Reflect', 'Embeddings'].map((title, i) => ({
      id: String(i),
      title,
      effective: i === 3 ? 'local · embedding' : 'openai-codex · gpt-6.1',
      fields: [
        { name: `EXAMPLE_MODEL_${i}`, label: 'Modèle', value: i === 3 ? 'embedding' : 'gpt-6.1' },
      ],
      models: [],
    })),
    warnings: [],
    backups: [],
    accounts: [
      {
        id: 'hindsight',
        title: 'Hindsight Cloud',
        status: 'Connecté à Exemple',
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
  hermes: {
    items: [
      { id: 'hermes-example', title: 'Session de recherche', sortDate: timestamp, taskCount: 4 },
    ],
    preview: null,
  },
};

let selectedBank = 'horizon';
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
    data: structuredClone(section === 'graph' ? graphData() : data[section] || {}),
    messages: [],
    confirmations: [],
  };
}
export async function exampleRequest(command: string, args: Row, section: Section): Promise<any> {
  await new Promise((resolve) => setTimeout(resolve, 130));
  if (command === 'section' && args.section === 'graph' && args.mode) graphMode = args.mode;
  if (command === 'bank.select') selectedBank = args.id;
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
    snapshot.messages = ['Exemple : aucune donnée réelle n’a été modifiée.'];
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
      'Cette action est disponible avec vos données dans l’application desktop. Aucune donnée réelle n’est modifiée en mode exemple.',
    ];
  }
  return snapshot;
}
