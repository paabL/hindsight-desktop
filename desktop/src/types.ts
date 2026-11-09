export type Row = Record<string, any>;
export type Section =
  | 'sources'
  | 'models'
  | 'model-settings'
  | 'search'
  | 'facts'
  | 'consolidation'
  | 'documents'
  | 'consumption'
  | 'dashboard'
  | 'memory'
  | 'operations'
  | 'audit'
  | 'timeline'
  | 'graph'
  | 'server'
  | 'admin'
  | 'settings';
export type Confirmation = {
  id: string;
  title: string;
  message: string;
  confirmTitle: string;
  destructive: boolean;
  requiredText?: string | null;
};
export type Snapshot = {
  serviceBusy?: boolean;
  updates?: Row;
  app: {
    connected: boolean;
    serverURL: string;
    bank: string | null;
    banks: Row[];
    folder?: string | null;
    connectionError?: string | null;
    serverURLNotice?: string | null;
    version?: Row;
    /** État réel de la pause : toutes les banques, banques une à une, consolidation pas encore coupée, worker du serveur arrêté. */
    pause?: PauseState;
    consultationOnly?: boolean;
  };
  section: Section;
  data: Row;
  messages: string[];
  /** Clé d’occurrence de chaque message (moteur natif) : un même texte produit de nouveau change de clé. */
  messageKeys?: string[];
  confirmations: Confirmation[];
};
export type PauseState = {
  all: boolean;
  banks: string[];
  uncut?: string[];
  unreleased?: string[];
  workerOff?: boolean;
};
export type Request = (command: string, args?: Row) => Promise<any>;
export type PageProps = {
  data: Row;
  run: Request;
  busy: boolean;
  navigate: (section: Section) => void;
  refresh: (args?: Row) => Promise<any>;
  notify: (message: string) => void;
  demo: boolean;
};

declare global {
  interface Window {
    __TAURI_INTERNALS__?: unknown;
  }
}
