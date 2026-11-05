import type { Row } from './types';

export type ModelOption = { id: string; title: string };
export const localDecisionURL = 'http://127.0.0.1:8766';
export function decisionProviderValue(role: Row, draft: Row): string {
  const provider = fieldValue(role, 'HINDSIGHT_API_DECISION_MODEL_PROVIDER', draft);
  if (provider !== 'hindsight') return provider;
  const url = fieldValue(role, 'HINDSIGHT_API_DECISION_MODEL_BASE_URL', draft);
  if (url === localDecisionURL) return '__hindsight_local__';
  return url && url !== 'https://inference.hindsight.vectorize.io'
    ? '__hindsight_custom__'
    : provider;
}
export function isBooleanField(field: Row): boolean {
  return /_(ENABLED|PRUNE|DEDUP)$|_USE_DECISION_MODEL$/.test(field.name);
}
const genericRoles = ['default', 'retain', 'consolidation', 'reflect', 'mental_model', 'vlm'];
const serviceProviders: Record<string, string[]> = {
  decision: ['none', 'hindsight', 'typesafe', 'cloudflare', 'openai'],
  reranker: ['local', 'hindsight', 'cohere', 'tei', 'litellm', 'google'],
  embeddings: ['local', 'hindsight', 'google', 'openai', 'cohere', 'tei', 'litellm'],
};
function unique(items: ModelOption[]): ModelOption[] {
  const seen = new Set<string>();
  return items.filter((item) => item.id && !seen.has(item.id) && seen.add(item.id));
}
function fieldValue(role: Row, name: string, draft: Row): string {
  return draft[name] ?? role.fields.find((field: Row) => field.name === name)?.value ?? '';
}
function primaryProvider(role: Row): string | undefined {
  return role.fields.find((field: Row) => field.name.endsWith('_PROVIDER'))?.name;
}
function resolvedProvider(role: Row, name: string, draft: Row, data: Row): string {
  if (!primaryProvider(role)) return '';
  const value = fieldValue(role, name, draft);
  if (value) return value;
  if (name === primaryProvider(role)) {
    const fallback = data.roles?.find((candidate: Row) => candidate.id === role.fallback);
    if (fallback) return resolvedProvider(fallback, primaryProvider(fallback) || '', {}, data);
    if (Object.hasOwn(draft, name)) return '';
    return data.modelWorkflow?.identities?.[role.id]?.provider || '';
  }
  return resolvedProvider(role, primaryProvider(role) || '', draft, data);
}
export function serviceModelField(role: Row, draft: Row = {}): Row | undefined {
  if (!['reranker', 'embeddings'].includes(role.id)) return undefined;
  const prefix = `HINDSIGHT_API_${role.id.toUpperCase()}_`;
  const provider = fieldValue(role, prefix + 'PROVIDER', draft) || 'local';
  const owner =
    role.id === 'embeddings' && provider === 'google' ? 'GEMINI' : provider.toUpperCase();
  return role.fields.find((field: Row) => field.name === `${prefix}${owner}_MODEL`);
}
export function visibleRoleFields(role: Row, draft: Row, data: Row = {}): Row[] {
  if (!['reranker', 'embeddings'].includes(role.id)) {
    const provider = resolvedProvider(role, primaryProvider(role) || '', draft, data);
    return role.fields.filter((field: Row) => {
      if (field.name === 'HINDSIGHT_API_LLM_CODEX_HOME') return provider === 'openai-codex';
      if (field.name === 'HINDSIGHT_API_LLM_CHATGPT_HOME') return provider === 'chatgpt';
      return true;
    });
  }
  const prefix = `HINDSIGHT_API_${role.id === 'reranker' ? 'RERANKER' : 'EMBEDDINGS'}_`;
  const provider = (fieldValue(role, prefix + 'PROVIDER', draft) || 'local').toLowerCase();
  const fieldProvider = role.id === 'embeddings' && provider === 'google' ? 'gemini' : provider;
  return role.fields.filter((field: Row) => {
    if (!field.name.startsWith(prefix) || field.name === prefix + 'PROVIDER') return true;
    const owner = field.name.slice(prefix.length).split('_')[0].toLowerCase();
    return owner === fieldProvider;
  });
}
export function providerOptions(role: Row, field: Row, data: Row): ModelOption[] {
  const isGeneric = role.isModelRole ?? genericRoles.includes(role.id);
  let available = isGeneric
    ? data.providerChoices || []
    : (serviceProviders[role.id] || []).map((id) => ({ id, title: id }));
  if (role.id === 'decision' && field.name === 'HINDSIGHT_API_REFLECT_DECISION_MODEL_PROVIDER')
    available = available.filter((option: ModelOption) =>
      ['none', 'hindsight', 'typesafe'].includes(option.id),
    );
  const configured = (data.roles || [])
    .filter((r: Row) =>
      isGeneric ? (r.isModelRole ?? genericRoles.includes(r.id)) : r.id === role.id,
    )
    .flatMap((r: Row) =>
      r.fields
        .filter((f: Row) => f.name.endsWith('_PROVIDER') && f.value)
        .map((f: Row) => ({ id: f.value, title: f.value })),
    );
  const options = unique([
    ...available,
    ...configured,
    ...(field.value ? [{ id: field.value, title: field.value }] : []),
  ]).map((option) => ({ ...option }));
  for (const option of options) {
    if (option.id === 'hindsight')
      option.title = role.id === 'decision' ? 'Hindsight · local / Cloud' : 'Hindsight Cloud';
    if (option.id === 'local') option.title = 'Local · on this Mac';
  }
  return role.id === 'decision' && field.name === 'HINDSIGHT_API_REFLECT_DECISION_MODEL_PROVIDER'
    ? options.filter((option) => ['none', 'hindsight', 'typesafe', field.value].includes(option.id))
    : options;
}
export function modelOptions(role: Row, field: Row, draft: Row, data: Row): ModelOption[] {
  const providerName = field.name.replace(/MODEL$/, 'PROVIDER');
  const paired = role.fields.some((f: Row) => f.name === providerName);
  const provider = paired ? resolvedProvider(role, providerName, draft, data) : '';
  const before = paired ? resolvedProvider(role, providerName, {}, data) : '';
  const generic = role.isModelRole ?? genericRoles.includes(role.id);
  const candidates: ModelOption[] = generic
    ? data.modelsByProvider?.[provider] || (provider === before ? role.models || [] : [])
    : role.id === 'decision' && provider === 'hindsight'
      ? [{ id: 'hs-decide-1-flash', title: 'hs-decide-1-flash' }]
      : [];
  const current =
    field.value && (!paired || provider === before)
      ? [{ id: field.value, title: field.value }]
      : [];
  const selected = draft[field.name];
  return unique([
    ...candidates,
    ...current,
    ...(selected ? [{ id: selected, title: selected }] : []),
  ]);
}
export function chooseProvider(role: Row, field: Row, value: string, draft: Row, data: Row): Row {
  const next: Row = { ...draft, [field.name]: value };
  const model = role.fields.find((f: Row) => f.name === field.name.replace(/PROVIDER$/, 'MODEL'));
  if (model) {
    delete next[model.name];
    next[model.name] = value ? modelOptions(role, model, next, data)[0]?.id || '' : '';
  }
  return next;
}
