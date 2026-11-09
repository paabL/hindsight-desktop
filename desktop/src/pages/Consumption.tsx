import { translate as t, useI18n } from '../i18n';
import { useMemo, useState } from 'react';
import {
  Activity,
  BarChart3,
  CircleDollarSign,
  Clock3,
  Gauge,
  MoreHorizontal,
  Pause,
  Play,
  Settings2,
  ShieldCheck,
  Trash2,
  Zap,
} from 'lucide-react';
import type { PageProps, PauseState, Row } from '../types';
import { nativeSystemMessage } from '../native-messages';
import { serverFunctionLabel } from '../server-functions';
import {
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  IconButton,
  Metric,
  Modal,
  PageHeader,
  Tabs,
  date,
  money,
  number,
} from '../ui';

export function PauseTools({
  run,
  busy,
  pause,
  bank,
  readOnly = false,
}: Pick<PageProps, 'run' | 'busy'> & {
  pause?: PauseState;
  bank?: string | null;
  readOnly?: boolean;
}) {
  useI18n();
  const [open, setOpen] = useState(false);
  const [all, setAll] = useState(false);
  const allPaused = !!pause?.all;
  const bankPaused = !!bank && !!pause?.banks?.includes(bank);
  // Ce que la portée choisie dans les options permet : mettre en pause ou reprendre, jamais les deux.
  const scopePaused = all ? allPaused : bankPaused;
  const disabled = busy || readOnly;
  return (
    <>
      {allPaused ? (
        <Button
          icon={Play}
          disabled={disabled}
          onClick={() => void run('pause.resume', { all: true })}
        >
          {t('Reprendre toutes les banques', 'Resume all banks')}
        </Button>
      ) : bankPaused ? (
        <Button
          icon={Play}
          disabled={disabled}
          onClick={() => void run('pause.resume', { all: false })}
        >
          {t('Reprendre', 'Resume')}
        </Button>
      ) : (
        <Button
          icon={Pause}
          disabled={disabled}
          onClick={() => void run('pause.pause', { all: false })}
        >
          {t('Mettre en pause', 'Pause')}
        </Button>
      )}
      <IconButton
        icon={MoreHorizontal}
        label={t('Autres options de traitement', 'More processing options')}
        disabled={disabled}
        onClick={() => setOpen(true)}
      />
      {open && (
        <Modal
          title={t('Options de traitement', 'Processing options')}
          subtitle={t(
            'Pour cette banque, toutes les banques ou le serveur entier.',
            'For this bank, every bank or the whole server.',
          )}
          onClose={() => setOpen(false)}
        >
          <label className="checkbox-label scope-choice">
            <input type="checkbox" checked={all} onChange={(e) => setAll(e.target.checked)} />
            {t('Appliquer à toutes les banques', 'Apply to all memory banks')}
          </label>
          <div className="pause-options">
            <article>
              <span className="category-icon peach">
                <Pause size={21} />
              </span>
              <div>
                <h3>{scopePaused ? t('Reprendre', 'Resume') : t('Mettre en pause', 'Pause')}</h3>
                <p>
                  {scopePaused
                    ? t(
                        'Les envois reprennent, la consolidation arrêtée par la pause repart sur les faits restants et la consolidation automatique retrouve son réglage d’avant.',
                        'Uploads resume, the consolidation stopped by the pause picks up the remaining facts and automatic consolidation returns to its setting from before.',
                      )
                    : t(
                        'Suspend les envois de cette app et la consolidation automatique. La consolidation en cours s’arrête après son lot et les régénérations de connaissances sont annulées, sans rien perdre. Les extractions déjà en file continuent.',
                        'Pause uploads from this app and automatic consolidation. The running consolidation stops after its batch and knowledge regenerations are cancelled, with nothing lost. Extractions already queued keep running.',
                      )}
                </p>
                <div className="action-row">
                  {scopePaused ? (
                    <Button
                      icon={Play}
                      disabled={disabled}
                      onClick={() => void run('pause.resume', { all })}
                    >
                      {t('Reprendre', 'Resume')}
                    </Button>
                  ) : (
                    <Button disabled={disabled} onClick={() => void run('pause.pause', { all })}>
                      {t('Mettre en pause', 'Pause')}
                    </Button>
                  )}
                </div>
              </div>
            </article>
            <article>
              <span className="category-icon neutral">
                <Trash2 size={21} />
              </span>
              <div>
                <h3>{t('Vider les opérations en attente', 'Clear pending operations')}</h3>
                <p>
                  {t(
                    'Annule les opérations qui n’ont pas encore commencé, après confirmation.',
                    'Cancel operations that have not started, after confirmation.',
                  )}
                </p>
                <Button
                  kind="danger"
                  disabled={disabled}
                  onClick={() => void run('pause.drain', { all })}
                >
                  {t('Vider la file', 'Clear the queue')}
                </Button>
              </div>
            </article>
          </div>
        </Modal>
      )}
    </>
  );
}

