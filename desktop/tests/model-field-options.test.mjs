import test from 'node:test';
import assert from 'node:assert/strict';
import {
  modelOptions,
  providerOptions,
  chooseProvider,
  visibleRoleFields,
  serviceModelField,
  isBooleanField,
} from '../src/model-field-options.ts';

const role = (id, provider, model, fallback) => ({
  id,
  fallback,
  isModelRole: true,
  fields: [
    { name: `${id}_PROVIDER`, value: provider },
    { name: `${id}_MODEL`, value: model },
  ],
});

test('Google embeddings use the Gemini fields, without filtering generic model roles', () => {
  const fields = [
    { name: 'HINDSIGHT_API_EMBEDDINGS_PROVIDER', value: 'google' },
    { name: 'HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL', value: 'gemini-embedding-2' },
    { name: 'HINDSIGHT_API_EMBEDDINGS_GEMINI_API_KEY' },
    { name: 'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL' },
  ];
  assert.deepEqual(visibleRoleFields({ id: 'embeddings', fields }, {}), fields.slice(0, 3));
  const reflect = role('reflect', 'claude-code', 'my-claude');
  assert.deepEqual(visibleRoleFields(reflect, {}), reflect.fields);
});
const choice = (id) => ({ id, title: id });

test('decision toggles are booleans even though their variable name ends in MODEL', () => {
  for (const name of [
    'HINDSIGHT_API_REFLECT_USE_DECISION_MODEL',
    'HINDSIGHT_API_RECALL_DECISION_MODEL_PRUNE',
    'HINDSIGHT_API_AUDIT_LOG_ENABLED',
  ])
    assert.ok(isBooleanField({ name }));
  assert.ok(!isBooleanField({ name: 'HINDSIGHT_API_DECISION_MODEL_MODEL' }));
  assert.ok(!isBooleanField({ name: 'HINDSIGHT_API_RERANKER_COHERE_MODEL' }));
});

test('service model fields use the selected provider, including Google reranking', () => {
  const fields = ['PROVIDER', 'GEMINI_MODEL', 'GOOGLE_MODEL'].map((suffix) => ({
    name: 'HINDSIGHT_API_RERANKER_' + suffix,
    value: suffix === 'PROVIDER' ? 'google' : 'saved',
  }));
  assert.equal(serviceModelField({ id: 'reranker', fields }).name, fields[2].name);
  assert.equal(
    serviceModelField({ id: 'reranker', fields }, { [fields[0].name]: 'hindsight' }),
    undefined,
  );
});

test('draft models remain selectable but never cross providers', () => {
  const reflect = role('reflect', 'claude-code', 'saved-claude');
  const data = { modelsByProvider: { 'openai-codex': [choice('gpt-model')] } };
  assert.ok(
    modelOptions(reflect, reflect.fields[1], { reflect_MODEL: 'typed-model' }, data).some(
      (m) => m.id === 'typed-model',
    ),
  );
  const draft = chooseProvider(
    reflect,
    reflect.fields[0],
    'openai-codex',
    { reflect_MODEL: 'typed-model' },
    data,
  );
  assert.equal(draft.reflect_MODEL, 'gpt-model');
  const emptyCatalog = chooseProvider(reflect, reflect.fields[0], 'custom-proxy', draft, data);
  assert.equal(emptyCatalog.reflect_MODEL, '');
});

test('service provider menus use server names and operation-specific support', () => {
  const embeddings = { id: 'embeddings', fields: [] };
  const options = providerOptions(embeddings, {}, {}).map((p) => p.id);
  assert.ok(options.includes('google'));
  assert.ok(!options.includes('gemini'));
  const decision = {
    id: 'decision',
    fields: [
      { name: 'HINDSIGHT_API_DECISION_MODEL_PROVIDER', value: 'openai' },
      { name: 'HINDSIGHT_API_REFLECT_DECISION_MODEL_PROVIDER', value: '' },
    ],
  };
  const data = { roles: [decision] };
  assert.deepEqual(
    providerOptions(decision, decision.fields[1], data).map((p) => p.id),
    ['none', 'hindsight', 'typesafe'],
  );
  decision.fields[1].value = 'openai';
  assert.ok(
    providerOptions(decision, decision.fields[1], data).some((p) => p.id === 'openai'),
    'preserve existing unsupported values for inspection',
  );
});

