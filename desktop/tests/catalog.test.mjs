import test from 'node:test';
import assert from 'node:assert/strict';
import {
  sourceKind,
  sourceTextPath,
  filterRecords,
  catalogRecords,
  catalogProjects,
  sourceOriginalPath,
  isAsideRecord,
} from '../src/catalog.ts';

test('le catalogue réel classe ses quatre familles de collecteurs', () => {
  assert.equal(sourceKind('conversations'), 'conversation');
  assert.equal(sourceKind('github'), 'git');
  assert.equal(sourceKind('wandb'), 'note');
  assert.equal(sourceKind('benchmarks'), 'report');
});

test('les archives techniques restent disponibles sans masquer une conversation du même titre', () => {
  const records = [
    { id: 'human', title: 'Guardian review', context: { conversation_kind: 'conversation' } },
    { id: 'review', title: 'Autre titre', context: { conversation_kind: 'internal_review' } },
    { id: 'empty', context: { conversation_kind: 'empty_export' } },
    { id: 'legacy', title: 'Guardian review' },
  ];
  assert.equal(catalogRecords({ records }).length, 4);
  assert.deepEqual(
    records.filter(isAsideRecord).map((r) => r.id),
    ['review', 'empty'],
  );
  assert.deepEqual(
    records.filter((r) => !isAsideRecord(r)).map((r) => r.id),
    ['human', 'legacy'],
  );
});

test('les dépôts restent distincts et se combinent au filtre de projet', () => {
  const records = [
    { id: 'a', kind: 'github', project: 'nomad', repository: 'training' },
    { id: 'b', kind: 'github', project: 'nomad', repository: 'benchmark' },
    { id: 'c', kind: 'github', project: 'other', repository: 'training' },
  ];
  assert.deepEqual(
    filterRecords(records, '', 'git', 'nomad', 'training').map((r) => r.id),
    ['a'],
  );
  assert.deepEqual(
    filterRecords(records, '', 'git', 'all', 'training').map((r) => r.id),
    ['a', 'c'],
  );
});

test('la recherche retrouve la provenance et les accents Unicode exportés sur macOS', () => {
  const records = [
    {
      id: 'a',
      title: 'Évaluation'.normalize('NFD'),
      source_id: 'wandb://team/project/run42',
      context: { tags: ['politique V4'] },
    },
  ];
  for (const query of ['éval', 'run42', 'politique V4'])
    assert.equal(filterRecords(records, query, 'all', 'all').length, 1);
});

test('reclasser les archives ne rend pas une vieille source plus récente', () => {
  const records = [
    { id: 'old', source_updated_at: '2026-10-20T00:00:00Z', collected_at: '2026-10-29T22:00:00Z' },
    {
      id: 'recent',
      source_updated_at: '2026-10-29T00:00:00Z',
      collected_at: '2026-10-29T18:00:00Z',
    },
  ];
  assert.deepEqual(
    filterRecords(records, '', 'all', 'all').map((r) => r.id),
    ['recent', 'old'],
  );
});
test('la lecture choisit le document texte plutôt que les données brutes de session', () => {
  assert.equal(
    sourceTextPath({ files: { 'session.json': 'a/session.json', 'document.md': 'a/document.md' } }),
    'a/document.md',
  );
  assert.equal(sourceTextPath({ files: [{ path: 'a/content.txt' }] }), 'a/content.txt');
  assert.equal(sourceTextPath({ files: {} }), null);
});
test('les filtres combinent le projet, le texte et les notes ou rapports', () => {
  const records = [
    { id: '1', title: 'Décision', kind: 'github', project: 'a' },
    { id: '2', title: 'Évaluation', kind: 'benchmarks', project: 'a' },
    { id: '3', title: 'Évaluation', kind: 'wandb', project: 'b' },
  ];
  assert.deepEqual(
    filterRecords(records, 'éval', 'research', 'a').map((r) => r.id),
    ['2'],
  );
  assert.equal(filterRecords(records, '', 'research', 'all').length, 2);
});

test('les projets configurés sans source restent disponibles pour un ajout manuel', () => {
  assert.deepEqual(
    catalogProjects({
      projects: [{ id: 'new', name: 'Nouveau' }],
      records: [{ project: 'nomad', project_name: 'NOMAD' }],
    }),
    [
      ['nomad', 'NOMAD'],
      ['new', 'Nouveau'],
    ],
  );
  assert.deepEqual(catalogProjects(null), []);
});

test('les documents manuels conservent leur format et ne sont pas des archives techniques', () => {
  const tex = {
    kind: 'documents',
    project: 'nomad',
    repository: '',
    files: { 'memo.tex': 'nomad/documents/42/memo.tex' },
  };
  const pdf = { ...tex, files: { 'paper.pdf': 'nomad/documents/43/paper.pdf' } };
  assert.equal(sourceKind(tex.kind), 'document');
  assert.equal(sourceTextPath(tex), 'nomad/documents/42/memo.tex');
  assert.equal(sourceOriginalPath(pdf), 'nomad/documents/43/paper.pdf');
  assert.equal(sourceTextPath(pdf), null);
  assert.equal(isAsideRecord(tex), false);
  assert.equal(filterRecords([tex, pdf], '', 'document', 'nomad').length, 2);
});
