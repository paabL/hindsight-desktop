import { getLocale, translate as t } from './i18n-core.ts';
import type { Confirmation, Row } from './types.ts';

/** Relevé du moteur pour le volet de la barre des menus (commande `menu.status`, MenuStatus.swift). */
export interface MenuStatus {
  connected: boolean;
  connecting: boolean;
  connectionError: string | null;
  serverURL: string;
  version: string | null;
  banks: Row[];
  bank: string | null;
  pause: {
    all: boolean;
    banks: string[];
    uncut: string[];
    unreleased: string[];
    workerOff: boolean;
    busy: boolean;
    progress: string | null;
  };
  consultationOnly: boolean;
  service: {
    local: boolean;
    installed: boolean;
    known: boolean;
    running: boolean;
    phase: string;
    canStart: boolean;
    canStop: boolean;
    busy: boolean;
  };
  activity: {
    pending: number;
    processing: number;
    running: MenuOperation[];
    queues: { bank: string; pending: number; processing: number }[];
  };
  bankStatus: {
    bank: string;
    consolidation: Consolidation | null;
    failed: number | null;
  } | null;
  usage: {
    tracked: boolean;
    today: number;
    todayTokens: number;
    subscription5h: number;
    tokensPerMinute: number;
    idle: boolean;
    gauges: { id: string; used: number; limit: number; fraction: number; level: number }[];
  };
  confirmations: Confirmation[];
  messages: string[];
  messageKeys: string[];
  at: string;
}

export interface MenuOperation {
  id: string;
  bank: string;
  type: string;
  title: string;
  target: string | null;
  createdAt: string;
  stage: string | null;
  processed: number | null;
  total: number | null;
}

/** État de consolidation calculé par le moteur (ConsolidationStatus.swift), le même que dans l’app. */
export interface Consolidation {
  enabled: boolean;
  automatic: boolean;
  pendingFacts: number;
  failedFacts: number;
  lastConsolidatedAt: string | null;
  running: number;
  queued: number;
  phase: 'disabled' | 'running' | 'queued' | 'pending' | 'upToDate';
}

/** Ce que le volet demande à la fenêtre principale (menubar.rs, `Action`). */
export type MenuAction =
  | { kind: 'open'; section?: string }
  | { kind: 'bank'; id: string }
  | { kind: 'changed' }
  | { kind: 'quit' };

export type TrayLook = 'idle' | 'working' | 'dim';
export type Tone = 'sage' | 'blue' | 'amber' | 'red' | 'neutral';

// Formats : mêmes réglages que ui.tsx, sans charger toute la bibliothèque d’interface dans le volet.
export const count = (value: number) =>
  new Intl.NumberFormat(getLocale(), { maximumFractionDigits: 0 }).format(value);
export const compact = (value: number) =>
  new Intl.NumberFormat(getLocale(), { notation: 'compact', maximumFractionDigits: 1 }).format(
    value,
  );
