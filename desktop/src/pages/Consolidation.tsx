import { translate as t, useI18n } from '../i18n';
import { useState } from 'react';
import { ChevronDown, ChevronRight, Layers3, RotateCcw, Settings2 } from 'lucide-react';
import type { PageProps, Row } from '../types';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  Loading,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { factTypeLabel } from '../fact-types';
import { requestMemoryTab } from '../memory-tab';
import { consolidationSummary } from './Explore';

/** Mémoire › Consolidation : où en est la consolidation, à quel rythme, dans quelles portées, et ce qu'elle a
 * changé dans les observations. Le seul endroit qui la lance. Les mots sont ceux de Hindsight : une
 * consolidation crée ou met à jour des observations à partir des faits sources. */
export default function Consolidation({ data, run, busy, refresh, navigate }: PageProps) {
  useI18n();
  const status: Row | undefined = data.status ?? undefined;
  const phase: string | undefined = status?.phase;
  const readOnly = !!data.consultationOnly;
  const canAct = !readOnly && !data.busy;
  const header = (
    <PageHeader
      eyebrow={t('Des faits aux observations', 'From facts to observations')}
      title={t('Consolidation', 'Consolidation')}
      description={t(
        'Où en est la consolidation de cette banque, et ce qu’elle a changé dans ses observations.',
        'Where this memory bank’s consolidation stands, and what it changed in its observations.',
      )}
      actions={
        ['pending', 'running', 'queued'].includes(phase || '') ? (
          <Button
            icon={Layers3}
            kind="primary"
            disabled={busy || !canAct || phase === 'running' || phase === 'queued'}
            title={
              phase === 'running'
                ? t(
                    'Une consolidation est déjà en cours pour cette banque.',
                    'A consolidation is already running for this memory bank.',
                  )
                : phase === 'queued'
                  ? t(
                      'Une consolidation est déjà en attente pour cette banque.',
                      'A consolidation is already queued for this memory bank.',
                    )
                  : t(
                      'Regroupe en observations les faits pas encore consolidés (appels LLM).',
                      'Groups facts not yet consolidated into observations (LLM calls).',
                    )
            }
            onClick={() => void run('consolidation.consolidate')}
          >
            {t('Consolider', 'Consolidate')}
          </Button>
        ) : undefined
      }
    />
  );
  if (!data.loaded)
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
      {phase === 'disabled' && (
        <div className="notice consolidation-off">
          <span>
            {t(
              'La consolidation est désactivée pour cette banque : les faits restent tels quels et aucune observation n’est créée, ni automatiquement ni à la demande.',
              'Consolidation is turned off for this memory bank: facts stay as they are and no observations are created, automatically or on demand.',
            )}
          </span>
          <Button kind="ghost" onClick={() => openSettings(navigate)}>
            {t('Ouvrir le réglage', 'Open the setting')}
          </Button>
        </div>
      )}
      <ConsolidationProgress data={data} run={run} busy={busy || !canAct} navigate={navigate} />
      {phase !== 'disabled' && (
        <ObservationScopes scopes={data.scopes} observations={Number(data.observationTotal) || 0} />
      )}
      <ObservationChanges data={data} run={run} busy={busy} refresh={refresh} />
      {(data.partialErrors || []).map((message: string) => (
        <ErrorNotice message={message} key={message} />
      ))}
    </>
  );
}

function openSettings(navigate: PageProps['navigate']) {
  requestMemoryTab('observations');
  navigate('memory');
}

/** Durée lisible : « 4 j 5 h », « 2 h 10 min », « 12 min ». */
export function duration(seconds: number) {
  const minutes = Math.max(1, Math.round(seconds / 60));
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days)
    return hours ? t(`${days} j ${hours} h`, `${days} d ${hours} h`) : t(`${days} j`, `${days} d`);
  if (hours) return rest ? `${hours} h ${rest} min` : `${hours} h`;
  return `${rest} min`;
}

function percent(fraction: number) {
  const value = fraction * 100;
  const text =
    value > 0 && value < 1
      ? '< 1'
      : value < 99.5 || value >= 100
        ? String(Math.round(value))
        : '99';
  return t(`${text} %`, `${text}%`);
}

