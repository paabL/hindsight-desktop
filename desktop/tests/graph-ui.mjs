import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const url = 'http://127.0.0.1:1422';
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1422'],
  { cwd: root, stdio: 'ignore' },
);
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let browser;
const errors = [];
try {
  for (let attempt = 0; ; attempt++) {
    if (server.exitCode != null) throw new Error('Le port de vérification 1422 est occupé.');
    try {
      if ((await fetch(url)).ok) break;
    } catch {}
    if (attempt === 100) throw new Error('Le serveur de vérification ne démarre pas.');
    await new Promise((r) => setTimeout(r, 100));
  }
  await mkdir(path.join(root, 'screenshots'), { recursive: true });
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.HINDSIGHT_BROWSER_EXECUTABLE || (existsSync(chrome) ? chrome : undefined),
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 }, locale: 'fr-CA' });
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(url + '/?demo=1#graph');
  await expect(page.getByRole('heading', { name: 'Atlas de la mémoire' })).toBeVisible();
  await expect(page.locator('.atlas-node')).toHaveCount(20);
  await expect(page.locator('.atlas-community')).toHaveCount(4);
  const positions = await page
    .locator('.atlas-node')
    .evaluateAll((nodes) => nodes.map((n) => n.getAttribute('transform')));
  await page.screenshot({
    path: path.join(root, 'screenshots/graph-dark.png'),
    animations: 'disabled',
  });
  await page.locator('[data-atlas-node="node-3"]').click();
  await expect(page.locator('.atlas-inspector h2')).toHaveText('Architecture');
  await page.getByRole('tab', { name: 'Faits & sources', exact: true }).click();
  await expect(page.locator('.atlas-fact')).toHaveCount(3);
  expect(
    await page
      .locator('.atlas-node')
      .evaluateAll((nodes) => nodes.map((n) => n.getAttribute('transform'))),
  ).toEqual(positions);
  await page.getByRole('button', { name: 'Consulter la source', exact: true }).first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Fermer', exact: true }).click();
  await page.getByRole('button', { name: 'Isoler', exact: true }).click();
  await expect(page.locator('.atlas-node')).toHaveCount(7);
  await page.getByRole('combobox', { name: 'Profondeur du voisinage' }).selectOption('2');
  expect(await page.locator('.atlas-node').count()).toBeGreaterThan(7);
  await page
    .locator('.atlas-view-switch')
    .getByRole('button', { name: 'Carte', exact: true })
    .click();
  await expect(page.locator('.atlas-node')).toHaveCount(20);
  await page.getByRole('button', { name: 'Relier à…', exact: true }).click();
  const search = page.getByRole('textbox', { name: 'Rechercher dans le graphe' });
  await search.fill('energie');
  await expect(page.locator('.atlas-node-row')).toHaveCount(1);
  await page.locator('.atlas-node-row').click();
  await expect(page.locator('.atlas-inspector h2')).toHaveText('Énergie');
  await expect(page.locator('.atlas-path-steps button')).toHaveCount(5);
  await expect(page.locator('.atlas-route-bar')).toContainText('4 liens');
  await page.locator('.atlas-path-steps button').nth(1).click();
  await expect(page.locator('.atlas-path-steps button')).toHaveCount(5);
  await expect(page.locator('.atlas-route-bar')).toContainText('Énergie');
  await page.getByRole('button', { name: 'Filtres', exact: true }).click();
  const strength = page.getByRole('slider', { name: 'Force minimale des liens' });
  await strength.focus();
  await strength.press('End');
  await expect(page.locator('.atlas-route-bar')).toContainText('Aucun chemin');
  await strength.press('Home');
  await expect(page.locator('.atlas-route-bar')).toContainText('4 liens');
  await page.getByRole('button', { name: 'Cadrer tous les nœuds visibles', exact: true }).click();
  await page.screenshot({
    path: path.join(root, 'screenshots/graph-path.png'),
    animations: 'disabled',
  });
  await page.getByRole('button', { name: 'Zoomer le graphe', exact: true }).click();
  await expect(page.locator('.atlas-zoom')).toHaveText('130 %');
  const canvas = page.locator('.atlas-svg');
  const box = await canvas.boundingBox();
  const beforePan = await canvas.getAttribute('viewBox');
  await page.mouse.move(box.x + 15, Math.max(100, box.y + 20));
  await page.mouse.down();
  await page.mouse.move(box.x + 90, Math.max(100, box.y + 20) + 50, { steps: 5 });
  await page.mouse.up();
  await expect(canvas).not.toHaveAttribute('viewBox', beforePan);
  await page.mouse.wheel(0, -200);
  await expect(page.locator('.atlas-zoom')).not.toHaveText('130 %');
  await canvas.focus();
  await canvas.press('0');
  await expect(page.locator('.atlas-zoom')).toHaveText('100 %');
  await page.getByRole('button', { name: 'Fermer le parcours', exact: true }).click();
  await page.getByRole('button', { name: 'Désélectionner le nœud', exact: true }).click();
  await page.getByRole('tab', { name: /Passerelles/ }).click();
  await expect(page.locator('.atlas-node-row')).toHaveCount(7);
  await page.locator('.page-header').getByRole('tab', { name: 'Faits', exact: true }).click();
  await expect(page.locator('.atlas-node')).toHaveCount(12);
  await page
    .getByRole('combobox', { name: 'Nature des liens', exact: true })
    .selectOption('temporal');
  await expect(page.locator('.atlas-edges path')).toHaveCount(4);
  await page.getByRole('combobox', { name: 'Nature des liens', exact: true }).selectOption('all');
  await page.locator('[data-atlas-node="fact-0"]').click();
  await page.getByRole('tab', { name: 'Faits & sources', exact: true }).click();
  await expect(page.locator('.atlas-fact')).toHaveCount(1);
  await expect(
    page.getByRole('button', { name: 'Consulter la source', exact: true }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Activer le thème clair', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.screenshot({
    path: path.join(root, 'screenshots/graph-light.png'),
    animations: 'disabled',
  });
  for (const width of [1440, 1180, 980]) {
    await page.setViewportSize({ width, height: 1100 });
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth),
    ).toBe(false);
    expect(
      await page.locator('.atlas-workspace').evaluate((el) => el.scrollWidth > el.clientWidth),
    ).toBe(false);
  }

  const dense = await browser.newPage({ viewport: { width: 1440, height: 1200 }, locale: 'fr-CA' });
  await dense.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  dense.on('pageerror', (e) => errors.push(e.message));
  const denseNodes = Array.from({ length: 100 }, (_, i) => ({
    id: `dense-${i}`,
    label: `Sujet ${i}`,
    detail: `Sujet de vérification ${i}`,
    kind: 'entity',
    weight: 10,
  }));
  const denseEdges = [];
  for (let group = 0; group < 5; group++)
    for (let a = 0; a < 20; a++)
      for (let b = a + 1; b < 20; b++)
        denseEdges.push({
          source: `dense-${group * 20 + a}`,
          target: `dense-${group * 20 + b}`,
          weight: 20,
          kind: 'cooccurrence',
        });
  for (let group = 0; group < 4; group++)
    denseEdges.push({
      source: `dense-${group * 20}`,
      target: `dense-${(group + 1) * 20}`,
      weight: 1,
      kind: 'cooccurrence',
    });
  await dense.addInitScript(
    ({ nodes, edges }) => {
      const snapshot = {
        app: {
          connected: true,
          serverURL: 'http://127.0.0.1:8888',
          bank: 'dense',
          banks: [{ bank_id: 'dense', name: 'Banque de vérification', fact_count: 100 }],
          paused: [],
        },
        section: 'graph',
        data: {
          mode: 'entities',
          nodes,
          edges,
          totalNodes: nodes.length,
          selectedNodeID: null,
          nodeFacts: [],
        },
        messages: [],
        confirmations: [],
      };
      window.__TAURI_INTERNALS__ = {
        invoke: async (_command, args) => {
          if (args.request.command === 'graph.select')
            snapshot.data.selectedNodeID = args.request.args.id;
          return structuredClone(snapshot);
        },
      };
    },
    { nodes: denseNodes, edges: denseEdges },
  );
  await dense.goto(url + '/#graph');
  await expect(dense.locator('.atlas-aggregate')).toHaveCount(5);
  await expect(dense.locator('.atlas-node')).toHaveCount(0);
  await expect(dense.locator('.atlas-bundles path')).toHaveCount(4);
  await dense.screenshot({
    path: path.join(root, 'screenshots/graph-groups.png'),
    animations: 'disabled',
  });
  await dense.locator('.atlas-aggregate').first().click();
  await expect(dense.locator('.atlas-node')).toHaveCount(20);
  await expect(dense.locator('.atlas-inspector .atlas-node-row')).toHaveCount(20);
  await expect(dense.locator('.atlas-aggregate')).toHaveCount(0);
  await dense.getByRole('button', { name: 'Tous les groupes', exact: true }).click();
  await expect(dense.locator('.atlas-aggregate')).toHaveCount(5);
  await dense.getByRole('button', { name: 'Zoomer le graphe', exact: true }).click();
  await dense.getByRole('button', { name: 'Zoomer le graphe', exact: true }).click();
  await expect(dense.locator('.atlas-node')).toHaveCount(100);
  await dense.getByRole('button', { name: 'Cadrer tous les nœuds visibles', exact: true }).click();
  await expect(dense.locator('.atlas-aggregate')).toHaveCount(5);
  await dense.close();
  expect(errors).toEqual([]);
  console.log(
    'Atlas vérifié : groupes, recherche sans accents, stabilité, voisinage, parcours conservé, filtres, provenance, pan/zoom, clavier, thèmes, 3 largeurs et déploiement sémantique d’une carte dense.',
  );
} finally {
  await browser?.close();
  server.kill();
}
