import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, readFile, mkdir, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
let bridge, server, folder;
const calls = [];
before(async () => {
  folder = await mkdtemp(path.join(tmpdir(), 'hindsight-desktop-test-'));
  await mkdir(path.join(folder, 'collection'));
  await writeFile(
    path.join(folder, 'collection/catalog.json'),
    JSON.stringify({ version: 1, mode: 'collection_only', records: [], sources: [] }),
  );
  await writeFile(path.join(folder, 'collection/source.md'), '# Source de test\nUn texte local.');
  await writeFile(path.join(folder, 'private.txt'), 'Hors du dossier autorisé');
  await symlink(path.join(folder, 'private.txt'), path.join(folder, 'collection/link.txt'));
  server = createServer(async (request, response) => {
    const url = new URL(request.url, 'http://localhost');
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    calls.push({
      method: request.method,
      path: url.pathname,
      query: Object.fromEntries(url.searchParams),
      body: Buffer.concat(chunks).toString(),
    });
    let data = {};
    if (url.pathname === '/version')
      data = {
        api_version: '1.1.0',
        features: Object.fromEntries(
          [
            'observations',
            'mcp',
            'worker',
            'bank_config_api',
            'bank_llm_health',
            'file_upload_api',
            'document_export_api',
            'document_import_api',
            'audit_log',
            'llm_trace',
            'store_document_text',
            // Réglages par banque acceptés, comme par défaut sur un serveur Hindsight.
          ].map((key) => [key, key === 'bank_config_api']),
        ),
      };
    else if (url.pathname === '/v1/default/banks')
      data = {
        banks: [
          {
            bank_id: 'fixture',
            name: 'Banque de test',
            disposition: { skepticism: 3, literalism: 3, empathy: 3 },
            fact_count: 1,
          },
        ],
        total: 1,
        limit: 200,
        offset: 0,
      };
    else if (url.pathname.endsWith('/entities/graph'))
      data = JSON.parse(
        await readFile(
          path.join(root, '../Tests/HindsightCoreTests/Fixtures/entity_graph.json'),
          'utf8',
        ),
      );
    else if (url.pathname.endsWith('/graph'))
      data = JSON.parse(
        await readFile(path.join(root, '../Tests/HindsightCoreTests/Fixtures/graph.json'), 'utf8'),
      );
    else if (url.pathname.endsWith('/config'))
      data = { bank_id: 'fixture', config: { enable_auto_consolidation: false }, overrides: {} };
    else if (url.pathname.endsWith('/reflect'))
      data = { text: 'Réponse du faux serveur, sans appel de modèle.' };
    else if (url.pathname.endsWith('/recall'))
      data = { results: [{ id: 'fact-1', text: 'Un fait synthétique.', type: 'world' }] };
    else if (url.pathname.endsWith('/memories/list')) {
      const memories = [
        {
          id: 'retained-fact',
          text: 'Un fait extrait de la source.',
          fact_type: 'world',
          document_id: 'source-document',
          mentioned_at: '2026-11-04T14:30:00Z',
          state: 'valid',
        },
        {
          id: 'consolidated-observation',
          text: 'Une observation consolidée à partir du fait.',
          fact_type: 'observation',
          source_memory_ids: ['retained-fact'],
          state: 'valid',
        },
      ].filter(
        (item) =>
          (!url.searchParams.get('type') || item.fact_type === url.searchParams.get('type')) &&
          item.text
            .toLocaleLowerCase()
            .includes((url.searchParams.get('q') || '').toLocaleLowerCase()),
      );
      data = { items: memories, total: memories.length, limit: 1000, offset: 0 };
    } else data = { items: [], total: 0, limit: 100, offset: 0, operations: [] };
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(data));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  // Aucun réglage utilisateur, historique local ou suivi en arrière-plan pendant les tests.
  const previous = process.env.HINDSIGHT_DESKTOP_TEST_MODE;
  process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
  bridge = new BridgeClient(path.join(root, 'native/HindsightBridge'));
  if (previous == null) delete process.env.HINDSIGHT_DESKTOP_TEST_MODE;
  else process.env.HINDSIGHT_DESKTOP_TEST_MODE = previous;
  await bridge.request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
});
after(async () => {
  bridge?.close();
  await new Promise((resolve) => server?.close(resolve));
  await rm(folder, { recursive: true, force: true });
});

test('une lecture de banque ne déclenche aucune écriture', async () => {
  await bridge.request('section', { section: 'admin' });
  assert.equal(calls.filter((c) => c.method !== 'GET').length, 0);
  const result = await bridge.request('snapshot');
  assert.equal(result.app.connected, true);
  assert.equal(result.app.bank, 'fixture');
});

test('le précontrôle de mise à jour est une lecture sans appel au serveur', async () => {
  const before = calls.length;
  assert.deepEqual(await bridge.request('updates.releaseReady'), { releaseUpdateReady: true });
  assert.equal(calls.length, before);
});

test('la mémoire affiche les faits et observations réels sans écriture ni génération', async () => {
  const before = calls.length;
  const result = await bridge.request('section', { section: 'facts' });
  assert.equal(result.section, 'facts');
  assert.equal(result.data.total, 2);
  assert.equal(result.data.truncated, false);
  assert.deepEqual(
    result.data.facts.map((fact) => fact.type),
    ['world', 'observation'],
  );
  assert.equal(result.data.facts[0].documentID, 'source-document');
  assert.deepEqual(result.data.facts[1].sourceFactIDs, ['retained-fact']);
  assert.equal(result.data.facts[1].documentID, null);
  const searched = await bridge.request('section', {
    section: 'facts',
    query: 'consolidée',
    type: 'observation',
  });
  assert.equal(searched.data.query, 'consolidée');
  assert.equal(searched.data.type, 'observation');
  assert.equal(searched.data.total, 1);
  assert.equal(searched.data.facts.length, 1);
  assert.equal(searched.data.facts[0].id, 'consolidated-observation');
  const requests = calls.slice(before);
  assert.ok(requests.length > 0);
  assert.ok(
    requests.every(
      (request) => request.method === 'GET' && request.path.endsWith('/memories/list'),
    ),
  );
  assert.equal(requests.at(-1).query.q, 'consolidée');
  assert.equal(requests.at(-1).query.type, 'observation');
  const timeline = await bridge.request('section', { section: 'timeline' });
  assert.equal(timeline.data.facts.length, 2);
  assert.equal(timeline.data.type, 'all');
  assert.equal(calls.at(-1).query.type, undefined);
});

test('les anciens contrôles de quota sont refusés sans lecture ni confirmation', async () => {
  const before = calls.length;
  await assert.rejects(bridge.request('subscription.refresh'), /Action inconnue/);
  assert.equal(calls.length, before);
  const result = await bridge.request('section', { section: 'consumption' });
  assert.equal(result.confirmations.length, 0);
  assert.equal('codexQuota' in result.data, false);
  assert.equal('claudeQuota' in result.data, false);
  assert.equal('quotaProblems' in result.data, false);
  assert.ok(calls.slice(before).every((call) => call.method === 'GET'));
});

test('les actions du lecteur refusent un document qui n’est plus ouvert', async () => {
  const before = calls.length;
  const status = await bridge.request('document.status', { id: 'source-document' });
  assert.deepEqual(status, { open: false, confirming: false });
  for (const command of [
    'document.delete',
    'document.reprocess',
    'document.tags',
    'document.scope',
  ])
    await assert.rejects(bridge.request(command, { id: 'source-document' }), /n’est plus ouvert/);
  assert.equal(calls.length, before);
});

test('reflect attend une confirmation et ne peut pas la rejouer', async () => {
  await bridge.request('section', { section: 'search' });
  const before = calls.filter((c) => c.path.endsWith('/reflect')).length;
  const prepared = await bridge.request('search', { query: 'Question de test', mode: 'reflect' });
  assert.equal(calls.filter((c) => c.path.endsWith('/reflect')).length, before);
  assert.equal(prepared.confirmations.length, 1);
  const id = prepared.confirmations[0].id;
  const result = await bridge.request('confirm', { id, typed: '' });
  assert.match(result.data.answer.text, /faux serveur/);
  assert.equal(calls.filter((c) => c.path.endsWith('/reflect')).length, before + 1);
  await assert.rejects(bridge.request('confirm', { id, typed: '' }), /expiré/);
});

test('une suppression impose le texte requis côté natif', async () => {
  const prepared = await bridge.request('admin.deleteBank');
  const request = prepared.confirmations[0];
  assert.equal(request.requiredText, 'fixture');
  await assert.rejects(
    bridge.request('confirm', { id: request.id, typed: 'autre-banque' }),
    /ne correspond pas/,
  );
  assert.equal(calls.filter((c) => c.method === 'DELETE').length, 0);
  await bridge.request('cancel');
  await assert.rejects(bridge.request('confirm', { id: request.id, typed: 'fixture' }), /expiré/);
  assert.equal(calls.filter((c) => c.method === 'DELETE').length, 0);
});

test('changer de banque invalide les confirmations précédentes', async () => {
  const prepared = await bridge.request('search', { query: 'Question', mode: 'reflect' });
  const id = prepared.confirmations[0].id;
  await bridge.request('bank.select', { id: 'fixture' });
  await assert.rejects(bridge.request('confirm', { id, typed: '' }), /expiré/);
});

test('le lecteur local refuse les traversées et les liens hors collection', async () => {
  await bridge.request('folder.choose', { path: folder });
  const result = await bridge.request('folder.read', { path: 'source.md' });
  assert.match(result.text, /Source de test/);
  await assert.rejects(
    bridge.request('folder.read', { path: '../private.txt' }),
    /hors du dossier/,
  );
  await assert.rejects(bridge.request('folder.read', { path: 'link.txt' }), /hors du dossier/);
  await assert.rejects(bridge.request('folder.read', { path: '/etc/passwd' }), /hors du dossier/);
});

test('les adresses distantes en HTTP et les identifiants intégrés sont refusés', async () => {
  await assert.rejects(bridge.request('server.url', { url: 'http://example.com' }));
  await assert.rejects(bridge.request('server.url', { url: 'https://user:secret@example.com' }));
});

test('les commandes non déclarées sont refusées', async () => {
  await assert.rejects(bridge.request('shell', { command: 'echo texte' }), /Action inconnue/);
  await assert.rejects(bridge.request('exec;rm', {}), /Action invalide/);
});

test('la reconstruction attend confirmation et une relance prématurée est refusée', async () => {
  const repository = path.join(folder, 'update-source');
  await mkdir(path.join(repository, '.git'), { recursive: true });
  await mkdir(path.join(repository, 'desktop/src-tauri'), { recursive: true });
  await mkdir(path.join(repository, 'desktop/scripts'), { recursive: true });
  await writeFile(path.join(repository, 'desktop/src-tauri/tauri.conf.json'), '{}');
  await writeFile(
    path.join(repository, 'desktop/scripts/update-build.mjs'),
    'throw new Error("Jamais exécuté avant confirmation");',
  );
  const result = await bridge.request('updates.rebuild', { path: repository });
  assert.equal(result.confirmations.length, 1);
  assert.match(result.confirmations[0].title, /Recompiler/);
  assert.equal(result.updates.working, false);
  const id = result.confirmations[0].id;
  await bridge.request('cancel');
  await assert.rejects(bridge.request('confirm', { id, typed: '' }), /expiré/);
  await assert.rejects(bridge.request('updates.relaunch'));
  // A tiny isolated source task exercises work that outlives its IPC response.
  // It deliberately fails before any bundle can be produced or installed.
  await writeFile(
    path.join(repository, 'desktop/scripts/update-build.mjs'),
    'await new Promise((resolve) => setTimeout(resolve, 1000)); throw new Error("Isolated test completed");',
  );
  const again = await bridge.request('updates.rebuild', { path: repository });
  await bridge.request('confirm', { id: again.confirmations[0].id, typed: '' });
  assert.deepEqual(await bridge.request('updates.releaseReady'), { releaseUpdateReady: false });
  const deadline = Date.now() + 5000;
  let ready = false;
  while (Date.now() < deadline) {
    ready = (await bridge.request('updates.releaseReady')).releaseUpdateReady;
    if (ready) break;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.equal(ready, true, 'the app becomes eligible again after detached work finishes');
});

test('la collecte locale reste distincte de Hindsight et attend une confirmation', async () => {
  const marker = path.join(folder, 'collector-started');
  await writeFile(
    path.join(folder, 'collect.py'),
    `from pathlib import Path
Path(${JSON.stringify(marker)}).write_text('executed')
`,
  );
  await bridge.request('cancel');
  await bridge.request('folder.choose', { path: folder });
  await bridge.request('section', { section: 'sources' });
  const before = calls.length;
  const result = await bridge.request('folder.collect');
  assert.equal(result.confirmations.length, 1);
  assert.match(result.confirmations[0].title, /Collecter les sources/);
  assert.match(result.confirmations[0].message, /Aucun envoi ni traitement Hindsight/);
  assert.equal(result.data.collecting, false);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  const cancelled = await bridge.request('cancel');
  assert.equal(cancelled.confirmations.length, 0);
  assert.equal(calls.length, before, 'aucun appel Hindsight pendant la collecte non confirmée');
});

test('actualiser le dossier ne contacte pas Hindsight et ne prépare aucun envoi', async () => {
  const marker = path.join(folder, 'local-refresh-started');
  await writeFile(
    path.join(folder, 'collect.py'),
    `from pathlib import Path
Path(${JSON.stringify(marker)}).write_text('executed')
`,
  );
  await bridge.request('folder.choose', { path: folder });
  const before = calls.length;
  const result = await bridge.request('folder.refresh');
  assert.equal(await readFile(marker, 'utf8'), 'executed');
  assert.equal(result.confirmations.length, 0);
  assert.equal(result.data.collecting, false);
  assert.match(result.data.memoryMessage, /Sources collectées/);
  assert.equal(calls.length, before, 'actualisation entièrement indépendante du serveur');
});

test('un ajout manuel confirmé transmet les fichiers choisis et ne fait que relire Hindsight', async () => {
  const marker = path.join(folder, 'manual-args.json');
  const doc = path.join(folder, 'note manuelle.tex');
  await writeFile(doc, String.raw`\section{Local}`);
  await writeFile(
    path.join(folder, 'collect.py'),
    `import sys, json
from pathlib import Path
Path(${JSON.stringify(marker)}).write_text(json.dumps(sys.argv[1:]))
print(json.dumps({"imported": 1, "unchanged": 0}))
`,
  );
  await bridge.request('cancel');
  await bridge.request('folder.choose', { path: folder });
  await bridge.request('section', { section: 'sources' });
  const before = calls.length;
  const prepared = await bridge.request('folder.import', { paths: [doc], project: 'nomad' });
  assert.equal(prepared.confirmations.length, 1);
  assert.match(prepared.confirmations[0].message, /documents\/nomad/);
  await assert.rejects(readFile(marker), { code: 'ENOENT' });
  const result = await bridge.request('confirm', { id: prepared.confirmations[0].id, typed: '' });
  assert.deepEqual(JSON.parse(await readFile(marker, 'utf8')), [
    '--project',
    'nomad',
    '--import-file',
    doc,
  ]);
  assert.equal(result.data.collecting, false);
  assert.ok(calls.slice(before).every((call) => call.method === 'GET'));
  assert.ok(result.messages.some((m) => /1 document/.test(m)));
  await assert.rejects(
    bridge.request('folder.open', { path: '../private.txt' }),
    /hors du dossier/,
  );
  await assert.rejects(bridge.request('folder.open', { path: 'link.txt' }), /hors du dossier/);
  await writeFile(path.join(folder, 'collection/doc.pdf'), '%PDF-1.4\n%%EOF');
  await bridge.request('folder.open', { path: 'doc.pdf' }); // test mode never launches an external reader
  assert.ok(calls.slice(before).every((call) => call.method === 'GET'));
});

test('le graphe conserve son mode, expose les limites et garde les sources des faits', async () => {
  const before = calls.length;
  const entities = await bridge.request('section', {
    section: 'graph',
    mode: 'entities',
    limit: 100,
  });
  assert.equal(entities.data.mode, 'entities');
  assert.equal(entities.data.nodes.length, 6);
  assert.equal(entities.data.totalNodes, 3800);
  const graph = await bridge.request('section', { section: 'graph', mode: 'facts', limit: 100 });
  assert.equal(graph.data.mode, 'facts');
  assert.equal(graph.data.totalNodes, 8012);
  const selected = await bridge.request('graph.select', { id: 'f0' });
  assert.equal(selected.data.selectedNodeID, 'f0');
  assert.equal(selected.data.nodeFacts[0].documentID, 'codex-abc-task-002');
  assert.match(selected.data.nodeFacts[0].text, /Fait numéro 0/);
  const reloaded = await bridge.request('section', { section: 'graph' });
  assert.equal(reloaded.data.mode, 'facts');
  assert.equal(reloaded.data.limit, 100);
  await assert.rejects(
    bridge.request('graph.select', { id: 'outside-loaded-graph' }),
    /ne fait pas partie/,
  );
  assert.ok(calls.slice(before).every((c) => c.method === 'GET'));
});

test('un même résultat d’action, produit deux fois, est une nouvelle occurrence à afficher', async () => {
  const before = calls.length;
  await bridge.request('section', { section: 'memory' });
  const key = (result) =>
    result.messageKeys[result.messages.indexOf('Aucun changement à enregistrer.')];
  const first = await bridge.request('memory.save', { config: {} });
  assert.equal(first.messages.length, first.messageKeys.length);
  assert.ok(key(first), 'enregistrer sans changement le dit');
  const polled = await bridge.request('snapshot');
  assert.equal(key(polled), key(first), 'un sondage ne recrée pas le message');
  const second = await bridge.request('memory.save', { config: {} });
  assert.ok(key(second));
  assert.notEqual(key(second), key(first), 'la seconde occurrence reçoit une nouvelle clé');
  await assert.rejects(
    bridge.request('memory.save', { config: { audit_log_enabled: true } }),
    /Clés non prises en charge ici : audit_log_enabled/,
  );
  assert.ok(calls.slice(before).every((c) => c.method === 'GET'));
});

test('un texte collé avec des séparateurs Unicode reste une seule requête et une seule réponse', async () => {
  // U+2028, U+2029 et U+0085 sont permis tels quels en JSON, mais beaucoup de lecteurs de lignes
  // y voient une fin de ligne : la requête ne doit pas être coupée, ni la réponse illisible.
  const separators = [0x2028, 0x2029, 0x85].map((code) => String.fromCharCode(code));
  const query = `avant${separators.join('milieu')}après`;
  const result = await bridge.request('section', { section: 'documents', query });
  assert.equal(result.data.query, query);
  const next = await bridge.request('snapshot');
  assert.equal(next.app.connected, true);
  await bridge.request('section', { section: 'documents', query: '' });
});
