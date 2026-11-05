// Runs only against an explicit disposable fixture and a local, read-only fake server.
import { createServer } from 'node:http';
import { readFile, writeFile, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { BridgeClient } from '../tests/support/bridge-client.mjs';
import { mergeSourceSnapshot } from '../src/source-snapshot.ts';

const [executable, folder, output, liveURL, bank = 'fixture', mode] = process.argv.slice(2);
if (!executable || !folder?.startsWith('/tmp/hindsight-sources-bench/'))
  throw new Error('Explicit disposable benchmark fixture required');
if (liveURL && !['127.0.0.1', 'localhost'].includes(new URL(liveURL).hostname))
  throw new Error('Local read-only server required');
const originals = await Promise.all(
  ['collection/.memory-workspace.json', 'memory-policy.json'].map(async (relative) => ({
    file: path.join(folder, relative),
    bytes: await readFile(path.join(folder, relative)).catch(() => null),
  })),
);
const catalog = JSON.parse(await readFile(path.join(folder, 'collection/catalog.json'), 'utf8'));
const docs = catalog.records.map((r) => ({
  id: `source:${r.id}`,
  content_hash: 'different',
  document_metadata: { source_record_id: r.id },
  updated_at: '2026-11-04T12:00:00Z',
}));
const calls = [];
const server = createServer(async (req, res) => {
  calls.push(req.method);
  if (req.method !== 'GET') {
    res.writeHead(405).end();
    return;
  }
  if (liveURL) {
    try {
      const upstream = await fetch(new URL(req.url, liveURL));
      res.writeHead(upstream.status, { 'content-type': 'application/json' });
      res.end(Buffer.from(await upstream.arrayBuffer()));
    } catch {
      res.writeHead(502).end('{}');
    }
    return;
  }
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
      banks: [
        {
          bank_id: 'fixture',
          name: 'Fixture',
          fact_count: 1,
          disposition: { skepticism: 3, literalism: 3, empathy: 3 },
        },
      ],
      total: 1,
      limit: 200,
      offset: 0,
    };
  else if (url.pathname.endsWith('/documents')) {
    const offset = Number(url.searchParams.get('offset') || 0),
      limit = Number(url.searchParams.get('limit') || 1000);
    data = { items: docs.slice(offset, offset + limit), total: docs.length, offset, limit };
  }
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(data));
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
const bridge = new BridgeClient(executable),
  samples = [];
let snapshot;
async function measure(name, command, args = {}) {
  const start = performance.now(),
    result = await bridge.request(command, { ...args, sourceRevision: snapshot?.catalogRevision }),
    ms = performance.now() - start;
  if (result.data?.error && !result.data.error.includes('Connectez'))
    throw new Error(result.data.error);
  samples.push({
    name,
    ms: Math.round(ms * 100) / 100,
    bytes: Buffer.byteLength(JSON.stringify(result)),
    rssMB:
      Number(
        execFileSync('ps', ['-o', 'rss=', '-p', String(bridge.pid)], { encoding: 'utf8' }).trim(),
      ) / 1024,
  });
  if (result.section === 'sources') {
    result.data = mergeSourceSnapshot(snapshot, result.data);
    snapshot = result.data;
  }
  return result;
}
try {
  await bridge.request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
  await bridge.request('bank.select', { id: bank });
  const started = performance.now();
  let result = await measure('open', 'folder.choose', {
    path: folder,
    background: mode === 'progressive',
  });
  let visibleMs = result.data.catalog?.records?.length ? performance.now() - started : null;
  while (result.data.refreshing) {
    await new Promise((resolve) => setTimeout(resolve, 20));
    result = await bridge.request('snapshot', { sourceRevision: snapshot?.catalogRevision });
    result.data = mergeSourceSnapshot(snapshot, result.data);
    snapshot = result.data;
    if (visibleMs == null && result.data.catalog?.records?.length)
      visibleMs = performance.now() - started;
    if (performance.now() - started > 60_000) throw new Error('Source verification did not finish');
  }
  const verifiedMs = performance.now() - started;
  const rows = result.data.catalog.records;
  const target = rows.find(
    (r) => r.memory?.enabled && !r.memory.locked && !r.id.startsWith('bank:'),
  );
  if (!target) throw new Error('No editable fixture source');
  const semantic = createHash('sha256')
    .update(
      JSON.stringify(
        rows
          .map((r) => [
            r.id,
            Object.fromEntries(
              Object.entries(r.memory || {}).sort(([a], [b]) => a.localeCompare(b)),
            ),
          ])
          .sort((a, b) => a[0].localeCompare(b[0])),
      ),
    )
    .digest('hex');
  for (let i = 0; i < 3; i++) await measure('refresh', 'section', { section: 'sources' });
  for (let i = 0; i < 3; i++) {
    await measure('toggle-off', 'folder.enabled', { id: target.id, enabled: false });
    await measure('toggle-on', 'folder.enabled', { id: target.id, enabled: true });
  }
  const report = {
    records: rows.length,
    visibleMs: Math.round(visibleMs || 0),
    verifiedMs: Math.round(verifiedMs),
    semantic,
    samples,
    readOnlyServer: calls.every((m) => m === 'GET'),
    server: liveURL ? 'live-read-only-proxy' : 'fixture',
    binarySHA256: createHash('sha256')
      .update(await readFile(executable))
      .digest('hex'),
  };
  // Optional state diff for synthetic fixtures only; never export document text.
  if (!liveURL && process.env.HINDSIGHT_BENCH_STATE_OUTPUT) {
    const stateFile = path.resolve(process.env.HINDSIGHT_BENCH_STATE_OUTPUT);
    if (!stateFile.startsWith('/tmp/hindsight-sources-bench/'))
      throw new Error('Synthetic state output must stay in the disposable benchmark directory');
    await writeFile(
      stateFile,
      JSON.stringify(
        rows.map((row) => ({ id: row.id, memory: row.memory })),
        null,
        2,
      ),
    );
  }
  await writeFile(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
} finally {
  bridge.close();
  await new Promise((resolve) => server.close(resolve));
  for (const { file, bytes } of originals) {
    if (bytes) await writeFile(file, bytes);
    else await rm(file, { force: true });
  }
}
