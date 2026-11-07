import { useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import {
  ArrowUpRight,
  CircleHelp,
  Cloud,
  Database,
  GitBranch,
  Laptop,
  LockKeyhole,
  MessagesSquare,
  NotebookText,
  PenLine,
  ScanText,
  Search,
  Settings2,
  type LucideIcon,
} from 'lucide-react';
import { useI18n } from '../i18n';
import { Button, ErrorNotice, Tabs } from '../ui';
import type { PageProps, Row } from '../types';
import { localDecisionNotice, serviceModelField } from '../model-field-options';
import './model-workflow.css';

type Flow = 'reflect' | 'retain' | 'pages' | 'recall';
type Edge = { from: string; to: string; type?: 'loop' | 'side'; label?: string };
type Node = { id: string; tone: string; content: ReactNode };
const P = 'HINDSIGHT_API_';

function Help({ title, text, icon: Icon }: { title: string; text: string; icon: LucideIcon }) {
  const id = useId();
  const ref = useRef<HTMLButtonElement>(null);
  const [hover, setHover] = useState(false),
    [focus, setFocus] = useState(false),
    [pinned, setPinned] = useState(false);
  const [position, setPosition] = useState({ top: 0, left: 0 });
  const open = hover || focus || pinned;
  function close() {
    setHover(false);
    setFocus(false);
    setPinned(false);
  }
  useLayoutEffect(() => {
    if (!open || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    setPosition({
      top: Math.min(r.bottom + 8, innerHeight - 120),
      left: Math.max(12, Math.min(r.left, innerWidth - 292)),
    });
    const dismiss = (event: Event) => {
      if (!ref.current?.contains(event.target as HTMLElement)) close();
    };
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('scroll', close, true);
    window.addEventListener('resize', close);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      document.removeEventListener('scroll', close, true);
      window.removeEventListener('resize', close);
    };
  }, [open]);
  return (
    <>
      <button
        ref={ref}
        type="button"
        className="mw-help"
        aria-label={title}
        aria-describedby={open ? id : undefined}
        onPointerEnter={(e) => {
          if (e.pointerType === 'mouse') setHover(true);
        }}
        onPointerLeave={() => setHover(false)}
        onFocus={(e) => setFocus(e.currentTarget.matches(':focus-visible'))}
        onBlur={close}
        onClick={() => setPinned((v) => !v)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            e.preventDefault();
            close();
          }
        }}
      >
        <Icon size={17} />
        <span>{title}</span>
        <CircleHelp className="mw-question" size={13} />
      </button>
      {open &&
        createPortal(
          <div id={id} role="tooltip" className="mw-tooltip" style={position}>
            {text}
          </div>,
          document.body,
        )}
    </>
  );
}