export const money = (value: number) =>
  new Intl.NumberFormat(getLocale(), {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(value);
const plural = (n: number, fr: string, frs: string, en: string, ens: string) =>
  `${count(n)} ${t(n > 1 ? frs : fr, n === 1 ? en : ens)}`;

/** Nom d’une banque à l’écran : comme `bankLabel` dans ui.tsx. */
export function bankName(status: MenuStatus | null, id: string | null | undefined): string {
  if (!id) return '';
  const bank = status?.banks.find((b) => b.bank_id === id);
  const name = typeof bank?.name === 'string' ? bank.name.trim() : '';
  const alias = typeof bank?.display_alias === 'string' ? bank.display_alias : '';
  return (name && name !== id ? name : '') || alias || name || id;
}

/** Adresse lisible du serveur : hôte et port, sans le schéma. */
export function serverName(url: string): string {
  try {
    const parsed = new URL(url);
    return parsed.host || url;
  } catch {
    return url;
  }
}

/** Icône de la barre des menus : elle pâlit hors connexion ou en pause, un halo quand le serveur travaille. */
export function trayLook(status: MenuStatus | null): TrayLook {
  if (!status?.connected || status.pause.all) return 'dim';
  return status.activity.processing > 0 ? 'working' : 'idle';
}

export function trayTooltip(status: MenuStatus | null): string {
  if (!status) return 'Hindsight';
  const parts = ['Hindsight'];
  if (!status.connected)
    parts.push(
      status.connecting
        ? t('connexion…', 'connecting…')
        : t('serveur injoignable', 'server unreachable'),
    );
  else {
    if (status.pause.all) parts.push(t('en pause', 'paused'));
    parts.push(activitySummary(status));
  }
  return parts.join(' — ');
}

/** « 2 en cours · 14 en attente », ou « Au repos ». */
export function activitySummary(status: MenuStatus): string {
  const { processing, pending } = status.activity;
  if (!processing && !pending) return t('Au repos', 'Idle');
  const parts: string[] = [];
  if (processing) parts.push(`${count(processing)} ${t('en cours', 'running')}`);
  if (pending) parts.push(`${count(pending)} ${t('en attente', 'queued')}`);
  return parts.join(' · ');
}

/** Bandeau du volet : ce qui empêche l’app de travailler normalement, le plus grave d’abord. */
export function notice(status: MenuStatus | null): { tone: Tone; text: string } | null {
  if (!status) return null;
  if (!status.connected && !status.connecting)
    return {
      tone: 'red',
      text: status.connectionError
        ? t('Serveur injoignable : ', 'Server unreachable: ') + status.connectionError
        : t('Serveur injoignable.', 'Server unreachable.'),
    };
  const parts: string[] = [];
  let tone: Tone = 'amber';
  if (status.pause.all)
    parts.push(
      t(
        'Pause sur toutes les banques : envois, consolidation automatique et régénérations suspendus.',
        'All banks paused: uploads, automatic consolidation and regenerations suspended.',
      ),
    );
  else if (status.pause.banks.length)
    parts.push(
      `${t('En pause :', 'Paused:')} ${status.pause.banks.map((id) => bankName(status, id)).join(', ')}.`,
    );
  if (status.pause.workerOff)
    parts.push(
      t(
        'Worker du serveur arrêté : les opérations attendent.',
        'Server worker off: operations wait.',
      ),
    );
  if (status.consultationOnly)
    parts.push(
      t(
        'Serveur en mode consultation : écritures refusées.',
        'Server in read-only mode: writes refused.',
      ),
    );
  const exceeded = status.usage.gauges.find((gauge) => gauge.level >= 2);
  if (exceeded) {
    tone = 'red';
    parts.push(t('Plafond de dépense atteint.', 'Spending cap reached.'));
  }
  return parts.length ? { tone, text: parts.join(' ') } : null;
}

/** Consolidation de la banque choisie, en une ligne et un ton. */
export function consolidationLine(
  c: Consolidation | null | undefined,
): { tone: Tone; text: string } | null {
  if (!c) return null;
  switch (c.phase) {
    case 'disabled':
      return { tone: 'neutral', text: t('Consolidation désactivée', 'Consolidation off') };
    case 'running':
      return {
        tone: 'blue',
        text: c.pendingFacts
          ? `${t('Consolidation en cours', 'Consolidating')} · ${plural(c.pendingFacts, 'fait restant', 'faits restants', 'fact left', 'facts left')}`
          : t('Consolidation en cours', 'Consolidating'),
      };
    case 'queued':
      return { tone: 'blue', text: t('Consolidation en attente', 'Consolidation queued') };
    case 'pending':
      return {
        tone: 'amber',
        text: plural(
          c.pendingFacts,
          'fait à consolider',
          'faits à consolider',
          'fact to consolidate',
          'facts to consolidate',
        ),
      };
    default:
      return { tone: 'sage', text: t('Tous les faits sont consolidés', 'All facts consolidated') };
  }
}

/** Nom d’un type d’opération : les mêmes que Activité › Traitements. */
export function operationName(op: Pick<MenuOperation, 'type' | 'title'>): string {
  const names: Record<string, [string, string]> = {
    retain: ['Extraction des faits', 'Fact extraction'],
    batch_retain: ['Extraction par lot', 'Batch extraction'],
    consolidation: ['Consolidation', 'Consolidation'],
    refresh_mental_model: ['Régénération des connaissances', 'Knowledge regeneration'],
    reprocess_document: ['Retraitement', 'Reprocessing'],
    file_convert_retain: ['Conversion et extraction', 'Conversion and extraction'],
    webhook_delivery: ['Envoi de webhook', 'Webhook delivery'],
    bank_export: ['Export', 'Export'],
    export: ['Export', 'Export'],
    bank_import: ['Import', 'Import'],
    import: ['Import', 'Import'],
    bank_clone: ['Clonage', 'Clone'],
    clone: ['Clonage', 'Clone'],
  };
  const name = names[op.type];
  return name ? t(name[0], name[1]) : op.title;
}

/** Avancement d’une opération (0…1) quand le serveur le donne. */
export function progress(op: MenuOperation): number | null {
  if (op.total == null || op.processed == null || op.total <= 0) return null;
  return Math.max(0, Math.min(1, op.processed / op.total));
}

/** Action principale : la pause d’un clic quand le serveur répond, sinon le démarrer s’il est sur ce Mac. */
export function primaryAction(
  status: MenuStatus | null,
): { kind: 'pause' | 'resume' | 'start'; label: string; disabled: boolean } | null {
  if (!status) return null;
  if (!status.connected) {
    if (!status.service.local || !status.service.installed || status.service.running) return null;
    return {
      kind: 'start',
      label: t('Démarrer le serveur', 'Start the server'),
      disabled: !status.service.canStart || status.service.busy,
    };
  }
  const disabled = status.pause.busy || status.consultationOnly;
  return status.pause.all
    ? { kind: 'resume', label: t('Reprendre toutes les banques', 'Resume all banks'), disabled }
    : { kind: 'pause', label: t('Tout mettre en pause', 'Pause everything'), disabled };
}

/** Une confirmation demandée par le volet, et non une confirmation déjà ouverte dans la fenêtre. */
export function newConfirmation(
  before: MenuStatus | null,
  after: MenuStatus | null,
): Confirmation | null {
  const known = new Set((before?.confirmations || []).map((c) => c.id));
  return after?.confirmations.find((c) => !known.has(c.id)) || null;
}
