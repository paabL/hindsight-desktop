import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

test(
  'operation polling preserves the selected filter and opened pages',
  { timeout: 30000 },
  async () => {
    const calls = [];
    const server = createServer((request, response) => {
      const url = new URL(request.url, 'http://localhost');
      calls.push({
        method: request.method,
        path: url.pathname,
        status: url.searchParams.get('status'),
      });
      let data = {};
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
          banks: [
            {
              bank_id: 'fixture',
              name: 'Fixture',
              disposition: { skepticism: 3, literalism: 3, empathy: 3 },
            },
          ],
          total: 1,
          limit: 200,
          offset: 0,
        };
      else if (url.pathname.endsWith('/stats'))
        data = {
          bank_id: 'fixture',
          total_nodes: 0,
          total_links: 0,
          total_documents: 0,
          nodes_by_fact_type: {},
          links_by_link_type: {},
          links_by_fact_type: {},
          links_breakdown: {},
          pending_operations: 0,
          failed_operations: 225,
          operations_by_status: { failed: 225, completed: 0 },
          pending_consolidation: 0,
          failed_consolidation: 0,
          total_observations: 0,
        };
      else if (url.pathname.endsWith('/operations')) {
        const offset = Number(url.searchParams.get('offset') || 0);
        const limit = Number(url.searchParams.get('limit') || 100);
        const status = url.searchParams.get('status') || 'completed';
        data = {
          bank_id: 'fixture',
          total: 225,
          offset,
          limit,
          operations: Array.from({ length: Math.min(limit, 225 - offset) }, (_, i) => ({
            id: `op-${i + offset}`,
            task_type: 'retain',
            status,
            items_count: 1,
            created_at: '2026-11-04T12:00:00Z',
          })),
        };
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
      await bridge.request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
      let result = await bridge.request('section', { section: 'operations', status: 'failed' });
      assert.equal(result.data.items.length, 100);
      assert.ok(result.data.items.every((row) => row.status === 'failed'));
      result = await bridge.request('operations.more');
      assert.equal(result.data.items.length, 200);
      result = await bridge.request('section', { section: 'operations', polling: true });
      assert.ok(result.data.items.every((row) => row.status === 'failed'));
      assert.equal(result.data.items.length, 200);
      assert.equal(result.data.statusFilter, 'failed');
      result = await bridge.request('operations.more');
      assert.equal(result.data.items.length, 225);
      assert.equal(result.data.canLoadMore, false);
      assert.equal(new Set(result.data.items.map((row) => row.id)).size, 225);
      assert.ok(
        calls
          .filter((call) => call.path.endsWith('/operations'))
          .every((call) => call.status === 'failed'),
      );
      assert.ok(
        calls.every((call) => call.method === 'GET'),
        'polling never starts or retries work',
      );
    } finally {
      bridge?.close();
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
  },
);
