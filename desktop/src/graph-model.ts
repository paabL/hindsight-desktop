import { translate as t, getLocale } from './i18n-core.ts';
import { factTypeLabel } from './fact-types.ts';
/** Analyse locale des liens fournis par Hindsight. Aucun lien ni sujet n'est inventé. */
export type MemoryNode = {
  id: string;
  label: string;
  detail: string;
  kind: string;
  weight: number;
  mentionedAt?: string;
  occurredAt?: string;
};
export type MemoryEdge = {
  id: string;
  source: string;
  target: string;
  kind: string;
  weight: number;
  label?: string;
};
export type Point = { x: number; y: number };
export type Community = {
  id: string;
  nodes: MemoryNode[];
  entry: MemoryNode;
  label: string;
  color: number;
  weight: number;
};
export type MemoryGraph = ReturnType<typeof analyzeGraph>;

export const relationLabel = (kind: string) =>
  ({
    related: t('Relation', 'Relationship'),
    cooccurrence: t('Cooccurrence', 'Co-occurrence'),
    semantic: t('Similarité', 'Similarity'),
    temporal: t('Chronologie', 'Timeline'),
    entity: t('Entité partagée', 'Shared entity'),
    causal: t('Causalité', 'Causality'),
    causes: t('Causalité', 'Causality'),
  })[kind] ||
  kind.replaceAll('_', ' ') ||
  t('Relation', 'Relationship');
export function edgeDescription(edge: MemoryEdge) {
  if (edge.kind === 'cooccurrence')
    return t(
      `${edge.weight.toLocaleString(getLocale())} cooccurrence${edge.weight > 1 ? 's' : ''}`,
      `${edge.weight.toLocaleString(getLocale())} co-occurrence${edge.weight > 1 ? 's' : ''}`,
    );
  return relationLabel(edge.kind) + (edge.label ? ` · ${edge.label}` : '');
}
export const kindLabel = (kind: string) =>
  kind === 'entity' ? t('Entité', 'Entity') : factTypeLabel(kind);
export const normalize = (value: string) =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('fr');
export const shorten = (value: string, length = 34) =>
  value.length > length ? value.slice(0, length - 1).trimEnd() + '…' : value;

export function cleanGraph(rawNodes: Record<string, any>[], rawEdges: Record<string, any>[]) {
  const byID = new Map<string, MemoryNode>();
  for (const raw of rawNodes) {
    if (typeof raw.id !== 'string' || !raw.id || byID.has(raw.id)) continue;
    byID.set(raw.id, {
      id: raw.id,
      label: String(raw.label || raw.detail || raw.id),
      detail: String(raw.detail || ''),
      kind: String(raw.kind || 'entity'),
      weight: Number.isFinite(raw.weight) ? Math.max(0, raw.weight) : 1,
      mentionedAt: raw.mentionedAt,
      occurredAt: raw.occurredAt,
    });
  }
  const links = new Map<string, MemoryEdge>();
  for (const raw of rawEdges) {
    if (!byID.has(raw.source) || !byID.has(raw.target) || raw.source === raw.target) continue;
    const [source, target] = [raw.source, raw.target].sort();
    const kind = String(raw.kind || 'related');
    const label = typeof raw.label === 'string' ? raw.label : '';
    const id = JSON.stringify([source, target, kind, label]);
    const weight =
      raw.weight == null ? 1 : Number.isFinite(raw.weight) ? Math.max(0, raw.weight) : 0;
    if (weight <= 0) continue;
    if (!links.has(id) || links.get(id)!.weight < weight)
      links.set(id, { id, source, target, kind, weight, label });
  }
  return {
    nodes: [...byID.values()],
    edges: [...links.values()].sort((a, b) => b.weight - a.weight || a.id.localeCompare(b.id)),
  };
}

