import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

// Sources d'une banque : ses dossiers, ordinaires ou à catalogue, jamais ceux d'une autre banque.
test('each memory bank lists only its own folders and opens a catalog only in its bank', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'hs-sources-folders-'));
  const notes = path.join(root, 'garden-notes');
  const archive = path.join(root, 'garden-archive');
  await mkdir(notes);
  await writeFile(path.join(notes, 'semis.md'), '# Semis de printemps\n');
  await writeFile(path.join(notes, 'arrosage.py'), 'print("pas un document")\n');
  await mkdir(path.join(archive, 'collection'), { recursive: true });
  await writeFile(
    path.join(archive, 'collection/catalog.json'),
    JSON.stringify({
      version: 1,
      mode: 'collection_only',
      generated_at: '2026-10-29T18:30:00Z',
      records: [
        { id: 'one', title: 'Récolte' },
        { id: 'two', title: 'Taille', context: { conversation_kind: 'empty_export' } },
      ],
    }),
  );
  await writeFile(path.join(archive, 'collect.py'), '# collecteur fictif\n');
  await writeFile(path.join(archive, 'notes.md'), '# Notes du dépôt\n');
  await writeFile(
    path.join(archive, 'memory-policy.json'),
    JSON.stringify({
      version: 1,
      bank_id: 'garden',
      excluded_document_ids: {},
      deferred_document_ids: {},
    }),
  );
  const writes = [];
  const server = createServer((req, res) => {
    if (req.method !== 'GET') writes.push(`${req.method} ${req.url}`);
    const url = new URL(req.url, 'http://localhost');
    let data = { items: [], total: 0, limit: 1000, offset: 0, operations: [] };
    if (url.pathname === '/version')
      data = {
        api_version: '1.2.0',
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
          ].map((key) => [key, false]),
        ),
      };
    else if (url.pathname === '/v1/default/banks')
      data = {
        banks: ['garden', 'kitchen'].map((bank_id) => ({
          bank_id,
          fact_count: 0,
          disposition: { skepticism: 3, literalism: 3, empathy: 3 },
        })),
        total: 2,
        limit: 200,
        offset: 0,
      };
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(data));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
  const bridge = new BridgeClient(
    fileURLToPath(new URL('../native/HindsightBridge', import.meta.url)),
  );
  try {
    await bridge.request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
    let result = await bridge.request('section', { section: 'sources' });
    assert.equal(result.app.bank, 'garden');
    assert.deepEqual(result.data.folders, []);
    assert.equal(result.data.openKind, null);

    // Deux dossiers dans « garden » : un dossier ordinaire et un dépôt dont le catalogue appartient à « garden ».
    await bridge.request('coverage.add', { paths: [notes] });
    await bridge.request('coverage.add', { paths: [archive] });
    result = await bridge.request('section', { section: 'sources' });
    const rows = Object.fromEntries(result.data.folders.map((row) => [row.name, row]));
    assert.equal(rows['garden-notes'].kind, 'folder');
    assert.equal(rows['garden-notes'].files, 1, 'seuls les documents sont comparés');
    assert.equal(rows['garden-notes'].toSend, 1);
    assert.equal(rows['garden-archive'].kind, 'catalog');
    assert.equal(rows['garden-archive'].sources, 1, 'les archives à part ne comptent pas');
    assert.equal(rows['garden-archive'].catalogBank, 'garden');
    assert.equal(rows['garden-archive'].files, undefined, 'un catalogue passe par son catalogue');

    // Un dossier ordinaire ouvert montre ses fichiers ; aucun catalogue n'est ouvert.
    result = await bridge.request('folder.choose', { path: notes });
    assert.equal(result.data.openKind, 'folder');
    assert.equal(result.app.folder, null);
    assert.deepEqual(
      result.data.items.map((item) => [item.title, item.state, item.canSend]),
      [['semis.md', 'notSent', true]],
    );
    result = await bridge.request('folder.close');
    assert.equal(result.data.openKind, null);

    // Le dépôt s'ouvre sur son catalogue dans sa banque.
    result = await bridge.request('folder.choose', { path: archive });
    assert.equal(result.data.openKind, 'catalog');
    assert.equal(result.app.folder, archive);
    assert.deepEqual(
      result.data.catalog.records.map((record) => record.id),
      ['one', 'two'],
    );

    // « kitchen » ne voit aucun dossier de « garden ».
    result = await bridge.request('bank.select', { id: 'kitchen' });
    assert.equal(result.app.folder, null);
    result = await bridge.request('section', { section: 'sources' });
    assert.deepEqual(result.data.folders, []);
    assert.equal(result.data.openKind, null);

    // Suivi dans « kitchen », le dépôt de « garden » est un dossier ordinaire : ses fichiers sont comparés.
    await bridge.request('coverage.add', { paths: [archive] });
    result = await bridge.request('section', { section: 'sources' });
    assert.equal(result.data.folders[0].kind, 'folder');
    result = await bridge.request('folder.choose', { path: archive });
    assert.equal(result.data.openKind, 'folder');
    assert.deepEqual(
      result.data.items.map((item) => item.title),
      ['notes.md'],
    );
    await bridge.request('coverage.removeRoot', { id: archive });
    result = await bridge.request('section', { section: 'sources' });
    assert.equal(result.data.openKind, null, 'ne plus suivre le dossier ouvert ramène à la liste');
    assert.deepEqual(result.data.folders, []);

    // « garden » a gardé ses deux dossiers ; rien n'a été envoyé.
    await bridge.request('bank.select', { id: 'garden' });
    result = await bridge.request('section', { section: 'sources' });
    assert.deepEqual(
      result.data.folders.map((row) => row.name),
      ['garden-notes', 'garden-archive'],
    );
    await assert.rejects(
      bridge.request('folder.choose', { path: path.join(root, 'absent') }),
      /introuvable/,
    );
    assert.deepEqual(writes, []);
  } finally {
    bridge.close();
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});
