import {
  Component,
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  Activity,
  ArrowLeft,
  ArrowRight,
  BarChart3,
  BookOpen,
  Check,
  ChevronDown,
  ChevronRight,
  CircleHelp,
  Command,
  Database,
  Eye,
  FileText,
  Folder,
  Gauge,
  GitBranch,
  Layers3,
  LayoutDashboard,
  ListTodo,
  LoaderCircle,
  Moon,
  Network,
  Plus,
  RefreshCw,
  Search,
  Server,
  Settings2,
  Sparkles,
  Sun,
  X,
} from 'lucide-react';
import type { PageProps, Row, Section, Snapshot } from './types';
import { useI18n, translate as tr, type Language } from './i18n';
import { localizeNativeSnapshot, nativeSystemMessage } from './native-messages';
import { nativeRequest, host } from './transport';
import { exampleRequest } from './demo';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  IconButton,
  Loading,
  Logo,
  Modal,
  PageHeader,
  number,
  shortName,
} from './ui';
import Sources from './pages/Sources';
import Updates from './pages/Updates';
import { Coverage, Documents, Models, SearchPage } from './pages/Library';
import Consumption from './pages/Consumption';
const Audit = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Audit })));
const Dashboard = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Dashboard })));
const Graph = lazy(() => import('./pages/Graph'));
const Timeline = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Timeline })));
import Operations from './pages/Operations';
const Admin = lazy(() => import('./pages/Manage').then((m) => ({ default: m.Admin })));
const Hermes = lazy(() => import('./pages/Manage').then((m) => ({ default: m.Hermes })));
const MemoryDesign = lazy(() =>
  import('./pages/Manage').then((m) => ({ default: m.MemoryDesign })),
);
const ServerSettings = lazy(() =>
  import('./pages/Manage').then((m) => ({ default: m.ServerSettings })),
);

const basePrimary = [
  { id: 'sources', label: 'Mémoire', icon: Folder },
  { id: 'models', label: 'Synthèses', icon: BookOpen },
  { id: 'search', label: 'Recherche', icon: Search },
  { id: 'consumption', label: 'Consommation', icon: BarChart3 },
] as const;
const baseAdvanced = [
  { id: 'documents', label: 'Lecteur de documents', icon: FileText },
  { id: 'dashboard', label: 'Vue d’ensemble', icon: LayoutDashboard },
  { id: 'memory', label: 'Structure de la mémoire', icon: Layers3 },
  { id: 'operations', label: 'Opérations', icon: ListTodo },
  { id: 'audit', label: 'Activité & lectures', icon: Activity },
  { id: 'timeline', label: 'Chronologie', icon: GitBranch },
  { id: 'graph', label: 'Graphe', icon: Network },
  { id: 'hermes', label: 'Import Hermes', icon: ArrowRight },
  { id: 'server', label: 'Serveur & modèles', icon: Server },
  { id: 'admin', label: 'Administration', icon: Database },
] as const;
const baseSections = [
  ...basePrimary,
  ...baseAdvanced,
  { id: 'settings', label: 'Réglages', icon: Settings2 },
  { id: 'coverage', label: 'Couverture des dossiers', icon: Folder },
] as const;
const englishLabels: Record<Section, string> = {
  sources: 'Memory',
  models: 'Summaries',
  search: 'Search',
  consumption: 'Usage',
  documents: 'Document reader',
  dashboard: 'Overview',
  memory: 'Memory structure',
  operations: 'Operations',
  audit: 'Activity & reads',
  timeline: 'Timeline',
  graph: 'Graph',
  hermes: 'Import Hermes',
  server: 'Server & models',
  admin: 'Administration',
  settings: 'Settings',
  coverage: 'Folder coverage',
};
const initial: Snapshot = {
  app: { connected: false, serverURL: 'http://127.0.0.1:8888', banks: [], bank: null },
  section: 'sources',
  data: {},
  confirmations: [],
  messages: [],
};
function initialRoute(): Section {
  const id = location.hash.slice(1);
  return baseSections.some((s) => s.id === id) ? (id as Section) : 'sources';
}

