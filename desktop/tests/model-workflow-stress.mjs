import assert from 'node:assert/strict';
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.HINDSIGHT_MODEL_TEST_PORT || 16471);
assert.ok(Number.isInteger(port) && port >= 16450 && port < 65536);
const base = `http://127.0.0.1:${port}`;
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
const errors = [];
const P = 'HINDSIGHT_API_';
const cases = [];
function check(name, fn) {
  cases.push({ name, fn });
}

async function open(page, mode = 'models') {
  await page.goto(`${base}/tests/support/model-workflow-fixture.html?mode=${mode}`);
  await expect.poll(() => page.evaluate(() => !!window.modelFixture?.update)).toBe(true);
}
async function calls(page) {
  return page.evaluate(() => window.modelFixture.calls);
}
const prepare = (dialog) =>
  dialog.getByRole('button', { name: 'Prepare these changes', exact: true });
const dialog = (page) => page.getByRole('dialog');
async function openRole(page, title) {
  // Les rôles sont repliés sous le schéma : on déplie la section avant de choisir une carte.
  const summary = page.locator('summary', { hasText: 'All roles and advanced settings' });
  if (!(await summary.evaluate((node) => node.parentElement.open))) await summary.click();
  await page
    .locator('.role-card')
    .filter({ has: page.getByRole('heading', { name: title, exact: true }) })
    .click();
  await expect(dialog(page)).toBeVisible();
  return dialog(page);
}

