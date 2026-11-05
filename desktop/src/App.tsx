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
  Cpu,
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
import { version as appVersion } from '../package.json';
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
import { mergeSourceSnapshot } from './source-snapshot';
import Updates from './pages/Updates';
import { Coverage, Documents, Models, SearchPage } from './pages/Library';
import Consumption from './pages/Consumption';
const Audit = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Audit })));
const Dashboard = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Dashboard })));
const Graph = lazy(() => import('./pages/Graph'));
const Timeline = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Timeline })));
const Facts = lazy(() => import('./pages/Explore').then((m) => ({ default: m.Facts })));
import Operations from './pages/Operations';
const Admin = lazy(() => import('./pages/Manage').then((m) => ({ default: m.Admin })));
const MemoryDesign = lazy(() =>
  import('./pages/Manage').then((m) => ({ default: m.MemoryDesign })),
);
const ServerSettings = lazy(() =>
  import('./pages/Manage').then((m) => ({ default: m.ServerSettings })),
);
const ModelChoices = lazy(() => import('./pages/ModelChoices'));

const basePrimary = [
  { id: 'dashboard', label: 'Vue d’ensemble', english: 'Overview', icon: LayoutDashboard },
  { id: 'facts', label: 'Mémoire', english: 'Memory', icon: Layers3 },
  { id: 'models', label: 'Connaissances', english: 'Knowledge', icon: BookOpen },
  { id: 'search', label: 'Recherche', icon: Search },
  { id: 'model-settings', label: 'Modèles', english: 'Models', icon: Cpu },
  { id: 'sources', label: 'Sources', english: 'Sources', icon: Folder },
  { id: 'operations', label: 'Activité', english: 'Activity', icon: Activity },
] as const;
const baseSections = [
  { id: 'dashboard', label: 'Vue d’ensemble', icon: LayoutDashboard },
  { id: 'facts', label: 'Faits', icon: Layers3 },
  { id: 'models', label: 'Connaissances', icon: BookOpen },
  { id: 'search', label: 'Recherche', icon: Search },
  { id: 'sources', label: 'Catalogue', icon: Folder },
  { id: 'documents', label: 'Documents', icon: FileText },
  { id: 'operations', label: 'Traitements', icon: ListTodo },
  { id: 'consumption', label: 'Consommation', icon: BarChart3 },
  { id: 'audit', label: 'Journaux', icon: Activity },
  { id: 'timeline', label: 'Chronologie', icon: GitBranch },
  { id: 'graph', label: 'Graphe', icon: Network },
  { id: 'coverage', label: 'Dossiers suivis', icon: Folder },
  { id: 'server', label: 'Serveur & modèles', icon: Server },
  { id: 'model-settings', label: 'Modèles', icon: Cpu },
  { id: 'admin', label: 'Banque', icon: Database },
  { id: 'memory', label: 'Comportement de la mémoire', icon: Layers3 },
  { id: 'settings', label: 'Application', icon: Settings2 },
] as const;
const englishLabels: Record<Section, string> = {
  sources: 'Catalog',
  facts: 'Facts',
  models: 'Knowledge',
  'model-settings': 'Models',
  search: 'Search',
  consumption: 'Usage',
  documents: 'Documents',
  dashboard: 'Overview',
  memory: 'Memory behavior',
  operations: 'Processing',
  audit: 'Logs',
  timeline: 'Timeline',
  graph: 'Graph',
  server: 'Server & models',
  admin: 'Memory bank',
  settings: 'Application',
  coverage: 'Tracked folders',
};
type NavigationGroup =
  | 'overview'
  | 'memory'
  | 'knowledge'
  | 'search'
  | 'sources'
  | 'activity'
  | 'settings'
  | 'model-settings';
const viewGroups: Partial<
  Record<NavigationGroup, { label: string; english: string; views: readonly Section[] }>
