import { translate as t, useI18n } from '../i18n';
import { useMemo, useState } from 'react';
import {
  Activity,
  ArrowRight,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  CircleDot,
  FileText,
  FolderPlus,
  GitBranch,
  Layers3,
  Network,
  RefreshCw,
  Search,
  Sparkles,
  TrendingUp,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  IconButton,
  Loading,
  Markdown,
  Metric,
  Modal,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { factTypeLabel, factTypePluralLabel } from '../fact-types';
import { DocumentReader } from './Library';
import { requestGraphMode } from '../graph-mode';
import { nativeSystemMessage } from '../native-messages';
import { serverFunctionLabel } from '../server-functions';

export function Dashboard({ data, navigate, run, busy }: PageProps) {
  useI18n();
  const stats = data.snapshot?.stats || {};
  const [reader, setReader] = useState<Row | null>(null);
  // Totaux lus en direct quand le moteur les a (mêmes que Faits et Documents) ; sinon les statistiques du serveur.
  const liveTypes: Record<string, number> | undefined = data.snapshot?.liveFactTypes;
  const types = (
    liveTypes
      ? Object.entries(liveTypes).filter(([, count]) => count > 0)
      : Object.entries(stats.nodes_by_fact_type || {})
  ) as [string, number][];
  const factTotal = data.snapshot?.liveFactTotal ?? stats.total_nodes;
  const observationTotal = liveTypes?.observation ?? stats.total_observations ?? 0;
  const documentTotal = data.snapshot?.liveDocumentTotal ?? stats.total_documents;
  const operationCounts: Row | undefined = data.snapshot?.operationCounts;
  const recent: Row[] = data.snapshot?.recentDocuments || [];
  const empty = Boolean(data.snapshot) && !Number(documentTotal);
  const header = (
    <PageHeader
      eyebrow={t('Un regard d’ensemble', 'At a glance')}
      title={t('Vue d’ensemble', 'Overview')}
      description={t(
        'L’état de votre banque, en quelques repères utiles.',
        'Your memory bank at a glance.',
      )}
      actions={
        empty ? (
          <Button kind="primary" icon={FolderPlus} onClick={() => navigate('sources')}>
            {t('Ajouter des documents', 'Add documents')}
          </Button>
        ) : undefined
      }
    />
  );
  if (!data.snapshot)
    return (
      <>
        {header}
        {data.error ? <ErrorNotice message={data.error} /> : <Loading />}
      </>
    );
  return (
    <>
      {header}
      <ErrorNotice message={data.error} />
      <div className="metrics-grid three">
        <Metric
          label={t('Faits en mémoire', 'Facts in memory')}
          // Même total que la page Faits (lu en direct) : observations comprises.
          value={number(factTotal)}
          note={t(
            `Dont ${number(observationTotal)} ${observationTotal > 1 ? 'observations' : 'observation'}`,
            `Including ${number(observationTotal)} ${observationTotal === 1 ? 'observation' : 'observations'}`,
          )}
          icon={Sparkles}
          onClick={() => navigate('facts')}
        />
        <Metric
          label={t('Documents', 'Documents')}
          value={number(documentTotal)}
          note={
            // La liste est triée par dernière modification (retag, retraitement compris), comme « Mis à jour » dans Documents.
            recent[0]?.updated_at
              ? t(
                  `Dernière mise à jour le ${date(recent[0].updated_at)}`,
                  `Last updated on ${date(recent[0].updated_at)}`,
                )
              : undefined
          }
          icon={FileText}
          tone="sage"
          onClick={() => navigate('documents')}
        />
        <Metric
          label={t('Liens', 'Links')}
          value={number(stats.total_links)}
          note={t('Entre les faits (statistiques du serveur)', 'Between facts (server statistics)')}
          icon={GitBranch}
          tone="blue"
          onClick={() => {
            // Ce total compte les liens entre faits : le graphe s'ouvre sur les faits, pas sur les entités.
            requestGraphMode('facts');
            navigate('graph');
          }}
        />
      </div>
      <div className="two-columns">
        <section className="card">
          <CardHeader title={t('De quoi se compose votre mémoire ?', 'What is in your memory?')} />
          {types.length ? (
            <div className="memory-breakdown">
              {types.map(([key, count], i) => (
                <div key={key}>
                  <span className={`category-icon color-${i % 4}`}>
                    <CircleDot size={21} />
                  </span>
                  <div>
                    <strong>
                      {['world', 'experience', 'observation', 'opinion'].includes(key)
                        ? factTypePluralLabel(key)
                        : key}
                    </strong>
                    <p>
                      {number(count)} {t('faits', 'facts')}
                    </p>
                  </div>
                  <div className="progress-track">
                    <span
                      style={{
                        width: `${Math.min(100, (count / (stats.total_nodes || 1)) * 100)}%`,
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <Empty title={t('Aucun fait pour le moment', 'No facts yet')} />
          )}
        </section>
        <section className="card">
          <CardHeader
            title={t('Traitements', 'Processing')}
            action={
              <Button kind="ghost" icon={ArrowRight} onClick={() => navigate('operations')}>
                {t('Voir l’activité', 'View activity')}
              </Button>
            }
          />
          {/* Mêmes compteurs que Traitements (lus en direct), même état de consolidation que sa vue. */}
          <div className="queue-overview">
            <div>
              <span className="status-dot warning" />
              <span>{t('En attente', 'Pending')}</span>
              <strong>{number(operationCounts?.pending ?? stats.pending_operations)}</strong>
            </div>
            {operationCounts && (
              <div>
                <span className="status-dot green" />
                <span>{t('En cours', 'Processing')}</span>
                <strong>{number(operationCounts.processing)}</strong>
              </div>
            )}
            <div>
              <span className="status-dot red" />
              <span>{t('En échec', 'Failed')}</span>
              <strong>{number(operationCounts?.failed ?? stats.failed_operations)}</strong>
            </div>
            <ConsolidationLine
              status={data.snapshot.consolidation}
              stats={stats}
              onOpen={() => navigate('consolidation')}
            />
          </div>
        </section>
      </div>
      <section className="card">
        <CardHeader
          title={t('Derniers documents', 'Recent documents')}
          action={
            <Button kind="ghost" onClick={() => navigate('documents')} icon={ArrowRight}>
              {t('Tout voir', 'View all')}
            </Button>
          }
        />
        {recent.map((doc: Row) => (
          <button
            key={doc.id}
            className="source-row"
            onClick={() => void run('document.open', { id: doc.id }).then(setReader)}
          >
            <span className="file-icon document">
              <FileText size={19} />
            </span>
            <span className="source-row-main">
              <strong>{doc.document_metadata?.title || doc.title || doc.id}</strong>
              <span>
                {number(doc.memory_unit_count)} {t('faits extraits', 'facts extracted')}
              </span>
            </span>
            <span className="source-date">{date(doc.updated_at)}</span>
            <ArrowRight size={15} />
          </button>
        ))}
        {!recent.length && <Empty title={t('Aucun document récent', 'No recent documents')} />}
      </section>
      {data.partialErrors?.map((e: string) => (
        <ErrorNotice message={e} key={e} />
      ))}
      {reader && (
        <DocumentReader reader={reader} busy={busy} run={run} onClose={() => setReader(null)} />
      )}
    </>
  );
}

/** État de la consolidation, le même que dans sa vue (Mémoire › Consolidation) : désactivée, en cours, faits à consolider
 * ou à jour, avec la date de la dernière consolidation qui a réellement traité des faits. */
export function consolidationSummary(status: Row | undefined): {
  value: string;
  tone: '' | 'green' | 'warning';
} {
  switch (status?.phase) {
    case 'disabled':
      return { value: t('Désactivée', 'Turned off'), tone: '' };
    case 'running':
      return { value: t('En cours', 'Processing'), tone: 'green' };
    case 'queued':
      return { value: t('En attente', 'Pending'), tone: 'warning' };
    case 'pending': {
      const n = Number(status.pendingFacts);
      return {
        value: t(
          `${number(n)} ${n > 1 ? 'faits' : 'fait'} à consolider`,
          `${number(n)} ${n === 1 ? 'fact' : 'facts'} to consolidate`,
        ),
        tone: 'warning',
      };
    }
    default:
      return { value: t('À jour', 'Up to date'), tone: 'green' };
  }
}

function ConsolidationLine({
  status,
  stats,
  onOpen,
}: {
  status?: Row;
  stats: Row;
  onOpen: () => void;
}) {
  const last = status ? status.lastConsolidatedAt : stats.last_consolidated_at;
  if (!status)
    return (
      <div>
        <span className="status-dot green" />
        <span>{t('Dernière consolidation', 'Last consolidation')}</span>
        <strong className="small-value">{last ? date(last) : '—'}</strong>
      </div>
    );
  const { value, tone } = consolidationSummary(status);
  // La consolidation a sa vue (Mémoire › Consolidation) : la ligne y mène.
  return (
    <button
      type="button"
      className="queue-row-link"
      onClick={onOpen}
      title={t('Voir la consolidation', 'View consolidation')}
    >
      <span className={`status-dot ${tone}`} />
      <span className="queue-label">
        {t('Consolidation', 'Consolidation')}
        <small>
          {last
            ? t(`Dernière le ${date(last)}`, `Last on ${date(last)}`)
            : t('Aucune consolidation effectuée', 'No consolidation yet')}
        </small>
      </span>
      <strong className="small-value">{value}</strong>
      <ChevronRight size={14} />
    </button>
  );
}

/** Un fait sur une ligne : son type, son texte, sa date et le chemin vers son document. */
export function FactRow({
  fact,
  busy,
  onSource,
  showDate = true,
}: {
  fact: Row;
  busy: boolean;
  onSource: (id: string) => void;
  showDate?: boolean;
}) {
  const when = showDate ? fact.occurredStart || fact.mentionedAt : null;
  return (
    <article className={`fact-row ${showDate ? '' : 'no-date'}`}>
      <span className="fact-row-type">
        <Badge tone={fact.type === 'observation' ? 'lavender' : 'sage'}>
          {factTypeLabel(fact.type)}
        </Badge>
      </span>
      <div className="fact-row-main">
        <p>{fact.text}</p>
        {(fact.state === 'invalidated' || !!fact.sourceFactIDs?.length) && (
          <small>
            {fact.state === 'invalidated' && t('Invalidé', 'Invalidated')}
            {fact.state === 'invalidated' && !!fact.sourceFactIDs?.length && ' · '}
            {!!fact.sourceFactIDs?.length &&
              t(
                `Issue de ${number(fact.sourceFactIDs.length)} fait${fact.sourceFactIDs.length > 1 ? 's' : ''}`,
                `Derived from ${number(fact.sourceFactIDs.length)} fact${fact.sourceFactIDs.length === 1 ? '' : 's'}`,
              )}
          </small>
        )}
      </div>
      {showDate && (
        <span
          className="fact-row-date"
          title={
            when
              ? fact.occurredStart
                ? t('Date de l’événement', 'Event date')
                : t('Date de mention', 'Mention date')
              : undefined
          }
        >
          {when ? date(when) : ''}
        </span>
      )}
      {fact.documentID ? (
        <IconButton
          icon={FileText}
          label={t('Voir le document source', 'View source document')}
          disabled={busy}
          onClick={() => onSource(fact.documentID)}
        />
      ) : (
        <span />
      )}
    </article>
  );
}

export function Facts({ data, run, busy, refresh, notify }: PageProps) {
  useI18n();
  // Une seule recherche, toujours sur toute la banque : le texte s'applique à la validation, le type aussitôt.
  const [query, setQuery] = useState(typeof data.query === 'string' ? data.query : '');
  const [type, setType] = useState(typeof data.type === 'string' ? data.type : 'all');
  const [limit, setLimit] = useState(80);
  const [reader, setReader] = useState<Row | null>(null);
  const loaded = Array.isArray(data.facts);
  const facts = (data.facts || []) as Row[];
  const total = typeof data.total === 'number' ? data.total : facts.length;
  const activeQuery = typeof data.query === 'string' ? data.query : '';
  const activeType = typeof data.type === 'string' ? data.type : 'all';
  const searching = Boolean(activeQuery) || activeType !== 'all';

  async function searchBank(value = query, selectedType = type) {
    setLimit(80);
    await refresh({ query: value.trim(), type: selectedType });
  }
  async function openSource(id: string) {
    const result = await run('document.open', { id });
    if (result && !result.error) setReader(result);
    else
      notify(
        result?.error ||
          t('Impossible d’ouvrir le document source.', 'The source document could not be opened.'),
      );
  }
  const summary = !loaded
    ? '—'
    : searching
      ? t(
          `${number(total)} résultat${total > 1 ? 's' : ''}`,
          `${number(total)} result${total === 1 ? '' : 's'}`,
        ) +
        (activeQuery ? t(` pour « ${activeQuery} »`, ` for “${activeQuery}”`) : '') +
        (activeType !== 'all' ? ` · ${factTypePluralLabel(activeType)}` : '')
      : t(
          `${number(total)} fait${total > 1 ? 's' : ''} dans la banque`,
          `${number(total)} fact${total === 1 ? '' : 's'} in the bank`,
        );

  return (
    <>
      <PageHeader
        eyebrow={t('Ce que la banque retient', 'What the bank remembers')}
        title={t('Faits', 'Facts')}
        description={t(
          'Les faits extraits de vos documents et les observations qui les relient.',
          'The facts extracted from your documents and the observations that connect them.',
        )}
      />
      <ErrorNotice message={data.error} />
      <form
        className="list-toolbar facts-toolbar"
        onSubmit={(event) => {
          event.preventDefault();
          void searchBank();
        }}
      >
        <div className="input-with-icon">
          <Search size={16} />
          <input
            type="search"
            aria-label={t('Rechercher des faits', 'Search facts')}
            placeholder={t('Rechercher dans les faits…', 'Search facts…')}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
        </div>
        <select
          aria-label={t('Type de fait', 'Fact type')}
          value={type}
          disabled={busy}
          onChange={(event) => {
            setType(event.target.value);
            void searchBank(query, event.target.value);
          }}
        >
          <option value="all">{t('Tous les types', 'All types')}</option>
          <option value="world">{factTypePluralLabel('world')}</option>
          <option value="experience">{factTypePluralLabel('experience')}</option>
          <option value="observation">{factTypePluralLabel('observation')}</option>
        </select>
        <Button icon={Search} disabled={busy}>
          {t('Rechercher', 'Search')}
        </Button>
      </form>
      <div className="list-summary">
        <span role="status">{summary}</span>
        {searching && (
          <button
            type="button"
            className="text-button"
            disabled={busy}
            onClick={() => {
              setQuery('');
              setType('all');
              void searchBank('', 'all');
            }}
          >
            {t('Effacer la recherche', 'Clear search')}
          </button>
        )}
      </div>
      {data.truncated && (
        <div className="notice">
          {t(
            `Seuls les ${number(facts.length)} premiers faits sont affichés. Précisez la recherche pour atteindre les autres.`,
            `Only the first ${number(facts.length)} facts are shown. Refine the search to reach the others.`,
          )}
        </div>
      )}
      {!!facts.length && (
        <section className="card fact-rows">
          {facts.slice(0, limit).map((fact) => (
            <FactRow key={fact.id} fact={fact} busy={busy} onSource={(id) => void openSource(id)} />
          ))}
        </section>
      )}
      {!loaded && !data.error && <Loading />}
      {loaded && !data.error && !facts.length && (
        <Empty
          icon={Layers3}
          title={
            searching
              ? t('Aucun fait ne correspond', 'No matching fact')
              : t('Aucun fait pour le moment', 'No facts yet')
          }
          description={
            searching
              ? t('Essayez d’autres mots ou un autre type.', 'Try other words or another type.')
              : t(
                  'Les faits extraits des documents de cette banque apparaîtront ici.',
                  'Facts extracted from this bank’s documents will appear here.',
                )
          }
        />
      )}
      {facts.length > limit && (
        <Button onClick={() => setLimit(limit + 80)}>{t('Afficher la suite', 'Show more')}</Button>
      )}
      {reader && (
        <DocumentReader reader={reader} busy={busy} run={run} onClose={() => setReader(null)} />
      )}
    </>
  );
}

export function Timeline({ data, run, busy, refresh }: PageProps) {
  useI18n();
  const [query, setQuery] = useState('');
  const [axis, setAxis] = useState('event');
  const [limit, setLimit] = useState(80);
  const [reader, setReader] = useState<Row | null>(null);
  const groups = useMemo(() => {
    const map = new Map<string, Row[]>();
    for (const fact of (data.facts || []) as Row[]) {
      const day =
        String(
          axis === 'event' ? fact.occurredStart || fact.mentionedAt || '' : fact.mentionedAt || '',
        ).slice(0, 10) || 'undated';
      const group = map.get(day) || [];
      group.push(fact);
      map.set(day, group);
    }
    // Du plus récent au plus ancien ; les faits sans date viennent en dernier.
    return [...map.entries()].sort(([a], [b]) =>
      a === 'undated' ? 1 : b === 'undated' ? -1 : b.localeCompare(a),
    );
  }, [data.facts, axis]);
  const loaded = Array.isArray(data.facts);
  const activeQuery = typeof data.query === 'string' ? data.query : '';
  let shown = 0;
  return (
    <>
      <PageHeader
        eyebrow={t('Les idées dans le temps', 'Ideas over time')}
        title={t('Chronologie', 'Timeline')}
        description={t(
          'Reconstituez le fil des événements et des décisions.',
          'Follow events and decisions over time.',
        )}
      />
      <ErrorNotice message={data.error} />
      <form
        className="timeline-toolbar"
        onSubmit={(e) => {
          e.preventDefault();
          void refresh({ query: query.trim() });
        }}
      >
        <div className="input-with-icon">
          <Search size={16} />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('Rechercher dans la chronologie…', 'Search the timeline…')}
            aria-label={t('Rechercher dans la chronologie', 'Search the timeline')}
          />
        </div>
        <select
          value={axis}
          onChange={(e) => setAxis(e.target.value)}
          aria-label={t('Date à utiliser', 'Date to use')}
        >
          <option value="event">{t('Date de l’événement', 'Event date')}</option>
          <option value="mentioned">{t('Date de mention', 'Mention date')}</option>
        </select>
        <Button icon={Search} disabled={busy}>
          {t('Rechercher', 'Search')}
        </Button>
      </form>
      <div className="list-summary">
        <span role="status">
          {loaded
            ? activeQuery
              ? t(
                  `${number(data.facts.length)} fait${data.facts.length > 1 ? 's' : ''} pour « ${activeQuery} »`,
                  `${number(data.facts.length)} fact${data.facts.length === 1 ? '' : 's'} for “${activeQuery}”`,
                )
              : t(
                  `${number(data.facts.length)} fait${data.facts.length > 1 ? 's' : ''}`,
                  `${number(data.facts.length)} fact${data.facts.length === 1 ? '' : 's'}`,
                )
            : '—'}
        </span>
        {activeQuery && (
          <button
            type="button"
            className="text-button"
            disabled={busy}
            onClick={() => {
              setQuery('');
              void refresh({ query: '' });
            }}
          >
            {t('Effacer la recherche', 'Clear search')}
          </button>
        )}
      </div>
      {data.truncated && (
        <div className="notice">
          {t('La chronologie est limitée à', 'The timeline is limited to')}{' '}
          {number(data.facts?.length)} {t('faits sur', 'facts out of')} {number(data.total)}
          {t(
            '. Affinez la recherche pour explorer une autre période.',
            '. Refine your search to explore another period.',
          )}
        </div>
      )}
      <div className="timeline">
        {groups.map(([day, facts]) => {
          if (shown >= limit) return null;
          const visible = facts.slice(0, limit - shown);
          shown += visible.length;
          return (
            <section className="timeline-group" key={day}>
              <div className="timeline-date">
                <CalendarDays size={16} />
                <strong>
                  {day === 'undated' ? t('Sans date', 'Undated') : date(day + 'T12:00:00')}
                </strong>
                <span>
                  {facts.length} {t('faits', 'facts')}
                </span>
              </div>
              <div className="card fact-rows timeline-facts">
                {visible.map((fact) => (
                  <FactRow
                    key={fact.id}
                    fact={fact}
                    busy={busy}
                    showDate={false}
                    onSource={(id) => void run('document.open', { id }).then(setReader)}
                  />
                ))}
              </div>
            </section>
          );
        })}
      </div>
      {!loaded && !data.error && <Loading />}
      {loaded && !data.error && !groups.length && (
        <Empty
          icon={CalendarDays}
          title={t('Aucun fait à afficher', 'No facts to display')}
          description={t(
            'Les faits datés de la banque apparaîtront ici.',
            'Dated facts from this bank will appear here.',
          )}
        />
      )}
      {groups.reduce((n, [, f]) => n + f.length, 0) > limit && (
        <Button onClick={() => setLimit(limit + 80)}>{t('Afficher la suite', 'Show more')}</Button>
      )}
      {reader && (
        <DocumentReader reader={reader} run={run} busy={busy} onClose={() => setReader(null)} />
      )}
    </>
  );
}

export function Audit({ data, run, busy }: PageProps) {
  useI18n();
  const [tab, setTab] = useState('reads');
  const [selected, setSelected] = useState<Row | null>(null);
  const [query, setQuery] = useState('');
  const all: Row[] = data[tab] || [];
  // Texte cherchable de chaque ligne calculé une fois par réponse, pas à chaque frappe ou sélection.
  const haystacks = useMemo(() => all.map((r) => JSON.stringify(r).toLowerCase()), [all]);
  const needle = query.toLowerCase();
  const rows = useMemo(
    () => all.filter((_, i) => haystacks[i].includes(needle)),
    [all, haystacks, needle],
  );
  // Le tableau s’arrête à 300 lignes et le moteur ne charge que les 500 dernières entrées : le dire.
  const shown = Math.min(rows.length, 300);
  const serverTotal =
    tab === 'audit' ? data.auditTotal : tab === 'traces' ? data.traceTotal : undefined;
  return (
    <>
      <PageHeader
        eyebrow={t('Une mémoire qui s’explique', 'Understand your memory')}
        title={t('Journaux', 'Logs')}
        description={t(
          'Comprenez qui consulte votre mémoire et quels appels aux modèles ont été faits.',
          'See who reads your memory and which model calls were made.',
        )}
        actions={
          // Pas de bouton tant que l’état du journal est inconnu ; inactif si le serveur refuserait l’écriture.
          data.auditStatus === 'enabled' ? (
            <Button
              onClick={() => void run('audit.disable')}
              disabled={busy || data.canToggleAudit === false}
            >
              {t('Désactiver le journal', 'Disable logging')}
            </Button>
          ) : data.auditStatus === 'disabled' ? (
            <Button
              onClick={() => void run('audit.enable')}
              disabled={busy || data.canToggleAudit === false}
              title={
                data.canToggleAudit === false
                  ? t(
                      'Ce serveur n’accepte pas les réglages par banque : ajoutez HINDSIGHT_API_AUDIT_LOG_ENABLED=true au script de lancement, puis redémarrez-le.',
                      'This server does not accept per-bank settings: add HINDSIGHT_API_AUDIT_LOG_ENABLED=true to the launch script, then restart it.',
                    )
                  : undefined
              }
            >
              {t('Activer le journal', 'Enable logging')}
            </Button>
          ) : undefined
        }
      />
      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          { id: 'reads', label: t('Lectures', 'Reads'), count: data.reads?.length },
          {
            id: 'traces',
            label: t('Appels aux modèles', 'Model calls'),
            // Le total du serveur, comme le texte sous les onglets (pas seulement les lignes chargées).
            count: Math.max(Number(data.traceTotal) || 0, data.traces?.length || 0),
          },
          {
            id: 'audit',
            label: t('Journal d’accès', 'Access log'),
            count: Math.max(Number(data.auditTotal) || 0, data.audit?.length || 0),
          },
        ]}
      />
      <ErrorNotice message={tab === 'traces' ? data.traceError : data.error} />
      <section className="card">
        <div className="list-toolbar">
          <div className="input-with-icon">
            <Search size={16} />
            <input
              aria-label={t('Filtrer l’activité', 'Filter activity')}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('Filtrer l’activité…', 'Filter activity…')}
            />
          </div>
          <span className="muted">
            {shown < rows.length
              ? t(
                  `${number(shown)} affiché${shown > 1 ? 's' : ''} sur ${number(rows.length)} événement${rows.length > 1 ? 's' : ''}`,
                  `${number(shown)} shown of ${number(rows.length)} event${rows.length === 1 ? '' : 's'}`,
                )
              : t(
                  `${number(rows.length)} événement${rows.length > 1 ? 's' : ''}`,
                  `${number(rows.length)} event${rows.length === 1 ? '' : 's'}`,
                )}
            {typeof serverTotal === 'number' && serverTotal > all.length
              ? all.length === 1
                ? t(
                    ` · le plus récent sur ${number(serverTotal)}`,
                    ` · the most recent of ${number(serverTotal)}`,
                  )
                : t(
                    ` · les ${number(all.length)} plus récents sur ${number(serverTotal)}`,
                    ` · the ${number(all.length)} most recent of ${number(serverTotal)}`,
                  )
              : ''}
          </span>
        </div>
        {rows.length ? (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>{tab === 'reads' ? t('Lecteur', 'Reader') : t('Action', 'Action')}</th>
                  <th>{tab === 'traces' ? t('Modèle', 'Model') : t('Contexte', 'Context')}</th>
                  <th>{t('Date', 'Date')}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {rows.slice(0, 300).map((row, i) => (
                  <tr key={row.id || i}>
                    <td>
                      <span className="inline-icon">
                        <Activity size={15} />
                        {(row.who && nativeSystemMessage(row.who)) ||
                          serverFunctionLabel(row.action || row.operation || row.operation_type) ||
                          row.method ||
                          t('Appel', 'Call')}
                      </span>
                    </td>
                    <td className="truncate-cell">
                      {tab === 'traces'
                        ? row.model || '—'
                        : row.query ||
                          row.path ||
                          row.document_id ||
                          row.request_id ||
                          t('Consulter le détail', 'View details')}
                    </td>
                    <td className="muted">
                      {date(row.date || row.started_at || row.timestamp || row.created_at, true)}
                    </td>
                    <td>
                      <IconButton
                        icon={ArrowRight}
                        label={t('Voir le détail de l’événement', 'View event details')}
                        onClick={() => setSelected(row)}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <Empty
            icon={Activity}
            title={t('Aucune activité disponible', 'No activity available')}
            description={t(
              'Les lectures et les appels apparaissent lorsque les journaux correspondants sont activés sur le serveur.',
              'Reads and calls appear when their corresponding server logs are enabled.',
            )}
          />
        )}
      </section>
      {selected && (
        <Modal
          title={t('Détail de l’activité', 'Activity details')}
          subtitle={t('Données enregistrées par le serveur', 'Data recorded by the server')}
          onClose={() => setSelected(null)}
          wide
        >
          <pre className="json-view">{JSON.stringify(selected, null, 2)}</pre>
        </Modal>
      )}
    </>
  );
}
