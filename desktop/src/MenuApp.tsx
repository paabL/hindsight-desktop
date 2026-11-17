import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import {
  Activity,
  ChevronDown,
  CircleAlert,
  Pause,
  Play,
  Power,
  RefreshCw,
  TriangleAlert,
} from 'lucide-react';
import { getLanguage, languageStorageKey, translate as t } from './i18n-core.ts';
import { localizeConfirmation, nativeSystemMessage } from './native-messages.ts';
import type { Confirmation } from './types.ts';
import {
  activitySummary,
  bankName,
  compact,
  consolidationLine,
  count,
  money,
  newConfirmation,
  notice,
  operationName,
  primaryAction,
  progress,
  serverName,
  trayLook,
  trayTooltip,
  type MenuAction,
  type MenuStatus,
} from './menu-model.ts';
import { demoMenuStatus } from './menu-demo.ts';
import './menubar.css';

const tauri = Boolean(window.__TAURI_INTERNALS__);
const themeKey = 'hindsight-desktop-theme-v2';
const storedTheme = () => {
  try {
    return localStorage.getItem(themeKey) === 'light' ? 'light' : 'dark';
  } catch {
    return 'dark';
  }
};
const storedLanguage = () => {
  try {
    return localStorage.getItem(languageStorageKey);
  } catch {
    return null;
  }
};

async function invoke<T>(command: string, args: Record<string, unknown> = {}): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(command, args);
}
/** Commande du moteur, avec le relevé du volet en retour (`menu: true`) au lieu des données de la fenêtre. */
async function engine(command: string, args: Record<string, unknown> = {}): Promise<MenuStatus> {
  if (!tauri)
    return demoMenuStatus(new URLSearchParams(location.search).get('state'), command, args);
  return invoke<MenuStatus>('bridge', {
    request: { command, args: { ...args, menu: true, background: true } },
  });
}
const send = (action: MenuAction) =>
  tauri ? invoke('menu_action', { action }) : Promise.resolve();
const hide = () => (tauri ? invoke('menu_hide') : Promise.resolve());
const closePopover = (element: HTMLElement | null) => {
  try {
    if (element?.matches(':popover-open')) element.hidePopover();
  } catch {}
};

/** Le volet suit sa hauteur naturelle ; le panneau natif garde son haut sous l’icône. */
function useNativeHeight(panel: React.RefObject<HTMLElement | null>) {
  const sent = useRef(0);
  const measure = useCallback(() => {
    const box = panel.current;
    if (!tauri || !box) return;
    const height = Math.ceil(box.scrollHeight);
    if (Math.abs(height - sent.current) < 1) return;
    sent.current = height;
    void invoke('menu_resize', { height }).catch(() => {});
  }, [panel]);
  useLayoutEffect(measure);
  useEffect(() => {
    if (!panel.current) return;
    const observer = new ResizeObserver(measure);
    observer.observe(panel.current);
    return () => observer.disconnect();
  }, [measure, panel]);
}

function Dot({ tone, pulse = false }: { tone: string; pulse?: boolean }) {
  return (
    <span className={`menu-dot ${pulse ? 'pulse' : ''}`} data-tone={tone} aria-hidden="true" />
  );
}

function Spinner({ label }: { label: string }) {
  return <span className="menu-spinner" role="status" aria-label={label} />;
}

