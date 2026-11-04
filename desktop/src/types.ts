export type Row = Record<string, any>;
export type Section =
  | 'sources'
  | 'models'
  | 'search'
  | 'facts'
  | 'documents'
  | 'consumption'
  | 'dashboard'
  | 'memory'
  | 'operations'
  | 'audit'
  | 'timeline'
  | 'graph'
  | 'hermes'
  | 'server'
  | 'admin'
  | 'settings'
  | 'coverage';
export type Confirmation = {
  id: string;
  title: string;
  message: string;
  confirmTitle: string;
  destructive: boolean;
  requiredText?: string | null;
};
export type Snapshot = {
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
    paused?: string[];
  };
  section: Section;
  data: Row;
  messages: string[];
  confirmations: Confirmation[];
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