check(
  'admin rejects keep input for retry, and a delayed reply cannot close a newly opened dialog',
  async (page) => {
    await open(page, 'admin');
    const create = page.getByRole('button', { name: 'New bank', exact: true });
    await create.click();
    const editor = dialog(page);
    await editor.getByRole('textbox', { name: 'Name', exact: true }).fill('First bank');
    await editor.getByRole('textbox', { name: 'New bank ID', exact: true }).fill('bank-a');
    await page.evaluate(() => {
      window.modelFixture.failure = 'bank.create';
    });
    await editor.getByRole('button', { name: 'Continue', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.modelFixture.completed)).toBe(1);
    await expect(editor.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(
      'First bank',
    );
    await page.evaluate(() => {
      window.modelFixture.failure = '';
      window.modelFixture.delay = 220;
      const form = document.querySelector('.modal form');
      for (let i = 0; i < 25; i++) form.requestSubmit();
    });
    await expect.poll(async () => (await calls(page)).length).toBe(2);
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    await create.click();
    await editor.getByRole('textbox', { name: 'Name', exact: true }).fill('New unsaved bank');
    await expect.poll(() => page.evaluate(() => window.modelFixture.completed)).toBe(2);
    await expect(editor.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(
      'New unsaved bank',
    );
    assert.equal((await calls(page)).length, 2, 'rapid submissions send one request for the retry');
  },
);

const emptyList = (page) => page.getByRole('heading', { name: /No folder feeds/ });

check('sources waits for the bank’s folders and opens one only when asked, once', async (page) => {
  await open(page, 'sources');
  await expect(page.getByRole('status')).toContainText('Loading sources');
  await expect(emptyList(page)).toHaveCount(0);
  assert.deepEqual(await calls(page), []);
  await page.evaluate(() =>
    window.modelFixture.update({
      bank: 'bank-a',
      listBank: 'bank-a',
      openKind: null,
      open: null,
      folders: [{ path: '/fictional/notes', name: 'notes', kind: 'folder', files: 2, toSend: 1 }],
    }),
  );
  await expect(page.locator('.folder-row')).toContainText('2 files · 1 to upload');
  assert.deepEqual(await calls(page), [], 'listing the folders neither tracks nor opens one');
  await page.evaluate(() => {
    window.modelFixture.delay = 180;
    const row = document.querySelector('.folder-row');
    for (let i = 0; i < 25; i++) row.click();
  });
  await expect(page.getByRole('heading', { name: 'notes', exact: true })).toBeVisible();
  assert.deepEqual(await calls(page), [
    { command: 'folder.choose', args: { path: '/fictional/notes' } },
  ]);
});

check(
  'sources never replaces a loading or failed comparison with an empty list, and finds the open folder under another spelling',
  async (page) => {
    await open(page, 'sources');
    const folder = {
      path: '/fictional/réunions',
      name: 'réunions',
      kind: 'folder',
      allFiles: true,
    };
    await page.evaluate(
      (folder) =>
        window.modelFixture.update({
          bank: 'bank-a',
          listBank: 'bank-a',
          folders: [folder, { path: '/fictional/moved', name: 'moved', exists: false }],
          foldersLoading: true,
        }),
      folder,
    );
    await expect(page.locator('.folder-row').first()).toContainText(
      'Comparing with the memory bank…',
    );
    // Un dossier introuvable ne s’ouvre pas : il peut seulement ne plus être suivi.
    await expect(page.locator('.folder-row.missing')).toContainText('Folder not found on this Mac');
    await expect(page.locator('button.folder-row')).toHaveCount(1);
    await page.evaluate(() => window.modelFixture.update({ folders: undefined }));
    await expect(page.getByRole('status')).toContainText('Loading sources');
    await expect(emptyList(page)).toHaveCount(0);
    await page.evaluate(
      (folder) =>
        window.modelFixture.update({
          folders: [folder],
          foldersLoading: false,
          foldersError: 'Fixture cannot compare the folders',
        }),
      folder,
    );
    await expect(page.getByRole('alert')).toContainText('Fixture cannot compare');
    await expect(page.locator('.folder-row')).toContainText('Not compared yet');
    await expect(emptyList(page)).toHaveCount(0);
    // macOS peut rendre le chemin décomposé (NFD) et avec une barre finale : c’est le même dossier suivi.
    await page.evaluate(() =>
      window.modelFixture.update({
        foldersError: null,
        openKind: 'folder',
        open: '/fictional/réunions/',
        compared: true,
        items: [],
      }),
    );
    await expect(page.getByRole('heading', { name: 'réunions', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: /Include all text files/ })).toBeChecked();
    assert.deepEqual(await calls(page), []);
  },
);

check(
  'a folder upload failure keeps the selection, and refreshed or other-bank files never submit vanished IDs',
  async (page) => {
    await open(page, 'sources');
    const folder = { path: '/fictional/notes', name: 'notes', kind: 'folder', files: 1, toSend: 1 };
    await page.evaluate(
      (folder) =>
        window.modelFixture.update({
          bank: 'bank-a',
          listBank: 'bank-a',
          folders: [folder],
          openKind: 'folder',
          open: folder.path,
          compared: true,
          // Le bouton n’annonce que les fichiers réellement envoyables (`canSend`, fourni par le moteur).
          items: [{ id: 'obsolete-id', title: 'Old source', state: 'modified', canSend: true }],
        }),
      folder,
    );
    await page.getByRole('checkbox', { name: 'Select all', exact: true }).check();
    const upload = page.getByRole('button', { name: 'Upload (1)', exact: true });
    await expect(upload).toBeEnabled();
    await page.evaluate(() => (window.modelFixture.failure = 'coverage.send'));
    await upload.click();
    await expect(page.getByRole('alert')).toContainText('Fixture rejects');
    await expect(upload).toBeEnabled();
    assert.deepEqual(await calls(page), [
      { command: 'coverage.send', args: { ids: ['obsolete-id'] } },
    ]);
    await page.evaluate(() => {
      window.modelFixture.failure = '';
      window.modelFixture.update({
        items: [{ id: 'new-id', title: 'New source', state: 'current' }],
      });
    });
    await expect(page.getByRole('button', { name: 'Upload all (0)', exact: true })).toBeDisabled();
    await page.evaluate(
      (folder) =>
        window.modelFixture.mount(
          'sources',
          {
            bank: 'bank-b',
            listBank: 'bank-b',
            folders: [{ ...folder, path: '/fictional/bank-b' }],
            openKind: 'folder',
            open: '/fictional/bank-b',
            compared: true,
            items: [{ id: 'new-id', title: 'Bank B source', state: 'current' }],
          },
          'bank-b',
        ),
      folder,
    );
    await expect(page.locator('.folder-path-line')).toHaveText('/fictional/bank-b');
    await expect(page.getByRole('button', { name: 'Upload all (0)', exact: true })).toBeDisabled();
    assert.deepEqual(await calls(page), []);
  },
);

check('decision tabs support arrows, Home and End without preparing changes', async (page) => {
  await open(page);
  const editor = await openRole(page, 'Décision');
  await editor.getByRole('tab', { name: 'Model', exact: true }).focus();
  await page.keyboard.press('ArrowRight');
  await expect(editor.getByRole('tab', { name: 'Search', exact: true })).toBeFocused();
  await expect(
    editor.getByRole('combobox', { name: 'Recherche : fournisseur', exact: true }),
  ).toBeVisible();
  await page.keyboard.press('End');
  await expect(editor.getByRole('tab', { name: 'Knowledge', exact: true })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await page.keyboard.press('Home');
  await expect(editor.getByRole('tab', { name: 'Model', exact: true })).toBeFocused();
  assert.deepEqual(await calls(page), []);
});

check(
  'common action buttons do not submit forms; explicit and implicit submits still work',
  async (page) => {
    await open(page, 'controls');
    await page.getByRole('button', { name: 'Action', exact: true }).click();
    await page.getByRole('button', { name: 'Icon action', exact: true }).click();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 0);
    assert.equal(await page.evaluate(() => window.modelFixture.actions), 2);
    await expect(page.getByRole('button', { name: 'Disabled action', exact: true })).toBeDisabled();
    await page.getByRole('button', { name: 'Submit', exact: true }).click();
    await page.getByRole('button', { name: 'Explicit submit', exact: true }).click();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 2);
  },
);

check(
  'modal keyboard focus skips hidden and disabled controls and restores its trigger',
  async (page) => {
    await open(page, 'controls');
    const trigger = page.getByRole('button', { name: 'Open dialog', exact: true });
    await trigger.click();
    await expect(page.getByRole('textbox', { name: 'Visible input', exact: true })).toBeFocused();
    await dialog(page).getByRole('button', { name: 'Finish', exact: true }).focus();
    await page.keyboard.press('Tab');
    await expect(dialog(page).getByRole('button', { name: 'Close', exact: true })).toBeFocused();
    await page.keyboard.press('Shift+Tab');
    await expect(dialog(page).getByRole('button', { name: 'Finish', exact: true })).toBeFocused();
    await page
      .getByRole('textbox', { name: 'Outside input', exact: true })
      .evaluate((el) => el.focus());
    await page.keyboard.press('Tab');
    await expect(dialog(page).getByRole('button', { name: 'Close', exact: true })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialog(page)).toHaveCount(0);
    await expect(trigger).toBeFocused();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 0);
  },
);

