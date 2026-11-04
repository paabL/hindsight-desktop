import { translate as t, useI18n } from '../i18n';
import { useMemo, useState } from 'react';
import {
  Activity,
  ArrowDownToLine,
  BarChart3,
  CircleDollarSign,
  Clock3,
  Gauge,
  Pause,
  Play,
  Settings2,
  ShieldCheck,
  Snowflake,
  Trash2,
  Zap,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  Metric,
  Modal,
  PageHeader,
  Tabs,
  date,
  money,
  number,
} from '../ui';

export function PauseTools({ run, busy }: Pick<PageProps, 'run' | 'busy'>) {
  useI18n();
  const [open, setOpen] = useState(false);
  const [all, setAll] = useState(false);
  return (
    <>
      <Button icon={Pause} onClick={() => setOpen(true)}>
        {t('Gérer les traitements', 'Manage processing')}
      </Button>
      {open && (
        <Modal
          title={t('Garder la main sur les traitements', 'Control processing')}
          subtitle={t('Choisissez l’action adaptée à votre besoin.', 'Choose the action you need.')}
          onClose={() => setOpen(false)}
        >
          <label className="checkbox-label scope-choice">
            <input type="checkbox" checked={all} onChange={(e) => setAll(e.target.checked)} />
            {t('Appliquer à toutes les banques', 'Apply to all banks')}
          </label>
          <div className="pause-options">
            <article>
              <span className="category-icon peach">
                <Pause size={21} />
              </span>
              <div>
                <h3>{t('Mettre en pause', 'Pause')}</h3>
                <p>
                  {t(
                    'Suspend les nouveaux envois de cette app et la consolidation automatique.',
                    'Pause new uploads from this app and automatic consolidation.',
                  )}
                </p>
                <div className="action-row">
                  <Button disabled={busy} onClick={() => void run('pause.pause', { all })}>
                    {t('Mettre en pause', 'Pause')}
                  </Button>
                  <Button
                    icon={Play}
                    disabled={busy}
                    onClick={() => void run('pause.resume', { all })}
                  >
                    {t('Reprendre', 'Resume')}
                  </Button>
                </div>
              </div>
            </article>
            <article>
              <span className="category-icon lavender">
                <Snowflake size={21} />
              </span>
              <div>
                <h3>{t('Geler la file du serveur', 'Freeze the server queue')}</h3>
                <p>
                  {t(
                    'Redémarre le serveur avec son traitement en arrière-plan suspendu. Toutes les banques sont concernées.',
                    'Restart the server with background processing suspended. All banks are affected.',
                  )}
                </p>
                <div className="action-row">
                  <Button disabled={busy} onClick={() => void run('pause.freeze')}>
                    {t('Geler', 'Freeze')}
                  </Button>
                  <Button disabled={busy} onClick={() => void run('pause.unfreeze')}>
                    {t('Dégeler', 'Unfreeze')}
                  </Button>
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
                  disabled={busy}
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

function QuotaCard({ title, quota, tone }: { title: string; quota?: Row; tone: string }) {
  useI18n();
  return (
    <article className="card quota-card">
      <div className="quota-title">
        <span className={`provider-monogram ${tone}`}>{title === 'Codex' ? 'O' : '✳'}</span>
        <div>
          <h3>{title === 'Codex' ? 'ChatGPT / Codex' : 'Claude Code'}</h3>
          <p>{t('Quota de l’abonnement', 'Subscription quota')}</p>
        </div>
        {quota && <Badge tone="sage">{t('Relevé', 'Checked')}</Badge>}
      </div>
      {quota ? (
        <>
          <div className="quota-windows">
            {[
              { key: 'primary', title: t('Fenêtre courte', 'Short window') },
              { key: 'secondary', title: t('Semaine', 'Week') },
            ].map(({ key, title: label }) => {
              const window = quota[key];
              return (
                <div key={key}>
                  <div className="quota-label">
                    <span>{label}</span>
                    <strong>
                      {window ? `${number(Math.max(0, 100 - window.usedPercent))} %` : '—'}{' '}
                      <small>{t('restant', 'remaining')}</small>
                    </strong>
                  </div>
                  <div className="progress-track">
                    <span
                      className={window?.usedPercent > 80 ? 'amber-fill' : tone}
                      style={{ width: `${Math.max(0, Math.min(100, window?.usedPercent || 0))}%` }}
                    />
                  </div>
                  <p>
                    {window?.resetsAt
                      ? `${t('Réinitialisation :', 'Resets:')} ${date(window.resetsAt, true)}`
                      : t('Réinitialisation non disponible', 'Reset time unavailable')}
                  </p>
                </div>
              );
            })}
          </div>
          <div className="quota-footnote">
            <Clock3 size={12} />
            {t('Observé le', 'Observed on')} {date(quota.observedAt, true)}
          </div>
        </>
      ) : (
        <Empty
          icon={Gauge}
          title={t('Quota non disponible', 'Quota unavailable')}
          description={t(
            'Connectez le compte avec son client officiel. Le dernier relevé disponible apparaîtra ici.',
            'Sign in through the official client. The latest available reading will appear here.',
          )}
        />
      )}
    </article>
  );
}

export default function Consumption({ data, run, busy, notify, demo }: PageProps) {
  const { language } = useI18n();
  const [period, setPeriod] = useState('day');
  const [budgets, setBudgets] = useState(false);
  const [prices, setPrices] = useState(false);
  const [priceText, setPriceText] = useState('');
  const [dollars, setDollars] = useState('');
  const [quota, setQuota] = useState('');
  const [autoPause, setAutoPause] = useState(false);
  const [budgetAction, setBudgetAction] = useState('softPause');
  const [subscriptionLimits, setSubscriptionLimits] = useState<Row>({});
  const summary = data.summary || {};
  const today = summary.today || {};
  const events: Row[] = data.events || [];
  const chart = useMemo(() => {
    const groups = new Map<string, { tokens: number; calls: number; label: string }>();
    const latest = events.reduce((latest, e) => Math.max(latest, Date.parse(e.date) || 0), 0);
    const cutoff = latest - (period === 'day' ? 86_400_000 : 7 * 86_400_000);
    for (const event of events) {
      if ((Date.parse(event.date) || 0) < cutoff) continue;
      const d = new Date(event.date);
      const key = period === 'day' ? d.toISOString().slice(0, 13) : d.toISOString().slice(0, 10);
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
  }, [events, period, language]);
  const peak = Math.max(1, ...chart.map((c) => c.tokens));
  const distribution = useMemo(() => {
    const groups = new Map<string, number>();
    for (const e of events)
      groups.set(
        e.operation || t('Autre', 'Other'),
        (groups.get(e.operation || t('Autre', 'Other')) || 0) +
          (e.tokens?.input || 0) +
          (e.tokens?.output || 0),
      );
    return [...groups.entries()].sort((a, b) => b[1] - a[1]);
  }, [events, language]);
  const sum = distribution.reduce((n, [, v]) => n + v, 0) || 1;
  function editBudgets() {
    setDollars(String(data.budgets?.dailyDollars ?? ''));
    setQuota(String(data.budgets?.codexQuotaPercent ?? ''));
    setAutoPause(data.budgets?.actionConfirmed || false);
    setBudgetAction(data.budgets?.action || 'softPause');
    setSubscriptionLimits(structuredClone(data.budgets?.subscriptions || {}));
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
          <>
            <PauseTools run={run} busy={busy} />
            <Button icon={Settings2} onClick={editBudgets}>
              {t('Mes plafonds', 'My limits')}
            </Button>
          </>
        }
      />
      <ErrorNotice message={data.error} />
      <div className="metrics-grid">
        <Metric
          label={t('Coût estimé aujourd’hui', 'Estimated cost today')}
          value={money(today.dollars)}
          note={t('Appels facturés à l’usage · USD', 'Pay-per-use calls · USD')}
          icon={CircleDollarSign}
        />
        <Metric
          label={t('Appels aujourd’hui', 'Calls today')}
          value={number(today.calls)}
          note={t('Toutes les banques', 'All banks')}
          icon={Activity}
          tone="sage"
        />
        <Metric
          label={t('Jetons sur abonnement', 'Subscription tokens')}
          value={number(today.subscriptionTokens, true)}
          note={t('Comptés dans le quota du fournisseur', 'Counted toward the provider quota')}
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
      <div className="action-row">
        <Button
          icon={Gauge}
          disabled={busy || demo}
          onClick={() => void run('subscription.refresh')}
        >
          {t('Vérifier les quotas d’abonnement', 'Check subscription quotas')}
        </Button>
        <span className="form-hint">
          {t(
            'Lecture ponctuelle des comptes officiels, après confirmation. Aucun accès automatique.',
            'Check official accounts once, after confirmation. No automatic access.',
          )}
        </span>
      </div>
      <div className="two-columns quota-grid">
        <QuotaCard title="Codex" quota={data.codexQuota} tone="sage" />
        <QuotaCard title="Claude" quota={data.claudeQuota} tone="accent" />
      </div>
      {data.quotaProblems?.length > 0 && (
        <details className="muted-details">
          <summary>
            {t('Pourquoi certains relevés manquent', 'Why some readings are missing')}
          </summary>
          {data.quotaProblems.map((p: string) => (
            <p key={p}>{p}</p>
          ))}
        </details>
      )}
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
                  {number(events.length)} {t('appels chargés', 'calls loaded')}
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
            subtitle={t('Par type de traitement', 'By operation type')}
          />
          {distribution.length ? (
            distribution.map(([key, value], i) => (
              <div key={key} className="distribution-row">
                <div>
                  <span className={`legend-dot color-${i % 4}`} />
                  <span>
                    {{
                      retain: t('Extraction de faits', 'Fact extraction'),
                      consolidation: t('Consolidation', 'Consolidation'),
                      reflect: t('Réponses', 'Answers'),
                      mental_model: t('Synthèses', 'Knowledge pages'),
                    }[key] || key}
                  </span>
                  <strong>{number((value / sum) * 100)} %</strong>
                </div>
                <div className="progress-track">
                  <span className={`color-${i % 4}`} style={{ width: `${(value / sum) * 100}%` }} />
                </div>
              </div>
            ))
          ) : (
            <p className="card-placeholder">{t('Aucun appel enregistré.', 'No calls recorded.')}</p>
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
      {!!data.gauges?.length && (
        <section className="card">
          <CardHeader
            title={t('Vos plafonds', 'Your limits')}
            action={
              <Button kind="ghost" onClick={editBudgets}>
                {t('Modifier', 'Edit')}
              </Button>
            }
          />
          <div className="budget-gauges">
            {data.gauges.map((gauge: Row) => (
              <div key={gauge.id}>
                <strong>{gauge.title}</strong>
                <span>
                  {number(gauge.used)} / {number(gauge.limit)}
                </span>
                <div className="progress-track">
                  <span style={{ width: `${Math.min(100, (gauge.used / gauge.limit) * 100)}%` }} />
                </div>
              </div>
            ))}
          </div>
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
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
              const dailyDollars = dollars ? Number(dollars) : null,
                codexQuotaPercent = quota ? Number(quota) : null;
              if (
                (dailyDollars != null && (!Number.isFinite(dailyDollars) || dailyDollars <= 0)) ||
                (codexQuotaPercent != null &&
                  (!Number.isFinite(codexQuotaPercent) ||
                    codexQuotaPercent <= 0 ||
                    codexQuotaPercent > 100))
              ) {
                notify(t('Indiquez des plafonds valides.', 'Enter valid limits.'));
                return;
              }
              void run('budget.save', {
                budget: {
                  ...data.budgets,
                  dailyDollars,
                  codexQuotaPercent,
                  subscriptions: subscriptionLimits,
                  action: autoPause ? budgetAction : 'alert',
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
            <label>
              {t(
                'Alerte au pourcentage de quota Codex consommé',
                'Alert at percentage of Codex quota used',
              )}
              <input
                type="number"
                min="1"
                max="100"
                value={quota}
                onChange={(e) => setQuota(e.target.value)}
                placeholder={t('Sans plafond', 'No limit')}
              />
            </label>
            <fieldset className="subscription-limits">
              <legend>
                {t('Plafonds par abonnement (jetons)', 'Limits per subscription (tokens)')}
              </legend>
              {[
                ['openai-codex', 'ChatGPT / Codex'],
                ['claude-code', 'Claude Code'],
              ].map(([provider, title]) => (
                <div key={provider}>
                  <strong>{title}</strong>
                  <div className="two-fields">
                    {[
                      ['tokens5h', t('Sur 5 heures', 'Over 5 hours')],
                      ['tokensWeek', t('Sur 7 jours', 'Over 7 days')],
                    ].map(([key, label]) => (
                      <label key={key}>
                        {label}
                        <input
                          type="number"
                          min="1"
                          step="1"
                          placeholder={t('Sans plafond', 'No limit')}
                          value={subscriptionLimits[provider]?.[key] ?? ''}
                          onChange={(e) =>
                            setSubscriptionLimits((old) => ({
                              ...old,
                              [provider]: {
                                ...old[provider],
                                [key]: e.target.value ? Number(e.target.value) : null,
                              },
                            }))
                          }
                        />
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </fieldset>
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={autoPause}
                onChange={(e) => setAutoPause(e.target.checked)}
              />
              {t(
                'Autoriser une action automatique au dépassement',
                'Allow an automatic action when a limit is reached',
              )}
            </label>
            {autoPause && (
              <label>
                {t('Action autorisée', 'Allowed action')}
                <select value={budgetAction} onChange={(e) => setBudgetAction(e.target.value)}>
                  <option value="softPause">
                    {t('Mettre les traitements en pause', 'Pause processing')}
                  </option>
                  <option value="freezeQueue">
                    {t(
                      'Geler la file (redémarre le serveur)',
                      'Freeze queue (restarts the server)',
                    )}
                  </option>
                </select>
              </label>
            )}
            <p className="form-hint">
              {t(
                'La pause automatique nécessite de laisser cette application ouverte. Sans cette option, les plafonds déclenchent une alerte.',
                'Automatic pause requires this app to stay open. Otherwise, limits trigger an alert.',
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
