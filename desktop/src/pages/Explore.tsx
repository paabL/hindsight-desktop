import { translate as t, useI18n } from '../i18n';
import { useMemo, useState } from 'react';
import {
  Activity,
  ArrowRight,
  CalendarDays,
  CheckCircle2,
  CircleDot,
  FileText,
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
  Markdown,
  Metric,
  Modal,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { DocumentReader } from './Library';

export function Dashboard({ data, navigate, run, busy }: PageProps) {
  useI18n();
  const stats = data.snapshot?.stats || {};
  const [reader, setReader] = useState<Row | null>(null);
  const types = Object.entries(stats.nodes_by_fact_type || {}) as [string, number][];
  return (
    <>
      <PageHeader
        eyebrow={t('Un regard d’ensemble', 'At a glance')}
        title={t('Vue d’ensemble', 'Overview')}
        description={t(
          'L’état de votre banque, en quelques repères utiles.',
          'Your memory bank at a glance.',
        )}
      />
      <ErrorNotice message={data.error} />
      <div className="metrics-grid">
        <Metric
          label={t('Faits en mémoire', 'Facts in memory')}
          value={number(stats.total_nodes)}
          note={t('Faits conservés', 'Stored facts')}
          icon={Sparkles}
        />
        <Metric
          label={t('Documents', 'Documents')}
          value={number(stats.total_documents)}
          note={t('Documents conservés', 'Stored documents')}
          icon={FileText}
          tone="sage"
        />
        <Metric
          label={t('Observations', 'Observations')}
          value={number(stats.total_observations)}
          note={t('Connaissances consolidées', 'Consolidated knowledge')}
          icon={Layers3}
          tone="lavender"
        />
        <Metric
          label={t('Relations', 'Relationships')}
          value={number(stats.total_links)}
          note={t('Relations entre les faits', 'Relationships between facts')}
          icon={GitBranch}
          tone="blue"
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
                      {{
                        world: t('Faits du monde', 'World facts'),
                        experience: t('Expériences', 'Experiences'),
                        observation: t('Observations', 'Observations'),
                      }[key] || key}
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
            title={t('Les traitements', 'Processing')}
            action={
              <Button kind="ghost" icon={ArrowRight} onClick={() => navigate('operations')}>
                {t('Ouvrir la file', 'Open queue')}
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
        {(data.snapshot?.recentDocuments || []).map((doc: Row) => (
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
        {!data.snapshot?.recentDocuments?.length && (
          <Empty title={t('Aucun document récent', 'No recent documents')} />
        )}
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

export function Timeline({ data, run, busy, refresh }: PageProps) {
  useI18n();
  const [query, setQuery] = useState('');
  const [axis, setAxis] = useState('event');
  const [limit, setLimit] = useState(80);
  const [reader, setReader] = useState<Row | null>(null);
  // Textes en minuscules calculés une fois par réponse : jusqu'à 20 000 faits à chaque frappe sinon.
  const lowered = useMemo(
    () => ((data.facts || []) as Row[]).map((fact) => fact.text.toLowerCase() as string),
    [data.facts],
  );
  const groups = useMemo(() => {
    const map = new Map<string, Row[]>();
    const needle = query.toLowerCase();
    for (const [i, fact] of ((data.facts || []) as Row[]).entries()) {
      if (!lowered[i].includes(needle)) continue;
      const day =
        String(
          axis === 'event' ? fact.occurredStart || fact.mentionedAt || '' : fact.mentionedAt || '',
        ).slice(0, 10) || 'undated';
      const group = map.get(day) || [];
      group.push(fact);
      map.set(day, group);
    }
    return [...map.entries()].sort(([a], [b]) => b.localeCompare(a));
  }, [data.facts, lowered, query, axis]);
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
          void refresh({ query });
        }}
      >
        <div className="input-with-icon">
          <Search size={16} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('Filtrer les faits…', 'Filter facts…')}
            aria-label={t('Filtrer la chronologie', 'Filter timeline')}
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
        <Badge>
          {number(data.facts?.length || 0)} {t('faits chargés', 'facts loaded')}
        </Badge>
      </form>
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
              <div className="timeline-facts">
                {visible.map((fact) => (
                  <article className="card timeline-fact" key={fact.id}>
                    <Badge tone={fact.type === 'observation' ? 'lavender' : 'sage'}>
                      {fact.type === 'observation'
                        ? t('Observation', 'Observation')
                        : t('Fait', 'Fact')}
                    </Badge>
                    <p>{fact.text}</p>
                    {fact.documentID && (
                      <button
                        className="text-button"
                        onClick={() =>
                          void run('document.open', { id: fact.documentID }).then(setReader)
                        }
                      >
                        {t('Voir le document', 'View document')}
                        <ArrowRight size={14} />
                      </button>
                    )}
                  </article>
                ))}
              </div>
            </section>
          );
        })}
      </div>
      {!groups.length && (
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
  return (
    <>
      <PageHeader
        eyebrow={t('Une mémoire qui s’explique', 'Understand your memory')}
        title={t('Activité & lectures', 'Activity & reads')}
        description={t(
          'Comprenez qui consulte votre mémoire et quels traitements ont été effectués.',
          'See who reads your memory and which operations have run.',
        )}
        actions={
          <Button onClick={() => void run('audit.enable')} disabled={busy}>
            {t('Activer le journal', 'Enable logging')}
          </Button>
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
            {number(rows.length)} {t('événements', 'events')}
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
