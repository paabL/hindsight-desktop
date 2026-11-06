import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setLanguage } from '../src/i18n-core.ts';
import { nativeCatalogText, nativeRoleEffective } from '../src/native-catalog.ts';
import { localizeNativeSnapshot } from '../src/native-messages.ts';

test('le catalogue serveur traduit tous ses libellés français fixes', () => {
  setLanguage('en');
  const swift = readFileSync(
    new URL(
      '../../Sources/HindsightCore/ServerConfig/ServerSettingsCatalog.swift',
      import.meta.url,
    ),
    'utf8',
  );
  for (const [, text] of swift.matchAll(/(?:title|help|label|caution): "((?:\\.|[^"\\])*)"/g)) {
    if (text.includes('\\(')) continue; // Runtime labels with interpolation are checked below.
    if (/[àâçéèêëîïôùûüœ]/i.test(text))
      assert.notEqual(nativeCatalogText(text), text, `Traduction absente : ${text}`);
  }
  // Libellés d'opération : les noms de fonctions de l'app (Recherche, Réponses, Consolidation).
  for (const [fr, en] of [
    ['Recherche', 'Search'],
    ['Réponses', 'Answers'],
    ['Consolidation', 'Consolidation'],
  ]) {
    assert.equal(nativeCatalogText(`${fr} : modèle`), `${en}: model`);
    assert.equal(nativeCatalogText(`${fr} : clé`), `${en}: key`);
    assert.equal(nativeCatalogText(`${fr} : fournisseur`), `${en}: provider`);
  }
});

test('la localisation des métadonnées serveur préserve valeurs, noms modèles, URL et journaux', () => {
  setLanguage('en');
  const roles = [
    {
      id: 'default',
      title: 'LLM par défaut',
      effective: 'openai · Modèle',
      fields: [
        {
          name: 'HINDSIGHT_API_LLM_PROVIDER',
          label: 'Fournisseur',
          help: 'Plafond de concurrence vers ce LLM',
          value: 'openai',
        },
        { name: 'HINDSIGHT_API_LLM_MODEL', label: 'Modèle', help: '', value: 'Modèle' },
        {
          name: 'HINDSIGHT_API_LLM_BASE_URL',
          label: 'URL de base',
          help: '',
          value: 'https://exemple.invalid/Modèle',
        },
      ],
      models: [{ id: 'Modèle', title: 'Modèle' }],
    },
  ];
  const data = {
    roles,
    otherVariables: [{ name: 'CUSTOM', label: 'CUSTOM', help: '', value: 'Fournisseur' }],
    accounts: [{ title: 'Mon organisation', status: 'Connecté à Équipe mémoire' }],
    warnings: [
      "Modèle : la référence à l'environnement sera remplacée. Vous pouvez rétablir sa valeur d'origine.",
    ],
    service: { log: 'LLM par défaut', scriptWarning: null },
    hindsightModels: {
      local: {
        summary: 'Non installé',
        problem: 'Le serveur local ne répond pas : voir /Exemple/mémoire.log.',
        log: 'Non installé',
      },
    },
  };
  const raw = {
    app: { connected: true, serverURL: 'http://127.0.0.1:8888', banks: [], bank: 'mémoire' },
    section: 'server',
    data,
    confirmations: [],
    messages: [],
  };
  const result = localizeNativeSnapshot(raw);
  assert.equal(result.data.roles[0].title, 'Default LLM');
  assert.equal(result.data.roles[0].fields[0].label, 'Provider');
  assert.equal(result.data.roles[0].fields[1].value, 'Modèle');
  assert.equal(result.data.roles[0].effective, 'openai · Modèle');
  assert.equal(result.data.roles[0].fields[2].value, 'https://exemple.invalid/Modèle');
  assert.strictEqual(result.data.roles[0].models, roles[0].models);
  assert.equal(result.data.otherVariables[0].value, 'Fournisseur');
  assert.equal(result.data.accounts[0].title, 'Mon organisation');
  assert.equal(result.data.accounts[0].status, 'Connected to Équipe mémoire');
  assert.match(result.data.warnings[0], /^Model: the environment reference/);
  assert.equal(result.data.service.log, 'LLM par défaut');
  assert.equal(result.data.hindsightModels.local.log, 'Non installé');
  assert.equal(result.data.hindsightModels.local.summary, 'Not installed');
  assert.equal(
    result.data.hindsightModels.local.problem,
    'The local server is not responding: see /Exemple/mémoire.log.',
  );
  assert.equal(raw.data.roles[0].title, 'LLM par défaut');
  const quick = localizeNativeSnapshot({ ...raw, section: 'model-settings' });
  assert.equal(quick.data.roles[0].title, 'Default LLM');
  assert.equal(quick.data.roles[0].fields[1].value, 'Modèle');
  assert.strictEqual(localizeNativeSnapshot({ ...raw, section: 'documents' }).data.roles, roles);
  setLanguage('fr');
  assert.strictEqual(localizeNativeSnapshot(raw), raw);
});

test('les marqueurs hérités sont traduits sans altérer les noms configurés', () => {
  setLanguage('en');
  const roles = [
    {
      id: 'default',
      fields: [
        { name: 'HINDSIGHT_API_LLM_PROVIDER', value: 'openai' },
        { name: 'HINDSIGHT_API_LLM_MODEL', value: 'modèle par défaut' },
      ],
    },
    {
      id: 'retain',
      fields: [
        { name: 'HINDSIGHT_API_RETAIN_LLM_PROVIDER', value: null },
        { name: 'HINDSIGHT_API_RETAIN_LLM_MODEL', value: null },
      ],
      effective: 'openai · modèle par défaut — hérité du LLM par défaut',
    },
  ];
  assert.equal(
    nativeRoleEffective(roles[1], roles),
    'openai · modèle par défaut — inherited from Default LLM',
  );
  roles[0].fields[1].value = null;
  roles[1].effective = 'openai · gpt-4o-mini (défaut) — hérité du LLM par défaut';
  assert.equal(
    nativeRoleEffective(roles[1], roles),
    'openai · gpt-4o-mini (default) — inherited from Default LLM',
  );
});

test('les résumés spécialisés ne reprennent pas le modèle inactif du premier champ', () => {
  setLanguage('en');
  for (const id of ['reranker', 'embeddings']) {
    const role = {
      id,
      effective: 'local · modèle par défaut',
      fields: [
        { name: `HINDSIGHT_API_${id.toUpperCase()}_PROVIDER`, value: 'local' },
        { name: `HINDSIGHT_API_${id.toUpperCase()}_COHERE_MODEL`, value: 'inactive-cohere' },
      ],
    };
    assert.equal(nativeRoleEffective(role, [role]), 'local · default model');
    role.effective = 'local · selected-local';
    assert.equal(nativeRoleEffective(role, [role]), role.effective);
  }
});
