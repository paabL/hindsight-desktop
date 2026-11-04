import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1426', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch('http://127.0.0.1:1426')).ok) break;
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
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, locale: 'fr-CA' });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('http://127.0.0.1:1426/');
  await expect(
    page.getByRole('heading', { name: 'Bienvenue dans Hindsight Desktop' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Connecter mon serveur', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Connexion à Hindsight' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Voir les versions', exact: true })).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Recompiler cette copie', exact: true }),
  ).toBeHidden();
  await page.getByRole('combobox', { name: 'Langue de l’interface' }).selectOption('en');
  await expect(page.getByRole('heading', { name: 'Connect to Hindsight' })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toContainText('Memory');
  await page.reload();
  await expect(page.getByRole('combobox', { name: 'Interface language' })).toHaveValue('en');
  await page.getByRole('button', { name: 'Explore the example', exact: true }).click();
  await expect(page.getByText('Example · fictional data', { exact: true })).toBeVisible();
  await page
    .getByRole('navigation', { name: 'Main navigation' })
    .getByRole('button', { name: /^Memory/ })
    .click();
  await page.keyboard.press('Meta+5');
  await expect(page.getByRole('heading', { name: 'Memory', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Settings', exact: false }).first().click();
  await page.getByRole('combobox', { name: 'Interface language' }).selectOption('fr');
  await expect(page.getByRole('heading', { name: 'Connexion à Hindsight' })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Premier lancement et changement de langue vérifiés : français, anglais et préférence conservée.',
  );
} finally {
  await browser?.close();
  server.kill();
}