test('sign-in folders follow the selected LLM provider', () => {
  const llm = role('default', 'openai-codex', 'gpt-model');
  llm.fields.push(
    { name: 'HINDSIGHT_API_LLM_CODEX_HOME' },
    { name: 'HINDSIGHT_API_LLM_CHATGPT_HOME' },
  );
  const names = (provider) =>
    visibleRoleFields(llm, { default_PROVIDER: provider }).map((f) => f.name);
  assert.ok(names('openai-codex').includes('HINDSIGHT_API_LLM_CODEX_HOME'));
  assert.ok(!names('openai-codex').includes('HINDSIGHT_API_LLM_CHATGPT_HOME'));
  assert.ok(names('chatgpt').includes('HINDSIGHT_API_LLM_CHATGPT_HOME'));
  assert.ok(!names('anthropic').some((name) => name.endsWith('_HOME')));
});

test('service fields follow the draft provider and preserve inactive configuration', () => {
  for (const id of ['reranker', 'embeddings']) {
    const prefix = `HINDSIGHT_API_${id.toUpperCase()}_`;
    const fields = [
      'PROVIDER',
      'COHERE_MODEL',
      'COHERE_API_KEY',
      'LOCAL_MODEL',
      'HINDSIGHT_API_KEY',
    ].map((suffix) => ({
      name: prefix + suffix,
      value: suffix === 'PROVIDER' ? 'cohere' : 'saved',
    }));
    const service = { id, fields };
    const names = (draft) =>
      visibleRoleFields(service, draft).map((f) => f.name.slice(prefix.length));
    assert.deepEqual(names({}), ['PROVIDER', 'COHERE_MODEL', 'COHERE_API_KEY']);
    const draft = chooseProvider(service, fields[0], 'hindsight', {}, {});
    assert.deepEqual(names(draft), ['PROVIDER', 'HINDSIGHT_API_KEY']);
    assert.deepEqual(names({ [prefix + 'PROVIDER']: 'local' }), ['PROVIDER', 'LOCAL_MODEL']);
    assert.deepEqual(names({ [prefix + 'PROVIDER']: '' }), ['PROVIDER', 'LOCAL_MODEL']);
    assert.deepEqual(names({ [prefix + 'PROVIDER']: 'tei' }), ['PROVIDER']);
    assert.deepEqual(draft, { [prefix + 'PROVIDER']: 'hindsight' });
    assert.equal(fields[1].value, 'saved');
  }
});

test('provider selection replaces the former model and preserves configured custom choices', () => {
  const reflect = role('reflect', 'claude-code', 'my-claude');
  const custom = role('retain', 'custom-proxy', 'custom-model');
  const data = {
    roles: [reflect, custom],
    providerChoices: [{ id: 'openai-codex', title: 'ChatGPT / Codex' }],
    modelsByProvider: {
      'openai-codex': [choice('gpt-model')],
      'custom-proxy': [choice('custom-model')],
    },
  };
  assert.ok(providerOptions(reflect, reflect.fields[0], data).some((c) => c.id === 'custom-proxy'));
  const draft = chooseProvider(reflect, reflect.fields[0], 'openai-codex', {}, data);
  assert.equal(draft.reflect_MODEL, 'gpt-model');
  assert.deepEqual(
    modelOptions(reflect, reflect.fields[1], draft, data).map((c) => c.id),
    ['gpt-model'],
  );
  const customDraft = chooseProvider(reflect, reflect.fields[0], 'custom-proxy', draft, data);
  assert.equal(customDraft.reflect_MODEL, 'custom-model');
  assert.equal(
    reflect.fields[1].value,
    'my-claude',
    'local editing does not modify saved metadata',
  );
});

test('inherited provider resolves through pages, reflect and default without touching other fields', () => {
  const primary = role('default', 'openai-codex', 'gpt-model');
  const reflect = role('reflect', null, null, 'default');
  const pages = role('mental_model', null, null, 'reflect');
  const data = {
    roles: [primary, reflect, pages],
    modelsByProvider: { 'openai-codex': [choice('gpt-model')] },
  };
  assert.deepEqual(
    modelOptions(pages, pages.fields[1], {}, data).map((c) => c.id),
    ['gpt-model'],
  );
  const draft = chooseProvider(pages, pages.fields[0], '', { API_KEY: 'unchanged' }, data);
  assert.deepEqual(draft, {
    API_KEY: 'unchanged',
    mental_model_PROVIDER: '',
    mental_model_MODEL: '',
  });
});

test('clearing the global provider does not reuse its former identity or model catalog', () => {
  const primary = role('default', 'claude-code', 'saved-claude');
  primary.models = [choice('saved-claude')];
  const data = { modelWorkflow: { identities: { default: { provider: 'claude-code' } } } };
  const draft = chooseProvider(primary, primary.fields[0], '', {}, data);
  assert.equal(draft.default_MODEL, '');
  assert.deepEqual(modelOptions(primary, primary.fields[1], draft, data), []);
});