export function analyzeGraph(nodes: MemoryNode[], edges: MemoryEdge[]) {
  const byID = new Map(nodes.map((n) => [n.id, n]));
  const adjacency = new Map(nodes.map((n) => [n.id, new Map<string, number>()]));
  for (const e of edges) {
    if (!byID.has(e.source) || !byID.has(e.target)) continue;
    // Une racine réduit l'influence des cooccurrences très fréquentes sur le regroupement.
    const weight = Math.sqrt(e.weight);
    adjacency.get(e.source)!.set(e.target, (adjacency.get(e.source)!.get(e.target) || 0) + weight);
    adjacency.get(e.target)!.set(e.source, (adjacency.get(e.target)!.get(e.source) || 0) + weight);
  }
  const degree = new Map(nodes.map((n) => [n.id, adjacency.get(n.id)!.size]));
  const strength = new Map(
    nodes.map((n) => [n.id, [...adjacency.get(n.id)!.values()].reduce((a, b) => a + b, 0)]),
  );
  const order = [...nodes].sort(
    (a, b) => strength.get(b.id)! - strength.get(a.id)! || a.id.localeCompare(b.id),
  );
  const membership = new Map(nodes.map((n) => [n.id, n.id]));
  const totals = new Map(strength);
  const total = [...strength.values()].reduce((a, b) => a + b, 0) || 1;
  // Optimisation locale de modularité, déterministe : la couleur suit la topologie, jamais l'ordre des lignes.
  for (let pass = 0; pass < 18; pass++) {
    let moved = false;
    for (const node of order) {
      const current = membership.get(node.id)!;
      const k = strength.get(node.id)!;
      if (!k) continue;
      totals.set(current, totals.get(current)! - k);
      const weights = new Map<string, number>();
      for (const [id, w] of adjacency.get(node.id)!) {
        const community = membership.get(id)!;
        weights.set(community, (weights.get(community) || 0) + w);
      }
      let best = current;
      let score = (weights.get(current) || 0) - (k * (totals.get(current) || 0)) / total;
      for (const [candidate, weight] of weights) {
        const candidateScore = weight - (k * (totals.get(candidate) || 0)) / total;
        if (candidateScore > score + 1e-8) {
          score = candidateScore;
          best = candidate;
        }
      }
      membership.set(node.id, best);
      totals.set(best, (totals.get(best) || 0) + k);
      moved ||= best !== current;
    }
    if (!moved) break;
  }
  const grouped = new Map<string, MemoryNode[]>();
  for (const n of nodes) {
    const key = membership.get(n.id)!;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key)!.push(n);
  }
  const communities: Community[] = [...grouped.values()]
    .map((members) => {
      members.sort(
        (a, b) =>
          degree.get(b.id)! - degree.get(a.id)! || b.weight - a.weight || a.id.localeCompare(b.id),
      );
      const id = members.map((n) => n.id).sort()[0];
      const readable = members.filter(
        (n) => !/^(kind|statut|knowledge|repo|projet|source|task):/i.test(n.label),
      );
      const representatives = readable.length ? readable : members;
      return {
        id,
        nodes: members,
        entry: representatives[0],
        label: representatives
          .slice(0, 2)
          .map((n) => shorten(n.label, 24))
          .join(' · '),
        color: 0,
        weight: members.length,
      };
    })
    .sort((a, b) => b.weight - a.weight || a.id.localeCompare(b.id));
  for (const [i, c] of communities.entries()) {
    c.color = i % 6;
    for (const n of c.nodes) membership.set(n.id, c.id);
  }
  const visited = new Set<string>();
  let components = 0;
  for (const node of nodes) {
    if (visited.has(node.id)) continue;
    components++;
    const queue = [node.id];
    visited.add(node.id);
    for (let i = 0; i < queue.length; i++)
      for (const id of adjacency.get(queue[i])!.keys()) {
        if (!visited.has(id)) {
          visited.add(id);
          queue.push(id);
        }
      }
  }
  const bridges = nodes
    .map((n) => {
      const groups = new Set([...adjacency.get(n.id)!.keys()].map((id) => membership.get(id)!));
      groups.delete(membership.get(n.id)!);
      return { node: n, groups: groups.size };
    })
    .filter((n) => n.groups > 0)
    .sort((a, b) => b.groups - a.groups || degree.get(b.node.id)! - degree.get(a.node.id)!);
  return { nodes, edges, byID, adjacency, degree, membership, communities, bridges, components };
}

/** Le chemin le plus court en nombre de liens, dans l'échantillon et avec les filtres actifs. */
export function shortestPath(
  graph: Pick<MemoryGraph, 'adjacency'>,
  start: string,
  end: string,
): string[] {
  if (!graph.adjacency.has(start) || !graph.adjacency.has(end)) return [];
  const previous = new Map<string, string | null>([[start, null]]);
  const queue = [start];
  for (let i = 0; i < queue.length; i++) {
    if (queue[i] === end) {
      const result: string[] = [];
      for (let id: string | null = end; id !== null; id = previous.get(id) ?? null) result.push(id);
      return result.reverse();
    }
    for (const id of graph.adjacency.get(queue[i])!.keys())
      if (!previous.has(id)) {
        previous.set(id, queue[i]);
        queue.push(id);
      }
  }
  return [];
}

export function neighborhood(graph: Pick<MemoryGraph, 'adjacency'>, start: string, hops: number) {
  if (!graph.adjacency.has(start)) return new Set<string>();
  const found = new Set([start]);
  let frontier = [start];
  for (let i = 0; i < hops; i++) {
    const next: string[] = [];
    for (const source of frontier)
      for (const id of graph.adjacency.get(source)!.keys()) {
        if (!found.has(id)) {
          found.add(id);
          next.push(id);
        }
      }
    frontier = next;
  }
  return found;
}