export default function Consumption({ data, run, busy, notify }: PageProps) {
  const { language } = useI18n();
  const [period, setPeriod] = useState('day');
  const [budgets, setBudgets] = useState(false);
  const [prices, setPrices] = useState(false);
  const [priceText, setPriceText] = useState('');
  const [dollars, setDollars] = useState('');
  const [autoPause, setAutoPause] = useState(false);
  const summary = data.summary || {};
  const today = summary.today || {};
  const events: Row[] = data.events || [];
  const gauges: Row[] = (data.gauges || []).filter((gauge: Row) => gauge.id === 'dollars.day');
  const dailyLimit: Row | undefined = gauges.find((gauge) => Number(gauge.limit) > 0);
  // La période se compte jusqu’au dernier relevé (l’heure actuelle à défaut), pas jusqu’au dernier appel :
  // une banque au repos depuis deux jours n’affiche rien sur 24 heures. Le graphique, la répartition et le
  // nombre d’appels portent tous sur cette même période.
  const periodEvents = useMemo(() => {
    const reference = Date.parse(data.lastPoll) || Date.now();
    const cutoff = reference - (period === 'day' ? 86_400_000 : 7 * 86_400_000);
    return events.filter((event) => (Date.parse(event.date) || 0) >= cutoff);
  }, [events, period, data.lastPoll]);
  // Moteur natif : agrégats complets de la période. Mode exemple : recalcul à partir des appels fournis.
  const engine: Row | undefined = data.periods?.[period];
  type Bar = { key: string; tokens: number; calls: number; label: string };
  const chart = useMemo((): Bar[] => {
    if (engine)
      return (engine.buckets || []).map((bucket: Row): Bar => ({
        key: bucket.start,
        tokens: Number(bucket.tokens) || 0,
        calls: Number(bucket.calls) || 0,
        label: period === 'day' ? `${new Date(bucket.start).getHours()} h` : date(bucket.start),
      }));
    const groups = new Map<string, { tokens: number; calls: number; label: string }>();
    const pad = (n: number) => String(n).padStart(2, '0');
    for (const event of periodEvents) {
      const d = new Date(event.date);
      // Regroupement à l’heure locale, comme les libellés des barres.
      const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
      const key = period === 'day' ? `${day} ${pad(d.getHours())}` : day;
      const current = groups.get(key) || {
        tokens: 0,
        calls: 0,
        label: period === 'day' ? `${d.getHours()} h` : date(event.date),
      };
      current.tokens += (event.tokens?.input || 0) + (event.tokens?.output || 0);
      current.calls++;
      groups.set(key, current);
    }
    return [...groups.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, value]) => ({ key, ...value }));
  }, [periodEvents, period, language, engine]);
  const peak = Math.max(1, ...chart.map((c) => c.tokens));
  const distribution = useMemo((): [string, number][] => {
    if (engine)
      return (engine.operations || []).map(
        (share: Row) =>
          [share.id || t('Autre', 'Other'), Number(share.tokens) || 0] as [string, number],
      );
    const groups = new Map<string, number>();
    for (const e of periodEvents)
      groups.set(
        e.operation || t('Autre', 'Other'),
        (groups.get(e.operation || t('Autre', 'Other')) || 0) +
          (e.tokens?.input || 0) +
          (e.tokens?.output || 0),
      );
    return [...groups.entries()].sort((a, b) => b[1] - a[1]);
  }, [periodEvents, language, engine]);
  const periodCalls = engine ? Number(engine.calls) || 0 : periodEvents.length;
  const periodLabel = period === 'day' ? t('24 heures', '24 hours') : t('7 jours', '7 days');
  const sum = distribution.reduce((n, [, v]) => n + v, 0) || 1;
  function editBudgets() {
    setDollars(String(data.budgets?.dailyDollars ?? ''));
    setAutoPause(data.budgets?.actionConfirmed || false);
    setBudgets(true);
  }

  return (
    <>
      <PageHeader
        eyebrow={t('Le contrôle, en toute clarté', 'Clear controls')}
        title={t('Consommation', 'Usage')}
        description={t(
          'Comprenez ce que votre mémoire utilise et choisissez ses limites.',
          'Understand memory usage and set your limits.',
        )}
        actions={
          <Button icon={Settings2} onClick={editBudgets}>
            {t('Mes plafonds', 'My limits')}
          </Button>
        }
      />
      <ErrorNotice message={data.error} />
      {data.tracesOff && (
        <div className="notice">
          {t(
            'Le serveur n’enregistre pas ses appels LLM : rien n’est mesuré ici et un plafond ne peut pas se déclencher. Ajoutez HINDSIGHT_API_LLM_TRACE_ENABLED=true à son environnement (Modèles), puis redémarrez-le.',
            'The server does not record its model calls: nothing is measured here and a limit cannot trigger. Add HINDSIGHT_API_LLM_TRACE_ENABLED=true to its environment (Models), then restart it.',
          )}
        </div>
      )}
      <div className="metrics-grid">
        <Metric
          label={t('Coût estimé aujourd’hui', 'Estimated cost today')}
          value={data.tracesOff ? '—' : money(today.dollars)}
          // Le plafond quotidien se lit ici, avec le coût qu'il borne : un seul endroit pour ce chiffre.
          note={
            dailyLimit && data.tracesOff
              ? t(
                  `Plafond : ${money(dailyLimit.limit)} par jour, inopérant sans traces`,
                  `Limit: ${money(dailyLimit.limit)} per day, inactive without traces`,
                )
              : dailyLimit
                ? t(
                    `Plafond : ${money(dailyLimit.limit)} par jour (${Math.round((dailyLimit.used / dailyLimit.limit) * 100)} %)`,
                    `Limit: ${money(dailyLimit.limit)} per day (${Math.round((dailyLimit.used / dailyLimit.limit) * 100)}%)`,
                  )
                : t('Appels facturés à l’usage · USD', 'Pay-per-use calls · USD')
          }
          icon={CircleDollarSign}
        />
        <Metric
          label={t('Appels aujourd’hui', 'Calls today')}
          value={number(today.calls)}
          note={t('Toutes les banques', 'All memory banks')}
          icon={Activity}
          tone="sage"
        />
        <Metric
          label={t('Jetons sur abonnement', 'Subscription tokens')}
          value={number(today.subscriptionTokens, true)}
          note={t('Jetons réellement utilisés sur abonnement', 'Actual subscription token usage')}
          icon={Zap}
          tone="lavender"
        />
        <Metric
          label={t('Rythme actuel', 'Current rate')}
          value={
            <>
              {number(summary.rate?.tokensPerMinute, true)}
              <small> / min</small>
            </>
          }
          note={t('Jetons par minute', 'Tokens per minute')}
          icon={Gauge}
          tone="blue"
        />
      </div>
      <div className="chart-layout">
        <section className="card chart-card">
          <CardHeader
            title={t('L’activité de votre mémoire', 'Memory activity')}
            subtitle={t(
              'Jetons mesurés dans les traces disponibles',
              'Tokens measured in available traces',
            )}
            action={
              <Tabs
                value={period}
                onChange={setPeriod}
                items={[
                  { id: 'day', label: t('24 heures', '24 hours') },
                  { id: 'week', label: t('7 jours', '7 days') },
                ]}
              />
            }
          />
          {chart.length ? (
            <>
              <div
                className="bar-chart"
                role="img"
                aria-label={t('Jetons utilisés par période', 'Tokens used by period')}
              >
                <div className="chart-y">
                  <span>{number(peak, true)}</span>
                  <span>{number(peak / 2, true)}</span>
                  <span>0</span>
                </div>
                <div className="chart-bars">
                  {chart.map((bar, i) => (
                    <div className="bar-column" key={bar.key}>
                      <span
                        className="chart-bar"
                        style={{ height: `${Math.max(2, (bar.tokens / peak) * 100)}%` }}
                        title={`${bar.label}: ${number(bar.tokens)} ${t('jetons', 'tokens')}, ${bar.calls} ${t('appels', 'calls')}`}
                      />
                      <small>
                        {i % Math.max(1, Math.floor(chart.length / 6)) === 0 ? bar.label : ''}
                      </small>
                    </div>
                  ))}
                </div>
              </div>
              <div className="chart-legend">
                <span className="legend-square" />
                {t('Jetons en entrée et sortie', 'Input and output tokens')}
                <span className="spacer" />
                <span>
                  {number(periodCalls)} {t('appels sur', 'calls in')} {periodLabel}
                </span>
              </div>
            </>
          ) : (
            <Empty
              icon={BarChart3}
              title={t('L’activité apparaîtra ici', 'Activity will appear here')}
              description={t(
                'Les traces LLM du serveur permettent de suivre les jetons réellement utilisés.',
                'Server model traces track actual token usage.',
              )}
            />
          )}
        </section>
        <section className="card distribution-card">
          <CardHeader
            title={t('Répartition', 'Breakdown')}
            subtitle={`${t('Par type de traitement', 'By operation type')} · ${periodLabel}`}
          />
          {distribution.length ? (
            distribution.map(([key, value], i) => (
              <div key={key} className="distribution-row">
                <div>
                  <span className={`legend-dot color-${i % 4}`} />
                  <span>{serverFunctionLabel(key)}</span>
                  <strong>{number((value / sum) * 100)} %</strong>
                </div>
                <div className="progress-track">
                  <span className={`color-${i % 4}`} style={{ width: `${(value / sum) * 100}%` }} />
                </div>
              </div>
            ))
          ) : (
            <p className="card-placeholder">
              {t('Aucun appel sur cette période.', 'No calls in this period.')}
            </p>
          )}
          <div className="distribution-note">
            <ShieldCheck size={17} />
            <p>
              {t(
                'Les montants utilisent votre grille tarifaire. Les jetons d’abonnement restent distincts des frais à l’usage.',
                'Amounts use your price list. Subscription tokens are tracked separately from pay-per-use charges.',
              )}
            </p>
          </div>
          <button
            className="text-button"
            onClick={() => {
              setPriceText(JSON.stringify(data.prices, null, 2));
              setPrices(true);
            }}
          >
            {t('Consulter les tarifs', 'View prices')}
            <Settings2 size={14} />
          </button>
        </section>
      </div>
      <ErrorNotice message={data.servicesError} />
      {!!data.services?.length && (
        <section className="card">
          <CardHeader
            title={t('Modèles sans génération', 'Non-generative models')}
            subtitle={t(
              'Décisions, réordonnancement et embeddings des 7 derniers jours, toutes banques',
              'Decisions, reranking and embeddings over the last 7 days, all banks',
            )}
          />
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>{t('Rôle', 'Role')}</th>
                  <th>{t('Modèle', 'Model')}</th>
                  <th>{t('Appels', 'Calls')}</th>
                  <th>{t('Jetons', 'Tokens')}</th>
                  <th>{t('Équivalent API', 'API equivalent')}</th>
                </tr>
              </thead>
              <tbody>
                {data.services.map((row: Row) => (
                  <tr key={`${row.kind}|${row.model}`}>
                    <td>
                      {{
                        decision: t('Décisions', 'Decisions'),
                        rerank: t('Réordonnancement', 'Reranking'),
                        embedding: t('Embeddings', 'Embeddings'),
                      }[row.kind as string] || row.kind}
                    </td>
                    <td className="truncate-cell">{row.model || '—'}</td>
                    <td>{number(row.calls)}</td>
                    <td>{number(row.tokens)}</td>
                    <td className="muted">
                      {typeof row.dollars === 'number'
                        ? row.dollars > 0 && row.dollars < 0.01
                          ? t('< 0,01 $', '< $0.01')
                          : money(row.dollars)
                        : t('non chiffré', 'not estimated')}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="form-hint">
            {t(
              'Montants indicatifs aux tarifs Hindsight Inference : le relevé par modèle ne distingue pas un appel hébergé du même modèle servi localement. Les appels locaux n’entraînent pas de frais par jeton. Ces montants restent hors des plafonds LLM.',
              'Indicative amounts use Hindsight Inference prices. Per-model usage does not distinguish hosted calls from the same model served locally. Local calls have no per-token charge. These amounts are excluded from model spending limits.',
            )}
          </p>
        </section>
      )}
      <p className="page-footnote">
        <Clock3 size={13} />
        {data.lastPoll
          ? `${t('Dernier relevé :', 'Last reading:')} ${date(data.lastPoll, true)}.`
          : t('Aucun relevé effectué.', 'No readings yet.')}{' '}
        {t(
          'Les traces disponibles peuvent ne couvrir qu’une partie de la période.',
          'Available traces may cover only part of the period.',
        )}
      </p>
      {budgets && (
        <Modal
          title={t('Mes plafonds', 'My limits')}
          subtitle={t(
            'Des limites pour garder une consommation prévisible.',
            'Set limits to keep usage predictable.',
          )}
          onClose={() => setBudgets(false)}
        >
          {data.tracesOff && (
            <div className="notice">
              {t(
                'Le serveur n’enregistre pas ses appels LLM : ces plafonds ne pourront pas se déclencher tant que ses traces sont coupées.',
                'The server does not record its model calls: these limits cannot trigger while its traces are off.',
              )}
            </div>
          )}
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
              const dailyDollars = dollars ? Number(dollars) : null;
              if (dailyDollars != null && (!Number.isFinite(dailyDollars) || dailyDollars <= 0)) {
                notify(t('Indiquez des plafonds valides.', 'Enter valid limits.'));
                return;
              }
              // Seuls les champs encore pris en charge sont envoyés : pas d’anciens quotas d’abonnement.
              void run('budget.save', {
                budget: {
                  dailyDollars,
                  warnAt: data.budgets?.warnAt ?? 0.8,
                  action: autoPause ? 'softPause' : 'alert',
                  actionConfirmed: autoPause,
                },
              }).then(() => setBudgets(false));
            }}
          >
            <label>
              {t('Budget quotidien en dollars US', 'Daily budget in US dollars')}
              <input
                type="number"
                min="0.01"
                step="0.01"
                value={dollars}
                onChange={(e) => setDollars(e.target.value)}
                placeholder={t('Sans plafond', 'No limit')}
              />
            </label>
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={autoPause}
                onChange={(e) => setAutoPause(e.target.checked)}
              />
              {t(
                'Mettre toutes les banques en pause au dépassement',
                'Pause all memory banks when a limit is reached',
              )}
            </label>
            <p className="form-hint">
              {t(
                'L’action automatique nécessite de laisser cette application ouverte. Sans elle, un plafond atteint déclenche une alerte.',
                'The automatic action requires this app to stay open. Without it, a reached limit triggers an alert.',
              )}
            </p>
            <div className="modal-actions">
              <Button type="button" onClick={() => setBudgets(false)}>
                {t('Annuler', 'Cancel')}
              </Button>
              <Button kind="primary" disabled={busy}>
                {t('Enregistrer les plafonds', 'Save limits')}
              </Button>
            </div>
          </form>
        </Modal>
      )}
      {prices && (
        <Modal
          title={t('Grille tarifaire', 'Price list')}
          subtitle={t(
            'Montants en dollars US par million de jetons.',
            'US dollars per million tokens.',
          )}
          onClose={() => setPrices(false)}
          wide
        >
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
              try {
                const parsed = JSON.parse(priceText);
                void run('prices.save', { prices: parsed }).then(() => setPrices(false));
              } catch {
                notify(
                  t(
                    'La grille doit contenir un JSON valide.',
                    'The price list must contain valid JSON.',
                  ),
                );
              }
            }}
          >
            <textarea
              className="code-input"
              aria-label={t('Grille tarifaire JSON', 'Price list JSON')}
              value={priceText}
              onChange={(e) => setPriceText(e.target.value)}
              rows={18}
            />
            <div className="modal-actions">
              <Button type="button" onClick={() => setPrices(false)}>
                {t('Fermer', 'Close')}
              </Button>
              <Button kind="primary" disabled={busy}>
                {t('Enregistrer', 'Save')}
              </Button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}