/** État, avancement sur toute la banque, rythme récent et faits en échec. */
function ConsolidationProgress({
  data,
  run,
  busy,
  navigate,
}: {
  data: Row;
  run: PageProps['run'];
  busy: boolean;
  navigate: PageProps['navigate'];
}) {
  const status: Row | undefined = data.status ?? undefined;
  if (!status) return null;
  const { value, tone } = consolidationSummary(status);
  const raw = Number(data.rawFacts) || 0;
  const done = Number(data.consolidatedFacts) || 0;
  const failed = Number(status.failedFacts) || 0;
  const pace: Row | null = data.pace ?? null;
  const last = status.lastConsolidatedAt;
  return (
    <section className="card consolidation-progress">
      <div className="consolidation-headline">
        <span className={`status-dot ${tone}`} />
        <strong>{value}</strong>
        <span className="consolidation-last">
          {last
            ? t(`Dernière le ${date(last, true)}`, `Last on ${date(last, true)}`)
            : t('Aucune consolidation effectuée', 'No consolidation yet')}
        </span>
        {status.phase !== 'disabled' && (
          <Button kind="ghost" icon={Settings2} onClick={() => openSettings(navigate)}>
            {t('Réglages', 'Settings')}
          </Button>
        )}
      </div>
      {raw > 0 && status.phase !== 'disabled' && (
        <div className="consolidation-advance">
          <div
            className="progress-track"
            role="progressbar"
            aria-label={t('Faits consolidés', 'Consolidated facts')}
            aria-valuemin={0}
            aria-valuemax={raw}
            aria-valuenow={done}
          >
            <span className="sage" style={{ width: `${Math.min(100, (done / raw) * 100)}%` }} />
          </div>
          <p>
            {t(
              `${number(done)} ${done > 1 ? 'faits consolidés' : 'fait consolidé'} sur ${number(raw)} · ${percent(done / raw)}`,
              `${number(done)} of ${number(raw)} ${raw === 1 ? 'fact' : 'facts'} consolidated · ${percent(done / raw)}`,
            )}
          </p>
          {pace && (
            <p className="consolidation-pace">
              {pace.remainingSeconds != null
                ? t(
                    `Au rythme de la dernière heure (${number(Math.round(pace.factsPerHour))} faits par heure), il reste environ ${duration(pace.remainingSeconds)}.`,
                    `At the pace of the last hour (${number(Math.round(pace.factsPerHour))} facts per hour), about ${duration(pace.remainingSeconds)} remain.`,
                  )
                : t(
                    `Rythme de la dernière heure : ${number(Math.round(pace.factsPerHour))} faits par heure.`,
                    `Pace over the last hour: ${number(Math.round(pace.factsPerHour))} facts per hour.`,
                  )}
            </p>
          )}
        </div>
      )}
      {failed > 0 && status.enabled !== false && (
        <div className="consolidation-failed">
          <span className="status-dot red" />
          <span>
            {t(
              `${number(failed)} ${failed > 1 ? 'faits en échec' : 'fait en échec'} de consolidation`,
              `${number(failed)} ${failed === 1 ? 'fact' : 'facts'} failed to consolidate`,
            )}
          </span>
          <Button
            kind="ghost"
            icon={RotateCcw}
            disabled={busy}
            title={t(
              'Remet en file les faits dont la consolidation a échoué.',
              'Puts facts whose consolidation failed back in the queue.',
            )}
            onClick={() => void run('consolidation.recover')}
          >
            {t(
              `Reconsolider ${number(failed)} fait${failed > 1 ? 's' : ''}`,
              `Reconsolidate ${number(failed)} fact${failed === 1 ? '' : 's'}`,
            )}
          </Button>
        </div>
      )}
    </section>
  );
}

/** Portées des observations : une barre où chaque portée prend sa part des observations, et sa légende.
 * Un fait ne se fond qu'avec les observations de sa portée ; une portée se consolide lot après lot,
 * des portées distinctes en parallèle. C'est ce qui règle la vitesse d'une consolidation. */