check(
  'cancelling role edits sends nothing and reopening uses the unchanged provider',
  async (page) => {
    await open(page);
    let editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    assert.deepEqual(await calls(page), []);
    editor = await openRole(page, 'Réponses');
    await expect(editor.getByRole('combobox', { name: 'Fournisseur', exact: true })).toHaveValue(
      'claude-code',
    );
  },
);

check(
  'a delayed rejected field stops the batch, retains the editor and accepts one retry',
  async (page) => {
    await open(page);
    const editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await editor.locator('.model-advanced > summary').click();
    await editor
      .getByRole('textbox', { name: 'Endpoint', exact: true })
      .fill('https://llm.fixture.invalid');
    await page.evaluate(() => {
      window.modelFixture.delay = 80;
      window.modelFixture.failure = 'HINDSIGHT_API_REFLECT_LLM_MODEL';
      const form = document.querySelector('.model-editor');
      for (let i = 0; i < 30; i++) form.requestSubmit();
    });
    await expect(editor.getByRole('alert')).toContainText('Fixture rejects this change');
    assert.deepEqual(
      (await calls(page)).map((c) => c.command),
      ['server.provider', 'server.field'],
    );
    assert.equal((await calls(page))[1].args.name, P + 'REFLECT_LLM_MODEL');
    await expect(editor.getByRole('textbox', { name: 'Endpoint', exact: true })).toHaveValue(
      'https://llm.fixture.invalid',
    );
    await page.evaluate(() => {
      window.modelFixture.failure = '';
    });
    await prepare(editor).click();
    await expect(editor).toHaveCount(0);
    assert.ok((await calls(page)).some((c) => c.args.name === P + 'REFLECT_LLM_BASE_URL'));
  },
);

check(
  'local and Cloud selection updates the URL immediately and preserves later explicit advanced fields',
  async (page) => {
    await open(page);
    const editor = await openRole(page, 'Décision');
    const provider = editor.getByRole('combobox', { name: 'Fournisseur', exact: true });
    await expect(provider).toHaveValue('__hindsight_local__');
    await provider.selectOption('hindsight');
    await editor.locator('.model-advanced > summary').click();
    const url = editor.getByRole('textbox', { name: 'URL de base', exact: true });
    await expect(url).toHaveValue('');
    await provider.selectOption('__hindsight_local__');
    await expect(url).toHaveValue('http://127.0.0.1:8766');
    await provider.selectOption('hindsight');
    await editor.getByLabel('API key', { exact: true }).fill('fixture-explicit-key');
    await url.fill('https://decision.fixture.invalid');
    await expect(provider).toHaveValue('__hindsight_custom__');
    await prepare(editor).click();
    await expect(editor).toHaveCount(0);
    const requests = await calls(page);
    assert.equal(requests[0].command, 'server.decision');
    assert.equal(requests[0].args.source, 'cloud');
    assert.ok(
      requests.some(
        (c) =>
          c.args.name === P + 'DECISION_MODEL_BASE_URL' &&
          c.args.value === 'https://decision.fixture.invalid',
      ),
    );
    assert.ok(
      requests.some(
        (c) =>
          c.args.name === P + 'DECISION_MODEL_API_KEY' && c.args.value === 'fixture-explicit-key',
      ),
    );
  },
);

