import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1425', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch('http://127.0.0.1:1425')).ok) break;
    } catch {}
    if (server.exitCode != null || attempt === 99)
      throw new Error('Le serveur de test ne démarre pas.');
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.HINDSIGHT_BROWSER_EXECUTABLE ||
      (existsSync('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        : undefined),
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, locale: 'fr-CA' });
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('http://127.0.0.1:1425/?demo=1');
  const nav = page.getByRole('navigation', { name: 'Navigation principale' });
  await nav.getByRole('button', { name: /Recherche/ }).click();
  await page.getByRole('button', { name: 'Filtres', exact: true }).click();
  const prune = page.getByRole('combobox', { name: 'Écarter les faits inutiles', exact: true });
  const dedup = page.getByRole('combobox', { name: 'Retirer les doublons', exact: true });
  await expect(prune).toHaveValue('');
  await prune.selectOption('false');
  await dedup.selectOption('true');
  await expect(prune).toHaveValue('false');
  await expect(dedup).toHaveValue('true');
  await page.getByRole('tab', { name: 'Texte exact', exact: true }).click();
  await expect(prune).toHaveCount(0);
  await page.getByRole('tab', { name: 'Retrouver des faits', exact: true }).click();
  await expect(prune).toHaveValue('false');
  await nav.getByRole('button', { name: /Consommation/ }).click();
  await expect(page.getByRole('columnheader', { name: 'Équivalent API' })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'hs-decide-1-flash', exact: true })).toBeVisible();
  await expect(
    page.getByText('Montants indicatifs aux tarifs Hindsight Inference', { exact: false }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Avancé', exact: true }).click();
  const advanced = page.getByRole('navigation', { name: 'Outils avancés' });
  await advanced.getByRole('button', { name: 'Structure de la mémoire', exact: true }).click();
  await page.getByRole('tab', { name: 'Réponses', exact: true }).click();
  await expect(page.getByRole('switch')).toHaveCount(3);
  await page.getByRole('tab', { name: 'Recherche', exact: true }).click();
  await expect(page.getByRole('switch', { name: /Écarter les faits inutiles/ })).not.toBeChecked();
  await page.getByRole('switch', { name: /Retirer les doublons/ }).check();
  await expect(page.getByRole('switch', { name: /Retirer les doublons/ })).toBeChecked();
  await advanced.getByRole('button', { name: 'Serveur & modèles', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Modèles Hindsight', exact: true })).toBeVisible();
  await mkdir(path.join(root, 'screenshots'), { recursive: true });
  for (const width of [1440, 1000]) {
    await page.setViewportSize({ width, height: 1000 });
    await expect
      .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1))
      .toBe(true);
  }
  await page.screenshot({
    path: path.join(root, 'screenshots/hindsight120-models.png'),
    fullPage: true,
  });
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Interface Hindsight 1.2 vérifiée : recherche, banque, coûts et modèles, à deux largeurs.',
  );
} finally {
  await browser?.close();
  server.kill();
}
