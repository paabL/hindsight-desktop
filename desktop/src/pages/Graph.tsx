import { useI18n } from '../i18n';
import { translate as t, getLocale } from '../i18n-core';
import { useEffect, useId, useMemo, useRef, useState } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronRight,
  Compass,
  FileText,
  Focus,
  GitBranch,
  Layers3,
  Maximize2,
  MousePointer2,
  Network,
  Route,
  Search,
  SlidersHorizontal,
  X,
  ZoomIn,
  ZoomOut,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
import {
  Badge,
  Button,
  Empty,
  ErrorNotice,
  IconButton,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { nativeSystemMessage } from '../native-messages';
import { DocumentReader } from './Library';
import {
  analyzeGraph,
  aggregateConnections,
  edgeDescription,
  cleanGraph,
  framePoints,
  kindLabel,
  layoutGraph,
  neighborhood,
  normalize,
  relationLabel,
  shorten,
  shortestPath,
  type MemoryEdge,
  type MemoryNode,
} from '../graph-model';
import '../graph.css';

type Camera = { x: number; y: number; zoom: number };
const edgeKey = (a: string, b: string) => JSON.stringify([a, b].sort());
const colors = [
  'var(--accent)',
  'var(--lavender-ink)',
  'var(--sage-ink)',
  'var(--blue-ink)',
  'var(--atlas-plum)',
  'var(--atlas-rose)',
];

export default function Graph({ data, run, refresh, busy }: PageProps) {
  useI18n();
  const [requestedMode, setRequestedMode] = useState('entities');
  const mode: string = data.mode || requestedMode;
  const [limit, setLimit] = useState(300);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [community, setCommunity] = useState<string | null>(null);
  const [scope, setScope] = useState('map');
  const [hops, setHops] = useState(1);
  const [anchor, setAnchor] = useState<string | null>(null);
  const [pathTarget, setPathTarget] = useState<string | null>(null);
  const [relation, setRelation] = useState('all');
  const [density, setDensity] = useState(0);
  const [filters, setFilters] = useState(false);
  const [tab, setTab] = useState('connections');
  const [overviewTab, setOverviewTab] = useState('groups');
  const [overviewLimit, setOverviewLimit] = useState(24);
  const [factsLimit, setFactsLimit] = useState(10);
  const [loadingDetails, setLoadingDetails] = useState(false);
  const [selectionDetails, setSelectionDetails] = useState<Row | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [reader, setReader] = useState<Row | null>(null);
  const [hovered, setHovered] = useState<string | null>(null);
  const [hoveredGroup, setHoveredGroup] = useState<string | null>(null);
  const [camera, setCamera] = useState<Camera | null>(null);
  const [size, setSize] = useState({ width: 900, height: 650 });
  const surface = useRef<HTMLDivElement>(null);
  const svg = useRef<SVGSVGElement>(null);
  const selectionRequest = useRef(0);
  const sourceRequest = useRef(0);
  const drag = useRef<{ x: number; y: number; camera: Camera } | null>(null);
  const id = useId().replaceAll(':', '');
  // Les réponses d'inspection ne doivent ni recalculer ni déplacer la carte. La clé (près d'un mégaoctet
  // de texte) n'est recalculée qu'à l'arrivée d'une réponse, pas à chaque image de zoom ou de survol.
  const graphKey = useMemo(
    () => JSON.stringify([data.mode, data.nodes || [], data.edges || []]),
    [data.mode, data.nodes, data.edges],
  );
  const source = useMemo(() => cleanGraph(data.nodes || [], data.edges || []), [graphKey]);
  const kinds = useMemo(() => [...new Set(source.edges.map((e) => e.kind))].sort(), [source]);
  const eligibleEdges = useMemo(
    () => source.edges.filter((e) => relation === 'all' || e.kind === relation),
    [source, relation],
  );
  const weights = useMemo(
    () => eligibleEdges.map((e) => e.weight).sort((a, b) => a - b),
    [eligibleEdges],
  );
  const threshold = weights[Math.floor((Math.max(0, weights.length - 1) * density) / 100)] || 0;
  const graph = useMemo(
    () =>
      analyzeGraph(
        source.nodes,
        eligibleEdges.filter((e) => e.weight >= threshold),
      ),
    [source, eligibleEdges, threshold],
  );
  const layout = useMemo(() => layoutGraph(graph), [graph]);
  const activeCommunity = graph.communities.find((c) => c.id === community);
  const current = selected ? graph.byID.get(selected) : undefined;
  const hoverNode = hovered ? graph.byID.get(hovered) : undefined;
  const hoverPoint = hovered ? layout.positions.get(hovered) : undefined;
  // Valeurs dérivées gardées d'un rendu à l'autre : le zoom et le survol ne changent que la caméra.
  const neighbors = useMemo(
    () =>
      selected
        ? graph.adjacency.get(selected) || new Map<string, number>()
        : new Map<string, number>(),
    [graph, selected],
  );
  const matches = useMemo(
    () =>
      query.trim()
        ? graph.nodes
            .filter((n) => normalize(n.label + ' ' + n.detail).includes(normalize(query.trim())))
            .sort((a, b) => graph.degree.get(b.id)! - graph.degree.get(a.id)!)
        : [],
    [graph, query],
  );
  const matchIDs = useMemo(() => new Set(matches.map((n) => n.id)), [matches]);
  const path = useMemo(
    () => (anchor && pathTarget ? shortestPath(graph, anchor, pathTarget) : []),
    [graph, anchor, pathTarget],
  );
  const pathIDs = useMemo(() => new Set(path), [path]);
  const pathEdges = useMemo(
    () => new Set(path.slice(1).map((node, i) => edgeKey(node, path[i]))),
    [path],
  );
  // Sans chemin affiché, aucun lien n'en fait partie : inutile de construire la clé de chacun.
  const isOnPath = (e: MemoryEdge) =>
    pathEdges.size > 0 && pathEdges.has(edgeKey(e.source, e.target));
  const visibleIDs = useMemo(() => {
    if (scope === 'neighbors' && selected) return neighborhood(graph, selected, hops);
    return new Set((activeCommunity?.nodes || graph.nodes).map((n) => n.id));
  }, [graph, scope, selected, hops, activeCommunity]);
  const visibleNodes = useMemo(
    () => graph.nodes.filter((n) => visibleIDs.has(n.id)),
    [graph, visibleIDs],
  );
  const visibleEdges = useMemo(
    () => graph.edges.filter((e) => visibleIDs.has(e.source) && visibleIDs.has(e.target)),
    [graph, visibleIDs],
  );
  const edgeBudget = Math.min(1800, Math.max(120, visibleNodes.length * 2));
  const shownEdges = useMemo(
    () =>
      visibleEdges.filter(
        (e, i) => i < edgeBudget || e.source === selected || e.target === selected || isOnPath(e),
      ),
    [visibleEdges, edgeBudget, selected, pathEdges],
  );
  const frame = useMemo(
    () => framePoints(visibleNodes.map((n) => layout.positions.get(n.id)!)),
    [layout, visibleIDs],
  );
  const aspect = size.width / size.height;
  const span = Math.max(frame.width, frame.height * aspect);
  const view = camera || { x: frame.x, y: frame.y, zoom: 1 };
  const width = span / view.zoom,
    height = width / aspect;
  const viewport = { x: view.x - width / 2, y: view.y - height / 2, width, height };
  const aggregate =
    graph.nodes.length > 80 &&
    !selected &&
    !community &&
    !query &&
    !anchor &&
    scope === 'map' &&
    view.zoom < 1.6;
  const groupLinks = useMemo(() => aggregateConnections(graph), [graph]);
  const hoverCommunity = graph.communities.find((c) => c.id === hoveredGroup);
  const cameraRef = useRef({ view, span, aspect });
  cameraRef.current = { view, span, aspect };
  const miniFrame = useMemo(() => framePoints([...layout.positions.values()], 70), [layout]);
  // Conserver la réponse de la dernière sélection acceptée : une ancienne inspection peut encore
  // arriver dans le snapshot global après celle-ci, sans avoir le droit d'effacer ses faits.
  const detailData = selectionDetails || data;
  const detailsReady = detailData.selectedNodeID === selected;
  const facts: Row[] = detailsReady ? detailData.nodeFacts || [] : [];
  // Couleur du premier groupe portant l'identifiant, comme une recherche dans la liste, sans la parcourir.
  const communityColors = useMemo(() => {
    const byID = new Map<string, number>();
    for (const c of graph.communities) if (!byID.has(c.id)) byID.set(c.id, c.color);
    return byID;
  }, [graph]);
  const colorFor = (node: MemoryNode) => {
    const community = graph.membership.get(node.id);
    return colors[(community !== undefined && communityColors.get(community)) || 0];
  };

  useEffect(() => {
    setCamera(null);
    setSelected(null);
    setCommunity(null);
    setAnchor(null);
    setPathTarget(null);
    setScope('map');
    setDetailError(null);
    setSelectionDetails(null);
    setLoadingDetails(false);
    setReader(null);
    selectionRequest.current++;
    sourceRequest.current++;
    return () => {
      selectionRequest.current++;
      sourceRequest.current++;
    };
  }, [graphKey]);
  useEffect(() => {
    setCamera(null);
  }, [scope, community, hops, relation, density]);
  useEffect(() => {
    if (data.limit) setLimit(data.limit);
  }, [data.limit]);
  useEffect(() => {
    if (!surface.current) return;
    const observer = new ResizeObserver((entries) => {
      const { width, height } = entries[0].contentRect;
      if (width && height) setSize({ width, height });
    });
    observer.observe(surface.current);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    const element = svg.current;
    if (!element) return;
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      const { view, span, aspect } = cameraRef.current;
      const rect = element.getBoundingClientRect();
      const zoom = Math.max(0.25, Math.min(12, view.zoom * Math.exp(-event.deltaY * 0.002)));
      const px = (((event.clientX - rect.left) / rect.width - 0.5) * span) / view.zoom;
      const py = (((event.clientY - rect.top) / rect.height - 0.5) * span) / view.zoom / aspect;
      setCamera({
        x: view.x + px * (1 - view.zoom / zoom),
        y: view.y + py * (1 - view.zoom / zoom),
        zoom,
      });
    };
    element.addEventListener('wheel', wheel, { passive: false });
    return () => element.removeEventListener('wheel', wheel);
  }, [graphKey]);

  async function choose(nodeID: string, recenter = false, preservePath = false) {
    if (anchor && !preservePath) {
      setPathTarget(nodeID === anchor ? null : nodeID);
      setScope('map');
      setCommunity(null);
    }
    if (recenter && community && graph.membership.get(nodeID) !== community) setCommunity(null);
    setSelected(nodeID);
    setFactsLimit(10);
    setDetailError(null);
    setSelectionDetails(null);
    setReader(null);
    sourceRequest.current++;
    setLoadingDetails(true);
    setQuery('');
    if (recenter) {
      const point = layout.positions.get(nodeID)!;
      setCamera({ ...point, zoom: Math.max(1.4, view.zoom) });
    }
    const request = ++selectionRequest.current;
    try {
      const result = await run('graph.select', { id: nodeID });
      if (selectionRequest.current === request) {
        if (result?.error) setDetailError(result.error);
        else if (result?.data?.selectedNodeID === nodeID) setSelectionDetails(result.data);
      }
    } catch (error) {
      if (selectionRequest.current === request)
        setDetailError(error instanceof Error ? error.message : String(error));
    } finally {
      if (selectionRequest.current === request) setLoadingDetails(false);
    }
  }
  function resetSelection() {
    selectionRequest.current++;
    sourceRequest.current++;
    setSelected(null);
    setSelectionDetails(null);
    setLoadingDetails(false);
    setDetailError(null);
    setReader(null);
    setAnchor(null);
    setPathTarget(null);
    setScope('map');
    setCamera(null);
  }
  async function openSource(documentID: string) {
    const request = ++sourceRequest.current;
    try {
      const value = await run('document.open', { id: documentID });
      if (sourceRequest.current !== request) return;
      if (value && !value.error) setReader(value);
      else
        setDetailError(
          (value?.error && nativeSystemMessage(value.error)) ||
            t(
              'Impossible d’ouvrir le document source.',
              'The source document could not be opened.',
            ),
        );
    } catch (error) {
      if (sourceRequest.current === request)
        setDetailError(error instanceof Error ? error.message : String(error));
    }
  }
  function switchMode(value: string) {
    setRequestedMode(value);
    resetSelection();
    setCommunity(null);
    setQuery('');
    setRelation('all');
    setDensity(0);
    void refresh({ mode: value, limit });
  }
  const jumpToCommunity = (value: string) => {
    setCommunity(value === community ? null : value);
    setScope('map');
    setCamera(null);
  };
  const zoom = (factor: number) =>
    setCamera({ ...view, zoom: Math.max(0.25, Math.min(12, view.zoom * factor)) });
  const neighborNodes = useMemo(
    () =>
      [...neighbors.keys()]
        .map((id) => graph.byID.get(id)!)
        .sort((a, b) => (neighbors.get(b.id) || 0) - (neighbors.get(a.id) || 0)),
    [neighbors, graph],
  );
  // Liens de la sélection rangés par voisin en un seul passage (dans l'ordre de la liste des liens),
  // au lieu de parcourir tous les liens pour chaque voisin à chaque rendu.
  const neighborNotes = useMemo(() => {
    const links = new Map<string, MemoryEdge[]>();
    if (current)
      for (const e of graph.edges) {
        const other =
          e.source === current.id ? e.target : e.target === current.id ? e.source : undefined;
        if (other === undefined) continue;
        const list = links.get(other);
        if (list) list.push(e);
        else links.set(other, [e]);
      }
    return new Map(
      [...links].map(([id, list]) => [id, [...new Set(list.map(edgeDescription))].join(' · ')]),
    );
  }, [graph, current]);
  const isolated = useMemo(
    () => graph.nodes.filter((n) => !graph.degree.get(n.id)).length,
    [graph],
  );
  const labelCandidates = useMemo(
    () =>
      [...visibleNodes].sort((a, b) => {
        const rank = (n: MemoryNode) =>
          n.id === selected
            ? 1e9
            : pathIDs.has(n.id)
              ? 1e8
              : matchIDs.has(n.id)
                ? 1e7
                : neighbors.has(n.id)
                  ? 1e6
                  : graph.degree.get(n.id)!;
        return rank(b) - rank(a) || a.id.localeCompare(b.id);
      }),
    [visibleNodes, selected, pathIDs, matchIDs, neighbors, graph],
  );
  const labeled = new Map<string, { x: number; y: number; anchor: 'middle' | 'start' | 'end' }>();
  const labelBoxes: { x: number; y: number; w: number; h: number }[] = [];
  const unit = width / size.width;
  const overlaps = (
    a: { x: number; y: number; w: number; h: number },
    b: { x: number; y: number; w: number; h: number },
  ) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  const nodeBoxes = useMemo(
    () =>
      visibleNodes.map((n) => {
        const p = layout.positions.get(n.id)!;
        const r = 8 + Math.min(9, Math.sqrt(graph.degree.get(n.id) || 0) * 1.7);
        return { id: n.id, x: p.x - r, y: p.y - r, w: r * 2, h: r * 2 };
      }),
    [visibleNodes, layout, graph],
  );
  for (const n of labelCandidates) {
    const important = n.id === selected || n.id === anchor || n.id === pathTarget;
    const eligible =
      important ||
      pathIDs.has(n.id) ||
      matchIDs.has(n.id) ||
      (selected
        ? neighbors.has(n.id)
        : scope === 'neighbors' || !!community || visibleNodes.length < 3);
    if (
      !eligible ||
      (!important && labeled.size >= (query || selected ? 22 : view.zoom > 2 ? 28 : 12))
    )
      continue;
    const p = layout.positions.get(n.id)!;
    if (
      p.x < viewport.x ||
      p.x > viewport.x + width ||
      p.y < viewport.y ||
      p.y > viewport.y + height
    )
      continue;
    const r = 5.5 + Math.min(9, Math.sqrt(graph.degree.get(n.id) || 0) * 1.7);
    const labelWidth = Math.min(n.label.length, 28) * 6.2 * unit,
      labelHeight = 16 * unit;
    const candidates: { x: number; y: number; anchor: 'middle' | 'start' | 'end' }[] = [
      { x: 0, y: r + 18 * unit, anchor: 'middle' },
      { x: r + 9 * unit, y: 4 * unit, anchor: 'start' },
      { x: -r - 9 * unit, y: 4 * unit, anchor: 'end' },
      { x: 0, y: -r - 9 * unit, anchor: 'middle' },
    ];
    for (const candidate of candidates) {
      const box = {
        x:
          p.x +
          candidate.x -
          (candidate.anchor === 'middle'
            ? labelWidth / 2
            : candidate.anchor === 'end'
              ? labelWidth
              : 0),
        y: p.y + candidate.y - 12 * unit,
        w: labelWidth,
        h: labelHeight,
      };
      if (
        !important &&
        (box.x < viewport.x ||
          box.x + box.w > viewport.x + width ||
          box.y < viewport.y ||
          box.y + box.h > viewport.y + height ||
          labelBoxes.some((b) => overlaps(box, b)) ||
          nodeBoxes.some((b) => b.id !== n.id && overlaps(box, b)))
      )
        continue;
      labeled.set(n.id, candidate);
      labelBoxes.push(box);
      break;
    }
  }
  const total = data.totalNodes || graph.nodes.length;

  return (
    <div className="atlas">
      <PageHeader
        eyebrow={t('EXPLORER · COMPRENDRE · RELIER', 'EXPLORE · UNDERSTAND · CONNECT')}
        title={t('Graphe', 'Graph')}
        description={t(
          'Repérez les sujets liés, explorez leurs connexions et revenez aux sources.',
          'Find related topics, explore their connections, and return to the sources.',
        )}
        actions={
          <Tabs
            value={mode}
            onChange={switchMode}
            items={[
              { id: 'entities', label: t('Entités', 'Entities') },
              { id: 'facts', label: t('Faits', 'Facts') },
            ]}
          />
        }
      />
      <ErrorNotice message={data.error} />
      <div className="atlas-summary">
        <span>
          <Network size={16} />
          <strong>{number(graph.nodes.length)}</strong>{' '}
          {mode === 'entities' ? t('entités', 'entities') : t('faits', 'facts')}
          {total > graph.nodes.length ? t(` sur ${number(total)}`, ` of ${number(total)}`) : ''}
        </span>
        <span>
          <GitBranch size={16} />
          <strong>{number(graph.edges.length)}</strong>
          {t(' liens', ' links')}
        </span>
        <span>
          <Layers3 size={16} />
          <strong>{number(graph.communities.length)}</strong>
          {t(' groupes', ' groups')}
        </span>
      </div>
      <div className="atlas-toolbar">
        <div className="atlas-search input-with-icon">
          <Search size={17} />
          <input
            aria-label={t('Rechercher dans le graphe', 'Search the graph')}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t(
              'Retrouver une idée, un projet, une personne…',
              'Find an idea, a project, a person…',
            )}
          />
          {query && (
            <IconButton
              icon={X}
              label={t('Effacer la recherche du graphe', 'Clear graph search')}
              onClick={() => setQuery('')}
            />
          )}
        </div>
        <Button
          icon={SlidersHorizontal}
          kind={filters ? 'primary' : 'secondary'}
          onClick={() => setFilters(!filters)}
        >
          {t('Filtres', 'Filters')}
          {relation !== 'all' || density ? t(' actifs', ' on') : ''}
        </Button>
        <select
          aria-label={t('Taille de l’échantillon du graphe', 'Graph sample size')}
          value={limit}
          disabled={busy}
          onChange={(e) => {
            const limit = Number(e.target.value);
            setLimit(limit);
            void refresh({ mode, limit });
          }}
        >
          <option value={100}>{t('100 nœuds', '100 nodes')}</option>
          <option value={300}>{t('300 nœuds', '300 nodes')}</option>
          <option value={1000}>{t('1 000 nœuds', '1,000 nodes')}</option>
        </select>
      </div>
      {filters && (
        <div className="atlas-filters">
          <label>
            {t('Nature des liens', 'Link type')}
            <select
              value={relation}
              onChange={(e) => setRelation(e.target.value)}
              aria-label={t('Nature des liens', 'Link type')}
            >
              <option value="all">{t('Toutes les relations', 'All relationships')}</option>
              {kinds.map((k) => (
                <option value={k} key={k}>
                  {relationLabel(k)}
                </option>
              ))}
            </select>
          </label>
          <label className="atlas-density">
            {t('Liens les plus forts', 'Strongest links')}{' '}
            <span>
              {density
                ? t(
                    `Seuil : ${Number(threshold.toFixed(2))}`,
                    `Threshold: ${Number(threshold.toFixed(2)).toLocaleString(getLocale())}`,
                  )
                : t('Tous les liens chargés', 'All loaded links')}
            </span>
            <input
              type="range"
              min="0"
              max="90"
              step="10"
              value={density}
              onChange={(e) => setDensity(Number(e.target.value))}
              aria-label={t('Force minimale des liens', 'Minimum link strength')}
            />
          </label>
          <p>
            {t(
              'Le filtre conserve les liens au-dessus du seuil. Les groupes sont recalculés à partir de ces liens.',
              'The filter keeps links above the threshold. Groups are recalculated from these links.',
            )}
          </p>
          {(density > 0 || relation !== 'all') && (
            <button
              className="text-button"
              onClick={() => {
                setDensity(0);
                setRelation('all');
              }}
            >
              {t('Réinitialiser', 'Reset')}
            </button>
          )}
        </div>
      )}
      {anchor && (
        <div className="atlas-route-bar" role="status">
          <Route size={19} />
          <div>
            <strong>
              {pathTarget && pathTarget !== anchor
                ? `${shorten(graph.byID.get(anchor)?.label || '', 30)} → ${shorten(graph.byID.get(pathTarget || '')?.label || '', 30)}`
                : t(
                    `Départ : ${graph.byID.get(anchor)?.label}`,
                    `Start: ${graph.byID.get(anchor)?.label}`,
                  )}
            </strong>
            <span>
              {pathTarget && pathTarget !== anchor
                ? path.length
                  ? t(
                      `${path.length - 1} lien${path.length > 2 ? 's' : ''} · chemin non orienté le plus court dans la vue filtrée`,
                      `${path.length - 1} link${path.length > 2 ? 's' : ''} · shortest undirected path in the filtered view`,
                    )
                  : t(
                      'Aucun chemin dans cet échantillon avec ces filtres.',
                      'No path in this sample with these filters.',
                    )
                : t(
                    'Choisissez un second nœud, dans la carte ou avec la recherche.',
                    'Choose a second node on the map or using search.',
                  )}
            </span>
          </div>
          <IconButton
            icon={X}
            label={t('Fermer le parcours', 'Close path')}
            onClick={() => {
              setAnchor(null);
              setPathTarget(null);
            }}
          />
        </div>
      )}
      <div className="atlas-workspace">
        <section
          className="atlas-map card"
          aria-label={t('Carte interactive de la mémoire', 'Interactive memory map')}
        >
          <div className="atlas-map-header">
            <div className="atlas-view-switch">
              <button
                className={scope === 'map' ? 'active' : ''}
                onClick={() => {
                  setScope('map');
                  setCamera(null);
                }}
              >
                <Compass size={15} />
                {t('Carte', 'Map')}
              </button>
              <button
                className={scope === 'neighbors' ? 'active' : ''}
                disabled={!selected}
                title={
                  !selected
                    ? t(
                        'Sélectionnez un nœud pour explorer son voisinage',
                        'Select a node to explore its neighborhood',
                      )
                    : undefined
                }
                onClick={() => {
                  setScope('neighbors');
                  setCommunity(null);
                  setCamera(null);
                }}
              >
                <Focus size={15} />
                {t('Voisinage', 'Neighborhood')}
              </button>
            </div>
            {scope === 'neighbors' ? (
              <select
                aria-label={t('Profondeur du voisinage', 'Neighborhood depth')}
                value={hops}
                onChange={(e) => setHops(Number(e.target.value))}
              >
                <option value={1}>{t('1 degré', '1 hop')}</option>
                <option value={2}>{t('2 degrés', '2 hops')}</option>
              </select>
            ) : activeCommunity ? (
              <button
                className="atlas-back"
                onClick={() => {
                  setCommunity(null);
                  setCamera(null);
                }}
              >
                <ArrowLeft size={14} />
                {t('Tous les groupes', 'All groups')}
              </button>
            ) : (
              <span className="atlas-map-count">
                {aggregate
                  ? t(
                      `${graph.communities.length} groupes · cliquer pour déplier`,
                      `${graph.communities.length} groups · click to expand`,
                    )
                  : t(
                      `${number(visibleNodes.length)} nœuds`,
                      `${number(visibleNodes.length)} nodes`,
                    )}
              </span>
            )}
          </div>
          <div className="atlas-surface" ref={surface}>
            {!graph.nodes.length ? (
              <Empty
                icon={Network}
                title={
                  busy
                    ? t('La carte se prépare', 'Preparing the map')
                    : t('Aucune connexion à explorer', 'No connections to explore')
                }
                description={
                  busy
                    ? t('Chargement des liens de la banque…', 'Loading bank connections…')
                    : t(
                        'Les entités et les faits reliés apparaîtront ici après leur extraction.',
                        'Connected entities and facts will appear here after extraction.',
                      )
                }
              />
            ) : (
              <svg
                ref={svg}
                className="atlas-svg"
                viewBox={`${viewport.x} ${viewport.y} ${width} ${height}`}
                tabIndex={0}
                role="group"
                aria-label={t(
                  'Graphe interactif : glisser pour déplacer, molette pour zoomer, Entrée pour sélectionner',
                  'Interactive graph: drag to pan, scroll to zoom, press Enter to select',
                )}
                onDoubleClick={() => setCamera(null)}
                onPointerDown={(e) => {
                  if (
                    e.button ||
                    (e.target as Element).closest('[data-atlas-node], [data-atlas-community]')
                  )
                    return;
                  const { view } = cameraRef.current;
                  drag.current = { x: e.clientX, y: e.clientY, camera: { ...view } };
                  e.currentTarget.setPointerCapture(e.pointerId);
                }}
                onPointerMove={(e) => {
                  if (!drag.current) return;
                  const rect = e.currentTarget.getBoundingClientRect();
                  setCamera({
                    ...drag.current.camera,
                    x: drag.current.camera.x - ((e.clientX - drag.current.x) * width) / rect.width,
                    y:
                      drag.current.camera.y - ((e.clientY - drag.current.y) * height) / rect.height,
                  });
                }}
                onPointerUp={() => {
                  drag.current = null;
                }}
                onPointerCancel={() => {
                  drag.current = null;
                }}
                onKeyDown={(e) => {
                  if (e.target !== e.currentTarget) return;
                  if (e.key === 'Escape') resetSelection();
                  else if (e.key === '0') setCamera(null);
                  else if (e.key === '+' || e.key === '=') zoom(1.3);
                  else if (e.key === '-') zoom(1 / 1.3);
                  else if (e.key.startsWith('Arrow')) {
                    e.preventDefault();
                    setCamera({
                      ...view,
                      x:
                        view.x +
                        (e.key === 'ArrowRight'
                          ? width * 0.1
                          : e.key === 'ArrowLeft'
                            ? -width * 0.1
                            : 0),
                      y:
                        view.y +
                        (e.key === 'ArrowDown'
                          ? height * 0.1
                          : e.key === 'ArrowUp'
                            ? -height * 0.1
                            : 0),
                    });
                  }
                }}
              >
                <defs>
                  <pattern id={`grid-${id}`} width="34" height="34" patternUnits="userSpaceOnUse">
                    <circle cx="1" cy="1" r=".8" fill="var(--graph-dot)" />
                  </pattern>
                </defs>
                <rect
                  x={viewport.x}
                  y={viewport.y}
                  width={width}
                  height={height}
                  fill={`url(#grid-${id})`}
                />
                {aggregate ? (
                  <>
                    <g className="atlas-bundles">
                      {groupLinks.slice(0, 70).map((link) => {
                        const a = layout.bounds.get(link.source)!,
                          b = layout.bounds.get(link.target)!;
                        return (
                          <path
                            key={link.id}
                            d={`M${a.x},${a.y} Q${(a.x + b.x) / 2 + (b.y - a.y) * 0.08},${(a.y + b.y) / 2 - (b.x - a.x) * 0.08} ${b.x},${b.y}`}
                            strokeWidth={(0.5 + Math.log1p(link.count) * 0.42) * unit}
                          >
                            <title>
                              {link.count}
                              {t(
                                ' relations entre ces groupes',
                                ' relationships between these groups',
                              )}
                            </title>
                          </path>
                        );
                      })}
                    </g>
                    {graph.communities.map((c, i) => {
                      const p = layout.bounds.get(c.id)!;
                      const r = 20 + Math.sqrt(c.nodes.length) * 9;
                      return (
                        <g
                          key={c.id}
                          className="atlas-aggregate"
                          data-atlas-community={c.id}
                          transform={`translate(${p.x},${p.y})`}
                          style={{ '--cluster-color': colors[c.color] } as React.CSSProperties}
                          role="button"
                          tabIndex={0}
                          aria-label={t(
                            `Explorer le groupe ${c.label}, ${c.nodes.length} nœuds`,
                            `Explore group ${c.label}, ${c.nodes.length} nodes`,
                          )}
                          onClick={() => {
                            setHoveredGroup(null);
                            jumpToCommunity(c.id);
                          }}
                          onDoubleClick={(e) => e.stopPropagation()}
                          onPointerEnter={() => setHoveredGroup(c.id)}
                          onPointerLeave={() => setHoveredGroup(null)}
                          onFocus={() => setHoveredGroup(c.id)}
                          onBlur={() => setHoveredGroup(null)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === ' ') {
                              e.preventDefault();
                              setHoveredGroup(null);
                              jumpToCommunity(c.id);
                            }
                          }}
                        >
                          <circle className="atlas-aggregate-halo" r={r + 7} />
                          <circle className="atlas-aggregate-body" r={r} strokeWidth={1.2 * unit} />
                          <text
                            className="atlas-aggregate-count"
                            textAnchor="middle"
                            y={4 * unit}
                            fontSize={Math.min(16, (r / unit) * 0.7) * unit}
                          >
                            {c.nodes.length}
                          </text>
                          {i < 10 && (
                            <text
                              className="atlas-aggregate-label"
                              textAnchor="middle"
                              y={r + 18 * unit}
                              fontSize={11 * unit}
                              strokeWidth={3 * unit}
                            >
                              {shorten(c.entry.label, 23)}
                            </text>
                          )}
                        </g>
                      );
                    })}
                  </>
                ) : (
                  <>
                    {scope === 'map' &&
                      graph.communities
                        .filter((c) => c.nodes.length > 2 && (!community || c.id === community))
                        .map((c) => {
                          const b = layout.bounds.get(c.id)!;
                          return (
                            <g
                              key={c.id}
                              className="atlas-cluster"
                              style={{ '--cluster-color': colors[c.color] } as React.CSSProperties}
                            >
                              <ellipse cx={b.x} cy={b.y} rx={b.rx} ry={b.ry} />
                              {!selected &&
                                !query &&
                                (graph.communities.length <= 8 ||
                                  graph.communities.slice(0, 8).includes(c) ||
                                  c.id === community) && (
                                  <g transform={`translate(${b.x},${b.y - b.ry + 12})`}>
                                    <text textAnchor="middle" fontSize={11 * unit}>
                                      {shorten(c.label, graph.communities.length > 8 ? 22 : 40)}
                                    </text>
                                  </g>
                                )}
                            </g>
                          );
                        })}
                    <g className="atlas-edges">
                      {shownEdges.map((e) => {
                        const a = layout.positions.get(e.source)!,
                          b = layout.positions.get(e.target)!;
                        const onPath = isOnPath(e);
                        const near = e.source === selected || e.target === selected;
                        const dim = selected
                          ? !near && !onPath
                          : query
                            ? !matchIDs.has(e.source) && !matchIDs.has(e.target)
                            : false;
                        return (
                          <path
                            key={e.id}
                            d={`M${a.x},${a.y} Q${(a.x + b.x) / 2 + (b.y - a.y) * 0.04},${(a.y + b.y) / 2 - (b.x - a.x) * 0.04} ${b.x},${b.y}`}
                            className={`${dim ? 'dim' : ''} ${near ? 'near' : ''} ${onPath ? 'path' : ''}`}
                            style={{
                              opacity: onPath
                                ? 1
                                : near
                                  ? 0.85
                                  : dim
                                    ? 0.035
                                    : shownEdges.length > visibleNodes.length * 4
                                      ? 0.14
                                      : undefined,
                            }}
                            strokeWidth={
                              onPath
                                ? 2.8 * unit
                                : near
                                  ? 1.8 * unit
                                  : Math.min(2, 0.7 + Math.log1p(e.weight) * 0.15) * unit
                            }
                            strokeDasharray={
                              e.kind === 'temporal' ? `${4 * unit} ${4 * unit}` : undefined
                            }
                          >
                            <title>
                              {edgeDescription(e)}
                              {t(' · force ', ' · strength ')}
                              {e.weight}
                            </title>
                          </path>
                        );
                      })}
                    </g>
                    {visibleNodes.map((n) => {
                      const p = layout.positions.get(n.id)!,
                        radius = 5.5 + Math.min(9, Math.sqrt(graph.degree.get(n.id) || 0) * 1.7);
                      const dim = query
                        ? !matchIDs.has(n.id)
                        : selected
                          ? n.id !== selected && !neighbors.has(n.id) && !pathIDs.has(n.id)
                          : false;
                      return (
                        <g
                          key={n.id}
                          data-atlas-node={n.id}
                          onPointerEnter={() => setHovered(n.id)}
                          onPointerLeave={() => setHovered(null)}
                          onFocus={() => setHovered(n.id)}
                          onBlur={() => setHovered(null)}
                          className={`atlas-node ${n.id === selected ? 'selected' : ''} ${pathIDs.has(n.id) ? 'on-path' : ''} ${dim ? 'dim' : ''}`}
                          style={{ '--node-color': colorFor(n) } as React.CSSProperties}
                          transform={`translate(${p.x},${p.y})`}
                          role="button"
                          tabIndex={0}
                          aria-label={t(
                            `${n.label}, ${number(graph.degree.get(n.id) || 0)} connexions`,
                            `${n.label}, ${number(graph.degree.get(n.id) || 0)} connections`,
                          )}
                          aria-pressed={n.id === selected}
                          onClick={() => void choose(n.id)}
                          onDoubleClick={(e) => e.stopPropagation()}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === ' ') {
                              e.preventDefault();
                              void choose(n.id);
                            }
                          }}
                        >
                          <circle className="atlas-node-hit" r={Math.max(radius + 8, 12 * unit)} />
                          <circle className="atlas-node-halo" r={radius + 7} />
                          <circle className="atlas-node-core" r={radius} />
                          {n.id === anchor && (
                            <circle
                              className="atlas-anchor"
                              r={radius + 12}
                              strokeWidth={1.5 * unit}
                            />
                          )}
                          {labeled.has(n.id) && (
                            <text
                              textAnchor={labeled.get(n.id)!.anchor}
                              x={labeled.get(n.id)!.x}
                              y={labeled.get(n.id)!.y}
                              fontSize={12 * unit}
                              strokeWidth={3 * unit}
                            >
                              {shorten(n.label, 28)}
                            </text>
                          )}
                          <title>
                            {n.label} · {kindLabel(n.kind)} · {graph.degree.get(n.id) || 0}{' '}
                            {t(' connexions', ' connections')}
                          </title>
                        </g>
                      );
                    })}
                  </>
                )}
              </svg>
            )}
            {aggregate && hoverCommunity && (
              <div className="atlas-group-tip" role="tooltip">
                <strong>{hoverCommunity.label}</strong>
                <span>
                  {hoverCommunity.nodes.length}
                  {t(
                    ' nœuds · cliquer pour explorer ce groupe',
                    ' nodes · click to explore this group',
                  )}
                </span>
              </div>
            )}
            {hoverNode && hoverPoint && !aggregate && (
              <div
                className="atlas-tooltip"
                role="tooltip"
                style={{
                  left: Math.max(
                    12,
                    Math.min(
                      size.width - 230,
                      ((hoverPoint.x - viewport.x) / width) * size.width + 18,
                    ),
                  ),
                  top: Math.max(
                    12,
                    Math.min(
                      size.height - 85,
                      ((hoverPoint.y - viewport.y) / height) * size.height - 55,
                    ),
                  ),
                }}
              >
                <strong>{hoverNode.label}</strong>
                <span>
                  {kindLabel(hoverNode.kind)} · {number(graph.degree.get(hoverNode.id))}
                  {t(' connexions', ' connections')}
                </span>
              </div>
            )}
            {!!graph.nodes.length && (
              <>
                <div className="atlas-map-tools">
                  <IconButton
                    icon={ZoomOut}
                    label={t('Dézoomer le graphe', 'Zoom out')}
                    onClick={() => zoom(1 / 1.3)}
                  />
                  <button
                    className="atlas-zoom"
                    onClick={() => setCamera(null)}
                    aria-label={t('Rétablir le cadrage du graphe', 'Reset graph view')}
                  >
                    {Math.round(view.zoom * 100)} %
                  </button>
                  <IconButton
                    icon={ZoomIn}
                    label={t('Zoomer le graphe', 'Zoom in')}
                    onClick={() => zoom(1.3)}
                  />
                  <span />
                  <IconButton
                    icon={Maximize2}
                    label={t('Cadrer tous les nœuds visibles', 'Fit all visible nodes')}
                    onClick={() => setCamera(null)}
                  />
                </div>
                <svg
                  className="atlas-minimap"
                  viewBox={`${miniFrame.x - miniFrame.width / 2} ${miniFrame.y - miniFrame.height / 2} ${miniFrame.width} ${miniFrame.height}`}
                  aria-hidden="true"
                >
                  {graph.communities.map((c) => {
                    const b = layout.bounds.get(c.id)!;
                    return (
                      <ellipse
                        key={c.id}
                        cx={b.x}
                        cy={b.y}
                        rx={Math.max(12, b.rx * 0.8)}
                        ry={Math.max(12, b.ry * 0.8)}
                        fill={colors[c.color]}
                      />
                    );
                  })}
                  <rect x={viewport.x} y={viewport.y} width={width} height={height} />
                </svg>
              </>
            )}
          </div>
          <footer className="atlas-map-footer">
            <span>
              <MousePointer2 size={13} />
              {t('Glisser pour déplacer · molette pour zoomer', 'Drag to pan · scroll to zoom')}
            </span>
            <span>
              {selected
                ? t(`${neighbors.size} connexions directes`, `${neighbors.size} direct connections`)
                : aggregate
                  ? t('Taille et nombre : nœuds du groupe', 'Size and count: nodes in group')
                  : t('Couleur : groupe · taille : connexions', 'Color: group · size: connections')}
            </span>
          </footer>
          {aggregate && (
            <p className="atlas-render-note">
              {t('Vue d’ensemble : ', 'Overview: ')}
              {Math.min(70, groupLinks.length)}
              {t(' liaisons entre groupes affichées sur ', ' group links displayed out of ')}
              {groupLinks.length}
              {t(
                '. Chaque trait regroupe des relations réelles. Cliquez un groupe ou zoomez pour voir ses nœuds.',
                '. Each line combines real relationships. Click a group or zoom in to see its nodes.',
              )}
            </p>
          )}
          {!aggregate && shownEdges.length < visibleEdges.length && (
            <p className="atlas-render-note">
              {number(shownEdges.length)}
              {t(' liens dessinés sur ', ' links displayed out of ')}
              {number(visibleEdges.length)}
              {t(
                ' pour garder la carte lisible. Le calcul des chemins utilise tous les liens retenus.',
                ' to keep the map readable. Paths use all retained links.',
              )}
            </p>
          )}
        </section>

        <aside
          className="atlas-inspector card"
          aria-label={t('Exploration et sources du graphe', 'Graph exploration and sources')}
        >
          {query ? (
            <>
              <div className="atlas-inspector-heading">
                <span className="atlas-kicker">{t('DANS CET ÉCHANTILLON', 'IN THIS SAMPLE')}</span>
                <h2>
                  {number(matches.length)}
                  {t(' résultat', ' result')}
                  {matches.length > 1 ? 's' : ''}
                </h2>
                <p>
                  {t(
                    'Choisissez une idée pour en voir les connexions.',
                    'Choose an idea to see its connections.',
                  )}
                </p>
              </div>
              <div className="atlas-list">
                {matches.slice(0, 60).map((n) => (
                  <NodeRow
                    key={n.id}
                    node={n}
                    color={colorFor(n)}
                    note={t(
                      `${graph.degree.get(n.id)} connexions`,
                      `${graph.degree.get(n.id)} connections`,
                    )}
                    onClick={() => void choose(n.id, true)}
                  />
                ))}
                {!matches.length && (
                  <Empty
                    icon={Search}
                    title={t('Aucun résultat', 'No results')}
                    description={t(
                      'Essayez un autre terme ou augmentez l’échantillon.',
                      'Try another term or increase the sample.',
                    )}
                  />
                )}
                {matches.length > 60 && (
                  <p className="atlas-footnote">
                    {t(
                      '60 résultats affichés. Précisez la recherche.',
                      'Showing 60 results. Refine your search.',
                    )}
                  </p>
                )}
              </div>
            </>
          ) : current ? (
            <>
              <div className="atlas-inspector-heading">
                <div className="atlas-kicker">
                  <span className="atlas-swatch" style={{ background: colorFor(current) }} />
                  {kindLabel(current.kind)}
                  <IconButton
                    icon={X}
                    label={t('Désélectionner le nœud', 'Deselect node')}
                    onClick={resetSelection}
                  />
                </div>
                <h2>{current.label}</h2>
                <div className="atlas-node-stats">
                  <span>
                    <strong>{neighbors.size}</strong>
                    {t(' connexions', ' connections')}
                  </span>
                  {mode === 'entities' && (
                    <span>
                      <strong>{number(current.weight)}</strong>
                      {t(' mentions', ' mentions')}
                    </span>
                  )}
                </div>
                <div className="atlas-node-actions">
                  <Button
                    icon={Focus}
                    onClick={() => {
                      setScope('neighbors');
                      setCommunity(null);
                      setCamera(null);
                    }}
                  >
                    {t('Isoler', 'Isolate')}
                  </Button>
                  <Button
                    icon={Route}
                    kind={anchor === selected ? 'primary' : 'secondary'}
                    onClick={() => {
                      setAnchor(selected);
                      setPathTarget(null);
                      setScope('map');
                      setCommunity(null);
                      setCamera(null);
                    }}
                  >
                    {t('Relier à…', 'Connect to…')}
                  </Button>
                </div>
              </div>
              {path.length > 1 && (
                <div className="atlas-path-steps">
                  <span className="atlas-kicker">
                    {t('LE FIL ENTRE CES IDÉES', 'THE THREAD BETWEEN THESE IDEAS')}
                  </span>
                  {path.map((nodeID, i) => (
                    <button key={nodeID} onClick={() => void choose(nodeID, true, true)}>
                      <span>{i + 1}</span>
                      <strong>{graph.byID.get(nodeID)?.label}</strong>
                      {i < path.length - 1 && <ChevronRight size={13} />}
                    </button>
                  ))}
                </div>
              )}
              <Tabs
                value={tab}
                onChange={setTab}
                items={[
                  {
                    id: 'connections',
                    label: t('Connexions', 'Connections'),
                    count: neighbors.size,
                  },
                  { id: 'facts', label: t('Faits & sources', 'Facts & sources') },
                ]}
              />
              {tab === 'connections' ? (
                <div className="atlas-list">
                  {neighborNodes.map((n) => (
                    <NodeRow
                      key={n.id}
                      node={n}
                      color={colorFor(n)}
                      note={neighborNotes.get(n.id) || ''}
                      onClick={() => void choose(n.id, true)}
                    />
                  ))}
                  {!neighbors.size && (
                    <Empty
                      icon={GitBranch}
                      title={t('Aucun voisin dans cette vue', 'No neighbors in this view')}
                      description={t(
                        'Réduisez les filtres ou agrandissez l’échantillon pour chercher d’autres liens.',
                        'Reduce filters or increase the sample to find more connections.',
                      )}
                    />
                  )}
                </div>
              ) : (
                <div className="atlas-evidence">
                  {loadingDetails && (
                    <p className="atlas-detail-status" role="status">
                      {t(
                        'Lecture des faits et de leur provenance…',
                        'Loading facts and their provenance…',
                      )}
                    </p>
                  )}
                  <ErrorNotice
                    message={detailError || (detailsReady ? detailData.detailError : null)}
                  />
                  {facts.slice(0, factsLimit).map((fact) => (
                    <article className="atlas-fact" key={fact.id}>
                      <div>
                        <Badge tone={fact.type === 'observation' ? 'lavender' : 'sage'}>
                          {kindLabel(fact.type)}
                        </Badge>
                        {fact.mentionedAt && <time>{date(fact.mentionedAt)}</time>}
                      </div>
                      <p>{fact.text}</p>
                      {(fact.documentID || fact.document_id) && (
                        <button
                          className="atlas-source-link"
                          onClick={() => void openSource(fact.documentID || fact.document_id)}
                        >
                          <FileText size={14} />
                          <span>{t('Voir le document source', 'View source document')}</span>
                          <ArrowRight size={13} />
                        </button>
                      )}
                    </article>
                  ))}
                  {!loadingDetails && !facts.length && !detailError && (
                    <Empty
                      icon={FileText}
                      title={t('Aucun fait accessible', 'No facts available')}
                      description={t(
                        'Les liens de la carte restent explorables. Aucun fait source n’a été renvoyé pour cette sélection.',
                        'You can still explore map connections. No source facts were returned for this selection.',
                      )}
                    />
                  )}
                  {facts.length > factsLimit && (
                    <Button onClick={() => setFactsLimit(factsLimit + 10)}>
                      {t('Afficher 10 faits de plus', 'Show 10 more facts')}
                    </Button>
                  )}
                  {!!facts.length && (
                    <p className="atlas-footnote">
                      {number(facts.length)}
                      {t(' fait', ' fact')}
                      {facts.length > 1 ? 's' : ''}
                      {t(' chargé', ' loaded')}
                      {facts.length > 1 ? 's' : ''}
                      {mode === 'entities'
                        ? t(' · jusqu’à 50 par entité', ' · up to 50 per entity')
                        : ''}
                      {t(
                        '. Les mentions et les faits sont des mesures différentes.',
                        '. Mentions and facts are different measures.',
                      )}
                    </p>
                  )}
                </div>
              )}
            </>
          ) : activeCommunity ? (
            <>
              <div className="atlas-inspector-heading">
                <div className="atlas-kicker">
                  <span
                    className="atlas-swatch"
                    style={{ background: colors[activeCommunity.color] }}
                  />
                  {t('Groupe de liens', 'Link group')}
                  <IconButton
                    icon={X}
                    label={t('Fermer le groupe', 'Close group')}
                    onClick={() => {
                      setCommunity(null);
                      setCamera(null);
                    }}
                  />
                </div>
                <h2>{activeCommunity.label}</h2>
                <p>
                  {activeCommunity.nodes.length}
                  {t(
                    ' nœuds dans ce groupe. Choisissez un sujet pour explorer ses connexions et ses sources.',
                    ' nodes in this group. Choose a topic to explore its connections and sources.',
                  )}
                </p>
              </div>
              <div className="atlas-list">
                {[
                  activeCommunity.entry,
                  ...activeCommunity.nodes.filter((n) => n.id !== activeCommunity.entry.id),
                ].map((n) => (
                  <NodeRow
                    key={n.id}
                    node={n}
                    color={colorFor(n)}
                    note={t(
                      `${graph.degree.get(n.id)} connexions dans l’échantillon`,
                      `${graph.degree.get(n.id)} connections in the sample`,
                    )}
                    onClick={() => void choose(n.id, true)}
                  />
                ))}
              </div>
              <div className="atlas-reading-guide">
                <Compass size={19} />
                <p>
                  {t(
                    'Le groupe met en évidence des liens plus denses. Les connexions vers d’autres groupes restent accessibles dans la fiche de chaque nœud.',
                    'This group highlights denser connections. Connections to other groups remain available in each node’s details.',
                  )}
                </p>
              </div>
            </>
          ) : (
            <>
              <div className="atlas-inspector-heading">
                <span className="atlas-kicker">
                  {t('UNE VUE, PLUSIEURS ENTRÉES', 'ONE MAP, MANY STARTING POINTS')}
                </span>
                <h2>{t('Où commencer ?', 'Where to start?')}</h2>
                <p>
                  {t(
                    'Un groupe rassemble des nœuds fortement reliés. Une passerelle vous mène d’un groupe à l’autre.',
                    'A group contains strongly connected nodes. A bridge takes you from one group to another.',
                  )}
                </p>
              </div>
              <Tabs
                value={overviewTab}
                onChange={setOverviewTab}
                items={[
                  { id: 'groups', label: t('Groupes', 'Groups'), count: graph.communities.length },
                  {
                    id: 'bridges',
                    label: t('Passerelles', 'Bridges'),
                    count: graph.bridges.length,
                  },
                ]}
              />
              <div className="atlas-list">
                {overviewTab === 'groups'
                  ? graph.communities.slice(0, overviewLimit).map((c) => (
                      <div
                        className={`atlas-community ${community === c.id ? 'active' : ''}`}
                        key={c.id}
                      >
                        <button
                          className="atlas-community-main"
                          onClick={() => jumpToCommunity(c.id)}
                        >
                          <span
                            className="atlas-community-orbit"
                            style={{ '--cluster-color': colors[c.color] } as React.CSSProperties}
                          >
                            <Layers3 size={18} />
                          </span>
                          <span>
                            <strong>{c.label}</strong>
                            <small>
                              {number(c.nodes.length)}
                              {t(' nœud', ' node')}
                              {c.nodes.length > 1 ? 's' : ''}
                            </small>
                          </span>
                          {community === c.id ? <Check size={15} /> : <ChevronRight size={15} />}
                        </button>
                        <button
                          className="atlas-community-entry"
                          onClick={() => void choose(c.entry.id, true)}
                        >
                          {t('Explorer ', 'Explore ')}
                          {shorten(c.entry.label, 26)}
                          <ArrowRight size={12} />
                        </button>
                      </div>
                    ))
                  : graph.bridges
                      .slice(0, overviewLimit)
                      .map(({ node, groups }) => (
                        <NodeRow
                          key={node.id}
                          node={node}
                          color={colorFor(node)}
                          note={t(
                            `Vers ${groups} autre${groups > 1 ? 's' : ''} groupe${groups > 1 ? 's' : ''}`,
                            `To ${groups} other group${groups > 1 ? 's' : ''}`,
                          )}
                          onClick={() => void choose(node.id, true)}
                        />
                      ))}
                {(overviewTab === 'groups' ? graph.communities.length : graph.bridges.length) >
                  overviewLimit && (
                  <Button kind="ghost" onClick={() => setOverviewLimit(overviewLimit + 24)}>
                    {t('Afficher la suite', 'Show more')}
                  </Button>
                )}
                {overviewTab === 'bridges' && !graph.bridges.length && (
                  <Empty
                    icon={Route}
                    title={t('Pas de passerelle dans cette vue', 'No bridges in this view')}
                    description={t(
                      'Aucun nœud ne relie plusieurs groupes avec les liens chargés.',
                      'No node connects multiple groups with the loaded links.',
                    )}
                  />
                )}
              </div>
              <div className="atlas-reading-guide">
                <Compass size={19} />
                <p>
                  <strong>
                    {t('Une carte à lire, pas un classement.', 'A map to explore, not a ranking.')}
                  </strong>
                  {t(
                    ' Les noms des groupes reprennent leurs nœuds les plus connectés. La proximité visuelle aide à naviguer ; seuls les traits représentent des liens.',
                    ' Groups are named after their most connected nodes. Visual proximity helps navigation; only lines represent links.',
                  )}
                </p>
              </div>
            </>
          )}
        </aside>
      </div>
      <div className="atlas-method">
        <span>
          <span className="atlas-swatch" />
          {t(
            'Groupes calculés sur ce Mac à partir des liens de la banque.',
            'Groups calculated on this Mac from the bank’s links.',
          )}
        </span>
      </div>
      {reader && (
        <DocumentReader reader={reader} run={run} busy={busy} onClose={() => setReader(null)} />
      )}
    </div>
  );
}

function NodeRow({
  node,
  color,
  note,
  onClick,
}: {
  node: MemoryNode;
  color: string;
  note: string;
  onClick: () => void;
}) {
  return (
    <button className="atlas-node-row" onClick={onClick}>
      <span className="atlas-swatch" style={{ background: color }} />
      <span>
        <strong>{node.label}</strong>
        <small>{note}</small>
      </span>
      <ArrowRight size={13} />
    </button>
  );
}
