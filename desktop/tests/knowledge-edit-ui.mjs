import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect as baseExpect } from '@playwright/test';
import { createServer } from 'vite';

// A knowledge item's name and question are edited from its own page in Knowledge. A new question
// goes with its regeneration (one confirmed LLM call); a new name alone changes nothing else. Renders
// the Knowledge page with fictional data; no native bridge or Hindsight server is involved.
const fixture = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Models } from '/src/pages/Library.tsx';
import { I18nProvider } from '/src/i18n.tsx';
import '/src/styles.css';

const full = {
  id: 'mm-todo', bank_id: 'b', name: 'TODO', source_query: 'What is waiting for me?', tags: [],
  is_knowledge_page: false, content: '## Next\\n\\nNothing dated yet.',
  last_refreshed_at: '2026-11-08T10:00:00Z', created_at: '2026-11-01T10:00:00Z',
};
// The list carries metadata only, never the question: the page reads it from the full item.
const listed = { id: full.id, bank_id: 'b', name: full.name, tags: [], is_knowledge_page: false,
  last_refreshed_at: full.last_refreshed_at, created_at: full.created_at };
const controls = (window.__knowledgeFixture = { requests: [] });
function Fixture() {
  const [data, setData] = useState({ models: [listed], refreshing: [] });
  controls.setData = setData;
  async function run(command, args = {}) {
    controls.requests.push({ command, args });
    if (command === 'model.open') return { model: full };
    return {};
  }
  const props = { data, run, busy: false, demo: false, navigate: () => {}, refresh: async () => ({}),
    notify: (message) => { throw new Error(message); } };
  return React.createElement(Models, props);
}
createRoot(document.getElementById('root')).render(
  React.createElement(I18nProvider, null, React.createElement(Fixture)));
