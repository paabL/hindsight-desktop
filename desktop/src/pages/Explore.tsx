import { translate as t, useI18n } from '../i18n';
import { useMemo, useState } from 'react';
import {
  Activity,
  ArrowRight,
  CalendarDays,
  CheckCircle2,
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

export function Dashboard({ data, navigate, run, busy }: PageProps) {
  useI18n();
  const stats = data.snapshot?.stats || {};
  const [reader, setReader] = useState<Row | null>(null);
  const types = Object.entries(stats.nodes_by_fact_type || {}) as [string, number][];
  const recent: Row[] = data.snapshot?.recentDocuments || [];
  const empty = Boolean(data.snapshot) && !Number(stats.total_documents);
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
            {t('Ajouter des sources', 'Add sources')}
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
          // Même total que la barre latérale (`fact_count` du serveur) et que la page Faits : observations comprises.
          value={number(stats.total_nodes)}
          note={t(
            `Dont ${number(stats.total_observations ?? 0)} observations`,
            `Including ${number(stats.total_observations ?? 0)} observations`,
          )}
          icon={Sparkles}
          onClick={() => navigate('facts')}
        />
        <Metric
          label={t('Documents', 'Documents')}
          value={number(stats.total_documents)}
          note={
            recent[0]?.updated_at
              ? t(
                  `Dernier ajout le ${date(recent[0].updated_at)}`,
                  `Last added on ${date(recent[0].updated_at)}`,
                )
              : undefined
          }
          icon={FileText}
          tone="sage"
          onClick={() => navigate('documents')}
        />
        <Metric
          label={t('Relations', 'Relationships')}
          value={number(stats.total_links)}
          note={t('Liens entre les faits', 'Links between facts')}
          icon={GitBranch}
          tone="blue"
          onClick={() => navigate('graph')}
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
          <div className="queue-overview">
            <div>
              <span className="status-dot warning" />
              <span>{t('En attente', 'Pending')}</span>
              <strong>{number(stats.pending_operations)}</strong>
            </div>
            <div>
              <span className="status-dot red" />
              <span>{t('En échec', 'Failed')}</span>
              <strong>{number(stats.failed_operations)}</strong>
            </div>
            <div>
              <span className="status-dot green" />
              <span>{t('Dernière consolidation', 'Last consolidation')}</span>
              <strong className="small-value">
                {stats.last_consolidated_at ? date(stats.last_consolidated_at) : '—'}
              </strong>
            </div>
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
                `Issue de ${number(fact.sourceFactIDs.length)} faits`,
                `Derived from ${number(fact.sourceFactIDs.length)} facts`,
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
      : t(`${number(total)} faits dans la banque`, `${number(total)} facts in the bank`);

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
        <Button onClick={() => setLimit(limit + 80)}>{t('Afficher la suite', 'Load more')}</Button>
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
              : t(`${number(data.facts.length)} faits`, `${number(data.facts.length)} facts`)
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
        <Button onClick={() => setLimit(limit + 80)}>{t('Afficher la suite', 'Load more')}</Button>
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
          data.auditStatus === 'enabled' ? (
            <Button onClick={() => void run('audit.disable')} disabled={busy}>
              {t('Désactiver le journal', 'Disable logging')}
            </Button>
          ) : (
            <Button onClick={() => void run('audit.enable')} disabled={busy}>
              {t('Activer le journal', 'Enable logging')}
            </Button>
          )
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
            count: data.traces?.length,
          },
          { id: 'audit', label: t('Journal d’accès', 'Access log'), count: data.audit?.length },
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
              ? `${number(shown)} ${t('affichés sur', 'shown of')} ${number(rows.length)} ${t('événements', 'events')}`
              : `${number(rows.length)} ${t('événements', 'events')}`}
            {typeof serverTotal === 'number' && serverTotal > all.length
              ? ` · ${t('les', 'the')} ${number(all.length)} ${t('plus récents sur', 'most recent of')} ${number(serverTotal)}`
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
                        {row.who ||
                          row.action ||
                          row.operation ||
                          row.operation_type ||
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
