import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, mkdir, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

test('slow Sources loads and collection keep navigation responsive and cannot cross banks', async () => {
  const folder = await mkdtemp(path.join(tmpdir(), 'hs-sources-background-'));
  await mkdir(path.join(folder, 'collection'));
  await writeFile(path.join(folder, 'collection/source.md'), '# Test source\n');
  await writeFile(
    path.join(folder, 'collection/catalog.json'),
    JSON.stringify({
      version: 1,
      mode: 'collection_only',
      records: [{ id: 'source', title: 'Source', files: { 'document.md': 'source.md' } }],
    }),
  );
  await writeFile(
    path.join(folder, 'collect.py'),
    'import time\nfrom pathlib import Path\ntime.sleep(0.7)\nPath("collected").write_text("done")\n',
  );
  let hold = false,
    held = [],
    calls = [];
  const server = createServer((req, res) => {
    calls.push(req.method);
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
          ].map((k) => [k, false]),
        ),
      };
    else if (url.pathname === '/v1/default/banks')
      data = {
        banks: ['first', 'second'].map((bank_id) => ({
          bank_id,
          fact_count: 0,
          disposition: { skepticism: 3, literalism: 3, empathy: 3 },
        })),
        total: 2,
        limit: 200,
        offset: 0,
      };
    else if (url.pathname.endsWith('/documents')) {
      const first = url.pathname.includes('/first/');
      data = {
        items: [{ id: first ? 'only-first' : 'only-second', content_hash: 'hash' }],
        total: 1,
        limit: 1000,
        offset: 0,
      };
      if (hold && first) {
        held.push(() => res.end(JSON.stringify(data)));
        return;
      }
    }
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(data));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
  const bridge = new BridgeClient(
    fileURLToPath(new URL('../native/HindsightBridge', import.meta.url)),
  );
  async function bounded(promise) {
    let timer;
    try {
      return await Promise.race([
        promise,
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error('Source task blocked navigation')), 3000);
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }
  try {
    await bridge.request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
    hold = true;
    let result = await bounded(bridge.request('folder.choose', { path: folder, background: true }));
    assert.equal(result.data.catalog.records[0].title, 'Source');
    assert.equal(result.data.catalog.records[0].memory.state, 'unknown');
    assert.equal(result.data.catalog.records[0].memory.locked, true);
    assert.equal(result.data.refreshing, true);
    result = await bounded(bridge.request('snapshot'));
    assert.equal(result.data.refreshing, true);
    const revision = result.data.catalogRevision;
    result = await bounded(bridge.request('snapshot', { sourceRevision: revision }));
    assert.equal(result.data.catalogUnchanged, true);
    assert.ok(Buffer.byteLength(JSON.stringify(result)) < 10_000);
    assert.equal(
      (await bounded(bridge.request('section', { section: 'settings' }))).section,
      'settings',
    );
    await bounded(bridge.request('bank.select', { id: 'second' }));
    held.forEach((release) => release());
    held = [];
    // Chaque banque a ses sources : changer de banque referme le catalogue et montre ses dossiers.
    result = await bounded(bridge.request('section', { section: 'sources', background: true }));
    assert.equal(result.data.openKind, null);
    assert.equal(result.app.folder, null);
    assert.deepEqual(result.data.folders, []);
    assert.equal(result.data.listBank, 'second');
    // Un catalogue sans banque déclarée s'ouvre dans la banque qui le consulte, avec ses seuls documents.
    result = await bounded(bridge.request('folder.choose', { path: folder, background: true }));
    assert.equal(result.data.openKind, 'catalog');
    for (let i = 0; i < 100 && result.data.refreshing; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
      result = await bounded(bridge.request('snapshot'));
    }
    assert.equal(result.data.refreshing, false);
    assert.ok(result.data.catalog.records.some((r) => r.id === 'bank:only-second'));
    assert.ok(!result.data.catalog.records.some((r) => r.id === 'bank:only-first'));
    const callCount = calls.length;
    result = await bounded(bridge.request('folder.refresh', { background: true }));
    assert.equal(result.data.collecting, true);
    assert.equal(
      (await bounded(bridge.request('section', { section: 'settings' }))).section,
      'settings',
    );
    await assert.rejects(readFile(path.join(folder, 'collected')), { code: 'ENOENT' });
    result = await bridge.request('section', { section: 'sources', background: true });
    for (let i = 0; i < 100 && result.data.collecting; i++) {
      await new Promise((resolve) => setTimeout(resolve, 20));
      result = await bounded(bridge.request('snapshot'));
    }
    assert.equal(result.data.collecting, false);
    assert.equal(await readFile(path.join(folder, 'collected'), 'utf8'), 'done');
    assert.equal(calls.length, callCount, 'Collection never contacts Hindsight');
    assert.ok(calls.every((method) => method === 'GET'));
  } finally {
    held.forEach((release) => release());
    bridge.close();
    await new Promise((resolve) => server.close(resolve));
    await rm(folder, { recursive: true, force: true });
  }
});