`;

const server = await createServer({
  root: fileURLToPath(new URL('../', import.meta.url)),
  logLevel: 'error',
  server: { host: '127.0.0.1', port: 0, strictPort: true, hmr: false, watch: null },
  plugins: [
    {
      name: 'knowledge-fixture',
      resolveId(id) {
        if (id === '/__knowledge-fixture.tsx') return '\0knowledge-fixture.tsx';
      },
      load(id) {
        if (id === '\0knowledge-fixture.tsx') return fixture;
      },
      configureServer(vite) {
        vite.middlewares.use(async (request, response, next) => {
          if (request.url !== '/__knowledge-test') return next();
          try {
            const html = await vite.transformIndexHtml(
              request.url,
              '<html><body><div id="root"></div><script type="module" src="/__knowledge-fixture.tsx"></script></body></html>',
            );
            response.setHeader('Content-Type', 'text/html');
            response.end(html);
          } catch (error) {
            next(error);
          }
        });
      },
    },
  ],
});

let browser;
const deadline = setTimeout(() => {
  console.error('Knowledge edit regression exceeded 60 seconds.');
  process.exitCode = 1;
  void browser?.close();
  void server.close();
  setTimeout(() => process.exit(1), 2000).unref();
}, 60_000);
const expect = baseExpect.configure({ timeout: 5000 });

try {
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  browser = await chromium.launch({
    headless: true,
    ...(process.env.HINDSIGHT_BROWSER_EXECUTABLE
      ? { executablePath: process.env.HINDSIGHT_BROWSER_EXECUTABLE }
      : { channel: 'chrome' }),
    timeout: 15_000,
  });
  for (const language of ['en', 'fr']) {
    const fr = language === 'fr';
    const tr = (french, english) => (fr ? french : english);
    const context = await browser.newContext({
      viewport: { width: 1280, height: 1000 },
      serviceWorkers: 'block',
    });
    await context.route('**/*', (route) =>
      new URL(route.request().url()).origin === base ? route.continue() : route.abort(),
    );
    await context.addInitScript(
      (lang) => localStorage.setItem('hindsight-desktop-language', lang),
      language,
    );
    const page = await context.newPage();
    page.setDefaultTimeout(5000);
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => message.type() === 'error' && errors.push(message.text()));
    await page.goto(`${base}/__knowledge-test`);
    const requests = () => page.evaluate(() => window.__knowledgeFixture.requests);

    await page.locator('.model-card').click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('What is waiting for me?');
    const edit = dialog.getByRole('button', {
      name: tr('Modifier le nom et la question', 'Edit the name and question'),
    });
    const regenerate = dialog.getByRole('button', {
      name: tr('Régénérer', 'Regenerate'),
      exact: true,
    });
    await expect(regenerate).toBeVisible();

    // The form starts from the current values; nothing to save yet, and one main action at a time.
    await edit.click();
    const form = dialog.getByRole('form', {
      name: tr('Modifier le nom et la question', 'Edit the name and question'),
    });
    const nameField = form.getByRole('textbox', {
      name: tr('Nom du modèle mental', 'Mental model name'),
    });
    const questionField = form.getByRole('textbox', {
      name: tr('La question à explorer', 'The question to explore'),
    });
    await expect(nameField).toHaveValue('TODO');
    await expect(questionField).toHaveValue('What is waiting for me?');
    await expect(regenerate).toHaveCount(0);
    await expect(edit).toHaveCount(0);
    const save = form.getByRole('button', { name: tr('Enregistrer', 'Save'), exact: true });
    await expect(save).toBeDisabled();

    // A new name alone: saved without regenerating.
    await nameField.fill('Deadlines');
    await expect(save).toBeEnabled();
    await expect(form).toContainText(
      tr(
        'Changer le nom ne touche pas au contenu.',
        'Changing the name leaves the content as it is.',
      ),
    );

    // A new question: saved with its regeneration, which the confirmation will price.
    await questionField.fill('What is due in the next six weeks, by date?');
    const saveAndRegenerate = form.getByRole('button', {
      name: tr('Enregistrer et régénérer', 'Save and regenerate'),
    });
    await expect(saveAndRegenerate).toBeEnabled();
    await expect(save).toHaveCount(0);
    await expect(form).toContainText(
      tr(
        'L’estimation sera présentée avant confirmation.',
        'An estimate will be shown before you confirm.',
      ),
    );
    // An emptied question cannot be saved.
    await questionField.fill('  ');
    await expect(
      form.getByRole('button', { name: tr('Enregistrer', 'Save'), exact: true }),
    ).toBeDisabled();
    await questionField.fill('What is due in the next six weeks, by date?');

    // Cancel sends nothing and brings the page's actions back.
    const before = (await requests()).length;
    await form.getByRole('button', { name: tr('Annuler', 'Cancel') }).click();
    await expect(form).toHaveCount(0);
    await expect(regenerate).toBeVisible();
    assert.equal((await requests()).length, before);

    // Submitting asks the engine; the form stays until the page read back carries the new values.
    await edit.click();
    await nameField.fill('Deadlines');
    await questionField.fill('What is due in the next six weeks, by date?');
    await saveAndRegenerate.click();
    assert.deepEqual((await requests()).at(-1), {
      command: 'model.update',
      args: {
        id: 'mm-todo',
        name: 'Deadlines',
        query: 'What is due in the next six weeks, by date?',
      },
    });
    await expect(form).toBeVisible();
    await page.evaluate(() =>
      window.__knowledgeFixture.setData((old) => ({
        ...old,
        refreshing: ['mm-todo'],
        openModel: {
          id: 'mm-todo',
          bank_id: 'b',
          name: 'Deadlines',
          source_query: 'What is due in the next six weeks, by date?',
          tags: [],
          is_knowledge_page: false,
          content: '## Next\n\nNothing dated yet.',
        },
      })),
    );
    await expect(form).toHaveCount(0);
    await expect(dialog.locator('.modal-header, header').first()).toContainText('Deadlines');
    await expect(dialog).toContainText('What is due in the next six weeks, by date?');
    await expect(
      dialog.getByRole('button', { name: tr('Régénération en cours', 'Regenerating') }),
    ).toBeDisabled();

    assert.deepEqual(errors, []);
    await context.close();
  }
  console.log('Knowledge edit regression passed in English and French.');
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  clearTimeout(deadline);
  await browser?.close();
  await server.close();
}
