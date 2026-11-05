// Synthetic diagnostics only. Run: node desktop/tests/graph-stress.mjs
// Reproduce the previous failure: node desktop/tests/graph-stress.mjs --baseline
// Uses its own Vite port (16467 by default), no app bridge, server, LLM or personal documents.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { chromium, expect } from '@playwright/test';
import { createServer } from 'vite';
import {
  analyzeGraph,
  cleanGraph,
  layoutGraph,
  neighborhood,
  shortestPath,
} from '../src/graph-model.ts';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.HINDSIGHT_GRAPH_STRESS_PORT || 16467);
assert.ok(Number.isInteger(port) && port >= 16460 && port <= 65535);
const origin = `http://127.0.0.1:${port}`;
const baseline = process.argv.includes('--baseline');
const baselineSource = baseline
  ? execFileSync('git', ['show', 'HEAD:desktop/src/pages/Graph.tsx'], {
      cwd: root,
      encoding: 'utf8',
    })
  : null;
const report = {
  kind: 'synthetic diagnostics, not comparative benchmarks',
  baseline,
  models: [],
  checks: [],
};
const nodes = Array.from({ length: 1000 }, (_, i) => ({
  id: `n${i}`,
  label: `Node ${String(i).padStart(4, '0')}`,
  detail: `Synthetic topic ${i}. ` + 'Synthetic context. '.repeat(60),
  weight: 20,
  kind: 'entity',
}));
const edge = (a, b, weight = 20, kind = 'cooccurrence') => ({
  source: `n${a}`,
  target: `n${b}`,
  weight,
  kind,
});
const dense = [];
for (let group = 0; group < 20; group++) {
  for (let a = 0; a < 50; a++)
    for (let b = a + 1; b < 50; b++) dense.push(edge(group * 50 + a, group * 50 + b));
  if (group) dense.push(edge((group - 1) * 50, group * 50, 1, 'temporal'));
}
const chain = nodes.slice(1).map((_, i) => edge(i, i + 1));
const star = nodes.slice(1).map((_, i) => edge(0, i + 1));
for (const [name, rawNodes, rawEdges] of [
  ['empty', [], []],
  ['1000 isolated', nodes, []],
  ['1000 chain', nodes, chain],
  ['1000 star', nodes, star],
  ['1000 nodes / 24519 links', nodes, dense],
]) {
  const start = performance.now();
  const cleaned = cleanGraph(rawNodes, rawEdges);
  const graph = analyzeGraph(cleaned.nodes, cleaned.edges);
  const layout = layoutGraph(graph);
  assert.equal(graph.nodes.length, rawNodes.length);
  assert.equal(graph.edges.length, rawEdges.length);
  assert.equal(layout.positions.size, rawNodes.length);
  for (const p of layout.positions.values())
    assert.ok(Number.isFinite(p.x) && Number.isFinite(p.y));
  if (name.includes('chain')) assert.equal(shortestPath(graph, 'n0', 'n999').length, 1000);
  if (name.includes('star')) assert.equal(neighborhood(graph, 'n0', 1).size, 1000);
  if (rawEdges === dense) {
    assert.equal(graph.communities.length, 20);
    assert.equal(shortestPath(graph, 'n0', 'n999').length, 21);
    const filtered = analyzeGraph(
      graph.nodes,
      graph.edges.filter((e) => e.kind !== 'temporal'),
    );
    assert.deepEqual(shortestPath(filtered, 'n0', 'n999'), []);
  }
  report.models.push({
    name,
    elapsedMs: Math.round(performance.now() - start),
    nodes: rawNodes.length,
    edges: rawEdges.length,
  });
}

