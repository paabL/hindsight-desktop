import test from 'node:test';
import assert from 'node:assert/strict';
import {
  analyzeGraph,
  aggregateConnections,
  cleanGraph,
  framePoints,
  layoutGraph,
  neighborhood,
  normalize,
  shortestPath,
} from '../src/graph-model.ts';

const nodes = (ids) => ids.map((id) => ({ id, label: id, kind: 'entity', weight: 1 }));
const edge = (source, target, weight = 1, kind = 'cooccurrence') => ({
  source,
  target,
  weight,
  kind,
});
const model = (ids, edges) => {
  const data = cleanGraph(nodes(ids), edges);
  return analyzeGraph(data.nodes, data.edges);
};

test('un chemin suit les liens réels et ne traverse jamais une composante déconnectée', () => {
  const graph = model(
    ['a', 'b', 'c', 'd', 'isolated'],
    [edge('a', 'b'), edge('b', 'c'), edge('c', 'd'), edge('a', 'c')],
  );
  assert.deepEqual(shortestPath(graph, 'a', 'd'), ['a', 'c', 'd']);
  assert.deepEqual(shortestPath(graph, 'a', 'a'), ['a']);
  assert.deepEqual(shortestPath(graph, 'a', 'isolated'), []);
  assert.deepEqual(shortestPath(graph, 'missing', 'a'), []);
  assert.equal(graph.components, 2);
});

test('le parcours et le voisinage respectent les filtres actifs', () => {
  const graph = model(
    ['a', 'b', 'c', 'd'],
    [edge('a', 'b'), edge('b', 'c'), edge('c', 'd', 1, 'temporal')],
  );
  assert.deepEqual([...neighborhood(graph, 'a', 1)], ['a', 'b']);
  assert.deepEqual([...neighborhood(graph, 'a', 2)], ['a', 'b', 'c']);
  const filtered = analyzeGraph(
    graph.nodes,
    graph.edges.filter((e) => e.kind !== 'temporal'),
  );
  assert.deepEqual(shortestPath(filtered, 'a', 'd'), []);
  assert.equal(neighborhood(graph, 'missing', 2).size, 0);
});

test('les doublons, boucles, poids invalides et liens vers des nœuds absents ne créent pas de relations', () => {
  const cleaned = cleanGraph(
    [...nodes(['a', 'b']), { id: 'a', label: 'doublon' }, { id: null }],
    [
      edge('a', 'b', 3),
      edge('b', 'a', 2),
      edge('a', 'a'),
      edge('a', 'missing'),
      edge('a', 'b', 0, 'semantic'),
      edge('a', 'b', Infinity, 'invalid'),
      edge('a', 'b', NaN, 'invalid'),
    ],
  );
  assert.equal(cleaned.nodes.length, 2);
  assert.equal(cleaned.edges.length, 1);
  const graph = analyzeGraph(cleaned.nodes, cleaned.edges);
  assert.equal(graph.degree.get('a'), 1);
  assert.equal(cleaned.edges[0].weight, 3);
});

test('les groupes suivent les liens forts et les passerelles identifient leurs points de contact', () => {
  const graph = model(
    ['a', 'b', 'c', 'd', 'e', 'f'],
    [
      edge('a', 'b', 20),
      edge('a', 'c', 20),
      edge('b', 'c', 20),
      edge('d', 'e', 20),
      edge('d', 'f', 20),
      edge('e', 'f', 20),
      edge('c', 'd', 1),
    ],
  );
  assert.equal(graph.communities.length, 2);
  assert.equal(graph.membership.get('a'), graph.membership.get('c'));
  assert.notEqual(graph.membership.get('a'), graph.membership.get('d'));
  assert.deepEqual(new Set(graph.bridges.map((b) => b.node.id)), new Set(['c', 'd']));
});

test('la carte reste déterministe entre deux inspections et dispose les groupes sans coordonnées invalides', () => {
  const graph = model(['a', 'b', 'c', 'd', 'e'], [edge('a', 'b'), edge('c', 'd')]);
  const first = layoutGraph(graph);
  assert.deepEqual(layoutGraph(graph), first);
  assert.equal(first.positions.size, 5);
  assert.equal(new Set([...first.positions.values()].map((p) => `${p.x},${p.y}`)).size, 5);
  for (const p of first.positions.values()) assert.ok(Number.isFinite(p.x) && Number.isFinite(p.y));
  assert.ok(framePoints([...first.positions.values()]).width > 0);
  assert.equal(normalize('Énergie'), normalize('energie'));
});

test('mille nœuds restent explorables, y compris avec des composantes et des nœuds isolés', () => {
  const ids = Array.from({ length: 1000 }, (_, i) => `n${i}`);
  const graph = model(
    ids,
    ids.slice(1, 900).map((id, i) => edge(`n${i}`, id)),
  );
  const layout = layoutGraph(graph);
  assert.equal(layout.positions.size, 1000);
  assert.equal(graph.components, 101);
  assert.equal(shortestPath(graph, 'n0', 'n899').length, 900);
  assert.deepEqual(shortestPath(graph, 'n0', 'n999'), []);
});

test('plusieurs entités partagées restent des explications distinctes du même voisinage', () => {
  const data = cleanGraph(nodes(['a', 'b']), [
    { ...edge('a', 'b', 1, 'entity'), label: 'NOMAD' },
    { ...edge('a', 'b', 1, 'entity'), label: 'PPO' },
  ]);
  assert.equal(data.edges.length, 2);
  assert.deepEqual(new Set(data.edges.map((e) => e.label)), new Set(['NOMAD', 'PPO']));
  assert.equal(analyzeGraph(data.nodes, data.edges).degree.get('a'), 1);
});

test('la vue agrégée compte seulement les liens réels entre groupes', () => {
  const graph = model(
    ['a', 'b', 'c', 'd', 'e', 'f'],
    [
      edge('a', 'b', 20),
      edge('a', 'c', 20),
      edge('b', 'c', 20),
      edge('d', 'e', 20),
      edge('d', 'f', 20),
      edge('e', 'f', 20),
      edge('c', 'd', 1),
    ],
  );
  const aggregated = aggregateConnections(graph);
  assert.equal(aggregated.length, 1);
  assert.equal(aggregated[0].count, 1);
  assert.notEqual(aggregated[0].source, aggregated[0].target);
});

test('les libellés des groupes favorisent les sujets lisibles sans retirer les marqueurs de la carte', () => {
  const data = cleanGraph(
    [
      { id: 'meta', label: 'kind:infra', weight: 100, kind: 'entity' },
      { id: 'cpu', label: 'CPU', weight: 4, kind: 'entity' },
      { id: 'gpu', label: 'GPU', weight: 3, kind: 'entity' },
    ],
    [edge('meta', 'cpu'), edge('meta', 'gpu'), edge('cpu', 'gpu')],
  );
  const graph = analyzeGraph(data.nodes, data.edges);
  assert.equal(graph.communities.length, 1);
  assert.equal(graph.communities[0].entry.label, 'CPU');
  assert.equal(graph.communities[0].label, 'CPU · GPU');
  assert.equal(graph.nodes.length, 3);
});
