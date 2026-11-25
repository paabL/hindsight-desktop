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

/** Séparateur entre fournisseur et modèle dans la valeur d’une option du menu des modèles. */
const PICK = '\u001f';
type Op = 'reflect' | 'consolidation' | 'pages' | 'pagesDelta' | 'recall';

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
  const decisionOf = (op: Op): Row => workflow.decisions[op] || workflow.decisions.pages || {};
  const recall = workflow.decisions.recall;
  const is120 = !!data.hindsightModels?.serverIs120;
  const values: Record<string, string> = workflow.values;
  const isUncertain = (op: Op) => !!decisionOf(op).uncertain;
  const isOn = (op: Op) => !!decisionOf(op).enabled && !isUncertain(op);
  function prepare(changes: Record<string, string>) {
    void request('server.models.prepare', { changes, revision: workflow.revision });
  }
  const globalProvider = role('decision').fields?.find(
    (f: Row) => f.name === `${P}DECISION_MODEL_PROVIDER`,
  )?.value;
  const recallReady = ['hindsight', 'typesafe', 'openai', 'cloudflare'].includes(globalProvider);
  function changeToggle(op: Op, enabled: boolean) {
    if (op === 'recall')
      prepare({
        [`${P}RECALL_DECISION_MODEL_PROVIDER`]: enabled ? globalProvider || 'none' : 'none',
      });
    else if (op === 'pages')
      prepare({ [`${P}MENTAL_MODEL_REFRESH_USE_DECISION_MODEL`]: String(enabled) });
    else if (op === 'pagesDelta')
      prepare({ [`${P}MENTAL_MODEL_DELTA_USE_DECISION_MODEL`]: String(enabled) });
    else prepare({ [`${P}${op.toUpperCase()}_USE_DECISION_MODEL`]: String(enabled) });
  }
  function toggleDisabled(op: Op) {
    const canEnable = op === 'recall' ? recallReady : !!decisionOf(op).configured;
    return (
      locked ||
      !is120 ||
      isUncertain(op) ||
      (!isOn(op) && !canEnable) ||
      (op === 'recall' && isOn(op) && !recall.shared)
    );
  }
  const labels: Record<Flow, string> = {
    // Mêmes noms de fonctions que la barre latérale, la recherche, le comportement et l’activité.
    reflect: t('Réponses', 'Answers'),
    retain: t('Extraction et consolidation', 'Extraction & consolidation'),
    pages: t('Connaissances', 'Knowledge'),
    recall: t('Recherche', 'Search'),
  };
  const providerTitle = (id: string): string =>
    data.providerChoices?.find((p: Row) => p.id === id)?.title || id;
  const modelTitle = (provider: string, model: string): string =>
    data.modelsByProvider?.[provider]?.find((m: Row) => m.id === model)?.title || model;
  /** Fournisseurs prêts : comptes connectés et fournisseurs déjà réglés dans un usage. */
  function readyProviders(current: string): string[] {
    const connected = (data.accounts || [])
      .filter((a: Row) => a.connected && a.id !== 'hindsight')
      .map((a: Row) => a.id);
    const used = Object.values(workflow.identities as Record<string, Row>).map((i) => i.provider);
    return [...new Set([...connected, ...used, current])].filter(
      (p) => p && p !== 'none' && !String(p).includes('$'),
    );
  }
  function modelSelect(id: string, title: string) {
    const r = role(id),
      current = identity(id),
      modelField = r.fields?.find((f: Row) => f.name.endsWith('_MODEL')),
      providerField = r.fields?.find((f: Row) => f.name.endsWith('_PROVIDER'));
    if (!modelField) return <span className="muted">{t('Non configuré', 'Not configured')}</span>;
    const own = Boolean(modelField.value || providerField?.value);
    const selected = own ? `${current.provider}${PICK}${current.model}` : '';
    const groups = readyProviders(current.provider).map((provider) => {
      const models: Row[] = [...(data.modelsByProvider?.[provider] || [])];
      if (provider === current.provider && !models.some((m) => m.id === current.model))
        models.unshift({ id: current.model, title: current.model });
      return { provider, models };
    });
    const inherited = r.fallback ? identity(r.fallback) : null;
    function choose(value: string) {
      if (value === '__other__') return configure(id);
      if (!value)
        return prepare({
          [modelField.name]: '',
          ...(providerField ? { [providerField.name]: '' } : {}),
        });
      const [provider, model] = value.split(PICK);
      prepare({
        [modelField.name]: model,
        ...(providerField ? { [providerField.name]: provider } : {}),
      });
    }
    return (
      <div className="mw-choice">
        <select
          aria-label={title}
          value={selected}
          disabled={locked || current.dynamic}
          onChange={(e) => choose(e.target.value)}
        >
          {(!own || id !== 'default') && (
            <option value="">
              {inherited?.model
                ? `${t('Comme', 'Same as')} ${modelTitle(inherited.provider, inherited.model)} · ${t('hérité', 'inherited')}`
                : current.model && !own
                  ? `${modelTitle(current.provider, current.model)} · ${t('hérité', 'inherited')}`
                  : t('Défaut du serveur', 'Server default')}
            </option>
          )}
          {groups.map(({ provider, models }) => (
            <optgroup key={provider} label={providerTitle(provider)}>
              {models.map((m) => (
                <option key={m.id} value={`${provider}${PICK}${m.id}`}>
                  {m.title || m.id}
                </option>
              ))}
            </optgroup>
          ))}
          {/* Fournisseur pas encore prêt (clé, adresse) : l’éditeur du rôle, plus bas sur la page. */}
          <option value="__other__">{t('Autre fournisseur…', 'Other provider…')}</option>
        </select>
        {quick ? (
          <div className="mw-provider">
            {current.dynamic
              ? t('Valeur définie ailleurs', 'Defined elsewhere')
              : providerTitle(current.provider) || t('Fournisseur', 'Provider')}
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
              : providerTitle(current.provider) || t('Fournisseur', 'Provider')}
            <span>{t('Réglages…', 'Settings…')}</span>
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
    const current = identity(modelRole);
    return {
      id: 'answer',
      tone: 'writing',
      content: (
        <div className="mw-row">
          <Help
            title={title}
            text={t(
              'Le même modèle que la rédaction écrit avec les preuves retenues.',
              'The same model as Writing writes using the selected evidence.',
            )}
            icon={PenLine}
          />
          <span>
            {current.model
              ? modelTitle(current.provider, current.model)
              : t('Modèle hérité', 'Inherited model')}{' '}
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
  function retrieve(): Node {
    return memory(
      'memories',
      t('Retrouver', 'Retrieve'),
      t('Sens, mots, dates et liens', 'Meaning, words, dates and links'),
      t(
        'Quatre recherches à la fois : par le sens (embeddings), par les mots, par les dates citées dans la question et par les liens entre faits.',
        'Four searches at once: by meaning (embeddings), by words, by dates in the question and by links between facts.',
      ),
    );
  }
  const rerankerName = () => {
    const r = role('reranker'),
      provider = r.fields?.find((f: Row) => f.name === `${P}RERANKER_PROVIDER`)?.value || 'local';
    const field = serviceModelField({ ...r, id: 'reranker', fields: r.fields || [] });
    return {
      provider,
      text:
        field?.value ||
        (provider === 'hindsight' ? 'hs-rerank-1' : provider === 'rrf' ? 'RRF' : r.effective),
    };
  };
  /** Classement des candidats : le reranker, sauf quand le modèle de décision le remplace (Recherche). */
  function rank(id = 'rank', title = t('Recherche', 'Search')): Node {
    const { provider, text } = rerankerName();
    const replaced = recall.enabled && !recall.uncertain;
    return {
      id,
      tone: 'retrieval',
      content: (
        <div className="mw-row">
          <Help
            title={title}
            text={
              replaced
                ? t(
                    'Retrouve les faits, puis le modèle de décision les classe à la place du reranker. Réglé dans l’onglet Recherche.',
                    'Finds facts, then the decision model ranks them instead of the reranker. Set in the Search tab.',
                  )
                : t(
                    'Retrouve les faits et les classe avec le reranker, puis ajoute les bonus de récence, de date et de preuves.',
                    'Finds facts and ranks them with the reranker, then adds recency, date and evidence boosts.',
                  )
            }
            icon={Search}
          />
          <div>
            {replaced ? (
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
  function judge(op: Op, title: string, tip: string): Node {
    const decision = decisionOf(op);
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
          {op === 'recall' && (
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
  const noDates = t(
    'Il juge chaque preuve sur son seul texte, sans voir sa date.',
    'It judges each piece of evidence on its text alone, without seeing its date.',
  );
  /** Rédiger en cherchant : Réponses, et régénération complète d’une page de connaissance. */
  function searchAndWrite(op: 'reflect' | 'pages'): { nodes: Node[]; edges: Edge[] } {
    const modelRole = op === 'pages' ? 'mental_model' : 'reflect',
      on = isOn(op);
    const nodes = [
      gen(
        'query',
        t('Rédaction', 'Writing'),
        modelRole,
        t(
          'Formule les recherches et rédige. Sans modèle de décision, choisit aussi quand arrêter de chercher.',
          'Writes the searches and the text. Without a decision model, also chooses when to stop searching.',
        ),
        MessagesSquare,
      ),
      rank(),
    ];
    if (on)
      nodes.push(
        judge(
          op,
          t('Preuves suffisantes ?', 'Enough evidence?'),
          `${t(
            'Écarte les preuves jugées inutiles, puis demande une nouvelle recherche si le reste ne suffit pas, dans la limite du budget.',
            'Drops evidence judged useless, then requests another search if the rest is not enough, within the budget.',
          )} ${noDates}`,
        ),
      );
    nodes.push(
      result(modelRole, op === 'pages' ? t('Page régénérée', 'Regenerated page') : undefined),
    );
    const edges = on
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
    return { nodes, edges };
  }
  function pageUpdate(): { nodes: Node[]; edges: Edge[] } {
    const on = isOn('pagesDelta');
    const nodes = [
      memory(
        'new',
        t('Nouveaux faits', 'New facts'),
        t('Depuis la dernière mise à jour', 'Since the last update'),
        t(
          'Sélectionne par date les nouveaux faits, sans modèle.',
          'Selects new facts by date, without a model.',
        ),
      ),
    ];
    if (on)
      nodes.push(
        judge(
          'pagesDelta',
          t('Modifier la page ?', 'Change the page?'),
          t(
            'Vérifie si les nouveaux faits peuvent modifier la page. Sinon, la garde telle quelle sans appeler la rédaction.',
            'Checks whether new facts could change the page. Otherwise keeps it as is without calling Writing.',
          ),
        ),
      );
    nodes.push(
      gen(
        'write',
        t('Rédaction', 'Writing'),
        'mental_model',
        t(
          'Intègre les nouveaux faits à la page existante.',
          'Merges the new facts into the existing page.',
        ),
        NotebookText,
      ),
      memory(
        'page',
        'Page',
        on ? t('Gardée ou mise à jour', 'Kept or updated') : t('Mise à jour', 'Updated'),
        t(
          'La page garde ses sections ; seules celles que les nouveaux faits changent sont réécrites.',
          'The page keeps its sections; only those the new facts change are rewritten.',
        ),
      ),
    );
    const edges = on
      ? [
          down('new', 'decision'),
          down('decision', 'write', t('Oui', 'Yes')),
          down('write', 'page'),
          side('decision', 'page', t('Non', 'No')),
        ]
      : [down('new', 'write'), down('write', 'page')];
    return { nodes, edges };
  }
  function extraction(): { nodes: Node[]; edges: Edge[] } {
    const on = isOn('consolidation');
    const nodes = [
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
          'consolidation',
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
    const edges = on
      ? [
          down('extract', 'decision'),
          down('decision', 'consolidate', t('À consolider', 'To consolidate')),
          down('consolidate', 'memory'),
          side('decision', 'memory', t('Sans réécrire', 'No rewrite')),
        ]
      : [down('extract', 'consolidate'), down('consolidate', 'memory')];
    return { nodes, edges };
  }
  function searchFlow(): { nodes: Node[]; edges: Edge[] } {
    if (!isOn('recall'))
      return {
        nodes: [retrieve(), rank('rank', t('Classer', 'Rank'))],
        edges: [down('memories', 'rank', t('Candidats', 'Candidates'))],
      };
    return {
      nodes: [
        retrieve(),
        judge(
          'recall',
          t('Classer', 'Rank'),
          `${t(
            `Remplace le reranker (${rerankerName().text}). Son ordre est final : plus de bonus de récence ni de date.`,
            `Replaces the reranker (${rerankerName().text}). Its order is final: no more recency or date boosts.`,
          )} ${noDates}`,
        ),
      ],
      edges: [down('memories', 'decision', t('Candidats', 'Candidates'))],
    };
  }
  function toggle(op: Op, title: string, tip: string) {
    const uncertain = isUncertain(op),
      on = isOn(op);
    return (
      <div className="mw-decision-toggle">
        <Help title={title} text={tip} icon={GitBranch} />
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
            aria-label={`${t('Décision', 'Decision')} · ${title === t('Modèle de décision', 'Decision model') ? labels[flow] : title}`}
            checked={on}
            disabled={toggleDisabled(op)}
            onChange={(e) => changeToggle(op, e.target.checked)}
          />
        </label>
      </div>
    );
  }
  function uncertainNotice() {
    return (
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
    );
  }
  const decisionTip = t(
    'Active le modèle de décision pour cette fonction, sur tout le serveur. Le classement dans Recherche et le tri des preuves dans Réponses sont indépendants.',
    'Turns on the decision model for this function, for the whole server. Ranking in Search and evidence filtering in Answers are independent.',
  );
  type Section = { op: Op; title?: string; tip: string; diagram: { nodes: Node[]; edges: Edge[] } };
  const sections: Section[] =
    flow === 'pages'
      ? [
          {
            op: 'pages',
            title: t('Régénération complète', 'Full regeneration'),
            tip: t(
              'Quand une page est régénérée en entier (bouton Régénérer, pages en mode complet) : la rédaction cherche dans la mémoire, et le modèle de décision peut trier les preuves.',
              'When a page is fully regenerated (Regenerate button, pages in full mode): Writing searches memory, and the decision model can filter the evidence.',
            ),
            diagram: searchAndWrite('pages'),
          },
          {
            op: 'pagesDelta',
            title: t('Mise à jour partielle', 'Partial update'),
            tip: t(
              'Quand une page en mode mise à jour reçoit de nouveaux faits : le modèle de décision peut ignorer ceux qui ne la changent pas.',
              'When a page in update mode receives new facts: the decision model can skip those that do not change it.',
            ),
            diagram: pageUpdate(),
          },
        ]
      : [
          {
            op: flow === 'retain' ? 'consolidation' : flow,
            tip: decisionTip,
            diagram:
              flow === 'reflect'
                ? searchAndWrite('reflect')
                : flow === 'retain'
                  ? extraction()
                  : searchFlow(),
          },
        ];
  const setupOp: Op = flow === 'retain' ? 'consolidation' : flow;
  const needsSetup = flow === 'recall' ? !recallReady : !decisionOf(setupOp).configured;
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
        {needsSetup && (
          <div className="mw-setup">
            {sourcePicker()}
            <Button kind="ghost" onClick={() => configure('decision')}>
              {t('Options du rôle', 'Role options')}
            </Button>
          </div>
        )}
        {sections.map((section) => (
          <div key={section.op} className="mw-section">
            {toggle(
              section.op,
              section.title || t('Modèle de décision', 'Decision model'),
              section.tip,
            )}
            {isUncertain(section.op) ? (
              uncertainNotice()
            ) : (
              <Diagram nodes={section.diagram.nodes} edges={section.diagram.edges} />
            )}
          </div>
        ))}
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