class PageBoundary extends Component<{ children: ReactNode }, { error: boolean }> {
  state = { error: false };
  static getDerivedStateFromError() {
    return { error: true };
  }
  render() {
    return this.state.error ? (
      <Empty
        title={tr('Cette vue n’a pas pu s’afficher', 'This view could not be displayed')}
        description={tr(
          'Actualisez la fenêtre pour recharger les données.',
          'Reload the window to try again.',
        )}
        action={<Button onClick={() => location.reload()}>{tr('Recharger', 'Reload')}</Button>}
      />
    ) : (
      this.props.children
    );
  }
}

export default function App() {
  const { t } = useI18n();
  const localize = <T extends { id: Section; label: string }>(item: T) => ({
    ...item,
    label: t(item.label, englishLabels[item.id]),
  });
  const primary = basePrimary.map(localize);
  const advancedItems = baseAdvanced.map(localize);
  const sections = baseSections.map(localize);
  const [route, setRoute] = useState<Section>(initialRoute);
  const routeRef = useRef(route);
  routeRef.current = route;
  const [rawSnapshot, setSnapshot] = useState<Snapshot>(initial);
  const snapshot = localizeNativeSnapshot(rawSnapshot);
  const [demo, setDemo] = useState(new URLSearchParams(location.search).get('demo') === '1');
  const demoRef = useRef(demo);
  demoRef.current = demo;
  const [ready, setReady] = useState(false);
  const [busyCount, setBusyCount] = useState(0);
  const [advanced, setAdvanced] = useState(advancedItems.some((s) => s.id === route));
  const [command, setCommand] = useState(false);
  const [commandQuery, setCommandQuery] = useState('');
  const [bankMenu, setBankMenu] = useState(false);
  const [typed, setTyped] = useState('');
  const [toast, setToast] = useState<string | null>(null);
  const [theme, setTheme] = useState(
    () => localStorage.getItem('hindsight-desktop-theme-v2') || 'dark',
  );
  const seenMessages = useRef(new Set<string>());
  const notify = useCallback((message: string) => setToast(message), []);
  const busy = busyCount > 0;
  const run = useCallback(async (action: string, args: Row = {}) => {
    setBusyCount((count) => count + 1);
    try {
      const result = demoRef.current
        ? await exampleRequest(action, args, routeRef.current)
        : await nativeRequest(action, args);
      if (result?.app && result?.section) {
        setSnapshot((old) => ({
          ...result,
          section: routeRef.current,
          data: result.section === routeRef.current ? result.data : old.data,
        }));
        for (const message of result.messages || [])
          if (!seenMessages.current.has(message)) {
            seenMessages.current.add(message);
            setToast(message);
          }
      }
      return result;
    } catch (error) {
      const message =
        (error instanceof Error ? error.message : typeof error === 'string' ? error : '') ||
        tr('L’action n’a pas abouti.', 'The action could not be completed.');
      setToast(message);
      return { error: nativeSystemMessage(message) };
    } finally {
      setBusyCount((count) => Math.max(0, count - 1));
    }
  }, []);
  const refresh = useCallback(
    (args: Row = {}) => run('section', { section: routeRef.current, ...args }),
    [run],
  );
  function navigate(section: Section) {
    routeRef.current = section;
    setRoute(section);
    location.hash = section;
    setSnapshot((old) => ({ ...old, section, data: {} }));
    if (advancedItems.some((s) => s.id === section)) setAdvanced(true);
    setCommand(false);
    setBankMenu(false);
  }
  const changeDemo = useCallback((value: boolean) => {
    setReady(false);
    setDemo(value);
    demoRef.current = value;
    seenMessages.current.clear();
    setSnapshot(initial);
  }, []);

  useEffect(() => {
    let active = true;
    setReady(false);
    const start = async () => {
      if (demo || host !== 'Navigateur') {
        await run('bootstrap');
        if (!active) return;
        // La banque n'est choisie qu'à la connexion : l'attendre évite de charger deux fois la section
        // ouverte (sans banque, puis avec). Le moteur traitant les requêtes une à une, ce premier
        // chargement attendait de toute façon la fin de la connexion.
        if (!demo) await run('connect');
        if (!active) return;
        setReady(true);
      } else {
        setReady(true);
      }
    };
    void start();
    return () => {
      active = false;
    };
  }, [demo, run]);
  useEffect(() => {
    if (ready && (demo || host !== 'Navigateur')) void refresh();
  }, [route, snapshot.app.bank, demo, ready, refresh]);
  // Le suivi ne lance aucun traitement. La surveillance reste active si des plafonds sont autorisés.
  // Page Serveur : suit l’installation du modèle local et la connexion à un compte, sans recharger.
  const serverWork =
    route === 'server' &&
    !!(snapshot.data?.connectingAccount || snapshot.data?.hindsightModels?.local?.busy);
  useEffect(() => {
    if (
      !ready ||
      demo ||
      host === 'Navigateur' ||
      (!snapshot.app.connected && route !== 'settings' && !serverWork)
    )
      return;
    const seconds =
      route === 'settings' || serverWork
        ? 2
        : route === 'operations'
          ? 20
          : route === 'consumption'
            ? 30
            : 0;
    if (!seconds) return;
    const interval = setInterval(() => {
      if (!document.hidden) {
        if (route === 'settings' || serverWork) void run('snapshot');
        else void refresh();
      }
    }, seconds * 1000);
    return () => clearInterval(interval);
  }, [route, snapshot.app.connected, ready, demo, refresh, serverWork]);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem('hindsight-desktop-theme-v2', theme);
  }, [theme]);
  useEffect(() => {
    if (!toast) return;
    const timeout = setTimeout(() => setToast(null), 9500);
    return () => clearTimeout(timeout);
  }, [toast]);
  useEffect(() => {
    setTyped('');
  }, [snapshot.confirmations[0]?.id]);
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey)) return;
      if (event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setCommand((open) => !open);
      } else if (event.key === ',') {
        event.preventDefault();
        navigate('settings');
      } else if (event.key.toLowerCase() === 'r') {
        event.preventDefault();
        void refresh();
      } else if (/^[1-9]$/.test(event.key) && primary[Number(event.key) - 1]) {
        event.preventDefault();
        navigate(primary[Number(event.key) - 1].id);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [refresh]);
  useEffect(() => {
    const changed = () => {
      const next = initialRoute();
      if (next !== routeRef.current) {
        routeRef.current = next;
        setRoute(next);
        setSnapshot((old) => ({ ...old, section: next, data: {} }));
      }
    };
    window.addEventListener('hashchange', changed);
    return () => window.removeEventListener('hashchange', changed);
  }, []);

  const props: PageProps = { data: snapshot.data, run, busy, navigate, refresh, notify, demo };
  const bank = snapshot.app.banks.find((b) => b.bank_id === snapshot.app.bank);
  const bankName =
    bank?.display_alias || bank?.name || bank?.bank_id || t('Votre espace', 'Your workspace');
  const title = sections.find((s) => s.id === route)?.label || 'Hindsight';
  const confirmation = snapshot.confirmations[0];
  const needsBank = !['sources', 'settings', 'server', 'consumption'].includes(route);
  const disconnected =
    needsBank && !snapshot.app.bank && !demo && !(route === 'admin' && snapshot.app.connected);

  function page() {
    if (!ready) return <Loading />;
    if (disconnected)
      return (
        <>
          <PageHeader
            title={title}
            description={t(
              'Connectez votre banque pour retrouver vos connaissances.',
              'Connect a memory bank to access your knowledge.',
            )}
          />
          <Empty
            icon={Database}
            title={
              snapshot.app.connected
                ? t('Votre première banque', 'Your first memory bank')
                : t('Votre mémoire vous attend', 'Your memory is waiting')
            }
            description={
              snapshot.app.connected
                ? t(
                    'Créez une banque pour commencer à mémoriser vos sources.',
                    'Create a memory bank to start remembering your sources.',
                  )
                : t(
                    'Le dossier mémoire reste consultable hors connexion. Les connaissances et les traitements nécessitent le serveur Hindsight.',
                    'You can browse a memory folder offline. Knowledge and processing require a Hindsight server.',
                  )
            }
            action={
              <div className="action-row">
                <Button
                  kind="primary"
                  disabled={busy}
                  onClick={() => {
                    if (snapshot.app.connected) navigate('admin');
                    else void run('connect');
                  }}
                >
                  {snapshot.app.connected
                    ? t('Créer une banque', 'Create a memory bank')
                    : t('Se reconnecter', 'Reconnect')}
                </Button>
                <Button onClick={() => navigate('settings')}>
                  {t('Réglages du serveur', 'Server settings')}
                </Button>
                {host === 'Navigateur' && (
                  <Button onClick={() => changeDemo(true)}>
                    {t('Explorer un exemple', 'Explore an example')}
                  </Button>
                )}
              </div>
            }
          />
          <ErrorNotice message={snapshot.app.connectionError} />
        </>
      );
    switch (route) {
      case 'sources':
        return (
          <Sources
            {...props}
            serverConnected={snapshot.app.connected}
            onExploreExample={() => changeDemo(true)}
          />
        );
      case 'models':
        return <Models {...props} />;
      case 'search':
        return <SearchPage {...props} />;
      case 'documents':
        return <Documents {...props} />;
      case 'coverage':
        return <Coverage {...props} />;
      case 'consumption':
        return <Consumption {...props} />;
      case 'dashboard':
        return <Dashboard {...props} />;
      case 'operations':
        return <Operations {...props} />;
      case 'timeline':
        return <Timeline {...props} />;
      case 'graph':
        return <Graph {...props} />;
      case 'audit':
        return <Audit {...props} />;
      case 'memory':
        return <MemoryDesign {...props} />;
      case 'admin':
        return <Admin {...props} />;
      case 'server':
        return <ServerSettings {...props} />;
      case 'hermes':
        return <Hermes {...props} />;
      case 'settings':
        return (
          <Settings
            snapshot={snapshot}
            run={run}
            demo={demo}
            setDemo={changeDemo}
            theme={theme}
            setTheme={setTheme}
            busy={busy}
          />
        );
    }
  }

  return (
    <div className={`app-shell host-${host.toLowerCase()}`}>
      <aside className="sidebar">
        <div className="window-drag" data-tauri-drag-region />
        <div className="sidebar-scroll">
          <div className="brand">
            <Logo />
            <div>
              <strong>Hindsight</strong>
              <span>{t('ESPACE DE MÉMOIRE', 'DESKTOP WORKSPACE')}</span>
            </div>
          </div>
          <div className="workspace-wrapper">
            <button
              className="workspace-switch"
              aria-expanded={bankMenu}
              onClick={() => setBankMenu(!bankMenu)}
            >
              <span className="workspace-avatar">
                {bankName
                  .split(/[\s-]+/)
                  .filter(Boolean)
                  .slice(0, 2)
                  .map((s: string) => s[0])
                  .join('')
                  .toUpperCase()}
              </span>
              <span>
                <strong>{bankName}</strong>
                <small>
                  {bank
                    ? t(
                        `${number(bank.fact_count)} faits en mémoire`,
                        `${number(bank.fact_count)} facts in memory`,
                      )
                    : t('Espace personnel', 'Personal workspace')}
                </small>
              </span>
              <ChevronDown size={14} />
            </button>
            {bankMenu && (
              <>
                <button
                  className="menu-dismiss"
                  aria-label={t('Fermer le choix de banque', 'Close memory bank menu')}
                  onClick={() => setBankMenu(false)}
                />
                <div className="bank-menu">
                  <span className="eyebrow">{t('Vos banques', 'Your memory banks')}</span>
                  {snapshot.app.banks.map((b) => (
                    <button
                      key={b.bank_id}
                      onClick={() => {
                        setBankMenu(false);
                        void run('bank.select', { id: b.bank_id });
                      }}
                    >
                      <Database size={15} />
                      <span>{b.display_alias || b.name || b.bank_id}</span>
                      {snapshot.app.bank === b.bank_id && <Check size={14} />}
                    </button>
                  ))}
                  {!snapshot.app.banks.length && (
                    <p className="muted">
                      {t('Aucune banque connectée', 'No connected memory banks')}
                    </p>
                  )}
                  <button onClick={() => navigate('admin')}>
                    <Plus size={15} />
                    {t('Gérer les banques', 'Manage memory banks')}
                  </button>
                </div>
              </>
            )}
          </div>
          <div className="sidebar-label">{t('VOTRE MÉMOIRE', 'YOUR MEMORY')}</div>
          <nav aria-label={t('Navigation principale', 'Main navigation')}>
            {primary.map(({ id, label, icon: Icon }, i) => (
              <button
                key={id}
                className={`nav-item ${route === id ? 'active' : ''}`}
                onClick={() => navigate(id)}
                aria-current={route === id ? 'page' : undefined}
              >
                <Icon size={18} strokeWidth={1.6} />
                <span>{label}</span>
                {id === 'models' && demo ? (
                  <span className="nav-count">4</span>
                ) : (
                  <kbd>{i + 1}</kbd>
                )}
              </button>
            ))}
          </nav>
          <div className="advanced-nav">
            <button
              className="advanced-toggle"
              aria-expanded={advanced}
              onClick={() => setAdvanced(!advanced)}
            >
              <Settings2 size={16} />
              <span>{t('Avancé', 'Advanced')}</span>
              <ChevronRight size={14} className={advanced ? 'rotated' : ''} />
            </button>
            {advanced && (
              <nav aria-label={t('Outils avancés', 'Advanced tools')}>
                {advancedItems.map(({ id, label, icon: Icon }) => (
                  <button
                    key={id}
                    className={`nav-item secondary-nav ${route === id ? 'active' : ''}`}
                    onClick={() => navigate(id)}
                  >
                    <Icon size={16} strokeWidth={1.6} />
                    <span>{label}</span>
                  </button>
                ))}
              </nav>
            )}
          </div>
          <div className="sidebar-bottom">
            <button
              className={`nav-item ${route === 'settings' ? 'active' : ''}`}
              onClick={() => navigate('settings')}
            >
              <Settings2 size={17} />
              <span>{t('Réglages', 'Settings')}</span>
              <kbd>⌘ ,</kbd>
            </button>
            <div className="connection-footer">
              <span className={`status-dot ${snapshot.app.connected ? 'green' : ''}`} />
              <div>
                <strong>
                  {demo
                    ? t('Espace de démonstration', 'Example workspace')
                    : snapshot.app.connected
                      ? t('Hindsight est connecté', 'Hindsight is connected')
                      : t('Dossier disponible hors ligne', 'Browse a folder offline')}
                </strong>
                <span>
                  {demo
                    ? t('Toutes les données sont fictives', 'All data is fictional')
                    : snapshot.app.connected
                      ? t('Votre mémoire est à portée de main', 'Your memory is within reach')
                      : t('Le serveur est déconnecté', 'The server is disconnected')}
                </span>
              </div>
              <IconButton
                icon={RefreshCw}
                label={t('Vérifier la connexion au serveur', 'Check the server connection')}
                disabled={busy}
                onClick={() => void run('connect')}
              />
            </div>
          </div>
        </div>
      </aside>
      <main className="main-shell">
        <header className="topbar" data-tauri-drag-region>
          <div className="breadcrumb">
            <span>{bankName}</span>
            <ChevronRight size={13} />
            <strong>{title}</strong>
          </div>
          <div className="topbar-actions">
            {demo ? (
              <button className="demo-badge" onClick={() => changeDemo(false)}>
                <span />
                {t('Exemple · données fictives', 'Example · fictional data')}
                <X size={12} />
              </button>
            ) : host === 'Navigateur' ? (
              <button className="preview-badge" onClick={() => changeDemo(true)}>
                {t('Explorer un exemple', 'Explore an example')}
                <ArrowRight size={12} />
              </button>
            ) : (
              <span className="host-badge">{host}</span>
            )}
            <button
              className="command-trigger"
              onClick={() => {
                setCommandQuery('');
                setCommand(true);
              }}
            >
              <Search size={15} />
              <span>{t('Aller à…', 'Go to…')}</span>
              <kbd>⌘ K</kbd>
            </button>
            <IconButton
              icon={theme === 'dark' ? Sun : Moon}
              label={
                theme === 'dark'
                  ? t('Activer le thème clair', 'Use light theme')
                  : t('Activer le thème sombre', 'Use dark theme')
              }
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
            />
            <IconButton
              icon={RefreshCw}
              label={t('Actualiser la vue', 'Refresh view')}
              disabled={busy}
              onClick={() => void refresh()}
            />
          </div>
        </header>
        {busy && (
          <div
            className="top-loading"
            role="status"
            aria-label={t('Action en cours', 'Action in progress')}
          />
        )}
        {snapshot.app.paused?.length ? (
          <div className="pause-banner">
            <span className="status-dot warning" />
            {t('Traitements en pause :', 'Processing paused:')} {snapshot.app.paused.join(', ')}
            <button onClick={() => navigate('consumption')}>
              {t('Gérer la pause', 'Manage pause')}
              <ArrowRight size={13} />
            </button>
          </div>
        ) : null}
        <div className="page-scroll">
          <div className="page-content">
            <PageBoundary key={`${route}-${snapshot.app.bank}-${demo}`}>
              <Suspense fallback={<Loading />}>{page()}</Suspense>
            </PageBoundary>
            <footer className="page-brand-footer">
              <Logo small />
              <span>Hindsight Desktop</span>
              <span className="spacer" />
              <span>Hindsight Desktop · 0.1.2</span>
            </footer>
          </div>
        </div>
      </main>
      {toast && (
        <div className="toast" role="status">
          <span>{nativeSystemMessage(toast)}</span>
          <IconButton
            icon={X}
            label={t('Fermer le message', 'Dismiss message')}
            onClick={() => setToast(null)}
          />
        </div>
      )}
      {command && (
        <Modal
          title={t('Un raccourci vers votre mémoire', 'A shortcut to your memory')}
          onClose={() => setCommand(false)}
        >
          <div className="command-search input-with-icon">
            <Search size={20} />
            <input
              autoFocus
              value={commandQuery}
              onChange={(e) => setCommandQuery(e.target.value)}
              placeholder={t('Où souhaitez-vous aller ?', 'Where would you like to go?')}
              aria-label={t('Rechercher une vue', 'Find a view')}
            />
          </div>
          <div className="command-list">
            {sections
              .filter((s) => s.label.toLowerCase().includes(commandQuery.toLowerCase()))
              .map(({ id, icon: Icon, label }) => (
                <button key={id} onClick={() => navigate(id)}>
                  <Icon size={18} />
                  <span>{label}</span>
                  <ArrowRight size={15} />
                </button>
              ))}
          </div>
        </Modal>
      )}
      {confirmation && (
        <Modal
          title={confirmation.title}
          subtitle={
            demo
              ? t(
                  'Mode exemple · aucune donnée réelle ne sera modifiée',
                  'Example mode · no real data will be changed',
                )
              : t(
                  'Vérifiez les détails avant de continuer.',
                  'Review the details before continuing.',
                )
          }
          onClose={() => {
            if (!busy) void run('cancel');
          }}
        >
          <div className="confirmation-message">{confirmation.message}</div>
          {confirmation.requiredText && (
            <label className="form-stack">
              {t('Pour confirmer, retapez', 'To confirm, type')} « {confirmation.requiredText} »
              <input
                value={typed}
                onChange={(e) => setTyped(e.target.value)}
                autoComplete="off"
                spellCheck={false}
                aria-label={t('Texte de confirmation', 'Confirmation text')}
              />
            </label>
          )}
          <div className="modal-actions">
            <Button disabled={busy} onClick={() => void run('cancel')}>
              {t('Annuler', 'Cancel')}
            </Button>
            <Button
              kind={confirmation.destructive ? 'danger' : 'primary'}
              disabled={
                busy || (!!confirmation.requiredText && typed !== confirmation.requiredText)
              }
              onClick={() =>
                void run('confirm', { id: confirmation.id, typed }).then(() => refresh())
              }
            >
              {busy ? <LoaderCircle size={15} className="spin" /> : null}
              {confirmation.confirmTitle}
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}

function Settings({
  snapshot,
  run,
  demo,
  setDemo,
  theme,
  setTheme,
  busy,
}: {
  snapshot: Snapshot;
  run: PageProps['run'];
  demo: boolean;
  setDemo: (value: boolean) => void;
  theme: string;
  setTheme: (value: string) => void;
  busy: boolean;
}) {
  const { t, language, setLanguage } = useI18n();
  const [url, setURL] = useState(snapshot.app.serverURL);
  useEffect(() => setURL(snapshot.app.serverURL), [snapshot.app.serverURL]);
  return (
    <>
      <PageHeader
        eyebrow={t('À votre façon', 'Make it yours')}
        title={t('Réglages', 'Settings')}
        description={t(
          'Connexion, apparence et préférences de l’application.',
          'Connection, appearance and application preferences.',
        )}
      />
      <section className="card settings-card">
        <div className="settings-section-heading">
          <span className="category-icon sage">
            <Server size={21} />
          </span>
          <div>
            <h2>{t('Connexion à Hindsight', 'Connect to Hindsight')}</h2>
            <p>
              {t(
                'Le serveur qui conserve les faits et génère les connaissances.',
                'The server that stores facts and builds knowledge.',
              )}
            </p>
          </div>
        </div>
        <form
          className="inline-form"
          onSubmit={(e) => {
            e.preventDefault();
            void run('server.url', { url });
          }}
        >
          <label>
            {t('Adresse du serveur', 'Server address')}
            <input
              type="url"
              required
              value={url}
              onChange={(e) => setURL(e.target.value)}
              placeholder="http://127.0.0.1:8888"
            />
          </label>
          <Button kind="primary" disabled={busy || demo}>
            {t('Appliquer et reconnecter', 'Apply and reconnect')}
          </Button>
        </form>
        <ErrorNotice message={snapshot.app.connectionError} />
        {snapshot.app.serverURLNotice && (
          <div className="notice" role="status">
            {nativeSystemMessage(snapshot.app.serverURLNotice)}
          </div>
        )}
        <p className="form-hint">
          {t(
            'L’application se connecte à un serveur Hindsight installé séparément. Vous pouvez utiliser un serveur sur ce Mac ou un serveur distant. Aucun serveur n’est installé au premier lancement.',
            'The app connects to a separately installed Hindsight server, on this Mac or remotely. No server is installed when you first open the app.',
          )}
        </p>
        <p className="form-hint">
          {t(
            'Les connexions distantes utilisent HTTPS. Les adresses avec des identifiants intégrés sont refusées.',
            'Remote connections use HTTPS. Addresses with embedded credentials are not allowed.',
          )}
        </p>
      </section>
      <section className="card settings-card">
        <CardHeader
          title={t('Langue', 'Language')}
          subtitle={t('Enregistrée sur cet appareil.', 'Saved on this device.')}
        />
        <label>
          {t('Langue de l’interface', 'Interface language')}
          <select
            aria-label={t('Langue de l’interface', 'Interface language')}
            value={language}
            onChange={(event) => setLanguage(event.target.value as Language)}
          >
            <option value="fr">Français</option>
            <option value="en">English</option>
          </select>
        </label>
        <p className="form-hint">
          {t(
            'Les documents et le contenu fourni par le serveur conservent leur langue d’origine.',
            'Documents and content provided by the server keep their original language.',
          )}
        </p>
      </section>
      <Updates data={snapshot.updates || {}} run={run} demo={demo} busy={busy} />
      <section className="card settings-card">
        <div className="settings-section-heading">
          <span className="category-icon peach">
            <Sun size={21} />
          </span>
          <div>
            <h2>{t('Apparence', 'Appearance')}</h2>
            <p>
              {t(
                'Thème clair ou sombre, enregistré sur cet appareil.',
                'Light or dark theme, saved on this device.',
              )}
            </p>
          </div>
        </div>
        <div className="theme-choices">
          {[
            ['light', t('Clair', 'Light'), Sun],
            ['dark', t('Sombre', 'Dark'), Moon],
          ].map(([id, label, Icon]: any) => (
            <button
              key={id}
              className={theme === id ? 'selected' : ''}
              onClick={() => setTheme(id)}
            >
              <div className={`theme-preview ${id}`}>
                <i />
                <i />
                <i />
              </div>
              <span>
                <Icon size={16} />
                {label}
                {theme === id && <Check size={15} />}
              </span>
            </button>
          ))}
        </div>
      </section>
      <section className="card settings-card">
        <div className="settings-section-heading">
          <span className="category-icon lavender">
            <Sparkles size={21} />
          </span>
          <div>
            <h2>{t('Explorer à votre rythme', 'Explore at your own pace')}</h2>
            <p>
              {t(
                'Un exemple fictif pour découvrir les vues sans toucher à vos données.',
                'Discover the app with a fictional example, without touching your data.',
              )}
            </p>
          </div>
        </div>
        <Button icon={demo ? ArrowLeft : Eye} onClick={() => setDemo(!demo)}>
          {demo
            ? t('Revenir à mes données', 'Return to my data')
            : t('Explorer l’exemple', 'Explore the example')}
        </Button>
      </section>
      <section className="card settings-card">
        <h2>{t('Quelques raccourcis', 'Keyboard shortcuts')}</h2>
        <div className="shortcut-list">
          <div>
            <span>{t('Ouvrir la navigation rapide', 'Open quick navigation')}</span>
            <kbd>⌘ K</kbd>
          </div>
          <div>
            <span>{t('Actualiser la vue', 'Refresh the view')}</span>
            <kbd>⌘ R</kbd>
          </div>
          <div>
            <span>{t('Ouvrir les réglages', 'Open settings')}</span>
            <kbd>⌘ ,</kbd>
          </div>
          <div>
            <span>{t('Parcourir les vues principales', 'Browse the main views')}</span>
            <kbd>⌘ 1…4</kbd>
          </div>
        </div>
      </section>
      <p className="page-footnote">
        Hindsight Desktop 0.1.3 · {host} · HindsightCore ·{' '}
        {t('macOS 15 et plus', 'macOS 15 or later')}
      </p>
      <p className="page-footnote">
        {t(
          'Client communautaire indépendant, sans affiliation à Vectorize.',
          'Independent community client, not affiliated with Vectorize.',
        )}{' '}
        {[
          ['LICENSE', t('Licence', 'License')],
          ['PRIVACY.md', t('Confidentialité', 'Privacy')],
          ['NOTICE', t('Attributions', 'Attributions')],
        ].map(([file, label]) => (
          <button
            key={file}
            className="inline-link"
            onClick={() =>
              void run('external.open', {
                url: `https://github.com/paabL/hindsight-desktop/blob/main/${file}`,
              })
            }
          >
            {label}
          </button>
        ))}
      </p>
    </>
  );
}