export function ObservationScopes({
  scopes,
  observations,
}: {
  scopes?: Row;
  observations: number;
}) {
  const listed: { tags: string[]; count: number }[] = scopes?.scopes ?? [];
  if (!listed.length) return null;
  const total = Number(scopes?.total) || listed.length;
  const listedSum = listed.reduce((sum, scope) => sum + scope.count, 0);
  const base = Math.max(observations, listedSum, 1);
  const rest = {
    scopes: Math.max(0, total - listed.length),
    count: Math.max(0, base - listedSum),
  };
  const share = (count: number) => {
    const value = (count / base) * 100;
    if (value === 0 || value >= 10) return t(`${Math.round(value)} %`, `${Math.round(value)}%`);
    if (value < 1) return t('< 1 %', '< 1%');
    const text = value.toFixed(1);
    return t(`${text.replace('.', ',')} %`, `${text}%`);
  };
  const label = (tags: string[]) =>
    tags.length ? tags.join(' · ') : t('Sans étiquette', 'Untagged');
  return (
    <section className="card observation-scopes">
      <CardHeader
        title={t('Portées des observations', 'Observation scopes')}
        subtitle={
          total === 1
            ? t(
                'Une seule portée : toute la banque se consolide d’un seul tenant, lot après lot.',
                'A single scope: the whole memory bank consolidates as one, batch after batch.',
              )
            : t(
                'Chaque portée se consolide lot après lot ; des portées distinctes avancent en parallèle.',
                'Each scope consolidates batch after batch; separate scopes progress in parallel.',
              )
        }
        action={
          <Badge>
            {number(total)} {total > 1 ? t('portées', 'scopes') : t('portée', 'scope')}
          </Badge>
        }
      />
      <div
        className="scope-bar"
        role="img"
        aria-label={t('Répartition des observations par portée', 'Observations by scope')}
      >
        {listed.map((scope, i) => (
          <span
            key={i}
            className={`color-${i % 4}`}
            style={{ flexGrow: scope.count }}
            title={label(scope.tags)}
          />
        ))}
        {rest.count > 0 && <span className="rest" style={{ flexGrow: rest.count }} />}
      </div>
      <ul className="scope-legend">
        {listed.map((scope, i) => (
          <li key={i}>
            <span className={`legend-dot color-${i % 4}`} />
            <span
              className={scope.tags.length ? 'scope-name' : 'scope-name untagged'}
              title={label(scope.tags)}
            >
              {label(scope.tags)}
            </span>
            <span className="scope-share">{share(scope.count)}</span>
            <strong>{number(scope.count)}</strong>
          </li>
        ))}
        {rest.scopes > 0 && (
          <li>
            <span className="legend-dot rest" />
            <span className="scope-name untagged">
              {t(
                `${number(rest.scopes)} ${rest.scopes > 1 ? 'autres portées' : 'autre portée'}`,
                `${number(rest.scopes)} ${rest.scopes === 1 ? 'other scope' : 'other scopes'}`,
              )}
            </span>
            <span className="scope-share">{share(rest.count)}</span>
            <strong>{number(rest.count)}</strong>
          </li>
        )}
      </ul>
    </section>
  );
}

const periods = () => [
  { id: 'hour', label: t('Dernière heure', 'Last hour') },
  { id: 'day', label: t('24 heures', '24 hours') },
  { id: 'week', label: t('7 jours', '7 days') },
];

function countsSentence(period: string, counts?: Row) {
  if (!counts) return undefined;
  const created = Number(counts.created) || 0;
  const updated = Number(counts.updated) || 0;
  const when =
    period === 'hour'
      ? t('Dernière heure', 'Last hour')
      : period === 'week'
        ? t('7 derniers jours', 'Last 7 days')
        : t('Dernières 24 heures', 'Last 24 hours');
  return t(
    `${when} : ${number(created)} ${created > 1 ? 'observations créées' : 'observation créée'}, ${number(updated)} ${updated > 1 ? 'mises à jour' : 'mise à jour'}.`,
    `${when}: ${number(created)} ${created === 1 ? 'observation' : 'observations'} created, ${number(updated)} updated.`,
  );
}

/** Ce que la consolidation a changé : les observations créées ou mises à jour, la plus récente d'abord. */
function ObservationChanges({
  data,
  run,
  busy,
  refresh,
}: {
  data: Row;
  run: PageProps['run'];
  busy: boolean;
  refresh: PageProps['refresh'];
}) {
  const changes: Row[] = data.changes || [];
  const period: string = data.period || 'day';
  const [open, setOpen] = useState<string | null>(null);
  return (
    <section className="card observation-changes">
      <CardHeader
        title={t('Ce que la consolidation a changé', 'What consolidation changed')}
        subtitle={countsSentence(period, data.counts)}
        action={
          <Tabs
            value={period}
            onChange={(value) => {
              setOpen(null);
              void refresh({ period: value });
            }}
            items={periods()}
          />
        }
      />
      {changes.length ? (
        <div className="change-rows">
          {changes.map((change) => (
            <ChangeRow
              key={change.id}
              change={change}
              open={open === change.id}
              onToggle={() => setOpen(open === change.id ? null : change.id)}
              run={run}
            />
          ))}
        </div>
      ) : (
        <Empty
          title={t('Aucun changement sur cette période', 'No changes in this period')}
          description={t(
            'Aucune observation n’a été créée ni mise à jour.',
            'No observation was created or updated.',
          )}
        />
      )}
      {data.canLoadMore && (
        <div className="card-footer">
          <Button
            disabled={busy || data.loadingMore}
            onClick={() => void run('consolidation.more')}
          >
            {t('Afficher plus de changements', 'Show more changes')}
          </Button>
        </div>
      )}
    </section>
  );
}

function sourceSentence(count: number) {
  return t(
    `Issue de ${number(count)} fait${count > 1 ? 's' : ''}`,
    `Derived from ${number(count)} fact${count === 1 ? '' : 's'}`,
  );
}

