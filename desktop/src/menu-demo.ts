import { translate as t } from './i18n-core.ts';
import type { MenuStatus } from './menu-model.ts';

/** Exemple du volet hors de l’app (aperçu navigateur, captures) : `?view=menu&state=paused|offline|idle`. */
let paused: boolean | null = null;

export function demoMenuStatus(
  state: string | null,
  command = 'menu.status',
  args: Record<string, unknown> = {},
): MenuStatus {
  if (paused === null) paused = state === 'paused';
  const asking = command === 'pause.pause' || command === 'pause.resume';
  if (command === 'confirm' && args.id === 'demo-pause') paused = !paused;
  const offline = state === 'offline';
  const idle = state === 'idle' || paused;
  const status: MenuStatus = {
    connected: !offline,
    connecting: false,
    connectionError: offline
      ? t('Connexion refusée par 127.0.0.1:8888.', 'Connection refused by 127.0.0.1:8888.')
      : null,
    serverURL: 'http://127.0.0.1:8888',
    version: offline ? null : '1.2.0',
    banks: [
      { bank_id: 'assistant', name: 'Assistant', fact_count: 18432 },
      { bank_id: 'recherche', name: 'Recherche', fact_count: 5210 },
      { bank_id: 'notes', name: 'Notes personnelles', fact_count: 912 },
    ],
    bank: 'assistant',
    pause: {
      all: paused,
      banks: [],
      uncut: [],
      unreleased: [],
      workerOff: false,
      busy: false,
      progress: null,
    },
    consultationOnly: false,
    service: {
      local: true,
      installed: true,
      known: true,
      running: !offline,
      phase: offline ? 'stopped' : 'ready',
      canStart: offline,
      canStop: !offline,
      busy: false,
    },
    activity: {
      pending: idle ? 0 : 14,
      processing: idle ? 0 : 2,
      running: idle
        ? []
        : [
            {
              id: 'assistant/op-1',
              bank: 'assistant',
              type: 'retain',
              title: 'Extraction des faits',
              target: 'notes-reunion.md',
              createdAt: new Date().toISOString(),
              stage: null,
              processed: 38,
              total: 120,
            },
            {
              id: 'recherche/op-2',
              bank: 'recherche',
              type: 'consolidation',
              title: 'Consolidation',
              target: null,
              createdAt: new Date().toISOString(),
              stage: null,
              processed: null,
              total: null,
            },
          ],
      queues: [
        { bank: 'assistant', pending: idle ? 0 : 9, processing: idle ? 0 : 1 },
        { bank: 'recherche', pending: idle ? 0 : 5, processing: idle ? 0 : 1 },
      ],
    },
    bankStatus: offline
      ? null
      : {
          bank: 'assistant',
          consolidation: {
            enabled: true,
            automatic: !paused,
            pendingFacts: idle ? 0 : 236,
            failedFacts: 0,
            lastConsolidatedAt: new Date().toISOString(),
            running: 0,
            queued: 0,
            phase: idle ? 'upToDate' : 'pending',
          },
          failed: idle ? 0 : 3,
        },
    usage: {
      tracked: true,
      today: idle ? 0.42 : 1.87,
      todayTokens: idle ? 128_000 : 1_460_000,
      subscription5h: idle ? 0 : 820_000,
      tokensPerMinute: idle ? 0 : 12_400,
      idle: !!idle,
      gauges: [
        {
          id: 'daily-dollars',
          used: idle ? 0.42 : 1.87,
          limit: 5,
          fraction: idle ? 0.084 : 0.374,
          level: 0,
        },
      ],
    },
    confirmations: asking
      ? [
          {
            id: 'demo-pause',
            title: paused
              ? 'Reprendre toutes les banques ?'
              : 'Mettre toutes les banques en pause ?',
            message: paused
              ? "Toutes les banques : les envois reprennent, la consolidation arrêtée par la pause repart sur les faits restants et la consolidation automatique retrouve son réglage d'avant."
              : "Toutes les banques : plus aucun envoi depuis cette app, consolidation automatique coupée. La consolidation en cours s'arrête après son lot et les régénérations de connaissances sont annulées ; rien n'est perdu. Les extractions déjà en file continuent.",
            confirmTitle: paused ? 'Reprendre' : 'Mettre en pause',
            destructive: false,
          },
        ]
      : [],
    messages: [],
    messageKeys: [],
    at: new Date().toISOString(),
  };
  return status;
}
