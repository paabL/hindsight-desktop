import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

test('Hindsight 1.2 : recall, réglages confirmés et statistiques traversent le pont', async () => {
  let version = '1.2.0';
  const calls = [];
  const config = { recall_decision_model_prune: true, reflect_use_decision_model: true };
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, 'http://localhost');
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const text = Buffer.concat(chunks).toString();
    const body = text ? JSON.parse(text) : null;
    calls.push({ method: request.method, path: url.pathname, query: url.searchParams, body });
    let data = {};
    if (url.pathname === '/version') {
      data = {
        api_version: version,
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
          ].map((key) => [key, key === 'llm_trace' || key === 'bank_config_api']),
        ),
      };
    } else if (url.pathname === '/v1/default/banks') {
      data = {
        banks: [
          {
            bank_id: 'fixture',
            name: 'Test 1.2',
            disposition: { skepticism: 3, literalism: 3, empathy: 3 },
          },
        ],
        total: 1,
        limit: 200,
        offset: 0,
      };
    } else if (url.pathname.endsWith('/config')) {
      if (request.method === 'PATCH') Object.assign(config, body.updates);
      data = { bank_id: 'fixture', config, overrides: {} };
    } else if (url.pathname.endsWith('/memories/recall')) {
      data = { results: [] };
    } else if (url.pathname.endsWith('/llm-requests/stats')) {
      const model = {
        decision: 'hs-decide-1-flash',
        rerank: 'hs-rerank-1',
        embedding: 'hs-embed-1',
      }[url.searchParams.get('call_type')];
      data = {
        bank_id: 'fixture',
        period: '7d',
        trunc: 'day',
        start: '',
        buckets: [
          {
            time: '',
            statuses: { success: 1 },
            total: 1,
            tokens: { input: 1000000, output: 0, cached: 0, total: 1000000 },
            series: { [model]: { calls: 1, tokens: 1000000 } },
          },
        ],
      };
    } else if (url.pathname.endsWith('/llm-requests')) {
      data = { items: [], total: 0, limit: 1000, offset: 0 };
    } else if (url.pathname.endsWith('/operations')) {
      data = { operations: [], total: 0, limit: 100, offset: 0 };
    }
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(data));
  });
  let bridge;
  try {
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const previous = process.env.HINDSIGHT_DESKTOP_TEST_MODE;
    process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
    try {
      bridge = new BridgeClient(
        fileURLToPath(new URL('../native/HindsightBridge', import.meta.url)),
      );
    } finally {
      if (previous == null) delete process.env.HINDSIGHT_DESKTOP_TEST_MODE;
      else process.env.HINDSIGHT_DESKTOP_TEST_MODE = previous;
    }
    const url = `http://127.0.0.1:${server.address().port}`;
    await bridge.request('server.url', { url });
    let result = await bridge.request('section', { section: 'search' });
    assert.equal(result.data.serverIs120, true);
    await bridge.request('search', { query: 'Test', prune: false, dedup: true });
    const recalls = () => calls.filter((c) => c.path.endsWith('/memories/recall'));
    assert.deepEqual(recalls().at(-1).body.rerank, { prune: false, dedup: true });
    await bridge.request('search', { query: 'Défauts' });
    assert.equal(recalls().at(-1).body.rerank, undefined);

    await bridge.request('section', { section: 'memory' });
    const patches = () => calls.filter((c) => c.method === 'PATCH');
    result = await bridge.request('memory.save', {
      config: {
        recall_decision_model_prune: false,
        reflect_use_decision_model: false,
      },
    });
    assert.equal(patches().length, 0);
    assert.equal(result.confirmations.length, 1);
    const id = result.confirmations[0].id;
    await bridge.request('confirm', { id, typed: '' });
    assert.equal(patches().length, 1);
    assert.deepEqual(patches()[0].body.updates, {
      recall_decision_model_prune: false,
      reflect_use_decision_model: false,
    });
    await assert.rejects(bridge.request('confirm', { id, typed: '' }), /expiré/);

    result = await bridge.request('section', { section: 'consumption' });
    assert.deepEqual(
      result.data.services.map((s) => s.dollars),
      [0.02, 0.015, 0.005],
    );
    assert.equal(result.data.servicesError, null);
    const stats = () => calls.filter((c) => c.path.endsWith('/llm-requests/stats'));
    assert.equal(stats().length, 3);
    assert.ok(stats().every((c) => c.query.get('split_by') === 'model'));

    version = '1.1.0';
    await bridge.request('server.url', { url });
    result = await bridge.request('section', { section: 'search' });
    assert.equal(result.data.serverIs120, false);
    await bridge.request('search', { query: 'Ancien serveur', prune: true, dedup: false });
    assert.equal(recalls().at(-1).body.rerank, undefined);
    result = await bridge.request('section', { section: 'consumption' });
    assert.deepEqual(result.data.services, []);
    assert.equal(stats().length, 3, 'aucun split_by sur le serveur 1.1');
  } finally {
    bridge?.close();
    await new Promise((resolve) => server.close(resolve));
  }
});
