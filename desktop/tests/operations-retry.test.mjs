import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

const bankPath = '/v1/default/banks/fixture';
const operationID = 'fixture-failed-operation';
const refusal = 'fixture-refusal-409: operation is not retryable';

async function withRetryFixture(t, run) {
  const calls = [];
  const unexpected = [];
  const state = { status: 'failed', refuseRetry: false };
  let command;
  let bridge;
  const server = createServer((request, response) => {
    const url = new URL(request.url, 'http://localhost');
    const call = {
      command,
      method: request.method,
      path: url.pathname,
      query: Object.fromEntries(url.searchParams),
    };
    calls.push(call);
    let code = 200;
    let data;
    if (request.method === 'GET' && url.pathname === '/health') {
      data = { status: 'healthy' };
    } else if (request.method === 'GET' && url.pathname === '/version') {
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
    } else if (request.method === 'GET' && url.pathname === '/v1/default/banks') {
      data = {
        banks: [
          {
            bank_id: 'fixture',
            name: 'Retry fixture',
            disposition: { skepticism: 3, literalism: 3, empathy: 3 },
          },
        ],
        total: 1,
        limit: 200,
        offset: 0,
      };
    } else if (request.method === 'GET' && url.pathname === `${bankPath}/stats`) {
      // Hindsight 1.2 caches this response; retries never update it in this fixture.
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
        failed_operations: 1,
        operations_by_status: { pending: 0, processing: 0, failed: 1, completed: 0 },
        pending_consolidation: 0,
        failed_consolidation: 0,
        total_observations: 0,
      };
    } else if (request.method === 'GET' && url.pathname === `${bankPath}/config`) {
      data = { bank_id: 'fixture', config: { enable_observations: true }, overrides: {} };
    } else if (request.method === 'GET' && url.pathname === `${bankPath}/operations`) {
      const limit = Number(url.searchParams.get('limit'));
      const offset = Number(url.searchParams.get('offset') || 0);
      const status = url.searchParams.get('status');
      // The only operation is a fact extraction: consolidation counters read none.
      const type = url.searchParams.get('type');
      const matching = (!status || status === state.status) && (!type || type === 'retain');
      data = {
        bank_id: 'fixture',
        total: matching ? 1 : 0,
        limit,
        offset,
        operations:
          matching && offset === 0
            ? [
                {
                  id: operationID,
                  task_type: 'retain',
                  operation_type: 'retain',
                  document_id: 'fixture-document',
                  status: state.status,
                  items_count: 1,
                  created_at: '2026-11-05T00:00:00Z',
                  error_message: state.status === 'failed' ? 'Fixture worker failure' : null,
                },
              ]
            : [],
      };
    } else if (
      request.method === 'POST' &&
      url.pathname === `${bankPath}/operations/${operationID}/retry` &&
      command === 'confirm'
    ) {
      if (state.refuseRetry) {
        code = 409;
        data = { detail: refusal };
      } else {
        state.status = 'pending';
        data = { success: true, operation_id: operationID, message: 'Fixture operation requeued' };
      }
    } else {
      unexpected.push(call);
      code = 501;
      data = { detail: 'Unexpected fixture request' };
    }
    response.writeHead(code, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(data));
  });
  const close = () => {
    bridge?.close();
    server.closeAllConnections();
    server.close();
  };
  t.signal.addEventListener('abort', close, { once: true });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
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
    const request = async (action, args = {}) => {
      command = action;
      const before = calls.length;
      const result = await bridge.request(action, { ...args, background: true });
      assert.deepEqual(unexpected, [], 'only explicit confirmations may write to the fake server');
      assert.ok(calls.length - before <= 12, `${action} uses a bounded number of requests`);
      assert.ok(calls.length <= 100, 'the one-operation scenario never scans unbounded pages');
      return result;
    };
    await request('server.url', { url: `http://127.0.0.1:${server.address().port}` });
    await run({ request, state, calls });
  } finally {
    t.signal.removeEventListener('abort', close);
    bridge?.close();
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

function assertFailedSnapshot(result, failed, pending) {
  assert.equal(result.section, 'operations');
  assert.equal(result.data.statusFilter, 'failed', 'retry and polling preserve the Failed tab');
  assert.equal(result.data.total, failed);
  assert.deepEqual(
    result.data.items.map((row) => ({ id: row.id, status: row.status })),
    failed ? [{ id: operationID, status: 'failed' }] : [],
  );
  assert.equal(result.data.counts?.failed, failed, 'failed count must not come from cached /stats');
  assert.equal(result.data.counts?.pending, pending);
  assert.equal(result.data.counts?.processing, 0);
  assert.equal(result.data.canLoadMore, false);
}

for (const mode of ['bulk', 'individual']) {
  test(
    `${mode} retry immediately reconciles counts with the list despite cached stats`,
    { timeout: 30000 },
    async (t) => {
      await withRetryFixture(t, async ({ request, state, calls }) => {
        const writes = () => calls.filter((call) => call.method !== 'GET');
        const retry = () =>
          request(
            mode === 'bulk' ? 'operations.retryFailed' : 'operation.retry',
            mode === 'bulk' ? {} : { id: operationID },
          );
        let result = await request('section', { section: 'operations', status: 'failed' });
        assertFailedSnapshot(result, 1, 0);

        result = await retry();
        assert.equal(result.confirmations.length, 1);
        assert.ok(result.confirmations[0].id);
        assert.deepEqual(writes(), [], 'preparing a retry never writes');
        const confirmation = result.confirmations[0].id;
        result = await request('snapshot');
        assert.equal(result.confirmations[0].id, confirmation);
        assert.deepEqual(writes(), [], 'reading a pending confirmation never executes it');

        result = await request('confirm', { id: confirmation });
        assert.equal(writes().length, 1);
        assert.equal(state.status, 'pending');
        // Assert the confirmation response itself, before any refresh or poll can hide the bug.
        assertFailedSnapshot(result, 0, 1);
        assert.deepEqual(result.confirmations, []);

        state.status = 'failed';
        const beforePoll = calls.length;
        result = await request('section', { section: 'operations', polling: true });
        assertFailedSnapshot(result, 1, 0);
        assert.deepEqual(result.confirmations, []);
        assert.ok(calls.slice(beforePoll).every((call) => call.method === 'GET'));
        assert.equal(writes().length, 1, 'quiet polling never automatically retries a failure');

        state.refuseRetry = true;
        result = await retry();
        assert.equal(result.confirmations.length, 1);
        assert.equal(writes().length, 1, 'the second retry also requires confirmation');
        result = await request('confirm', { id: result.confirmations[0].id });
        assert.equal(writes().length, 2);
        assert.equal(state.status, 'failed');
        assertFailedSnapshot(result, 1, 0);
        assert.deepEqual(result.confirmations, []);
        assert.ok(
          result.messages.some((message) => message.includes(refusal)),
          'the real bridge preserves the server refusal message',
        );

        // Another client resolves the operation while this screen still contains its failed row.
        state.status = 'completed';
        result = await request('operations.retryFailed');
        assertFailedSnapshot(result, 0, 0);
        assert.deepEqual(result.confirmations, []);
        assert.ok(result.messages.some((message) => message.includes('Aucune opération en échec')));
        assert.equal(writes().length, 2, 'an already-resolved retry refreshes without a POST');
        result = await request('section', { section: 'operations', polling: true });
        assertFailedSnapshot(result, 0, 0);
        assert.equal(writes().length, 2);

        const operationReads = calls.filter(
          (call) => call.method === 'GET' && call.path === `${bankPath}/operations`,
        );
        for (const call of operationReads) {
          assert.equal(call.query.offset ?? '0', '0', 'one operation never needs another page');
          assert.ok(['pending', 'processing', 'failed'].includes(call.query.status));
          if (call.query.status !== 'failed' || call.query.limit === '1') {
            assert.equal(call.query.limit, '1', 'global count probes fetch only one operation');
            // Mêmes lignes que la liste : les lots parents ne sont pas comptés en plus de leurs opérations.
            // (L'état de la consolidation lit seulement son type, qui n'a jamais de parent.)
            if (!call.query.type)
              assert.equal(call.query.exclude_parents, 'true', 'counts exclude parent operations');
            else assert.equal(call.query.type, 'consolidation');
          } else {
            assert.equal(call.query.limit, '100', 'only display/discovery reads fetch a full page');
          }
        }
        for (const status of ['pending', 'processing']) {
          assert.ok(
            operationReads.some((call) => call.query.status === status && call.query.limit === '1'),
            `${status} is counted with a lightweight list total`,
          );
        }
        assert.ok(
          calls
            .filter((call) => call.path === `${bankPath}/stats`)
            .every((call) => call.query.refresh !== 'true'),
          'never force-refresh cached bank stats',
        );
        assert.deepEqual(
          writes().map(({ command, method, path }) => ({ command, method, path })),
          [
            {
              command: 'confirm',
              method: 'POST',
              path: `${bankPath}/operations/${operationID}/retry`,
            },
            {
              command: 'confirm',
              method: 'POST',
              path: `${bankPath}/operations/${operationID}/retry`,
            },
          ],
        );
      });
    },
  );
}