/** Carte stable à deux échelles : groupes espacés, puis placement des nœuds guidé par leurs liens. */
export function layoutGraph(graph: MemoryGraph) {
  const centers = new Map<string, Point>();
  const radii = new Map<string, number>();
  const groups = graph.communities;
  for (const [i, c] of groups.entries()) {
    const angle = i * 2.399963;
    const distance = i ? 180 * Math.sqrt(i) : 0;
    centers.set(c.id, { x: Math.cos(angle) * distance, y: Math.sin(angle) * distance * 0.8 });
    radii.set(c.id, 52 + Math.sqrt(c.nodes.length) * 28);
  }
  // Répulsion des groupes avec une grille : coût borné même avec beaucoup de nœuds isolés.
  for (let step = 0; step < 80; step++) {
    const grid = new Map<string, Community[]>();
    const cell = 700;
    for (const c of groups) {
      const p = centers.get(c.id)!;
      const gx = Math.floor(p.x / cell),
        gy = Math.floor(p.y / cell);
      for (let x = gx - 2; x <= gx + 2; x++)
        for (let y = gy - 2; y <= gy + 2; y++)
          for (const other of grid.get(`${x},${y}`) || []) {
            const q = centers.get(other.id)!;
            const dx = p.x - q.x,
              dy = p.y - q.y;
            const d = Math.hypot(dx, dy) || 1;
            const gap = radii.get(c.id)! + radii.get(other.id)! + 40;
            if (d < gap) {
              const push = (gap - d) * 0.35;
              p.x += (dx / d) * push;
              p.y += (dy / d) * push;
              q.x -= (dx / d) * push;
              q.y -= (dy / d) * push;
            }
          }
      const key = `${Math.floor(p.x / cell)},${Math.floor(p.y / cell)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key)!.push(c);
    }
  }
  const local = new Map<string, Point>();
  for (const c of groups)
    for (const [i, n] of c.nodes.entries()) {
      const d = i ? Math.sqrt(i) * 42 : 0;
      local.set(n.id, { x: Math.cos(i * 2.399963) * d, y: Math.sin(i * 2.399963) * d });
    }
  // Attraction interne et collisions. Les groupes restent stables entre deux sélections.
  for (let step = 0; step < 55; step++) {
    for (const c of groups) {
      const grid = new Map<string, MemoryNode[]>();
      for (const n of c.nodes) {
        const p = local.get(n.id)!;
        let ax = 0,
          ay = 0,
          total = 0;
        for (const [id, w] of graph.adjacency.get(n.id)!)
          if (graph.membership.get(id) === c.id) {
            const q = local.get(id)!;
            ax += q.x * w;
            ay += q.y * w;
            total += w;
          }
        if (total) {
          p.x += (ax / total - p.x) * 0.025;
          p.y += (ay / total - p.y) * 0.025;
        }
        const gx = Math.floor(p.x / 70),
          gy = Math.floor(p.y / 70);
        for (let x = gx - 1; x <= gx + 1; x++)
          for (let y = gy - 1; y <= gy + 1; y++)
            for (const other of grid.get(`${x},${y}`) || []) {
              const q = local.get(other.id)!;
              const dx = p.x - q.x,
                dy = p.y - q.y,
                distance = Math.hypot(dx, dy) || 0.1;
              const gap = 46 + Math.min(10, Math.sqrt(graph.degree.get(n.id)!));
              if (distance < gap) {
                const push = (gap - distance) * 0.5;
                p.x += (dx / distance) * push;
                p.y += (dy / distance) * push;
                q.x -= (dx / distance) * push;
                q.y -= (dy / distance) * push;
              }
            }
        const key = `${Math.floor(p.x / 70)},${Math.floor(p.y / 70)}`;
        if (!grid.has(key)) grid.set(key, []);
        grid.get(key)!.push(n);
      }
    }
  }
  const positions = new Map<string, Point>();
  const bounds = new Map<string, { x: number; y: number; rx: number; ry: number }>();
  for (const c of groups) {
    const center = centers.get(c.id)!;
    let rx = 0,
      ry = 0;
    for (const n of c.nodes) {
      const p = local.get(n.id)!;
      rx = Math.max(rx, Math.abs(p.x));
      ry = Math.max(ry, Math.abs(p.y));
      positions.set(n.id, { x: center.x + p.x, y: center.y + p.y });
    }
    bounds.set(c.id, { ...center, rx: rx + 48, ry: ry + 60 });
  }
  return { positions, bounds };
}

export function framePoints(points: Point[], padding = 80) {
  if (!points.length) return { x: 0, y: 0, width: 900, height: 600 };
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  for (const p of points) {
    minX = Math.min(minX, p.x);
    minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x);
    maxY = Math.max(maxY, p.y);
  }
  return {
    x: (minX + maxX) / 2,
    y: (minY + maxY) / 2,
    width: Math.max(260, maxX - minX + padding * 2),
    height: Math.max(200, maxY - minY + padding * 2),
  };
}

/** Un trait par paire de groupes ; son compteur est le nombre de relations réellement agrégées. */
export function aggregateConnections(graph: MemoryGraph) {
  const pairs = new Map<string, { id: string; source: string; target: string; count: number }>();
  for (const edge of graph.edges) {
    const a = graph.membership.get(edge.source),
      b = graph.membership.get(edge.target);
    if (!a || !b || a === b) continue;
    const [source, target] = [a, b].sort();
    const id = JSON.stringify([source, target]);
    const pair = pairs.get(id) || { id, source, target, count: 0 };
    pair.count++;
    pairs.set(id, pair);
  }
  return [...pairs.values()].sort((a, b) => b.count - a.count || a.id.localeCompare(b.id));
}
