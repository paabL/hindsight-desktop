import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BridgeClient } from './support/bridge-client.mjs';

test('model diagram edits persist only after confirmation, without changing embeddings', async () => {
  let version = '1.2.0';
  const requests = [];
  const server = createServer((req, res) => {
    requests.push(req.method);
    res.setHeader('content-type', 'application/json');
    const features = Object.fromEntries(
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
    );
    res.end(
      JSON.stringify(
        req.url === '/version'
          ? { api_version: version, features }
          : req.url.startsWith('/v1/default/banks')
            ? { banks: [], total: 0 }
            : {},
      ),
    );
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const folder = await mkdtemp(path.join(tmpdir(), 'hs-model-workflow-'));
  const file = path.join(folder, 'start.sh');
  const original =
    '#!/bin/bash\nexport HINDSIGHT_API_REFLECT_LLM_PROVIDER=claude-code\nexport HINDSIGHT_API_REFLECT_LLM_MODEL=claude-sonnet-5-5\nexport HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL=gemini-embedding-2\nexport HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY=1536\nexport HINDSIGHT_API_DECISION_MODEL_PROVIDER=hindsight\nexport HINDSIGHT_API_DECISION_MODEL_BASE_URL=http://127.0.0.1:8766\nexport HINDSIGHT_API_DECISION_MODEL_API_KEY=fixture-private-key\nexec hindsight-api\n';
  await writeFile(file, original);
  let bridge;
  try {
    const prior = process.env.HINDSIGHT_DESKTOP_TEST_MODE;
    process.env.HINDSIGHT_DESKTOP_TEST_MODE = '1';
    try {
      bridge = new BridgeClient(
        fileURLToPath(new URL('../native/HindsightBridge', import.meta.url)),
      );
    } finally {
      if (prior == null) delete process.env.HINDSIGHT_DESKTOP_TEST_MODE;
      else process.env.HINDSIGHT_DESKTOP_TEST_MODE = prior;
    }
    const url = `http://127.0.0.1:${server.address().port}`;
    await bridge.request('server.url', { url });
    await bridge.request('server.script', { path: file });
    let result = await bridge.request('section', { section: 'model-settings' });
    assert.equal(result.app.bank, null, 'Quick model selection does not require a bank');
    const quickRevision = result.data.modelWorkflow.revision;
    result = await bridge.request('section', { section: 'server' });
    assert.equal(
      result.data.modelWorkflow.revision,
      quickRevision,
      'Management and quick selection share the same draft',
    );
    result = await bridge.request('section', { section: 'model-settings' });
    assert.equal(result.data.hindsightModels.serverIs120, true, result.app.connectionError);
    assert.equal(result.data.modelWorkflow.decisions.reflect.enabled, true);
    assert.equal(result.data.modelWorkflow.decisions.recall.enabled, false);
    assert.equal(JSON.stringify(result).includes('fixture-private-key'), false);
    assert.ok(result.data.providerChoices.some((choice) => choice.id === 'openai-codex'));
    assert.ok(
      result.data.modelsByProvider['claude-code'].some(
        (choice) => choice.id === 'claude-sonnet-5-5',
      ),
    );
    assert.ok(
      result.data.modelsByProvider['openai-codex'].every((choice) => !choice.id.includes('claude')),
    );
    const revision = result.data.modelWorkflow.revision;
    result = await bridge.request('server.models.prepare', {
      revision,
      changes: {
        HINDSIGHT_API_RECALL_DECISION_MODEL_PROVIDER: 'hindsight',
        HINDSIGHT_API_RECALL_DECISION_MODEL_PRUNE: 'true',
      },
    });
    assert.equal(result.data.modelWorkflow.decisions.recall.enabled, true);
    assert.equal(result.data.hasChanges, true);
    assert.equal(await readFile(file, 'utf8'), original);
    await assert.rejects(
      bridge.request('server.models.prepare', {
        revision,
        changes: { HINDSIGHT_API_REFLECT_LLM_MODEL: 'stale' },
      }),
      /changé/,
    );
    await assert.rejects(
      bridge.request('server.models.prepare', {
        revision: result.data.modelWorkflow.revision,
        changes: { HINDSIGHT_API_EMBEDDINGS_GEMINI_MODEL: 'wrong' },
      }),
      /avancées/,
    );
    result = await bridge.request('server.save');
    assert.equal(await readFile(file, 'utf8'), original);
    const id = result.confirmations[0].id;
    result = await bridge.request('confirm', { id, typed: '' });
    const saved = await readFile(file, 'utf8');
    assert.match(saved, /RECALL_DECISION_MODEL_PROVIDER=hindsight/);
    assert.deepEqual(
      saved.split('\n').filter((line) => line.includes('EMBEDDINGS_')),
      original.split('\n').filter((line) => line.includes('EMBEDDINGS_')),
    );
    assert.match(saved, /fixture-private-key/);
    assert.equal(result.data.needsRestart, true);
    await assert.rejects(bridge.request('confirm', { id, typed: '' }), /expiré/);
    const codexModel = result.data.modelsByProvider['openai-codex'][0].id;
    await bridge.request('server.provider', { role: 'reflect', provider: 'openai-codex' });
    result = await bridge.request('server.field', {
      name: 'HINDSIGHT_API_REFLECT_LLM_MODEL',
      value: codexModel,
    });
    assert.equal(result.data.modelWorkflow.identities.reflect.provider, 'openai-codex');
    assert.equal(result.data.modelWorkflow.identities.reflect.model, codexModel);
    assert.equal(await readFile(file, 'utf8'), saved, 'Menu preparation does not save the script');
    await bridge.request('server.revert');
    version = '1.1.0';
    await bridge.request('server.url', { url });
    result = await bridge.request('section', { section: 'server' });
    await assert.rejects(
      bridge.request('server.models.prepare', {
        revision: result.data.modelWorkflow.revision,
        changes: { HINDSIGHT_API_REFLECT_USE_DECISION_MODEL: 'false' },
      }),
      /1\.2\.0/,
    );
    assert.ok(
      requests.every((method) => method === 'GET'),
      'No memory writes or model calls',
    );
  } finally {
    bridge?.close();
    await new Promise((resolve) => server.close(resolve));
    await rm(folder, { recursive: true, force: true });
  }
});
