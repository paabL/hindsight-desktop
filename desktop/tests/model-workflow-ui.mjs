import assert from 'node:assert/strict';
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '16428', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch('http://127.0.0.1:16428')).ok) break;
    } catch {}
    if (server.exitCode != null || i === 99) throw new Error('Vite did not start');
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({ headless: true, channel: 'chrome' });
  await mkdir(path.join(root, 'screenshots'), { recursive: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'fr'));
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('http://127.0.0.1:16428/?demo=1');
  await expect(page.getByRole('navigation', { name: 'Navigation principale' })).toBeVisible();
  await page
    .getByRole('navigation', { name: 'Réglages du serveur et de l’application' })
    .getByRole('button', { name: /^Modèles/ })
    .click();
  await expect.poll(() => page.evaluate(() => location.hash)).toBe('#model-settings');
  const graph = page.getByRole('region', { name: 'Choix des modèles' });
  await expect(graph).toBeVisible();
  await expect(graph.locator('[data-edge="decision-query"]')).toHaveCount(1);
  await graph.locator('[data-node="decision"] .mw-help').hover();
  await expect(page.getByRole('tooltip')).toContainText('preuves');
  await page.mouse.move(10, 10);
  await graph.getByRole('switch', { name: 'Décision · Réponses' }).click();
  await expect(graph.getByRole('switch')).not.toBeChecked();
  await expect(graph.locator('[data-edge="rank-query"]')).toHaveCount(1);
  await expect(graph.locator('[data-node="decision"]')).toHaveCount(0);
  await graph
    .getByRole('combobox', { name: 'Modèle · Rédaction' })
    .selectOption('claude-haiku-5-5');
  await expect(graph.locator('[data-node="answer"]')).toContainText('claude-haiku-5-5');
  await expect(graph.getByRole('button', { name: /Modifier/ })).toHaveCount(0);
  // Comptes et rôles sont sur la même page, sous le schéma : rien à ouvrir ailleurs.
  await expect(page.getByRole('button', { name: 'Gérer les modèles', exact: true })).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => location.hash)).toBe('#model-settings');
  await expect(graph).toBeVisible();
  await expect(
    page.locator('.account-rows [data-state="connected"] .account-status-dot'),
  ).toHaveCount(2);
  await expect(
    page.locator('.account-rows [data-state="disconnected"] .account-status-dot'),
  ).toHaveCount(1);
  await expect(page.locator('.account-rows [data-state="disconnected"]')).toContainText(
    'Non connecté',
  );
  await page.locator('.account-card').screenshot({
    path: path.join(root, 'screenshots/account-status.png'),
    animations: 'disabled',
  });
  await page.getByRole('button', { name: 'Activer le thème clair', exact: true }).click();
  await page.locator('.account-card').screenshot({
    path: path.join(root, 'screenshots/account-status-light.png'),
    animations: 'disabled',
  });
  await page.getByRole('button', { name: 'Activer le thème sombre', exact: true }).click();
  // Tous les rôles sont repliés par défaut ; le brouillon du schéma s’y retrouve.
  await expect(page.locator('.role-card').first()).toBeHidden();
  await page.locator('summary', { hasText: 'Tous les rôles et réglages avancés' }).click();
  await expect(
    page
      .locator('.role-card')
      .filter({ has: page.getByRole('heading', { name: 'Réponses', exact: true }) }),
  ).toContainText('claude-haiku-5-5');
  await page
    .locator('.role-card')
    .filter({ has: page.getByRole('heading', { name: 'Réponses', exact: true }) })
    .click();
  const editor = page.getByRole('dialog');
  const provider = editor.getByRole('combobox', { name: 'Fournisseur', exact: true });
  const model = editor.getByRole('combobox', { name: 'Modèle', exact: true });
  await expect(editor.locator('input[list], datalist')).toHaveCount(0);
  await expect(provider).toHaveValue('claude-code');
  await expect(model).toHaveValue('claude-haiku-5-5');
  await provider.selectOption('openai-codex');
  await expect(model).toHaveValue('gpt-6-luna');
  await expect(model.locator('option[value="claude-haiku-5-5"]')).toHaveCount(0);
  await model.selectOption('gpt-5.4-mini');
  await expect(model).toHaveValue('gpt-5.4-mini');
  await model.selectOption('__custom_model__');
  await editor
    .getByRole('textbox', { name: 'Modèle · Nom personnalisé', exact: true })
    .fill('my-custom-model');
  await expect(model).toHaveValue('__custom_model__');
  await model.selectOption('my-custom-model');
  await expect(model).toHaveValue('my-custom-model');
  await provider.selectOption('claude-code');
  await expect(model.locator('option[value="my-custom-model"]')).toHaveCount(0);
  await expect(model).toHaveValue('claude-sonnet-5-5');
  await editor.screenshot({
    path: path.join(root, 'screenshots/model-dropdowns.png'),
    animations: 'disabled',
  });
  await editor.getByRole('button', { name: 'Annuler', exact: true }).click();
  await page
    .locator('.role-card')
    .filter({ has: page.getByRole('heading', { name: 'Réponses', exact: true }) })
    .click();
  await expect(provider).toHaveValue('claude-code');
  await expect(model).toHaveValue('claude-haiku-5-5');
  await editor.getByRole('button', { name: 'Annuler', exact: true }).click();
  await page.locator('.role-card').filter({ hasText: 'Classement' }).click();
  const cohereModel = editor.getByRole('combobox', { name: 'Modèle Cohere', exact: true });
  await expect(cohereModel).toHaveValue('rerank-v4.0-fast');
  await expect(editor.getByRole('textbox', { name: 'Clé Hindsight Inference' })).toHaveCount(0);
  await provider.selectOption('hindsight');
  await expect(cohereModel).toHaveCount(0);
  await expect(editor.locator('input[type="password"]')).toHaveCount(1);
  await expect(editor.getByRole('combobox', { name: 'Modèle local', exact: true })).toHaveCount(0);
  await editor.screenshot({
    path: path.join(root, 'screenshots/reranker-hindsight-fields.png'),
    animations: 'disabled',
  });
  await provider.selectOption('local');
  await expect(editor.getByRole('combobox', { name: 'Modèle local', exact: true })).toHaveValue(
    'hindsight-ai/hs-rerank-1',
  );
  await expect(editor.locator('input[type="password"]')).toHaveCount(0);
  await provider.selectOption('cohere');
  await expect(cohereModel).toHaveValue('rerank-v4.0-fast');
  await expect(editor.locator('input[type="password"]')).toHaveCount(1);
  await provider.selectOption('tei');
  await editor.locator('.model-advanced > summary').click();
  await expect(editor.getByRole('textbox', { name: 'URL TEI', exact: true })).toBeVisible();
  await expect(cohereModel).toHaveCount(0);
  await expect(editor.locator('input[type="password"]')).toHaveCount(0);
  await provider.selectOption('litellm');
  const liteModel = editor.getByRole('combobox', { name: 'Modèle LiteLLM', exact: true });
  await liteModel.selectOption('__custom_model__');
  await editor
    .getByRole('textbox', { name: 'Modèle LiteLLM · Nom personnalisé', exact: true })
    .fill('proxy/reranker');
  await provider.selectOption('hindsight');
  await expect(liteModel).toHaveCount(0);
  await provider.selectOption('litellm');
  await expect(
    editor.getByRole('textbox', { name: 'Modèle LiteLLM · Nom personnalisé', exact: true }),
  ).toHaveValue('proxy/reranker');
  await editor.getByRole('button', { name: 'Annuler', exact: true }).click();
  await page.locator('.role-card').filter({ hasText: 'Embeddings' }).click();
  await expect(provider).toHaveValue('google');
  await expect(provider.locator('option[value="gemini"]')).toHaveCount(0);
  await expect(editor.getByRole('combobox', { name: 'Modèle Gemini', exact: true })).toHaveValue(
    'gemini-embedding-2',
  );
  await provider.selectOption('openai');
  await expect(editor.getByRole('combobox', { name: 'Modèle Gemini', exact: true })).toHaveCount(0);
  await expect(editor.getByRole('textbox', { name: 'Dimensions Gemini', exact: true })).toHaveCount(
    0,
  );
  await expect(editor.getByRole('combobox', { name: 'Modèle OpenAI', exact: true })).toHaveValue(
    'text-embedding-3-small',
  );
  await provider.selectOption('hindsight');
  await expect(editor.getByRole('combobox')).toHaveCount(1);
  await expect(editor.locator('input[type="password"]')).toHaveCount(1);
  await provider.selectOption('google');
  await expect(editor.getByRole('combobox', { name: 'Modèle Gemini', exact: true })).toHaveValue(
    'gemini-embedding-2',
  );
  await editor.getByRole('button', { name: 'Annuler', exact: true }).click();
  await page.locator('.role-card').filter({ hasText: 'Décision' }).click();
  await expect(provider).toHaveValue('__hindsight_local__');
  await provider.selectOption('hindsight');
  await expect(provider).toHaveValue('hindsight');
  await provider.selectOption('__hindsight_local__');
  await expect(provider).toHaveValue('__hindsight_local__');
  await expect(editor.getByRole('combobox', { name: 'Modèle', exact: true })).toBeVisible();
  await expect(
    editor.getByRole('combobox', { name: 'Recherche : retirer les doublons', exact: true }),
  ).toHaveCount(0);
  const bounds = await editor.boundingBox();
  assert.ok(bounds.height < 650, `Decision editor too tall: ${bounds.height}`);
  const footer = await editor
    .getByRole('button', { name: 'Préparer ces changements', exact: true })
    .boundingBox();
  assert.ok(footer.y + footer.height <= 1100, 'Footer must remain visible');
  await editor.getByRole('tab', { name: 'Recherche', exact: true }).click();
  await expect(
    editor.getByRole('combobox', { name: 'Recherche : retirer les doublons', exact: true }),
  ).toBeVisible();
  await editor.getByRole('tab', { name: 'Connaissances', exact: true }).click();
  await expect(
    editor.getByRole('combobox', {
      name: 'Pages de connaissance : filtrage des nouveaux faits',
      exact: true,
    }),
  ).toBeVisible();
  await editor.getByRole('tab', { name: 'Réponses', exact: true }).click();
  const decisionFlag = editor.getByRole('combobox', {
    name: 'Réponses : utiliser la décision',
    exact: true,
  });
  await expect(decisionFlag).toHaveValue('false');
  await expect(decisionFlag.locator('option')).toHaveCount(3);
  await decisionFlag.selectOption('true');
  await expect(decisionFlag).toHaveValue('true');
  await expect(decisionFlag.locator('option[value="__custom_model__"]')).toHaveCount(0);
  await editor.getByRole('button', { name: 'Annuler', exact: true }).click();
  await expect(graph.getByRole('combobox', { name: 'Modèle · Rédaction' })).toHaveValue(
    'claude-haiku-5-5',
  );
  await graph.getByRole('tab', { name: 'Recherche', exact: true }).click();
  await graph.getByRole('switch', { name: 'Décision · Recherche' }).click();
  await expect(graph.getByRole('switch')).toBeChecked();
  await graph.getByRole('checkbox', { name: 'Écarter les faits inutiles', exact: true }).click();
  await expect(
    graph.getByRole('checkbox', { name: 'Écarter les faits inutiles', exact: true }),
  ).toBeChecked();
  await graph.getByRole('checkbox', { name: 'Retirer les doublons', exact: true }).click();
  await expect(
    graph.getByRole('checkbox', { name: 'Retirer les doublons', exact: true }),
  ).toBeChecked();
  await graph.getByRole('tab', { name: 'Réponses', exact: true }).click();
  await expect(graph.locator('[data-node="rank"]')).toContainText('hs-decide-1-flash');
  await graph.getByRole('button', { name: 'Réglé dans Recherche', exact: false }).click();
  await expect(graph.getByRole('tab', { name: 'Recherche', exact: true })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await graph.getByRole('button', { name: 'Annuler', exact: true }).click();
  await expect(graph.getByRole('switch')).not.toBeChecked();
  await graph.getByRole('tab', { name: 'Réponses', exact: true }).click();
  await expect(graph.getByRole('switch')).toBeChecked();
  await expect(graph.getByRole('combobox', { name: 'Modèle · Rédaction' })).toHaveValue(
    'claude-sonnet-5-5',
  );
  await graph.getByRole('tab', { name: 'Extraction et consolidation', exact: true }).click();
  await graph.getByRole('button', { name: 'Extraction', exact: true }).focus();
  await page.keyboard.press('Tab');
  await graph.getByRole('button', { name: 'Extraction', exact: true }).focus();
  await expect(page.getByRole('tooltip')).toContainText('faits à mémoriser');
  await page.keyboard.press('Escape');
  await graph.getByRole('tab', { name: 'Réponses', exact: true }).click();
  await graph.getByRole('switch').click();
  await expect(graph.getByRole('switch')).not.toBeChecked();
  await graph.getByRole('button', { name: 'Enregistrer', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('dialog').getByRole('button', { name: 'Enregistrer', exact: true }).click();
  await expect(graph).toContainText('Redémarrage requis');
  await graph.getByRole('switch').click();
  await expect(graph.getByRole('switch')).toBeChecked();
  for (const width of [1440, 1000]) {
    await page.setViewportSize({ width, height: 1100 });
    await expect
      .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1))
      .toBe(true);
    await expect(graph.locator('[data-edge="decision-query"]')).toHaveCount(1);
  }
  await mkdir(path.join(root, 'screenshots'), { recursive: true });
  await graph.screenshot({
    path: path.join(root, 'screenshots/model-workflow.png'),
    animations: 'disabled',
  });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('http://127.0.0.1:16428/?demo=1#model-settings');
  await expect(graph).toBeVisible();
  await page.screenshot({
    path: path.join(root, 'screenshots/models-sidebar.png'),
    animations: 'disabled',
  });
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Sidebar Models: selectors, accounts and roles on the same page with a shared draft, independent decisions, loops, tooltips and save/cancel verified.',
  );
} finally {
  await browser?.close();
  server.kill();
}
