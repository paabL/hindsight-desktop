import type { Row } from './types';

const P = 'HINDSIGHT_API_';
const definitions = [
  ['default', 'LLM par défaut', 'LLM_', 'openai-codex', 'gpt-6-luna'],
  ['retain', 'Extraction', 'RETAIN_LLM_', 'openai-codex', 'gpt-6-luna'],
  ['consolidation', 'Consolidation', 'CONSOLIDATION_LLM_', 'openai-codex', 'gpt-6-luna'],
  ['reflect', 'Réflexion', 'REFLECT_LLM_', 'claude-code', 'claude-sonnet-5-5'],
  ['mental_model', 'Pages', 'MENTAL_MODEL_REFRESH_LLM_', 'openai-codex', 'gpt-6-luna'],
  ['vlm', 'Vision', 'VLM_', 'gemini', 'gemini-3.5-flash'],
];
const flags = [
  'REFLECT_USE_DECISION_MODEL',
  'CONSOLIDATION_USE_DECISION_MODEL',
  'MENTAL_MODEL_REFRESH_USE_DECISION_MODEL',
  'MENTAL_MODEL_DELTA_USE_DECISION_MODEL',
];
const providerChoices = [
  { id: 'claude-code', title: 'Claude Code' },
  { id: 'openai-codex', title: 'ChatGPT / Codex' },
  { id: 'gemini', title: 'Gemini' },
];
const modelsByProvider = Object.fromEntries(
  [
    ['claude-code', ['claude-sonnet-5-5', 'claude-haiku-5-5']],
    ['openai-codex', ['gpt-6-luna', 'gpt-5.4-mini']],
    ['gemini', ['gemini-3.5-flash']],
  ].map(([provider, models]) => [provider, (models as string[]).map((id) => ({ id, title: id }))]),
);
export function modelWorkflowDemo() {
  const identities: Row = {},
    values: Row = {};
  const roles: Row[] = definitions.map(([id, title, prefix, provider, model]) => {
    identities[id] = { provider, model, dynamic: false };
    values[P + prefix + 'MODEL'] = model;
    return {
      id,
      title,
      isModelRole: true,
      fallback:
        id === 'mental_model'
          ? 'reflect'
          : ['retain', 'consolidation', 'reflect'].includes(id)
            ? 'default'
            : null,
      effective: `${provider} · ${model}`,
      fields: [
        { name: P + prefix + 'PROVIDER', label: 'Fournisseur', value: provider },
        { name: P + prefix + 'MODEL', label: 'Modèle', value: model },
      ],
      models: modelsByProvider[provider],
    };
  });
  roles.push({
    id: 'decision',
    title: 'Décision',
    effective: 'hindsight · hs-decide-1-flash',
    fields: [
      { name: P + 'DECISION_MODEL_PROVIDER', label: 'Fournisseur', value: 'hindsight' },
      { name: P + 'DECISION_MODEL_MODEL', label: 'Modèle', value: 'hs-decide-1-flash' },
      {
        name: P + 'REFLECT_USE_DECISION_MODEL',
        label: 'Réponses : utiliser la décision',
        value: 'true',
      },
    ],
    models: [],
  });
  roles.push({
    id: 'reranker',
    title: 'Classement',
    effective: 'cohere · rerank-v4.0-fast',
    fields: [
      { name: P + 'RERANKER_PROVIDER', label: 'Fournisseur', value: 'cohere' },
      { name: P + 'RERANKER_COHERE_MODEL', label: 'Modèle Cohere', value: 'rerank-v4.0-fast' },
      { name: P + 'RERANKER_COHERE_API_KEY', label: 'Clé Cohere', secret: true, configured: true },
      {
        name: P + 'RERANKER_LOCAL_MODEL',
        label: 'Modèle local',
        value: 'hindsight-ai/hs-rerank-1',
      },
      { name: P + 'RERANKER_HINDSIGHT_API_KEY', label: 'Clé Hindsight Inference', secret: true },
      { name: P + 'RERANKER_TEI_URL', label: 'URL TEI' },
      { name: P + 'RERANKER_LITELLM_MODEL', label: 'Modèle LiteLLM' },
      { name: P + 'RERANKER_LITELLM_API_KEY', label: 'Clé LiteLLM', secret: true },
      { name: P + 'RERANKER_LITELLM_API_BASE', label: 'URL LiteLLM' },
    ],
    models: [],
  });
  const decisionRole = roles.find((role) => role.id === 'decision')!;
  decisionRole.fields.push(
    { name: P + 'RECALL_DECISION_MODEL_PROVIDER', label: 'Fournisseur pour recall', value: '' },
    {
      name: P + 'RECALL_DECISION_MODEL_PRUNE',
      label: 'Recall : écarter les faits inutiles',
      value: 'false',
    },
    {
      name: P + 'RECALL_DECISION_MODEL_DEDUP',
      label: 'Recall : retirer les doublons',
      value: 'false',
    },
    {
      name: P + 'MENTAL_MODEL_DELTA_USE_DECISION_MODEL',
      label: 'Pages : filtrage des nouveautés',
      value: 'true',
    },
    {
      name: P + 'MENTAL_MODEL_REFRESH_USE_DECISION_MODEL',
      label: 'Pages : décision dans la réflexion',
      value: 'true',
    },
    { name: P + 'DECISION_MODEL_BASE_URL', label: 'URL de base', value: 'http://127.0.0.1:8766' },
    {
      name: P + 'DECISION_MODEL_MAX_REQUEST_TOKENS',
      label: 'Jetons max par requête',
      value: '7000',
    },
  );
  roles.push({
    id: 'embeddings',
    title: 'Embeddings',
    effective: 'google · gemini-embedding-2',
    fields: [
      { name: P + 'EMBEDDINGS_PROVIDER', label: 'Fournisseur', value: 'google' },
      { name: P + 'EMBEDDINGS_GEMINI_MODEL', label: 'Modèle Gemini', value: 'gemini-embedding-2' },
      {
        name: P + 'EMBEDDINGS_GEMINI_API_KEY',
        label: 'Clé Gemini',
        secret: true,
        configured: true,
      },
      {
        name: P + 'EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY',
        label: 'Dimensions Gemini',
        value: '1536',
      },
      {
        name: P + 'EMBEDDINGS_OPENAI_MODEL',
        label: 'Modèle OpenAI',
        value: 'text-embedding-3-small',
      },
      { name: P + 'EMBEDDINGS_OPENAI_API_KEY', label: 'Clé OpenAI', secret: true },
      { name: P + 'EMBEDDINGS_HINDSIGHT_API_KEY', label: 'Clé Hindsight Inference', secret: true },
    ],
    models: [],
  });
  flags.forEach((name) => {
    values[P + name] = 'true';
  });
  const decisions = Object.fromEntries(
    ['reflect', 'consolidation', 'pages', 'recall'].map((op) => [
      op,
      {
        provider: 'hindsight',
        model: 'hs-decide-1-flash',
        source: 'local',
        configured: op !== 'recall',
        enabled: op !== 'recall',
        uncertain: false,
        shared: true,
        partial: false,
      },
    ]),
  );
  return {
    roles,
    providerChoices,
    modelsByProvider,
    modelWorkflow: {
      revision: 'example-0',
      values,
      dynamicNames: [],
      identities,
      decisions,
      embeddings: 'gemini-embedding-2 · 1536',
    },
  };
}