function Diagram({ nodes, edges }: { nodes: Node[]; edges: Edge[] }) {
  const ref = useRef<HTMLDivElement>(null),
    marker = useId().replace(/:/g, '');
  const [geometry, setGeometry] = useState<{
    width: number;
    height: number;
    paths: { d: string; id: string }[];
    labels: { text: string; left: number; top: number; width: number }[];
  }>({ width: 1, height: 1, paths: [], labels: [] });
  const layoutKey = JSON.stringify(edges) + nodes.map((n) => n.id).join(',');
  useLayoutEffect(() => {
    const root = ref.current!;
    const measure = () => {
      const outer = root.getBoundingClientRect();
      const rect = (id: string) => {
        const r = root.querySelector(`[data-node="${id}"]`)!.getBoundingClientRect();
        return { x: r.left - outer.left, y: r.top - outer.top, w: r.width, h: r.height };
      };
      const paths: typeof geometry.paths = [],
        labels: typeof geometry.labels = [];
      edges.forEach((edge) => {
        const a = rect(edge.from),
          b = rect(edge.to);
        let d: string;
        if (edge.type === 'loop') {
          const x = a.x / 2,
            start = a.y + a.h / 2,
            end = b.y + b.h / 2;
          d = `M ${a.x - 2} ${start} H ${x + 6} Q ${x} ${start} ${x} ${start - 6} V ${end + 6} Q ${x} ${end} ${x + 6} ${end} H ${b.x - 5}`;
          if (edge.label)
            labels.push({ text: edge.label, left: 0, top: (start + end) / 2 - 18, width: a.x - 5 });
        } else if (edge.type === 'side') {
          const x = outer.width - 4,
            start = a.y + a.h / 2,
            end = b.y + b.h / 2;
          d = `M ${a.x + a.w + 2} ${start} H ${x - 6} Q ${x} ${start} ${x} ${start + 6} V ${end - 6} Q ${x} ${end} ${x - 6} ${end} H ${b.x + b.w + 5}`;
          if (edge.label)
            labels.push({
              text: edge.label,
              left: a.x + a.w + 4,
              top: (start + end) / 2 - 15,
              width: outer.width - a.x - a.w - 6,
            });
        } else {
          const x = a.x + a.w / 2,
            y = a.y + a.h;
          d = `M ${x} ${y + 2} V ${b.y - 5}`;
          if (edge.label)
            labels.push({
              text: edge.label,
              left: x + 9,
              top: y + (b.y - y) / 2 - 10,
              width: Math.min(105, outer.width - x - 12),
            });
        }
        paths.push({ d, id: `${edge.from}-${edge.to}` });
      });
      const next = { width: outer.width, height: outer.height, paths, labels };
      setGeometry((old) => (JSON.stringify(old) === JSON.stringify(next) ? old : next));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(root);
    root.querySelectorAll('[data-node]').forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, [layoutKey]);
  const loop = edges.some((e) => e.type === 'loop'),
    side = edges.some((e) => e.type === 'side');
  return (
    <div ref={ref} className={`mw-diagram ${loop ? 'has-loop' : ''} ${side ? 'has-side' : ''}`}>
      <svg
        className="mw-edges"
        viewBox={`0 0 ${geometry.width} ${geometry.height}`}
        aria-hidden="true"
      >
        <defs>
          <marker id={marker} markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto">
            <path d="M0 0 L7 3.5 L0 7 Z" />
          </marker>
        </defs>
        {geometry.paths.map((p) => (
          <path key={p.id} data-edge={p.id} d={p.d} markerEnd={`url(#${marker})`} />
        ))}
      </svg>
      {nodes.map((node) => (
        <div key={node.id} className={`mw-node ${node.tone}`} data-node={node.id}>
          {node.content}
        </div>
      ))}
      {geometry.labels.map((l, i) => (
        <span
          key={i}
          className="mw-edge-label"
          style={{ left: l.left, top: l.top, maxWidth: l.width }}
        >
          {l.text}
        </span>
      ))}
    </div>
  );
}

export function ModelWorkflowSettings({
  data,
  run,
  busy,
  configure,
  tools,
  quick = false,
}: Pick<PageProps, 'data' | 'run' | 'busy'> & {
  configure: (id: string) => void;
  tools: () => void;
  quick?: boolean;
}) {
  const { t } = useI18n();
  const [flow, setFlow] = useState<Flow>('reflect');
  const pendingRequest = useRef(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const locked = busy || pending;
  async function request(command: string, args: Row = {}) {
    if (busy || pendingRequest.current) return;
    pendingRequest.current = true;
    setPending(true);
    setError('');
    try {
      const result = await run(command, args);
      if (result?.error) setError(String(result.error));
    } catch (error) {
      setError(error instanceof Error ? error.message : String(error));
    } finally {
      pendingRequest.current = false;
      setPending(false);
    }
  }
  const workflow = data.modelWorkflow;
  if (!workflow) return null;
  const role = (id: string): Row => data.roles?.find((r: Row) => r.id === id) || {};
  const identity = (id: string): Row => workflow.identities[id] || {};
  const op = flow === 'retain' ? 'consolidation' : flow;
  const decision = workflow.decisions[op],
    recall = workflow.decisions.recall;
  const is120 = !!data.hindsightModels?.serverIs120;
  const uncertain = !!decision.uncertain || !!decision.partial;
  const on = decision.enabled && !uncertain;
  const values: Record<string, string> = workflow.values;
  function prepare(changes: Record<string, string>) {
    void request('server.models.prepare', { changes, revision: workflow.revision });
  }
  function changeToggle(enabled: boolean) {
    if (flow === 'recall') {
      const provider =
        role('decision').fields?.find((f: Row) => f.name === `${P}DECISION_MODEL_PROVIDER`)
          ?.value || 'none';
      prepare({ [`${P}RECALL_DECISION_MODEL_PROVIDER`]: enabled ? provider : 'none' });
    } else if (flow === 'pages')
      prepare({
        [`${P}MENTAL_MODEL_REFRESH_USE_DECISION_MODEL`]: String(enabled),
        [`${P}MENTAL_MODEL_DELTA_USE_DECISION_MODEL`]: String(enabled),
      });
    else prepare({ [`${P}${op.toUpperCase()}_USE_DECISION_MODEL`]: String(enabled) });
  }
  const globalProvider = role('decision').fields?.find(
    (f: Row) => f.name === `${P}DECISION_MODEL_PROVIDER`,
  )?.value;
  const canEnable =
    flow === 'recall'
      ? ['hindsight', 'typesafe', 'openai', 'cloudflare'].includes(globalProvider)
      : decision.configured;
  const toggleDisabled =
    locked ||
    !is120 ||
    uncertain ||
    (!on && !canEnable) ||
    (flow === 'recall' && on && !recall.shared);
  const labels: Record<Flow, string> = {
    // Mêmes noms de fonctions que la barre latérale, la recherche, le comportement et l’activité.
    reflect: t('Réponses', 'Answers'),
    retain: t('Extraction et consolidation', 'Extraction & consolidation'),
    pages: t('Connaissances', 'Knowledge'),
    recall: t('Recherche', 'Search'),
  };
  function modelSelect(id: string, title: string) {
    const r = role(id),
      current = identity(id),
      field = r.fields?.find((f: Row) => f.name.endsWith('_MODEL'));
    if (!field) return <span className="muted">{t('Non configuré', 'Not configured')}</span>;
    const options = new Map<string, string>(
      (r.models || []).map((m: Row) => [m.id, m.title || m.id]),
    );
    if (field.value) options.set(field.value, field.value);
    return (
      <div className="mw-choice">
        <select
          aria-label={title}
          value={field.value || ''}
          disabled={locked || current.dynamic}
          onChange={(e) => prepare({ [field.name]: e.target.value })}
        >
          <option value="">
            {current.model
              ? `${current.model} · ${t('hérité', 'inherited')}`
              : t('Défaut du serveur', 'Server default')}
          </option>
          {[...options].map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
        {quick ? (
          <div className="mw-provider">
            {current.dynamic
              ? t('Valeur définie ailleurs', 'Defined elsewhere')
              : current.provider || t('Fournisseur', 'Provider')}
          </div>
        ) : (
          <button
            type="button"
            className="mw-provider"
            disabled={locked}
            onClick={() => configure(id)}
          >
            <Settings2 size={12} />
            {current.dynamic
              ? t('Valeur définie ailleurs', 'Defined elsewhere')
              : current.provider || t('Fournisseur', 'Provider')}
            <span>{t('Modifier…', 'Edit…')}</span>
          </button>
        )}
      </div>
    );
  }
  function gen(id: string, title: string, modelRole: string, tip: string, icon: LucideIcon): Node {
    return {
      id,
      tone: 'writing',
      content: (
        <div className="mw-row">
          <Help title={title} text={tip} icon={icon} />
          {modelSelect(modelRole, `${t('Modèle', 'Model')} · ${title}`)}
        </div>
      ),
    };
  }
  function result(modelRole: string, title = t('Réponse', 'Answer')): Node {
    return {
      id: 'answer',
      tone: 'writing',
      content: (
        <div className="mw-row">
          <Help
            title={title}
            text={t(
              'Le modèle des Réponses rédige avec les preuves retenues. C’est le même modèle, choisi en haut.',
              'The Answers model writes using the selected evidence. It is the same model, chosen above.',
            )}
            icon={PenLine}
          />
          <span>
            {identity(modelRole).model || t('Modèle hérité', 'Inherited model')}{' '}
            <small>{t('même modèle', 'same model')}</small>
          </span>
        </div>
      ),
    };
  }
  function memory(id: string, title: string, text: string, tip: string): Node {
    return {
      id,
      tone: 'retrieval',
      content: (
        <div className="mw-row">
          <Help title={title} text={tip} icon={Database} />
          <span className="muted">{text}</span>
        </div>
      ),
    };
  }
  function rank(): Node {
    const r = role('reranker'),
      provider = r.fields?.find((f: Row) => f.name === `${P}RERANKER_PROVIDER`)?.value || 'local';
    const field = serviceModelField({ ...r, id: 'reranker', fields: r.fields || [] });
    const text =
      field?.value ||
      (provider === 'hindsight' ? 'hs-rerank-1' : provider === 'rrf' ? 'RRF' : r.effective);
    return {
      id: 'rank',
      tone: 'retrieval',
      content: (
        <div className="mw-row">
          <Help
            title={t('Recherche', 'Search')}
            text={t(
              'Retrouve les faits et classe les candidats. Le classement peut lui aussi utiliser le modèle de décision, indépendamment des Réponses.',
              'Finds facts and ranks candidates. Ranking can also use the decision model, independently of Answers.',
            )}
            icon={Search}
          />
          <div>
            {recall.enabled && !recall.uncertain ? (
              <>
                <span>{recall.model || recall.provider}</span>
                <button className="mw-related" onClick={() => setFlow('recall')}>
                  {t('Réglé dans Recherche', 'Set in Search')} <ArrowUpRight size={13} />
                </button>
              </>
            ) : (
              <>
                <button
                  className="mw-model-button"
                  disabled={locked}
                  onClick={() => configure('reranker')}
                >
                  {text || t('Classement du serveur', 'Server ranking')} <Settings2 size={14} />
                </button>
                <small>
                  {provider}
                  {recall.uncertain &&
                    ` · ${t('décision à vérifier', 'check decision configuration')}`}
                </small>
              </>
            )}
          </div>
        </div>
      ),
    };
  }
  function sourcePicker() {
    const source = data.hindsightModels?.decision || 'off';
    return (
      <div className="mw-choice">
        <select
          aria-label={t('Modèle de décision', 'Decision model')}
          disabled={locked || !is120}
          value={source}
          onChange={(e) => {
            if (e.target.value === 'advanced') configure('decision');
            else void request('server.decision', { source: e.target.value });
          }}
        >
          {/* Choisir cette option coupe le modèle de décision : même libellé que dans Réglages. */}
          <option value="off">{t('Désactivé', 'Off')}</option>
          {source === 'other' && (
            <option value="other">
              {t('Configuration personnalisée', 'Custom configuration')}
            </option>
          )}
          <optgroup label={t('Sur ce Mac', 'On this Mac')}>
            <option value="local" disabled={data.hindsightModels?.local?.phase !== 'running'}>
              hs-decide-1-flash
            </option>
          </optgroup>
          <optgroup label="Hindsight Cloud">
            <option
              value="cloud"
              disabled={
                quick &&
                !data.hindsightModels?.cloudConnected &&
                !(source === 'cloud' && !data.hindsightModels?.needsCloudAccount)
              }
            >
              hs-decide-1-flash
            </option>
          </optgroup>
          {!quick && (
            <option value="advanced">{t('Autre configuration…', 'Other configuration…')}</option>
          )}
        </select>
        <button className="mw-provider" type="button" onClick={tools}>
          {source === 'local' ? <Laptop size={12} /> : <Cloud size={12} />}
          {source === 'local'
            ? t('Sur ce Mac', 'On this Mac')
            : source === 'cloud'
              ? 'Hindsight Cloud'
              : t('Installer ou connecter…', 'Install or connect…')}
        </button>
      </div>
    );
  }
  function judge(title: string, tip: string): Node {
    return {
      id: 'decision',
      tone: 'decision',
      content: (
        <>
          <div className="mw-row">
            <Help title={title} text={tip} icon={GitBranch} />
            {decision.shared ? (
              sourcePicker()
            ) : (
              <div>
                <span>{decision.model || decision.provider}</span>
                <button className="mw-related" onClick={() => configure('decision')}>
                  {t('Configuration propre à ce rôle', 'Role-specific configuration')}{' '}
                  <Settings2 size={13} />
                </button>
              </div>
            )}
          </div>
          {flow === 'recall' && (
            <div className="mw-recall-options">
              {[
                ['PRUNE', t('Écarter les faits inutiles', 'Remove irrelevant facts')],
                ['DEDUP', t('Retirer les doublons', 'Remove duplicates')],
              ].map(([key, label]) => {
                const name = `${P}RECALL_DECISION_MODEL_${key}`;
                return (
                  <label key={name}>
                    <input
                      type="checkbox"
                      checked={['true', '1', 'yes'].includes(values[name]?.toLowerCase())}
                      disabled={locked || workflow.dynamicNames.includes(name)}
                      onChange={(e) => prepare({ [name]: String(e.target.checked) })}
                    />
                    {label}
                  </label>
                );
              })}
            </div>
          )}
        </>
      ),
    };
  }
  const down = (from: string, to: string, label?: string): Edge => ({ from, to, label });
  const loop = (from: string, to: string, label: string): Edge => ({
    from,
    to,
    label,
    type: 'loop',
  });
  const side = (from: string, to: string, label?: string): Edge => ({
    from,
    to,
    label,
    type: 'side',
  });
  let nodes: Node[], edges: Edge[];
  if (flow === 'reflect' || (flow === 'pages' && !on)) {
    const modelRole = flow === 'pages' ? 'mental_model' : 'reflect';
    nodes = [
      gen(
        'query',
        t('Rédaction', 'Writing'),
        modelRole,
        t(
          'Formule la recherche et rédige la réponse. Sans décision spécialisée, choisit aussi quand arrêter de chercher.',
          'Writes the query and the answer. Without a decision model, also chooses when to stop searching.',
        ),
        MessagesSquare,
      ),
      rank(),
    ];
    if (on)
      nodes.push(
        judge(
          t('Preuves suffisantes ?', 'Enough evidence?'),
          t(
            'Trie les preuves. Si elles ne suffisent pas, demande une nouvelle recherche, dans la limite du budget.',
            'Filters evidence. If it is insufficient, requests another search within the budget.',
          ),
        ),
      );
    nodes.push(
      result(
        modelRole,
        flow === 'pages' ? t('Régénérer la page', 'Regenerate the page') : undefined,
      ),
    );
    edges = on
      ? [
          down('query', 'rank', t('Requête', 'Query')),
          down('rank', 'decision', t('Preuves', 'Evidence')),
          down('decision', 'answer', t('Oui', 'Yes')),
          loop('decision', 'query', t('Non : chercher encore', 'No: search again')),
        ]
      : [
          down('query', 'rank', t('Chercher', 'Search')),
          loop('rank', 'query', t('Résultats', 'Results')),
          side('query', 'answer'),
        ];
  } else if (flow === 'retain') {
    nodes = [
      gen(
        'extract',
        t('Extraction', 'Extraction'),
        'retain',
        t(
          'Extrait du document les faits à mémoriser.',
          'Extracts facts to remember from a document.',
        ),
        ScanText,
      ),
    ];
    if (on)
      nodes.push(
        judge(
          t('Trier les faits', 'Triage facts'),
          t(
            'Envoie les nouveautés à consolider. Rattache les répétitions comme sources, sans réécriture.',
            'Sends new information for consolidation. Links repeated information as evidence without rewriting.',
          ),
        ),
      );
    nodes.push(
      gen(
        'consolidate',
        t('Consolidation', 'Consolidation'),
        'consolidation',
        t(
          'Rassemble les faits pour créer ou mettre à jour les observations.',
          'Combines facts to create or update observations.',
        ),
        Database,
      ),
      memory(
        'memory',
        t('Mémoire', 'Memory'),
        t('Faits & observations', 'Facts & observations'),
        t(
          'Les faits, leurs sources et les observations sont conservés par Hindsight.',
          'Hindsight stores facts, their sources and observations.',
        ),
      ),
    );
    edges = on
      ? [
          down('extract', 'decision'),
          down('decision', 'consolidate', t('À consolider', 'To consolidate')),
          down('consolidate', 'memory'),
          side('decision', 'memory', t('Sans réécrire', 'No rewrite')),
        ]
      : [down('extract', 'consolidate'), down('consolidate', 'memory')];
  } else if (flow === 'pages') {
    nodes = [
      memory(
        'new',
        t('Nouveaux faits', 'New facts'),
        t('Depuis la dernière mise à jour', 'Since the last update'),
        t(
          'Sélectionne par date les nouveaux faits, sans modèle.',
          'Selects new facts by date, without a model.',
        ),
      ),
      judge(
        t('Modifier la page ?', 'Change the page?'),
        t(
          'Vérifie si les nouveaux faits peuvent modifier la page. Sinon, la conserve telle quelle.',
          'Checks whether new facts could change the page. Otherwise keeps it unchanged.',
        ),
      ),
      gen(
        'write',
        t('Rédaction', 'Writing'),
        'mental_model',
        t('Réécrit la page avec les faits utiles.', 'Rewrites the page using relevant facts.'),
        NotebookText,
      ),
      memory(
        'page',
        'Page',
        t('Conservée ou régénérée', 'Kept or regenerated'),
        t(
          'La page reste intacte si aucun changement utile n’est détecté.',
          'The page remains unchanged when no relevant change is found.',
        ),
      ),
    ];
    edges = [
      down('new', 'decision'),
      down('decision', 'write', t('Oui', 'Yes')),
      down('write', 'page'),
      side('decision', 'page', t('Non', 'No')),
    ];
  } else {
    nodes = on
      ? [
          memory(
            'memories',
            t('Retrouver', 'Retrieve'),
            workflow.embeddings,
            t(
              'Les embeddings retrouvent des faits proches par le sens.',
              'Embeddings retrieve facts that are similar in meaning.',
            ),
          ),
          judge(
            t('Classer', 'Rank'),
            t(
              'Classe les faits selon leur utilité. Ne rédige pas de réponse.',
              'Ranks facts by usefulness. Does not write an answer.',
            ),
          ),
        ]
      : [rank()];
    edges = on ? [down('memories', 'decision')] : [];
  }
  return (
    <section className="card model-workflow" aria-label={t('Choix des modèles', 'Model settings')}>
      <header className="mw-heading">
        <div>
          {!quick && <h2>{t('Modèles', 'Models')}</h2>}
          <p>
            {t(
              'Réglages du serveur · applicables après enregistrement et redémarrage',
              'Server settings · applied after saving and restarting',
            )}
          </p>
        </div>
        {!quick && (
          <Button
            kind="ghost"
            icon={Settings2}
            disabled={locked}
            onClick={() => configure('default')}
          >
            {t('Défaut', 'Default')}
          </Button>
        )}
      </header>
      <Tabs
        value={flow}
        onChange={(v) => setFlow(v as Flow)}
        items={Object.entries(labels).map(([id, label]) => ({ id, label }))}
      />
      <div className="mw-body">
        <ErrorNotice message={error} />
        <div className="mw-decision-toggle">
          <Help
            title={t('Modèle de décision', 'Decision model')}
            text={t(
              'Active la décision spécialisée pour cette fonction. Les banques peuvent remplacer ces valeurs. Le classement dans Recherche et l’évaluation dans Réponses sont indépendants.',
              'Enables specialized decisions for this function. Banks may override these defaults. Ranking in Search and evidence evaluation in Answers are independent.',
            )}
            icon={GitBranch}
          />
          <label>
            <span>
              {uncertain
                ? t('À vérifier', 'Check configuration')
                : on
                  ? t('Activé', 'On')
                  : t('Désactivé', 'Off')}
            </span>
            <input
              type="checkbox"
              role="switch"
              aria-label={`${t('Décision', 'Decision')} · ${labels[flow]}`}
              checked={on}
              disabled={toggleDisabled}
              onChange={(e) => changeToggle(e.target.checked)}
            />
          </label>
        </div>
        {!is120 && (
          <p className="notice">
            {t(
              'Les contrôles de décision demandent Hindsight 1.2.',
              'Decision controls require Hindsight 1.2.',
            )}
          </p>
        )}
        {data.hindsightModels?.needsCloudAccount && (
          <div className="notice">
            <span>
              {t(
                'Connectez Hindsight Cloud avant d’utiliser ces modèles.',
                'Connect Hindsight Cloud before using these models.',
              )}
            </span>
            <Button kind="ghost" onClick={tools}>
              {t('Connexions', 'Connections')}
            </Button>
          </div>
        )}
        {data.hindsightModels?.decision === 'local' &&
          data.hindsightModels?.local?.phase !== 'running' && (
            <div className="notice">
              <span>{localDecisionNotice(data.hindsightModels?.local?.phase)}</span>
              <Button kind="ghost" onClick={tools}>
                {t('Gérer le modèle local', 'Manage local model')}
              </Button>
            </div>
          )}
        {!decision.configured && (
          <div className="mw-setup">
            {sourcePicker()}
            <Button kind="ghost" onClick={() => configure('decision')}>
              {t('Options du rôle', 'Role options')}
            </Button>
          </div>
        )}
        {uncertain ? (
          <div className="notice">
            <span>
              {t(
                'Ce parcours utilise des valeurs externes ou des options différentes. Vérifiez sa configuration avancée.',
                'This workflow uses external values or different options. Check its advanced configuration.',
              )}
            </span>
            <Button kind="ghost" onClick={() => configure('decision')}>
              {t('Vérifier', 'Review')}
            </Button>
          </div>
        ) : (
          <Diagram nodes={nodes} edges={edges} />
        )}
        <div className="mw-embeddings">
          <Help
            title="Embeddings"
            text={t(
              'Représentent le sens des textes. Le schéma conserve votre modèle et vos vecteurs existants.',
              'Represent the meaning of text. This diagram preserves your current model and existing vectors.',
            )}
            icon={LockKeyhole}
          />
          <span>
            {workflow.embeddings || t('Configuration conservée', 'Configuration preserved')}
          </span>
        </div>
      </div>
      <footer className="mw-footer">
        <span>
          {data.hasChanges
            ? t('Modifications préparées', 'Changes prepared')
            : data.needsRestart
              ? t('Redémarrage requis', 'Restart required')
              : t('Aucune modification', 'No changes')}
        </span>
        <div>
          {quick && data.needsRestart && !data.hasChanges && (
            <Button
              disabled={locked}
              onClick={() => (data.service?.installed ? void request('service.restart') : tools())}
            >
              {t('Appliquer au serveur…', 'Apply to server…')}
            </Button>
          )}
          <Button
            disabled={locked || !data.hasChanges}
            onClick={() => void request('server.revert')}
          >
            {t('Annuler', 'Cancel')}
          </Button>
          <Button
            kind="primary"
            disabled={locked || !data.hasChanges}
            onClick={() => void request('server.save')}
          >
            {t('Enregistrer', 'Save')}
          </Button>
        </div>
      </footer>
    </section>
  );
}