const fixture = {
  mode: 'entities',
  limit: 1000,
  nodes,
  edges: dense,
  totalNodes: 25000,
  selectedNodeID: null,
  nodeFacts: [],
};
const harness = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import Graph from '/src/pages/Graph.tsx';
import '/src/tokens.css';
import '/src/styles.css';
const fixture = ${JSON.stringify(fixture)};
let pending = [], next = 0;
function Harness() {
  const [data, setData] = useState(fixture);
  const [generation, setGeneration] = useState(0);
  const run = (command, args) => new Promise((resolve, reject) => {
    pending.push({ key: next++, command, args, resolve, reject });
  });
  window.readStress = {
    pending: () => pending.map(({ key, command, args }) => ({ key, command, args })),
    resolve: (key, count = 1) => {
      const request = pending.find((r) => r.key === key);
      if (!request) throw new Error('Missing synthetic request ' + key);
      pending = pending.filter((r) => r !== request);
      if (request.command === 'graph.select') {
        const nodeID = request.args.id;
        const snapshot = { ...fixture, selectedNodeID: nodeID, nodeFacts: Array.from({ length: count }, (_, i) => ({
          id: nodeID + '-fact-' + i, text: 'Accepted ' + nodeID + ' fact ' + i,
          type: 'world', documentID: nodeID + '-document',
        })) };
        setData(snapshot);
        request.resolve({ data: snapshot });
      } else if (request.command === 'document.open') {
        request.resolve({ document: { id: request.args.id }, text: 'Synthetic document. No private data.', facts: [] });
      } else request.resolve({});
    },
    reject: (key) => {
      const request = pending.find((r) => r.key === key);
      pending = pending.filter((r) => r !== request);
      request.reject(new Error('Synthetic rejected read'));
    },
    reset: () => { pending = []; setData(fixture); setGeneration((g) => g + 1); },
  };
  return React.createElement(Graph, { key: generation, data, run, busy: false,
    refresh: async () => ({}), notify: () => {}, navigate: () => {}, demo: false });
}
createRoot(document.getElementById('root')).render(React.createElement(Harness));
`;

const server = await createServer({
  root,
  logLevel: 'error',
  server: { host: '127.0.0.1', port, strictPort: true, watch: null },
  plugins: [
    {
      name: 'synthetic-read-stress',
      enforce: 'pre',
      resolveId(id) {
        if (id === '/read-stress-harness.js') return '\0read-stress-harness';
      },
      load(id) {
        if (id === '\0read-stress-harness') return harness;
      },
      transform(code, id) {
        if (baselineSource && id.split('?')[0] === root + 'src/pages/Graph.tsx')
          return baselineSource;
      },
      configureServer(vite) {
        vite.middlewares.use(async (req, res, next) => {
          if (req.url !== '/read-stress.html') return next();
          try {
            const html = await vite.transformIndexHtml(
              '/read-stress.html',
              '<html lang="fr" data-theme="dark"><head><meta charset="utf-8"></head><body><div id="root"></div><script type="module" src="/read-stress-harness.js"></script></body></html>',
            );
            res.setHeader('Content-Type', 'text/html');
            res.end(html);
          } catch (error) {
            next(error);
          }
        });
      },
    },
  ],
});
let browser;
const errors = [];
async function check(name, callback) {
  const start = performance.now();
  try {
    await callback();
    report.checks.push({ name, passed: true, elapsedMs: Math.round(performance.now() - start) });
  } catch (error) {
    report.checks.push({ name, passed: false, error: error.message.slice(0, 600) });
  }
}

try {
  await server.listen();
  const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.HINDSIGHT_BROWSER_EXECUTABLE || (existsSync(chrome) ? chrome : undefined),
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 }, locale: 'fr-CA' });
  await page.route('**/*', (route) =>
    new URL(route.request().url()).origin === origin ? route.continue() : route.abort(),
  );
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  const start = performance.now();
  await page.goto(origin + '/read-stress.html');
  await expect(page.locator('.atlas-aggregate')).toHaveCount(20);
  report.firstMapMs = Math.round(performance.now() - start);

  async function choose(index) {
    await page
      .getByRole('textbox', { name: 'Rechercher dans le graphe' })
      .fill(`Node ${String(index).padStart(4, '0')}`);
    await page.locator('.atlas-inspector .atlas-node-row').click();
    return page.evaluate(
      () =>
        window.readStress
          .pending()
          .filter((r) => r.command === 'graph.select')
          .at(-1).key,
    );
  }
  const resolve = (key, count = 1) =>
    page.evaluate(({ key, count }) => window.readStress.resolve(key, count), { key, count });
  const reset = async () => {
    await page.evaluate(() => window.readStress.reset());
    await expect(page.locator('.atlas-aggregate')).toHaveCount(20);
  };
  const factsTab = () => page.getByRole('tab', { name: 'Faits & sources', exact: true }).click();

  await check(
    '1000 nodes, bounded links, all 50 facts, stable layout, path and filters',
    async () => {
      await page.getByRole('button', { name: 'Zoomer le graphe', exact: true }).click();
      await page.getByRole('button', { name: 'Zoomer le graphe', exact: true }).click();
      await expect(page.locator('.atlas-node')).toHaveCount(1000);
      assert.ok((await page.locator('.atlas-edges path').count()) <= 1800);
      const positions = await page
        .locator('.atlas-node')
        .evaluateAll((ns) => ns.map((n) => n.getAttribute('transform')));
      const key = await choose(0);
      await resolve(key, 50);
      await factsTab();
      for (let count = 10; count < 50; count += 10) {
        await expect(page.locator('.atlas-fact')).toHaveCount(count);
        await page.getByRole('button', { name: 'Afficher 10 faits de plus', exact: true }).click();
      }
      await expect(page.locator('.atlas-fact')).toHaveCount(50);
      assert.deepEqual(
        await page
          .locator('.atlas-node')
          .evaluateAll((ns) => ns.map((n) => n.getAttribute('transform'))),
        positions,
      );
      await page.getByRole('button', { name: 'Relier à…', exact: true }).click();
      const target = await choose(999);
      await resolve(target);
      await expect(page.locator('.atlas-path-steps button')).toHaveCount(21);
      await page.getByRole('button', { name: 'Filtres', exact: true }).click();
      await page
        .getByRole('combobox', { name: 'Nature des liens', exact: true })
        .selectOption('cooccurrence');
      await expect(page.locator('.atlas-route-bar')).toContainText('Aucun chemin');
      await page
        .getByRole('combobox', { name: 'Nature des liens', exact: true })
        .selectOption('all');
      await expect(page.locator('.atlas-path-steps button')).toHaveCount(21);
    },
  );

  await reset();
  await check('late old selection cannot erase the current evidence', async () => {
    const old = await choose(0);
    const latest = await choose(1);
    await resolve(latest);
    await factsTab();
    await expect(page.locator('.atlas-fact')).toContainText('Accepted n1 fact 0');
    await resolve(old);
    await expect(page.locator('.atlas-inspector h2')).toHaveText('Node 0001');
    await expect(page.locator('.atlas-fact')).toContainText('Accepted n1 fact 0');
    await expect(page.locator('.atlas-detail-status')).toHaveCount(0);
  });

  await reset();
  await check(
    'twenty overlapping selections, including repeated IDs, finish in reverse order',
    async () => {
      const keys = [];
      for (let i = 0; i < 20; i++) keys.push(await choose(i % 10));
      await resolve(keys.pop(), 50);
      await factsTab();
      await expect(page.locator('.atlas-fact')).toHaveCount(10);
      for (const key of keys.reverse()) await resolve(key);
      await expect(page.locator('.atlas-inspector h2')).toHaveText('Node 0009');
      await expect(page.locator('.atlas-fact')).toHaveCount(10);
      await expect(page.locator('.atlas-fact').first()).toContainText('Accepted n9 fact 0');
      await expect(page.locator('.atlas-detail-status')).toHaveCount(0);
    },
  );

  await reset();
  await check('obsolete source response cannot open over a new selection', async () => {
    await resolve(await choose(0));
    await factsTab();
    await page.getByRole('button', { name: 'Consulter la source', exact: true }).click();
    const sourceKey = await page.evaluate(
      () => window.readStress.pending().find((r) => r.command === 'document.open').key,
    );
    await resolve(await choose(1));
    await resolve(sourceKey);
    await expect(page.getByRole('dialog')).toHaveCount(0);
  });

  await reset();
  await check('rejected detail read ends loading and remains recoverable', async () => {
    const failed = await choose(0);
    await factsTab();
    await page.evaluate((key) => window.readStress.reject(key), failed);
    await expect(page.locator('.atlas-detail-status')).toHaveCount(0);
    await expect(page.locator('.atlas-evidence')).toContainText('Synthetic rejected read');
    await resolve(await choose(1));
    await expect(page.locator('.atlas-fact')).toContainText('Accepted n1 fact 0');
  });
  // The baseline deliberately produces one unhandled rejection in the last regression.
  report.browserErrors = errors;
  if (!baseline) assert.deepEqual(errors, []);
  report.fixture = {
    nodes: nodes.length,
    edges: dense.length,
    bytes: Buffer.byteLength(JSON.stringify(fixture)),
  };
  console.log(JSON.stringify(report, null, 2));
  if (report.checks.some((check) => !check.passed)) process.exitCode = 1;
} finally {
  await browser?.close();
  await server.close();
}
