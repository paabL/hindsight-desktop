import { useRef, useState } from 'react';
import { Download, RefreshCw, FolderOpen, RotateCcw } from 'lucide-react';
import type { Request, Row } from '../types';
import { Badge, Button, CardHeader, ErrorNotice, date } from '../ui';
import { pickDirectory, host } from '../transport';
import { useI18n } from '../i18n';

type ReleaseOffer = { version: string };
type ReleasePhase = 'idle' | 'checking' | 'available' | 'current' | 'installing' | 'restarting';
const releaseErrorCodes = new Set([
  'UPDATE_BUSY',
  'UPDATE_CHECK_FAILED',
  'UPDATE_NOT_AVAILABLE',
  'UPDATE_VERSION_CHANGED',
  'UPDATE_INSTALL_FAILED',
  'UPDATE_RESTART_FAILED',
  'UPDATE_MOVE_TO_APPLICATIONS',
  'UPDATE_UNTRUSTED_SOURCE',
]);
function releaseErrorCode(error: unknown, fallback: string) {
  return typeof error === 'string' && releaseErrorCodes.has(error) ? error : fallback;
}

export default function Updates({
  data,
  run,
  demo,
  busy,
}: {
  data: Row;
  run: Request;
  demo: boolean;
  busy: boolean;
}) {
  const { t } = useI18n();
  demo = demo || host !== 'Tauri';
  const [path, setPath] = useState('');
  const working = !!data.working;
  const [phase, setPhase] = useState<ReleasePhase>('idle');
  const [offer, setOffer] = useState<ReleaseOffer | null>(null);
  const [releaseError, setReleaseError] = useState<string | null>(null);
  // A ref closes the small gap before React commits the disabled button state.
  const releaseLock = useRef(false);
  const updating = phase === 'checking' || phase === 'installing' || phase === 'restarting';
  const blocked = demo || busy || working || updating;
  async function checkRelease() {
    if (blocked || releaseLock.current) return;
    releaseLock.current = true;
    setReleaseError(null);
    setOffer(null);
    setPhase('checking');
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      const available = await invoke<ReleaseOffer | null>('release_update_check');
      setOffer(available);
      setPhase(available ? 'available' : 'current');
    } catch (error) {
      setReleaseError(releaseErrorCode(error, 'UPDATE_CHECK_FAILED'));
      setPhase('idle');
    } finally {
      releaseLock.current = false;
    }
  }
  async function installRelease() {
    if (blocked || releaseLock.current || !offer) return;
    releaseLock.current = true;
    setReleaseError(null);
    setPhase('installing');
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      await invoke('release_update_install', { version: offer.version });
      setPhase('restarting');
    } catch (error) {
      setReleaseError(releaseErrorCode(error, 'UPDATE_INSTALL_FAILED'));
      setOffer(null);
      setPhase('idle');
      releaseLock.current = false;
    }
  }
  function releaseErrorMessage(code: string | null) {
    switch (code) {
      case null:
        return null;
      case 'UPDATE_BUSY':
        return t(
          'Attendez la fin de l’action en cours, puis réessayez.',
          'Wait for the current action to finish, then try again.',
        );
      case 'UPDATE_MOVE_TO_APPLICATIONS':
        return t(
          'Déplacez Hindsight Desktop dans Applications, rouvrez l’app et réessayez.',
          'Move Hindsight Desktop to Applications, reopen the app and try again.',
        );
      case 'UPDATE_NOT_AVAILABLE':
      case 'UPDATE_VERSION_CHANGED':
        return t(
          'Cette mise à jour n’est plus disponible. Relancez la recherche.',
          'This update is no longer available. Check for updates again.',
        );
      case 'UPDATE_UNTRUSTED_SOURCE':
        return t(
          'La mise à jour n’a pas pu être vérifiée et n’a pas été installée. Réessayez plus tard.',
          'The update could not be verified and was not installed. Please try again later.',
        );
      case 'UPDATE_INSTALL_FAILED':
        return t(
          'L’installation n’a pas abouti. Réessayez ou téléchargez l’app depuis « Voir les versions ».',
          'The update could not be installed. Try again or download the app from View releases.',
        );
      case 'UPDATE_RESTART_FAILED':
        return t(
          'La mise à jour est installée. Quittez puis rouvrez Hindsight Desktop pour l’utiliser.',
          'The update is installed. Quit and reopen Hindsight Desktop to use it.',
        );
      default:
        return t(
          'Impossible de rechercher les mises à jour. Vérifiez votre connexion ou utilisez « Voir les versions ».',
          'Could not check for updates. Check your connection or use View releases.',
        );
    }
  }
  const releaseStatus =
    phase === 'checking'
      ? t('Recherche des mises à jour…', 'Checking for updates…')
      : phase === 'available' && offer
        ? t(`La version ${offer.version} est disponible.`, `Version ${offer.version} is available.`)
        : phase === 'current'
          ? t('Vous utilisez la dernière version.', 'You’re up to date.')
          : phase === 'installing'
            ? t(
                'Téléchargement et vérification… L’app va redémarrer lorsque la mise à jour sera prête.',
                'Downloading and verifying… The app will restart when the update is ready.',
              )
            : phase === 'restarting'
              ? t('Redémarrage de l’application…', 'Restarting the app…')
              : null;
  async function choose() {
    try {
      const value = await pickDirectory(
        t(
          'Choisir le dépôt source de Hindsight Desktop',
          'Choose the Hindsight Desktop source repository',
        ),
      );
      if (value) setPath(value);
    } catch (error) {
      setError(error instanceof Error ? error.message : String(error));
    }
  }
  const [error, setError] = useState<string | null>(null);
  return (
    <section className="card settings-card">
      <CardHeader
        title={t('Mises à jour de l’application', 'Application updates')}
        subtitle={
          data.version
            ? t(`Version installée : ${data.version}`, `Installed version: ${data.version}`)
            : undefined
        }
        action={
          <Badge>{working || updating ? t('En cours', 'In progress') : t('Bêta', 'Beta')}</Badge>
        }
      />
      <p>
        {t(
          'Recherchez une nouvelle version, puis mettez à jour et redémarrez. Vos réglages et dossiers mémoire sont conservés.',
          'Check for a new version, then update and restart. Your settings and memory folders are kept.',
        )}
      </p>
      <ErrorNotice message={releaseErrorMessage(releaseError)} />
      {releaseStatus && <p role="status">{releaseStatus}</p>}
      <div className="action-row">
        <Button icon={RefreshCw} disabled={blocked} onClick={() => void checkRelease()}>
          {t('Rechercher les mises à jour', 'Check for updates')}
        </Button>
        {offer && (
          <Button
            kind="primary"
            icon={Download}
            disabled={blocked}
            onClick={() => void installRelease()}
          >
            {t('Mettre à jour et redémarrer', 'Update and restart')}
          </Button>
        )}
        <Button
          icon={Download}
          disabled={demo || updating}
          onClick={() =>
            void run('external.open', {
              url: 'https://github.com/paabL/hindsight-desktop/releases',
            })
          }
        >
          {t('Voir les versions', 'View releases')}
        </Button>
      </div>
      <details
        open={working || data.state === 'failed' || data.state === 'ready' ? true : undefined}
      >
        <summary>
          {t('Construire depuis les sources (avancé)', 'Build from source (advanced)')}
        </summary>
        <p className="form-hint">
          {t(
            'Cette option s’adresse aux personnes qui ont installé les outils de développement et une copie du code source.',
            'This option requires development tools and a local copy of the source code.',
          )}
        </p>
        <div className="form-stack">
          <ErrorNotice message={error} />
          <label>
            {t('Dossier du projet', 'Project folder')}
            <div className="inline-form">
              <input
                style={{ flex: 1 }}
                aria-label={t('Dossier source des mises à jour', 'Update source folder')}
                value={path || data.repository || ''}
                onChange={(e) => setPath(e.target.value)}
                disabled={working || demo || busy || updating}
                placeholder={t(
                  'Choisir le dépôt Hindsight Desktop',
                  'Choose the Hindsight Desktop repository',
                )}
              />
              <Button
                icon={FolderOpen}
                disabled={working || demo || busy || updating}
                onClick={() => void choose()}
              >
                {t('Choisir', 'Choose')}
              </Button>
            </div>
          </label>
          {data.state === 'failed' ? (
            <ErrorNotice message={data.message} />
          ) : (
            <p role="status">
              {data.message ||
                t(
                  'Recherchez les commits disponibles avant de préparer l’installation.',
                  'Check for available changes before preparing the installation.',
                )}
            </p>
          )}
          {data.dirty && (
            <p className="form-hint">
              {t(
                'La copie locale contient des modifications. L’application de commits distants est bloquée ; vous pouvez reconstruire cette copie après confirmation.',
                'This local copy has changes. Remote changes cannot be applied; you can rebuild this copy after confirmation.',
              )}
            </p>
          )}
          {!!data.commits?.length && (
            <div className="update-commits">
              {data.commits.map((commit: Row) => (
                <div key={commit.sha}>
                  <code>{commit.sha.slice(0, 7)}</code>
                  <span>{commit.subject}</span>
                  <small>
                    {commit.author} · {commit.date}
                  </small>
                </div>
              ))}
            </div>
          )}
          <div className="action-row">
            <Button
              icon={RefreshCw}
              disabled={working || demo || busy || updating}
              onClick={() => void run('updates.check', { path: path || data.repository })}
            >
              {t('Rechercher les changements du code', 'Check source changes')}
            </Button>
            {data.state === 'available' && (
              <Button
                kind="primary"
                icon={Download}
                disabled={
                  working ||
                  demo ||
                  busy ||
                  updating ||
                  data.dirty ||
                  (!!path && path !== data.repository)
                }
                onClick={() => void run('updates.install')}
              >
                {t('Installer la mise à jour', 'Install update')}
              </Button>
            )}
            <Button
              icon={RotateCcw}
              disabled={working || demo || busy || updating || !(path || data.repository)}
              onClick={() => void run('updates.rebuild', { path: path || data.repository })}
            >
              {t('Recompiler cette copie', 'Rebuild this copy')}
            </Button>
            {data.state === 'ready' && (
              <Button
                kind="primary"
                disabled={working || demo || busy || updating}
                onClick={() => void run('updates.relaunch')}
              >
                {t('Relancer l’application', 'Relaunch application')}
              </Button>
            )}
          </div>
          {working && (
            <div className="notice" role="status">
              {data.message}{' '}
              {t(
                'Vous pouvez laisser cette fenêtre ouverte pendant la compilation.',
                'You can leave this window open while the app builds.',
              )}
            </div>
          )}
          {!!data.log && (
            <details open={data.state === 'failed'}>
              <summary>{t('Journal de mise à jour', 'Update log')}</summary>
              <pre className="json-view">{data.log}</pre>
            </details>
          )}
          <p className="form-hint">
            {t(
              'La version est reconstruite sur ce Mac avant de remplacer l’app ouverte. Node.js, Xcode et Rust sont nécessaires. Le code téléchargé sera exécuté avec vos droits après confirmation.',
              'The version is built on this Mac before replacing the open app. Node.js, Xcode and Rust are required. Downloaded code runs with your permissions after confirmation.',
            )}
          </p>
          {data.checkedAt && (
            <p className="page-footnote">
              {t('Dernière vérification :', 'Last checked:')} {date(data.checkedAt, true)}
            </p>
          )}
        </div>
      </details>
    </section>
  );
}