type DemoState = { saved: Row; pending?: Row; revision: number };
const states = new WeakMap<Row, DemoState>();
function modelSnapshot(server: Row): Row {
  return structuredClone({
    roles: server.roles,
    modelWorkflow: server.modelWorkflow,
    decision: server.hindsightModels?.decision,
  });
}
function restoreSnapshot(server: Row, snapshot: Row) {
  const saved = structuredClone(snapshot);
  server.roles = saved.roles;
  server.modelWorkflow = saved.modelWorkflow;
  if (server.hindsightModels) server.hindsightModels.decision = saved.decision;
}
export function changeModelWorkflowDemo(server: Row, command: string, args: Row): boolean {
  if (
    ![
      'server.models.prepare',
      'server.decision',
      'server.revert',
      'server.save',
      'confirm',
    ].includes(command)
  )
    return false;
  if (command === 'confirm' && args.id !== 'example-model-save') return false;
  let state = states.get(server);
  if (!state) {
    state = { saved: modelSnapshot(server), revision: 0 };
    states.set(server, state);
  }
  if (command === 'server.revert') {
    restoreSnapshot(server, state.saved);
    state.pending = undefined;
    server.hasChanges = false;
    return true;
  }
  if (command === 'server.save') {
    state.pending = modelSnapshot(server);
    return true;
  }
  if (command === 'confirm') {
    if (!state.pending) throw new Error('Cette confirmation a expiré.');
    state.saved = state.pending;
    state.pending = undefined;
    restoreSnapshot(server, state.saved);
    server.hasChanges = false;
    server.needsRestart = true;
    return true;
  }
  const w = server.modelWorkflow;
  if (command === 'server.models.prepare') {
    if (args.revision !== w.revision) throw new Error('Brouillon de démonstration périmé.');
    for (const [name, value] of Object.entries(args.changes)) {
      if (value === '') delete w.values[name];
      else w.values[name] = value;
      for (const role of server.roles)
        for (const field of role.fields)
          if (field.name === name) {
            field.value = value || null;
            if (w.identities[role.id] && name.endsWith('_MODEL')) {
              w.identities[role.id].model = value || 'gpt-6-luna';
              role.effective = `${w.identities[role.id].provider} · ${w.identities[role.id].model}`;
            }
          }
    }
  } else {
    server.hindsightModels.decision = args.source;
    Object.values(w.decisions).forEach((d: any) => {
      d.source = args.source;
    });
  }
  const global = server.hindsightModels.decision !== 'off';
  const enabled = (name: string) => w.values[P + name] !== 'false';
  for (const op of ['reflect', 'consolidation', 'pages', 'recall']) {
    const d = w.decisions[op];
    d.configured =
      global && (op !== 'recall' || w.values[P + 'RECALL_DECISION_MODEL_PROVIDER'] === 'hindsight');
    d.enabled =
      d.configured &&
      (op === 'recall' ||
        (op === 'pages'
          ? enabled('MENTAL_MODEL_DELTA_USE_DECISION_MODEL') &&
            enabled('MENTAL_MODEL_REFRESH_USE_DECISION_MODEL')
          : enabled(op.toUpperCase() + '_USE_DECISION_MODEL')));
  }
  w.revision = 'example-' + ++state.revision;
  server.hasChanges = true;
  return true;
}