> = {
  memory: {
    label: 'Vues de la mémoire',
    english: 'Memory views',
    views: ['facts', 'documents', 'timeline', 'graph'],
  },
  sources: {
    label: 'Vues des sources',
    english: 'Source views',
    views: ['sources', 'coverage'],
  },
  activity: {
    label: 'Vues de l’activité',
    english: 'Activity views',
    views: ['operations', 'consumption', 'audit'],
  },
  settings: {
    label: 'Vues des réglages',
    english: 'Settings views',
    views: ['settings', 'admin', 'memory', 'server'],
  },
};
function groupFor(section: Section): NavigationGroup {
  if (['facts', 'documents', 'timeline', 'graph'].includes(section)) return 'memory';
  if (['sources', 'coverage'].includes(section)) return 'sources';
  if (['operations', 'consumption', 'audit'].includes(section)) return 'activity';
  if (['settings', 'admin', 'memory', 'server'].includes(section)) return 'settings';
  if (section === 'models') return 'knowledge';
  if (section === 'model-settings') return 'model-settings';
  if (section === 'search') return 'search';
  return 'overview';
}
const initial: Snapshot = {
  app: { connected: false, serverURL: 'http://127.0.0.1:8888', banks: [], bank: null },
  section: 'dashboard',
  data: {},
  confirmations: [],
  messages: [],
};
function initialRoute(): Section {
  const id = location.hash.slice(1);
  return baseSections.some((s) => s.id === id) ? (id as Section) : 'dashboard';
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
  const localize = <T extends { id: Section; label: string; english?: string }>(item: T) => ({
    ...item,
    label: t(item.label, item.english || englishLabels[item.id]),
  });
  const primary = basePrimary.map(localize);
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
  const [lastViews, setLastViews] = useState<Partial<Record<NavigationGroup, Section>>>(() => {
    const section = initialRoute();
    return { [groupFor(section)]: section };
  });
  const [command, setCommand] = useState(false);
  const [commandQuery, setCommandQuery] = useState('');
  const [bankMenu, setBankMenu] = useState(false);
  const [typed, setTyped] = useState('');
  const [toast, setToast] = useState<string | null>(null);
  const [theme, setTheme] = useState(
    () => localStorage.getItem('hindsight-desktop-theme-v2') || 'dark',
  );
  const seenMessages = useRef(new Set<string>());
  const sourcesCache = useRef<{ key: string; data: Row } | null>(null);
  const requestSequence = useRef(0);
  const appliedSequence = useRef(0);
  const contextGeneration = useRef(0);
  const contextTransition = useRef<number | null>(null);
  const foregroundRequests = useRef(new Set<number>());
  const [contextRevision, setContextRevision] = useState(0);
  const sourceKey = (app: Snapshot['app']) =>
    `${app.serverURL}|${app.bank || ''}|${app.folder || ''}`;
  const notify = useCallback((message: string) => setToast(message), []);
  const busy = busyCount > 0;
  const run = useCallback(async (action: string, args: Row = {}) => {
    const quiet = action === 'snapshot' || args.polling === true;
    if (quiet && (foregroundRequests.current.size || contextTransition.current !== null))
      return null;
    const sequence = ++requestSequence.current;
    const changesContext = ['bank.select', 'server.url', 'folder.choose'].includes(action);
    if (changesContext) {
      contextGeneration.current++;
      contextTransition.current = sequence;
      sourcesCache.current = null;
      appliedSequence.current = sequence;
      setSnapshot((old) => ({ ...old, data: {}, confirmations: [] }));
    }
    const generation = contextGeneration.current;
    if (!quiet) {
      foregroundRequests.current.add(sequence);
      setBusyCount(foregroundRequests.current.size);
    }
    const sourceBase = sourcesCache.current;
    try {
      const result = demoRef.current
        ? await exampleRequest(action, args, routeRef.current)
        : await nativeRequest(action, {
            ...args,
            background: true,
            sourceRevision: sourceBase?.data.catalogRevision,
          });
      if (
        result?.app &&
        result?.section &&
        sequence >= appliedSequence.current &&
        generation === contextGeneration.current &&
        (contextTransition.current === null || contextTransition.current === sequence) &&
        (!quiet || foregroundRequests.current.size === 0)
      ) {
        appliedSequence.current = sequence;
        if (result.section === 'sources') {
          result.data = mergeSourceSnapshot(
            sourceBase?.key === sourceKey(result.app) ? sourceBase.data : undefined,
            result.data,
          );
          sourcesCache.current = { key: sourceKey(result.app), data: result.data };
        }
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
      if (generation === contextGeneration.current) setToast(message);
      return { error: nativeSystemMessage(message) };
    } finally {
      if (!quiet) {
        foregroundRequests.current.delete(sequence);
        setBusyCount(foregroundRequests.current.size);
      }
      if (changesContext && contextTransition.current === sequence) {
        contextTransition.current = null;
        setContextRevision((value) => value + 1);
      }
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
    setSnapshot((old) => ({
      ...old,
      section,
      data:
        section === 'sources' && sourcesCache.current?.key === sourceKey(old.app)
          ? sourcesCache.current.data
          : {},
    }));
    setLastViews((old) => ({ ...old, [groupFor(section)]: section }));
    setCommand(false);
    setBankMenu(false);
  }
  const changeDemo = useCallback((value: boolean) => {
    setReady(false);
    contextGeneration.current++;
    contextTransition.current = null;
    foregroundRequests.current.clear();
    setBusyCount(0);
    setDemo(value);
    demoRef.current = value;
    seenMessages.current.clear();
    sourcesCache.current = null;
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
  }, [
    route,
    snapshot.app.bank,
    snapshot.app.serverURL,
    snapshot.app.folder,
    contextRevision,
    demo,
    ready,
    refresh,
  ]);
  // Le suivi ne lance aucun traitement. La surveillance reste active si des plafonds sont autorisés.
  // Page Serveur : suit l’installation du modèle local et la connexion à un compte, sans recharger.
  const serverWork =
    !!snapshot.serviceBusy ||
    (route === 'server' &&
      !!(snapshot.data?.connectingAccount || snapshot.data?.hindsightModels?.local?.busy));
  const sourcesWork =
    route === 'sources' && !!(snapshot.data?.refreshing || snapshot.data?.collecting);
  useEffect(() => {
    if (
      !ready ||
      demo ||
      host === 'Navigateur' ||
      (!snapshot.app.connected && route !== 'settings' && !serverWork && !sourcesWork)
    )
      return;
    const seconds = sourcesWork
      ? 0.3
      : route === 'settings' || serverWork
        ? 2
        : route === 'operations'
          ? 20
          : route === 'consumption'
            ? 30
            : 0;
    if (!seconds) return;
    let polling = false;
    const interval = setInterval(async () => {
      if (!document.hidden && !polling) {
        polling = true;
        try {
          if (route === 'settings' || serverWork || sourcesWork) await run('snapshot');
          else await refresh({ polling: true });
        } finally {
          polling = false;
        }
      }
    }, seconds * 1000);
    return () => clearInterval(interval);
  }, [route, snapshot.app.connected, ready, demo, refresh, serverWork, sourcesWork]);
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
      if (location.hash.slice(1) !== next) history.replaceState(null, '', `#${next}`);
      if (next !== routeRef.current) {
        routeRef.current = next;
        setRoute(next);
        setSnapshot((old) => ({
          ...old,
          section: next,
          data:
            next === 'sources' && sourcesCache.current?.key === sourceKey(old.app)
              ? sourcesCache.current.data
              : {},
        }));
        setLastViews((old) => ({ ...old, [groupFor(next)]: next }));
      }
    };
    changed();
    window.addEventListener('hashchange', changed);
    return () => window.removeEventListener('hashchange', changed);
  }, []);

  const props: PageProps = { data: snapshot.data, run, busy, navigate, refresh, notify, demo };
  const bank = snapshot.app.banks.find((b) => b.bank_id === snapshot.app.bank);
  const bankName =
    bank?.display_alias || bank?.name || bank?.bank_id || t('Votre espace', 'Your workspace');
  const title = sections.find((s) => s.id === route)?.label || 'Hindsight';
  const currentGroup = groupFor(route);
  const groupTitle =
    currentGroup === 'settings'
      ? t('Réglages', 'Settings')
      : primary.find((item) => groupFor(item.id) === currentGroup)?.label || title;
  const views = viewGroups[currentGroup];
  function sectionName(section: { id: Section; label: string }) {
    const group = groupFor(section.id);
    if (!viewGroups[group]) return section.label;
    const name =
      group === 'settings'
        ? t('Réglages', 'Settings')
        : primary.find((item) => groupFor(item.id) === group)?.label;
    return `${name} · ${section.label}`;
  }
  const searchText = (value: string) =>
    value.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase();
  const confirmation = snapshot.confirmations[0];
  const needsBank = !['sources', 'settings', 'server', 'model-settings', 'consumption'].includes(
    route,
  );
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
                    else navigate('settings');
                  }}
                >
                  {snapshot.app.connected
                    ? t('Créer une banque', 'Create a memory bank')
                    : t('Connecter mon serveur', 'Connect my server')}
                </Button>
                <Button onClick={() => navigate('sources')}>
                  {t('Parcourir les sources', 'Browse sources')}
                </Button>
                <Button onClick={() => changeDemo(true)}>
                  {t('Explorer un exemple', 'Explore an example')}
                </Button>
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
            data={{ ...props.data, folder: props.data.folder ?? snapshot.app.folder }}
            serverConnected={snapshot.app.connected}
            onExploreExample={() => changeDemo(true)}
          />
        );
      case 'models':
        return <Models {...props} />;
      case 'facts':
        return <Facts {...props} />;
      case 'search':
        return <SearchPage {...props} />;
      case 'documents':
        return <Documents {...props} />;
      case 'coverage':
        return (
          <Coverage
            {...props}
            data={{ ...props.data, catalogFolder: props.data.catalogFolder ?? snapshot.app.folder }}
          />
        );
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
      case 'model-settings':
        return <ModelChoices {...props} />;
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
                    <Settings2 size={15} />
                    {t('Réglages de la banque', 'Memory bank settings')}
                  </button>
                  <button onClick={() => navigate('memory')}>
                    <Layers3 size={15} />
                    {t('Comportement de la mémoire', 'Memory behavior')}
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
                className={`nav-item ${currentGroup === groupFor(id) ? 'active' : ''}`}
                onClick={() => navigate(lastViews[groupFor(id)] || id)}
                aria-current={currentGroup === groupFor(id) ? 'page' : undefined}
              >
                <Icon size={18} strokeWidth={1.6} />
                <span>{label}</span>
                {id === 'models' && demo ? (
                  <span className="nav-count">4</span>
                ) : (
                  <kbd>⌘{i + 1}</kbd>
                )}
              </button>
            ))}
          </nav>
          <div className="sidebar-bottom">
            <button
              className={`nav-item ${currentGroup === 'settings' ? 'active' : ''}`}
              aria-current={currentGroup === 'settings' ? 'page' : undefined}
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
            {views && (
              <>
                <span>{groupTitle}</span>
                <ChevronRight size={13} />
              </>
            )}
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
            {views && (
              <div
                className="tabs workspace-tabs"
                role="tablist"
                aria-label={t(views.label, views.english)}
              >
                {views.views.map((id, index, items) => (
                  <button
                    key={id}
                    id={`view-tab-${id}`}
                    type="button"
                    role="tab"
                    aria-selected={route === id}
                    aria-controls={`view-panel-${id}`}
                    tabIndex={route === id ? 0 : -1}
                    className={route === id ? 'active' : ''}
                    onClick={() => navigate(id)}
                    onKeyDown={(event) => {
                      let next = index;
                      if (event.key === 'ArrowRight') next = (index + 1) % items.length;
                      else if (event.key === 'ArrowLeft')
                        next = (index - 1 + items.length) % items.length;
                      else if (event.key === 'Home') next = 0;
                      else if (event.key === 'End') next = items.length - 1;
                      else return;
                      event.preventDefault();
                      navigate(items[next]);
                      requestAnimationFrame(() =>
                        document.getElementById(`view-tab-${items[next]}`)?.focus(),
                      );
                    }}
                  >
                    {sections.find((section) => section.id === id)?.label}
                  </button>
                ))}
              </div>
            )}
            <div
              id={`view-panel-${route}`}
              role={views ? 'tabpanel' : undefined}
              aria-labelledby={views ? `view-tab-${route}` : undefined}
              tabIndex={views ? 0 : undefined}
            >
              <PageBoundary
                key={`${route}-${snapshot.app.serverURL}-${snapshot.app.bank}-${route === 'sources' ? snapshot.app.folder : ''}-${contextGeneration.current}-${demo}`}
              >
                <Suspense fallback={<Loading />}>{page()}</Suspense>
              </PageBoundary>
            </div>
            <footer className="page-brand-footer">
              <Logo small />
              <span>Hindsight Desktop</span>
              <span className="spacer" />
              <span>Hindsight Desktop · {appVersion}</span>
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
              .filter((s) => searchText(sectionName(s)).includes(searchText(commandQuery)))
              .map(({ id, icon: Icon, label }) => (
                <button key={id} onClick={() => navigate(id)}>
                  <Icon size={18} />
                  <span>{sectionName({ id, label })}</span>
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
            <kbd>⌘ 1…7</kbd>
          </div>
        </div>
      </section>
      <p className="page-footnote">
        Hindsight Desktop {appVersion} · {host} · HindsightCore ·{' '}
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