function changeSummary(change: Row) {
  if (!change.kind) return t('Historique indisponible', 'History unavailable');
  if (change.kind === 'created') return sourceSentence(Number(change.sourceCount) || 0);
  const parts = [
    change.textChanged
      ? t('Texte modifié', 'Text rewritten')
      : t('Texte inchangé', 'Text unchanged'),
  ];
  const updates = Number(change.updates) || 0;
  if (updates > 1) parts.push(t(`${number(updates)} mises à jour`, `${number(updates)} updates`));
  const added = Number(change.newSourceCount) || 0;
  if (added)
    parts.push(
      t(
        `${number(added)} ${added > 1 ? 'faits sources ajoutés' : 'fait source ajouté'}`,
        `${number(added)} source ${added === 1 ? 'fact' : 'facts'} added`,
      ),
    );
  return parts.join(' · ');
}

function ChangeRow({
  change,
  open,
  onToggle,
  run,
}: {
  change: Row;
  open: boolean;
  onToggle: () => void;
  run: PageProps['run'];
}) {
  const removed: string[] = change.removedValues || [];
  const [sources, setSources] = useState<Row[] | null>(null);
  const [sourceError, setSourceError] = useState<string | null>(null);
  function toggle() {
    onToggle();
    // Une observation créée ne dit ses faits sources que par sa fiche : lus à la première ouverture.
    if (!open && change.kind !== 'updated' && sources === null)
      void run('consolidation.sources', { id: change.id }).then((result) => {
        if (result?.error) setSourceError(result.error);
        else setSources(result?.sources || []);
      });
  }
  const shownSources: Row[] = change.kind === 'updated' ? change.newSources || [] : sources || [];
  return (
    <article className={`change-row ${open ? 'open' : ''}`}>
      <button type="button" className="change-row-head" aria-expanded={open} onClick={toggle}>
        {open ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
        <span className="change-row-badges">
          {change.kind === 'created' && <Badge tone="sage">{t('Créée', 'Created')}</Badge>}
          {change.kind === 'updated' && <Badge tone="accent">{t('Mise à jour', 'Updated')}</Badge>}
          {removed.length > 0 && (
            <Badge tone="amber">
              {t(
                `${number(removed.length)} ${removed.length > 1 ? 'valeurs retirées' : 'valeur retirée'}`,
                `${number(removed.length)} ${removed.length === 1 ? 'value' : 'values'} removed`,
              )}
            </Badge>
          )}
        </span>
        <span className="change-row-main">
          <span className="change-text">{change.text}</span>
          <small>{changeSummary(change)}</small>
        </span>
        <span className="change-row-date">
          {change.updatedAt ? date(change.updatedAt, true) : ''}
        </span>
      </button>
      {open && (
        <div className="change-detail">
          {Array.isArray(change.diff) && (
            <>
              <h3>{t('Ce qui a changé dans le texte', 'What changed in the text')}</h3>
              <p className="text-diff">
                {change.diff.map((segment: Row, i: number) => (
                  <span key={i} className={`diff-${segment.kind}`}>
                    {segment.text}
                  </span>
                ))}
              </p>
            </>
          )}
          {removed.length > 0 && (
            <div className="notice removed-values">
              <span>
                <strong>
                  {t('Valeurs retirées : ', 'Values removed: ')}
                  {removed.join(', ')}
                </strong>
                {'\n'}
                {t(
                  'Présentes avant, absentes du texte actuel. Une nouvelle valeur peut remplacer l’ancienne ; sinon, c’est une perte à vérifier. L’ancien texte reste dans l’historique de l’observation, et la valeur dans ses faits sources.',
                  'Present before, missing from the current text. A new value may replace the old one; otherwise it is a loss to check. The old text stays in the observation’s history, and the value in its source facts.',
                )}
              </span>
            </div>
          )}
          <h3>
            {change.kind === 'updated'
              ? t('Faits sources ajoutés', 'Source facts added')
              : t('Faits sources', 'Source facts')}
          </h3>
          {sourceError ? (
            <ErrorNotice message={sourceError} />
          ) : change.kind !== 'updated' && sources === null ? (
            <Loading />
          ) : shownSources.length ? (
            <ul className="change-sources">
              {shownSources.map((fact) => (
                <li key={fact.id}>
                  <Badge tone="sage">{factTypeLabel(fact.type)}</Badge>
                  <span>
                    {fact.text}
                    {fact.context && <small>{fact.context}</small>}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="change-empty">
              {t(
                'Aucun fait source renvoyé par le serveur.',
                'No source facts returned by the server.',
              )}
            </p>
          )}
          {change.kind === 'updated' && Number(change.newSourceCount) > shownSources.length && (
            <p className="change-empty">
              {t(
                `Et ${number(Number(change.newSourceCount) - shownSources.length)} de plus.`,
                `And ${number(Number(change.newSourceCount) - shownSources.length)} more.`,
              )}
            </p>
          )}
        </div>
      )}
    </article>
  );
}