check(
  'changed script/revision blocks stale edits, including a context change during a delayed response',
  async (page) => {
    await open(page);
    let editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await page.evaluate(() =>
      window.modelFixture.update({
        modelWorkflow: { ...window.modelFixture.data.modelWorkflow, revision: 'external-change' },
      }),
    );
    await expect(prepare(editor)).toBeDisabled();
    await expect(editor.getByRole('alert')).toContainText('Settings changed');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await page.evaluate(() => {
      window.modelFixture.delay = 200;
      window.modelFixture.applyReplies = false;
    });
    await prepare(editor).click();
    await expect.poll(async () => (await calls(page)).length).toBe(1);
    await page.evaluate(() => window.modelFixture.update({ scriptPath: '/fictional/other.sh' }));
    await expect(editor.getByRole('alert')).toContainText('Settings changed');
    assert.equal(
      (await calls(page)).length,
      1,
      'the old batch must not write its remaining fields into a new script',
    );
  },
);

check(
  'workflow blocks repeated same-turn commands and keeps request errors visible',
  async (page) => {
    await open(page, 'workflow');
    await page.evaluate(() => {
      window.modelFixture.delay = 120;
      window.modelFixture.failure = 'server.models.prepare';
      const toggle = document.querySelector('input[role="switch"]');
      for (let i = 0; i < 40; i++) toggle.click();
    });
    await expect(page.getByRole('alert')).toContainText('Fixture rejects this change');
    assert.equal((await calls(page)).length, 1);
    await expect(page.getByRole('switch')).toBeEnabled();
  },
);

check(
  'memory polling preserves local edits, rejects non-object JSON and resets on bank remount',
  async (page) => {
    await open(page, 'memory');
    await page.evaluate(() =>
      window.modelFixture.update({ draft: { retainMission: 'Server mission' } }),
    );
    const mission = page.getByRole('textbox', { name: 'Memory mission', exact: true });
    await mission.fill('Local mission');
    await page.evaluate(() =>
      window.modelFixture.update({ draft: { retainMission: 'Server mission' } }),
    );
    await expect(mission).toHaveValue('Local mission');
    await page.getByRole('tab', { name: 'Expert', exact: true }).click();
    const advanced = page.getByRole('textbox', {
      name: 'Advanced JSON configuration',
      exact: true,
    });
    for (const value of ['null', '[]', '42', '"text"']) {
      await advanced.fill(value);
      await page.getByRole('button', { name: /^Save/ }).click();
    }
    assert.deepEqual(await calls(page), []);
    assert.equal(await page.evaluate(() => window.modelFixture.notifications.length), 4);
    await advanced.fill('{"retain_chunk_size": 1200}');
    await page.getByRole('button', { name: /^Save/ }).click();
    const request = (await calls(page))[0];
    assert.equal(request.args.config.retain_mission, 'Local mission');
    assert.equal(request.args.config.retain_chunk_size, 1200);
    await page.evaluate(() =>
      window.modelFixture.mount('memory', { draft: { retainMission: 'Bank B mission' } }, 'bank-b'),
    );
    await expect(mission).toHaveValue('Bank B mission');
  },
);

check(
  'a large synthetic catalog keeps the selected custom model and changes providers coherently',
  async (page) => {
    await open(page);
    await page.evaluate(() => {
      const f = window.modelFixture;
      const models = Array.from({ length: 8000 }, (_, i) => ({
        id: `synthetic-${i}`,
        title: `Synthetic ${i}`,
      }));
      f.update({ modelsByProvider: { ...f.data.modelsByProvider, gemini: models } });
    });
    const editor = await openRole(page, 'Réponses');
    const start = performance.now();
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    const models = editor.getByRole('combobox', { name: 'Modèle', exact: true });
    await expect(models).toHaveValue('synthetic-0');
    await models.selectOption('synthetic-7999');
    await expect(models).toHaveValue('synthetic-7999');
    await editor
      .getByRole('combobox', { name: 'Fournisseur', exact: true })
      .selectOption('claude-code');
    await expect(models).toHaveValue('claude-sonnet-5-5');
    assert.equal(await models.locator('option[value^="synthetic-"]').count(), 0);
    console.log(
      `  8,000-model selection/provider round trip: ${Math.round(performance.now() - start)} ms`,
    );
  },
);

try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    if (server.exitCode != null || i === 99)
      throw new Error('Isolated model test server did not start');
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
  for (const { name, fn } of cases) {
    const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });
    page.on('pageerror', (error) => errors.push(error.message));
    const started = performance.now();
    try {
      await fn(page);
      console.log(`PASS ${name} (${Math.round(performance.now() - started)} ms)`);
    } finally {
      await page.close();
    }
  }
  assert.deepEqual(errors, []);
  console.log(
    `${cases.length} isolated model/settings regressions passed; no bridge, app build or screenshots used.`,
  );
} finally {
  await browser?.close();
  server.kill();
}