export default function MenuApp() {
  const [status, setStatus] = useState<MenuStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(!tauri);
  const [refreshing, setRefreshing] = useState(false);
  const [working, setWorking] = useState(false);
  const [asked, setAsked] = useState<Confirmation | null>(null);
  const [typed, setTyped] = useState('');
  const [feedback, setFeedback] = useState<string | null>(null);
  const [theme, setTheme] = useState(storedTheme);
  const panel = useRef<HTMLElement>(null);
  const banks = useRef<HTMLDivElement>(null);
  const latest = useRef<MenuStatus | null>(null);
  latest.current = status;
  const seen = useRef(new Set<string>());
  const banksClosedAt = useRef(0);
  const openRef = useRef(open);
  openRef.current = open;
  useNativeHeight(panel);

  // Thème de l’app, verre natif compris ; une langue changée dans la fenêtre recharge le volet.
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    if (tauri) void invoke('menu_theme', { dark: theme === 'dark' }).catch(() => {});
  }, [theme]);
  useEffect(() => {
    const changed = (event: StorageEvent) => {
      if (event.key === themeKey) setTheme(storedTheme());
      if (event.key === languageStorageKey && storedLanguage() !== getLanguage()) location.reload();
    };
    window.addEventListener('storage', changed);
    return () => window.removeEventListener('storage', changed);
  }, []);

  const accept = useCallback((next: MenuStatus, announce: boolean) => {
    setStatus(next);
    setError(null);
    // Résultats d’action produits pendant que le volet est ouvert ; la fenêtre les affiche aussi.
    next.messages.forEach((message, index) => {
      const key = next.messageKeys[index] || message;
      if (seen.current.has(key)) return;
      seen.current.add(key);
      if (announce) setFeedback(nativeSystemMessage(message));
    });
    if (tauri)
      void invoke('tray_state', { look: trayLook(next), tooltip: trayTooltip(next) }).catch(
        () => {},
      );
  }, []);

  const read = useCallback(
    async (live: boolean, announce = live) => {
      try {
        const next = await (tauri
          ? invoke<MenuStatus>('bridge', { request: { command: 'menu.status', args: { live } } })
          : engine('menu.status'));
        accept(next, announce);
      } catch (e) {
        setError(nativeSystemMessage(e instanceof Error ? e.message : String(e)));
      }
    },
    [accept],
  );

  // Ouvert : relevé toutes les 4 s, file et traces suivies de près. Fermé : une fois par minute, pour l’icône.
  useEffect(() => {
    void read(open, false);
    const timer = setInterval(() => void read(open), open ? 4000 : 60000);
    return () => clearInterval(timer);
  }, [open, read]);
  useEffect(() => {
    if (!tauri) return;
    let stop: (() => void) | undefined;
    let stopped = false;
    void import('@tauri-apps/api/event')
      .then(({ listen }) =>
        listen<boolean>('menu-visibility', ({ payload }) => {
          if (payload) {
            // À chaque ouverture : aucun bouton ne garde l’anneau de focus, aucun ancien message.
            (document.activeElement as HTMLElement | null)?.blur();
            setFeedback(null);
            setTheme(storedTheme());
            if (storedLanguage() && storedLanguage() !== getLanguage()) location.reload();
          } else {
            setAsked(null);
            closePopover(banks.current);
          }
          setOpen(payload);
        }).then((unlisten) => (stopped ? unlisten() : (stop = unlisten))),
      )
      .catch(() => {});
    return () => {
      stopped = true;
      stop?.();
    };
  }, []);

  useEffect(() => {
    const list = banks.current;
    const toggled = (event: Event) => {
      if ((event as ToggleEvent).newState === 'closed') banksClosedAt.current = Date.now();
    };
    list?.addEventListener('toggle', toggled);
    return () => list?.removeEventListener('toggle', toggled);
  }, [status?.connected]);

  const go = (section?: string) => void send({ kind: 'open', section });
  async function act(command: string, args: Record<string, unknown> = {}) {
    setWorking(true);
    setFeedback(null);
    const before = latest.current;
    try {
      const next = await engine(command, args);
      accept(next, true);
      const question = newConfirmation(before, next);
      if (question) {
        setTyped('');
        setAsked(localizeConfirmation(question));
      } else void send({ kind: 'changed' });
    } catch (e) {
      setFeedback(nativeSystemMessage(e instanceof Error ? e.message : String(e)));
    } finally {
      setWorking(false);
    }
  }
  async function answer(confirmed: boolean) {
    const question = asked;
    setAsked(null);
    if (!question) return;
    await act(confirmed ? 'confirm' : 'cancel', confirmed ? { id: question.id, typed } : {});
  }
  async function refresh() {
    setRefreshing(true);
    await read(true);
    setRefreshing(false);
  }
  /** Liste des banques sous le bouton : une couche au-dessus du volet, placée d’après le bouton. */
  function openBanks(button: HTMLElement) {
    const list = banks.current;
    if (!list) return;
    // Un clic sur le bouton ferme d’abord la liste (clic en dehors) : ne pas la rouvrir aussitôt.
    if (list.matches(':popover-open') || Date.now() - banksClosedAt.current < 250)
      return closePopover(list);
    const box = button.getBoundingClientRect();
    list.style.top = `${Math.round(box.bottom + 4)}px`;
    list.style.right = `${Math.max(8, Math.round(innerWidth - box.right))}px`;
    list.showPopover();
    list.querySelector<HTMLButtonElement>('[aria-checked="true"]')?.focus();
  }
  function chooseBank(id: string) {
    closePopover(banks.current);
    if (!status || id === status.bank) return;
    // La fenêtre change de banque avec tout son contexte ; le volet suit dès le relevé suivant.
    setStatus({ ...status, bank: id, bankStatus: null });
    void send({ kind: 'bank', id });
    setTimeout(() => void read(true, false), 700);
  }

  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        if (document.querySelector(':popover-open')) return;
        if (asked) void answer(false);
        else void hide();
        return;
      }
      if (!(event.metaKey || event.ctrlKey)) return;
      const keyName = event.key.toLowerCase();
      if (keyName === 'w') void hide();
      else if (keyName === 'q') void send({ kind: 'quit' });
      else if (keyName === ',') go('settings');
      else if (keyName === 'r') void refresh();
      else return;
      event.preventDefault();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  });

  const connected = status?.connected ?? false;
  const currentBank = status?.bank ?? null;
  const bankFacts = status?.banks.find((b) => b.bank_id === currentBank)?.fact_count;
  const reading = status?.bankStatus?.bank === currentBank ? status?.bankStatus : null;
  const consolidation = consolidationLine(reading?.consolidation);
  const banner = notice(status);
  const primary = primaryAction(status);
  const running = status?.activity.running ?? [];
  const queue = status?.activity.queues.find((q) => q.bank === currentBank);
  const gauge = status?.usage.gauges[0];
  const subtitle = !status
    ? t('Lecture…', 'Loading…')
    : status.connected
      ? `${serverName(status.serverURL)}${status.version ? ` · ${status.version}` : ''}`
      : status.connecting
        ? t('Connexion…', 'Connecting…')
        : t('Hors connexion', 'Offline');

  return (
    <main
      ref={panel}
      className="menu-panel"
      aria-label={t('Hindsight dans la barre des menus', 'Hindsight in the menu bar')}
    >
      <header className="menu-header">
        <img className="menu-brand" src="favicon.svg" alt="" width={30} height={30} />
        <div className="menu-title">
          <strong>Hindsight</strong>
          <span>
            <Dot
              tone={connected ? 'sage' : status?.connecting ? 'blue' : 'red'}
              pulse={status?.connecting}
            />
            {subtitle}
          </span>
        </div>
        <button
          className="menu-icon-button"
          aria-label={t('Actualiser', 'Refresh')}
          title={t('Actualiser (⌘R)', 'Refresh (⌘R)')}
          onClick={() => void refresh()}
          disabled={refreshing}
        >
          <RefreshCw size={15} strokeWidth={1.8} className={refreshing ? 'spin' : ''} />
        </button>
      </header>

      {asked ? (
        <section
          className="menu-card menu-confirm"
          role="alertdialog"
          aria-labelledby="menu-confirm-title"
        >
          <h2 id="menu-confirm-title">{asked.title}</h2>
          <p>{asked.message}</p>
          {asked.requiredText && (
            <label className="menu-typed">
              <span>
                {t('Saisissez', 'Type')} <code>{asked.requiredText}</code>
              </span>
              <input value={typed} onChange={(e) => setTyped(e.target.value)} autoFocus />
            </label>
          )}
          <div className="menu-confirm-actions">
            <button className="menu-button" onClick={() => void answer(false)}>
              {t('Annuler', 'Cancel')}
            </button>
            <button
              className={`menu-button primary ${asked.destructive ? 'danger' : ''}`}
              disabled={!!asked.requiredText && typed !== asked.requiredText}
              onClick={() => void answer(true)}
              autoFocus={!asked.requiredText}
            >
              {asked.confirmTitle}
            </button>
          </div>
        </section>
      ) : (
        <>
          {(banner || error) && (
            <div className="menu-notice" role="status" data-tone={error ? 'red' : banner!.tone}>
              {(error ? 'red' : banner!.tone) === 'red' ? (
                <CircleAlert size={14} aria-hidden="true" />
              ) : (
                <TriangleAlert size={14} aria-hidden="true" />
              )}
              <span>{error || banner!.text}</span>
            </div>
          )}

          {connected && (
            <section className="menu-card menu-bank" aria-labelledby="menu-bank-heading">
              <div className="menu-card-heading">
                <h2 id="menu-bank-heading">{t('Banque', 'Memory bank')}</h2>
                {(status?.banks.length ?? 0) > 1 && (
                  <button
                    className="menu-switch"
                    aria-haspopup="menu"
                    aria-label={t('Changer de banque', 'Switch memory bank')}
                    onClick={(event) => openBanks(event.currentTarget)}
                  >
                    {t('Changer', 'Switch')}
                    <ChevronDown size={12} strokeWidth={2} />
                  </button>
                )}
              </div>
              {currentBank ? (
                <button className="menu-row menu-bank-main" onClick={() => go('dashboard')}>
                  <span className="menu-bank-name">{bankName(status, currentBank)}</span>
                  {typeof bankFacts === 'number' && (
                    <span className="menu-bank-facts">
                      {count(bankFacts)}{' '}
                      {t(bankFacts > 1 ? 'faits' : 'fait', bankFacts === 1 ? 'fact' : 'facts')}
                    </span>
                  )}
                </button>
              ) : (
                <p className="menu-empty">
                  {t('Aucune banque choisie.', 'No memory bank selected.')}
                </p>
              )}
              {consolidation && (
                <button className="menu-row menu-line" onClick={() => go('consolidation')}>
                  <Dot
                    tone={consolidation.tone}
                    pulse={reading?.consolidation?.phase === 'running'}
                  />
                  <span>{consolidation.text}</span>
                </button>
              )}
              {!!reading?.failed && (
                <button className="menu-row menu-line" onClick={() => go('operations')}>
                  <Dot tone="red" />
                  <span>
                    {count(reading.failed)}{' '}
                    {t(
                      reading.failed > 1 ? 'opérations en échec' : 'opération en échec',
                      reading.failed === 1 ? 'failed operation' : 'failed operations',
                    )}
                  </span>
                </button>
              )}
              <div ref={banks} id="menu-banks" className="menu-popover" popover="auto" role="menu">
                {status?.banks.map((bank) => {
                  const id = String(bank.bank_id);
                  return (
                    <button
                      key={id}
                      role="menuitemradio"
                      aria-checked={id === currentBank}
                      className="menu-popover-item"
                      onClick={() => chooseBank(id)}
                    >
                      <span>{bankName(status, id)}</span>
                      {typeof bank.fact_count === 'number' && (
                        <small>{compact(bank.fact_count)}</small>
                      )}
                    </button>
                  );
                })}
              </div>
            </section>
          )}

          {connected && (
            <section className="menu-card" aria-labelledby="menu-activity-heading">
              <div className="menu-card-heading">
                <h2 id="menu-activity-heading">{t('Activité', 'Activity')}</h2>
                <span className="menu-count">{status && activitySummary(status)}</span>
              </div>
              {running.length === 0 ? (
                <button className="menu-row menu-line menu-quiet" onClick={() => go('operations')}>
                  <Activity size={14} strokeWidth={1.8} aria-hidden="true" />
                  <span>
                    {status?.activity.pending
                      ? t(
                          'Des opérations attendent leur tour.',
                          'Operations are waiting their turn.',
                        )
                      : t('Le serveur est au repos.', 'The server is idle.')}
                  </span>
                </button>
              ) : (
                running.map((op) => {
                  const share = progress(op);
                  return (
                    <button
                      key={op.id}
                      className="menu-row menu-op"
                      onClick={() => go('operations')}
                    >
                      <Dot tone="sage" pulse />
                      <span className="menu-op-text">
                        <span className="menu-op-title">
                          <strong>{operationName(op)}</strong>
                          {op.bank !== currentBank && <span>{bankName(status, op.bank)}</span>}
                        </span>
                        {share != null && (
                          <span
                            className="menu-progress"
                            aria-label={`${Math.round(share * 100)} %`}
                          >
                            <span style={{ width: `${share * 100}%` }} />
                          </span>
                        )}
                      </span>
                      {share != null && (
                        <span className="menu-op-count">
                          {compact(op.processed!)}/{compact(op.total!)}
                        </span>
                      )}
                    </button>
                  );
                })
              )}
              {queue && queue.pending > 0 && status && status.activity.pending > queue.pending && (
                <p className="menu-footnote">
                  {count(queue.pending)} {t('en attente dans cette banque', 'queued in this bank')}
                </p>
              )}
            </section>
          )}

          {connected && status?.usage.tracked && (
            <section className="menu-card menu-usage" aria-labelledby="menu-usage-heading">
              <div className="menu-card-heading">
                <h2 id="menu-usage-heading">{t('Aujourd’hui', 'Today')}</h2>
                {/* « Au repos » est déjà dit par Activité : le rythme n’apparaît que s’il y a des appels. */}
                {!status.usage.idle && (
                  <span className="menu-count">
                    {compact(status.usage.tokensPerMinute)} {t('jetons/min', 'tokens/min')}
                  </span>
                )}
              </div>
              <button className="menu-row menu-figures" onClick={() => go('consumption')}>
                <span>
                  <strong>{money(status.usage.today)}</strong>
                  <small>{t('facturés', 'billed')}</small>
                </span>
                <span>
                  <strong>{compact(status.usage.todayTokens)}</strong>
                  <small>{t('jetons', 'tokens')}</small>
                </span>
                {status.usage.subscription5h > 0 && (
                  <span>
                    <strong>{compact(status.usage.subscription5h)}</strong>
                    <small>{t('abonnements, 5 h', 'subscriptions, 5 h')}</small>
                  </span>
                )}
              </button>
              {gauge && (
                <div className="menu-gauge" data-level={gauge.level}>
                  <span className="menu-progress">
                    <span style={{ width: `${Math.min(1, gauge.fraction) * 100}%` }} />
                  </span>
                  <small>
                    {money(gauge.used)} {t('sur', 'of')} {money(gauge.limit)}{' '}
                    {t('par jour', 'per day')}
                  </small>
                </div>
              )}
            </section>
          )}

          {primary && (
            <div className="menu-controls">
              <button
                className={`menu-button primary wide ${primary.kind === 'resume' ? 'resume' : ''}`}
                disabled={primary.disabled || working}
                onClick={() =>
                  void act(
                    primary.kind === 'start' ? 'service.start' : `pause.${primary.kind}`,
                    primary.kind === 'start' ? {} : { all: true },
                  )
                }
              >
                {working ||
                status?.pause.busy ||
                (primary.kind === 'start' && status?.service.busy) ? (
                  <Spinner label={t('En cours', 'In progress')} />
                ) : primary.kind === 'pause' ? (
                  <Pause size={14} strokeWidth={2} />
                ) : primary.kind === 'resume' ? (
                  <Play size={14} strokeWidth={2} />
                ) : (
                  <Power size={14} strokeWidth={2} />
                )}
                <span>
                  {status?.pause.busy && status.pause.progress
                    ? nativeSystemMessage(status.pause.progress)
                    : primary.label}
                </span>
              </button>
              {connected &&
                status?.service.local &&
                status.service.installed &&
                status.service.known && (
                  <div className="menu-service">
                    <Dot tone={status.service.running ? 'sage' : 'neutral'} />
                    <span>
                      {t('Serveur local', 'Local server')} ·{' '}
                      {status.service.busy
                        ? t('en cours de modification', 'changing')
                        : status.service.running
                          ? t('en marche', 'running')
                          : t('arrêté', 'stopped')}
                    </span>
                    {status.service.canStop && (
                      <button
                        className="menu-link"
                        disabled={working}
                        onClick={() => void act('service.stop')}
                      >
                        {t('Arrêter', 'Stop')}
                      </button>
                    )}
                  </div>
                )}
            </div>
          )}
        </>
      )}

      {feedback && (
        <p className="menu-feedback" role="status">
          {feedback}
        </p>
      )}

      <nav className="menu-footer" aria-label={t('Application', 'Application')}>
        <button className="menu-item" onClick={() => go()}>
          <span>{t('Ouvrir Hindsight', 'Open Hindsight')}</span>
        </button>
        <button className="menu-item" onClick={() => go('settings')}>
          <span>{t('Réglages…', 'Settings…')}</span>
          <kbd>⌘,</kbd>
        </button>
        <button className="menu-item" onClick={() => void send({ kind: 'quit' })}>
          <span>{t('Quitter Hindsight', 'Quit Hindsight')}</span>
          <kbd>⌘Q</kbd>
        </button>
      </nav>
    </main>
  );
}
