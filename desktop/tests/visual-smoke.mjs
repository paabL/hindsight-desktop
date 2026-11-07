import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
await mkdir(path.join(root, 'screenshots'), { recursive: true });
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1423'],
  {
    cwd: root,
    stdio: 'ignore',
  },
);
for (let attempt = 0; attempt < 100; attempt++) {
  try {
    if ((await fetch('http://127.0.0.1:1423')).ok) break;
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 100));
  if (attempt === 99) {
    server.kill();
    throw new Error('Le serveur de test ne démarre pas.');
  }
}
let browser;
const errors = [];
try {
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.HINDSIGHT_BROWSER_EXECUTABLE ||
      (existsSync('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        : undefined),
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 960 }, locale: 'fr-CA' });
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  await page.goto('http://127.0.0.1:1423/?demo=1');
  page.on('pageerror', (error) => errors.push(error.message));
  await page.evaluate(() => localStorage.setItem('hindsight-desktop-theme-v2', 'dark'));
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Vue d’ensemble', exact: true })).toBeVisible();
  await page.keyboard.press('Meta+5');
  await expect(page.getByRole('heading', { name: 'Sources', exact: true })).toBeVisible();
  await expect(page.locator('.folder-row')).toHaveCount(2);
  await page.screenshot({ path: path.join(root, 'screenshots/00-sources.png') });
  await page.locator('.folder-row', { hasText: 'horizon-memory' }).click();
  await expect(page.getByRole('heading', { name: 'horizon-memory', exact: true })).toBeVisible();
  await expect(page.getByText('12 sources dans 2 projets')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Actualiser la vue', exact: true })).toBeEnabled();
  await page.screenshot({ path: path.join(root, 'screenshots/01-dossier.png') });
  await page.getByRole('textbox', { name: 'Filtrer les sources' }).fill('architecture');
  await expect(page.locator('.source-row')).toHaveCount(1);
  await page.locator('.source-row').click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Ce que nous avons retenu' })).toBeVisible();
  await page.getByRole('button', { name: 'Fermer', exact: true }).click();
  const nav = page.getByRole('navigation', { name: 'Navigation principale' });
  await nav.getByRole('button', { name: /Connaissances/ }).click();
  await expect(page.locator('.model-card')).toHaveCount(4);
  await page.screenshot({ path: path.join(root, 'screenshots/02-syntheses.png') });
  await page.locator('.model-card').first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Fermer', exact: true }).click();
  await nav.getByRole('button', { name: /Recherche/ }).click();
  await page.getByRole('textbox', { name: 'Votre recherche' }).fill('Les décisions du projet');
  await page.getByRole('button', { name: 'Rechercher', exact: true }).click();
  await expect(page.locator('.fact-card')).toHaveCount(12);
  await page.screenshot({ path: path.join(root, 'screenshots/03-recherche.png') });
  await nav.getByRole('button', { name: /^Activité/ }).click();
  await page
    .getByRole('tablist', { name: 'Vues de l’activité' })
    .getByRole('tab', { name: 'Consommation', exact: true })
    .click();
  await expect(page.locator('.quota-card')).toHaveCount(0);
  await expect(page.locator('.chart-bar')).not.toHaveCount(0);
  await page.screenshot({ path: path.join(root, 'screenshots/04-consommation.png') });
  await nav.getByRole('button', { name: /^Mémoire/ }).click();
  await page
    .getByRole('tablist', { name: 'Vues de la mémoire' })
    .getByRole('tab', { name: 'Graphe', exact: true })
    .click();
  await expect(page.locator('.atlas-node')).toHaveCount(20);
  await page.locator('.atlas-node').first().click();
  await page.getByRole('tab', { name: 'Faits & sources', exact: true }).click();
  await expect(page.locator('.atlas-fact')).toHaveCount(3);
  await page.screenshot({ path: path.join(root, 'screenshots/05-graphe.png') });
  for (const route of [
    'dashboard',
    'memory',
    'operations',
    'audit',
    'timeline',
    'server',
    'admin',
    'facts',
  ]) {
    await page.evaluate((route) => {
      location.hash = route;
    }, route);
    await expect.poll(() => page.evaluate(() => location.hash)).toBe(`#${route}`);
    await expect(page.locator('.page-header h1')).toBeVisible();
    await page.waitForTimeout(200);
    if (await page.getByText('Cette vue n’a pas pu s’afficher').count())
      throw new Error(`Échec de rendu : ${route}`);
  }
  await page.getByRole('button', { name: 'Activer le thème clair' }).click();
  // Sources rouvre le dossier laissé ouvert : le catalogue de l’exemple.
  await page.keyboard.press('Meta+5');
  await expect(page.locator('.source-row')).toHaveCount(12);
  await page.screenshot({ path: path.join(root, 'screenshots/06-clair.png') });
  await page.keyboard.press('Meta+k');
  await expect(page.getByRole('dialog', { name: 'Un raccourci vers votre mémoire' })).toBeVisible();
  await page.getByRole('textbox', { name: 'Rechercher une vue' }).fill('Documents');
  await page.locator('.command-list button').first().click();
  await expect(page.locator('tbody tr')).toHaveCount(12);
  await page.locator('.document-cell').first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('textbox', { name: 'Rechercher dans le document' }).fill('décisions');
  await expect(page.locator('.markdown mark')).not.toHaveCount(0);
  await page.getByRole('button', { name: 'Fermer', exact: true }).click();
  await page.keyboard.press('Meta+5');
  await page.getByRole('button', { name: 'Toutes les sources', exact: true }).click();
  await page.locator('.folder-row', { hasText: 'horizon-app' }).click();
  await expect(
    page.getByRole('heading', { name: 'horizon-app', level: 1, exact: true }),
  ).toBeVisible();
  await expect(page.locator('tbody tr')).toHaveCount(4);
  await page.getByRole('button', { name: 'Toutes les sources', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Sources', level: 1, exact: true })).toBeVisible();
  await page
    .getByRole('button', { name: /Réglages/ })
    .first()
    .click();
  await expect(page.getByRole('heading', { name: 'Langue', exact: true })).toBeVisible();
  await page
    .getByRole('tablist', { name: 'Vues des réglages' })
    .getByRole('tab', { name: 'Serveur', exact: true })
    .click();
  await expect(page.getByRole('heading', { name: 'Connexion à Hindsight' })).toBeVisible();
  const security = await page.evaluate(() => ({
    node: typeof window.require,
    host: typeof window.__TAURI_INTERNALS__,
  }));
  if (security.node !== 'undefined' || security.host !== 'undefined')
    throw new Error('Le renderer doit rester isolé de Node.');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Vérification visuelle réussie : 16 vues, sources par banque, recherche, lecture, filtres, graphe, raccourcis et thème sombre.',
  );
} finally {
  await browser?.close();
  server.kill();
}
